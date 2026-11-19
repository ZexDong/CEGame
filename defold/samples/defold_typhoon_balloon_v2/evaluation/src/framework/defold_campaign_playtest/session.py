"""Native candidate playtest session. No scoring or state-writing API."""
import fcntl
import json
import os
import subprocess
import time
from pathlib import Path
from framework.defold_cross_engine.native import stage_build,EXCLUDED
from framework.defold_player_runtime.player import DashboardReader
from framework.defold_player_runtime.evidence import capture_window
from framework.macos_evaluation.host import binding,sha,write
from framework.defold_campaign_dashboard.dashboard_self_check import validate_naming_tables,validate_snapshot
from .desktop import EvaluatorDesktop

ROOT=Path(__file__).resolve().parents[2]

class Session:
    def __init__(self,sample,output,candidate=None):
        self.sample=ROOT/'samples'/sample;self.candidate=Path(candidate).resolve()
        self.output=Path(output).resolve();self.output.mkdir(parents=True,exist_ok=False)
        self.tables=validate_naming_tables(json.loads((self.sample/'input/naming-tables.json').read_text()))
        self.spec=json.loads((self.sample/'input/campaign.json').read_text())
        self.profile=self.output/'profile';self.profile.mkdir()
        self.serial=0;self.counter=0;self.process=None;self.log=None;self.desktop=None;self.locked=False;self.lock=None
        self.events=(self.output/'events.jsonl').open('w');self.before=binding(self.candidate,EXCLUDED)
        self.deadline=time.monotonic()+3600;self.latest=None;self.passed_checks=[]
    def event(self,kind,**values):
        self.events.write(json.dumps({'event':kind,'monotonic':time.monotonic(),**values},ensure_ascii=False)+'\n');self.events.flush()
    def mark(self,*check_ids):
        for check_id in check_ids:
            if check_id not in self.passed_checks:self.passed_checks.append(check_id)
        write(self.output/'progress.json',{'passed_checks':self.passed_checks})
        self.event('evaluation_progress',passed_checks=self.passed_checks)
    def start(self):
        self.lock=(ROOT/'.locks/desktop-playtest.lock').open('a+')
        fcntl.flock(self.lock,fcntl.LOCK_EX|fcntl.LOCK_NB);self.locked=True
        self.lock.seek(0);self.lock.truncate();self.lock.write('candidate-evaluation:'+self.sample.name);self.lock.flush()
        self.desktop=EvaluatorDesktop();host=self.desktop.call('check');write(self.output/'host.json',host)
        if host['session_locked'] or not all(host[k] for k in ('accessibility','input','screen_recording')):raise RuntimeError('DESKTOP_NOT_READY')
        _,build,self.executable=stage_build(self.candidate,self.output)
        if self.executable is None:raise RuntimeError('BUILD_FAILED')
        self.launch()
    def launch(self):
        self.stop_game();self.serial+=1;self.session=self.output/f'session-{self.serial:03}';self.session.mkdir()
        self.log=(self.session/'runtime.log').open('wb')
        self.process=subprocess.Popen([str(self.executable)],cwd=self.session,env={**os.environ,'BENCHMARK_PROFILE_DIR':str(self.profile)},stdout=self.log,stderr=subprocess.STDOUT,start_new_session=True)
        self.event('launch',pid=self.process.pid,session=self.serial)
        self.reader=DashboardReader(self.session/'dashboard.jsonl');self.latest=None;self.revision=0;self.log_offset=0
        self.wait(lambda s:True,15);self.focus();self.delay(.25)
    def focus(self):
        for attempt in range(5):
            try:return self.desktop.call('focus',pid=self.process.pid,activate=True)
            except RuntimeError:
                if attempt==4:raise
                time.sleep(.1)
    def state(self):
        if time.monotonic()>self.deadline:raise RuntimeError('PLAYTEST_TIMEOUT')
        if self.process.poll() is not None:raise RuntimeError('GAME_PROCESS_EXITED')
        for s in self.reader.poll_updates():
            validate_snapshot(s,self.tables,self.revision);self.latest=s;self.revision=s['revision']
        with (self.session/'runtime.log').open(errors='replace') as f:
            f.seek(self.log_offset);lines=f.read().splitlines();self.log_offset=f.tell()
        bad=[x for x in lines if x.startswith(('ERROR:SCRIPT:','ERROR:GUI:','ERROR:RESOURCE:','FATAL:'))]
        if bad:raise RuntimeError('GAME_ERROR:'+bad[0])
        return self.latest
    def wait(self,predicate,timeout=10):
        end=time.monotonic()+timeout
        while time.monotonic()<end:
            s=self.state()
            if s is not None and predicate(s):return s
            time.sleep(.015)
        raise RuntimeError('STATE_CONDITION_TIMEOUT')
    def delay(self,seconds):
        end=time.monotonic()+seconds
        while time.monotonic()<end:self.state();time.sleep(min(.02,max(0,end-time.monotonic())))
    def press(self,key,seconds=.12,settle=.10):
        physical=self.tables['controls']['keys'][key]
        if isinstance(physical,list):physical=physical[0]
        down=False
        try:
            for attempt in range(3):
                try:self.desktop.call('key',pid=self.process.pid,key=physical,down=True);down=True;break
                except RuntimeError as error:
                    if str(error)!='FOREGROUND_LOST' or attempt==2:raise
                    self.event('focus_restored_before_key',logical=key);self.focus();self.state()
            self.event('key',logical=key,physical=physical,seconds=seconds);self.delay(seconds)
        finally:
            if down:self.desktop.call('release',keys=[physical])
        if settle:self.delay(settle)
    def click(self,kind,exit_expected=False):
        for attempt in range(3):
            self.focus();s=self.state();targets=[t for t in s['targets'] if t['kind']==kind and t['visible'] and t['interactable']]
            if len(targets)!=1:raise RuntimeError('TARGET_UNAVAILABLE:'+kind)
            x,y,w,h=targets[0]['rect']
            try:
                self.desktop.call('click',pid=self.process.pid,x=x+w/2,y=y+h/2,width=s['slots']['client_width'],height=s['slots']['client_height'])
                self.event('click',target=kind,rect=targets[0]['rect']);break
            except RuntimeError as error:
                if str(error)!='FOREGROUND_LOST' or attempt==2:raise
                self.event('focus_restored_before_click',target=kind)
        if not exit_expected:self.delay(.25)
    def drag(self,start,end,seconds=.4):
        s=self.state();self.focus();self.event('drag',start=start,end=end,seconds=seconds)
        self.desktop.call('drag',pid=self.process.pid,x=start[0],y=start[1],end_x=end[0],end_y=end[1],
                          width=s['slots']['client_width'],height=s['slots']['client_height'],seconds=seconds)
        self.delay(.1)
    def capture(self,label):
        try:self.desktop.call('focus',pid=self.process.pid,activate=False)
        except RuntimeError as error:
            if str(error)!='FOREGROUND_LOST':raise
            self.focus()
        s=self.state();self.counter+=1;name=f'{self.counter:04}-{label}'
        snapshot=self.output/'snapshots'/f'{name}.json';write(snapshot,s)
        image=self.output/'captures'/f'{name}.png';capture_window(self.process.pid,image)
        metadata={'path':str(image.relative_to(self.output)),'snapshot':str(snapshot.relative_to(self.output)),'sha256':sha(image),'pid':self.process.pid}
        write(image.with_suffix('.json'),metadata);self.event('capture',**metadata);return metadata
    def stop_game(self):
        if self.process:
            if self.process.poll() is None:
                self.process.terminate()
                try:self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:self.process.kill();self.process.wait(timeout=5)
            self.event('cleanup',pid=self.process.pid,returncode=self.process.returncode);self.process=None
        if self.log:self.log.close();self.log=None
    def close(self):
        self.stop_game()
        if self.desktop:self.desktop.close()
        if self.lock:
            if self.locked:
                self.lock.seek(0);self.lock.truncate();self.lock.flush();fcntl.flock(self.lock,fcntl.LOCK_UN)
            self.lock.close()
        write(self.output/'source-after.json',{'unchanged':binding(self.candidate,EXCLUDED)==self.before})
        self.events.close()
