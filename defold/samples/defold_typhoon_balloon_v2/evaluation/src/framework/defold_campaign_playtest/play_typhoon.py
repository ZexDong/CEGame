"""Native Typhoon v2 campaign acceptance using public geometry and normal keys."""
import argparse
import copy
import json
import math
import time
from pathlib import Path
from framework.defold_native_tasks.balloon_model import Model,State
from framework.macos_evaluation.host import write
from .session import Session


def balloon(v):return next(e for e in v['entities'] if e['kind']=='balloon')

def toggle(s,target):
    if s.state()['phase']==target:return
    for attempt in range(3):
        s.press('pause',seconds=.04,settle=.02)
        try:return s.wait(lambda v:v['phase']==target,.5)
        except RuntimeError as error:
            if str(error)!='STATE_CONDITION_TIMEOUT' or attempt==2:raise
            s.event('pause_key_retry',target=target,attempt=attempt+1)

def physical(s,logical):
    value=s.tables['controls']['keys'][logical]
    return value[0] if isinstance(value,list) else value

def key_down(s,key):
    for attempt in range(3):
        try:
            s.desktop.call('key',pid=s.process.pid,key=key,down=True);return
        except RuntimeError as error:
            if str(error) not in ('FOREGROUND_LOST','PROCESS_EXITED') or s.process.poll() is not None or attempt==2:raise
            time.sleep(.08);s.focus()

def hold(s,logical_keys,seconds):
    keys=[physical(s,k) for k in logical_keys];held=[]
    try:
        s.focus()
        for key in keys:key_down(s,key);held.append(key)
        s.event('combined_hold',logical=logical_keys,physical=keys,seconds=seconds);s.delay(seconds)
    finally:
        if held:s.desktop.call('release',keys=held)

def retry(s,committed):
    before=s.state();serial=before['slots']['run_serial'];index=before['slots']['level_index'];cleared=before['slots']['cleared_levels']
    s.press('restart',seconds=.05,settle=.03);s.wait(lambda v:v['phase']=='playing' and v['slots']['run_serial']==serial+1)
    after=s.state();assert after['slots']['level_index']==index and after['slots']['cleared_levels']==cleared
    assert after['slots']['elapsed']<1 and after['slots']['retries']==0 and after['slots']['stars_collected']==committed
    assert after['slots']['station_power_mask']==0 and after['slots']['station_used_mask']==0

def pilot(s,model,target,label,stop=None,timeout=180,planned_path=None):
    held=set();path=None;planned_retries=-1;progress=0;last_revision=-1
    deadline=time.monotonic()+timeout;anchor=None;anchor_elapsed=0;last_print=-1
    def release():
        if held:s.desktop.call('release',keys=sorted(held));held.clear()
    try:
        while time.monotonic()<deadline:
            snap=s.state();slots=snap['slots']
            if snap['phase'] in ('level_clear','campaign_won'):return snap
            if snap['phase'] not in ('playing','paused'):raise RuntimeError('TYPHOON_LEFT_ACTIVE_PHASE')
            if stop and stop(snap):release();toggle(s,'paused');return s.state()
            if slots['respawn_remaining']>0:
                release()
                if snap['phase']=='paused':toggle(s,'playing')
                s.wait(lambda v:v['slots']['respawn_remaining']==0,4);path=None;continue
            position=balloon(snap)['position']
            if math.dist(position,target)<8:
                release();toggle(s,'paused');return s.state()
            if path is None or slots['retries']!=planned_retries:
                release();toggle(s,'paused');snap=s.state();slots=snap['slots'];position=balloon(snap)['position']
                path=planned_path if planned_path is not None and planned_retries<0 else model.path(position,target)
                deadline=max(deadline,time.monotonic()+len(path)*.5+45)
                progress=0;planned_retries=slots['retries'];last_revision=-1
                s.event('public_geometry_route',label=label,target=target,source_revision=snap['revision'],nodes=len(path))
                toggle(s,'playing');continue
            if snap['revision']==last_revision:time.sleep(.015);continue
            last_revision=snap['revision']
            if anchor is None:anchor=position;anchor_elapsed=slots['elapsed']
            elif slots['elapsed']-anchor_elapsed>5:
                if math.dist(position,anchor)<4 and progress<len(path)-4:
                    release();path=None;anchor=None;continue
                anchor=position;anchor_elapsed=slots['elapsed']
            begin=min(progress,len(path)-1);end=min(len(path),begin+24)
            progress=min(range(begin,end),key=lambda i:math.dist(path[i],position))
            waypoint=path[min(progress+4,len(path)-1)]
            state=State(*position,slots['velocity_x'],slots['velocity_y'],slots['elapsed'])
            horizontal,lift=model.choose(state,waypoint)
            wanted=({physical(s,'left')} if horizontal<0 else {physical(s,'right')} if horizontal>0 else set())
            if lift:wanted.add(physical(s,'action'))
            for key in sorted(held-wanted):s.desktop.call('release',keys=[key]);held.remove(key)
            for key in sorted(wanted-held):key_down(s,key);held.add(key)
            if int(slots['elapsed'])//15!=last_print:
                last_print=int(slots['elapsed'])//15
                print('TYPHOON',label,'elapsed',round(slots['elapsed'],1),'cp',slots['checkpoint_index'],
                      'stars',slots['stars_collected'],'retries',slots['retries'],flush=True)
            if slots['retries']>30:raise RuntimeError('TYPHOON_RETRY_BUDGET')
            time.sleep(.025)
        raise RuntimeError('TYPHOON_ROUTE_TIMEOUT:'+label)
    finally:release()

def use_station(s,model,station,mask):
    pilot(s,model,station['position'],'station-'+station['id'],
          stop=lambda v:math.dist(balloon(v)['position'],station['position'])<=station['interaction_radius']-4)
    toggle(s,'playing');s.press('interact',seconds=.04,settle=.12);toggle(s,'paused')
    state=s.state();assert state['slots']['station_used_mask']&mask and state['slots']['station_power_mask']&mask
    s.capture('station-'+station['id']+'-used');return state

def cause_hazard(s,model):
    before=copy.deepcopy(s.state());retries=before['slots']['retries'];stars=before['slots']['stars_collected']
    power=before['slots']['station_power_mask'];used=before['slots']['station_used_mask'];checkpoint=before['slots']['checkpoint_index']
    toggle(s,'playing')
    for _ in range(70):
        snap=s.state()
        if snap['slots']['retries']>retries:break
        x,y=balloon(snap)['position'];choices=[]
        for ix,iy in s.spec['world']['spike_cells']:
            target=((ix+.5)*16,(iy+.5)*16);distance=math.dist((x,y),target)
            if distance<=220:choices.append((distance,target))
        if not choices:raise RuntimeError('NO_NEARBY_SPIKE')
        _,target=min(choices);slots=snap['slots'];keys=[]
        vx=max(-20,min(20,(target[0]-x)*1.5));vy=max(-20,min(20,(target[1]-y)*1.5))
        if slots['velocity_x']<vx-1:keys.append('right')
        elif slots['velocity_x']>vx+1:keys.append('left')
        if slots['velocity_y']<vy:keys.append('action')
        hold(s,keys,.25)
    s.wait(lambda v:v['slots']['retries']==retries+1,3);s.wait(lambda v:v['slots']['respawn_remaining']==0,4);toggle(s,'paused')
    after=s.state();assert after['slots']['checkpoint_index']==checkpoint and after['slots']['stars_collected']==stars
    assert after['slots']['station_power_mask']==power and after['slots']['station_used_mask']==used
    s.capture('checkpoint-hazard-respawn')

def collect_all_stars(s,model):
    count=0
    while True:
        snap=s.state();stars=[e for e in snap['entities'] if e['kind']=='star']
        if not stars:return
        position=balloon(snap)['position'];stars.sort(key=lambda e:math.dist(position,e['position']))
        routes=[]
        for target in stars[:12]:
            try:
                path=model.path(position,target['position']);routes.append((len(path),target,path))
            except ValueError:pass
        if not routes:raise RuntimeError('NO_REACHABLE_REMAINING_STAR')
        _,target,path=min(routes,key=lambda row:row[0]);before=snap['slots']['stars_collected']
        pilot(s,model,target['position'],'star-'+target['id'],stop=lambda v:not any(e['id']==target['id'] for e in v['entities']),
              planned_path=path)
        assert s.state()['slots']['stars_collected']>before
        count+=1
        if count%10==0 or not [e for e in s.state()['entities'] if e['kind']=='star']:
            print('TYPHOON STAR SWEEP',s.state()['slots']['stars_collected'],'/ 99',flush=True)

def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--candidate',type=Path);a=p.parse_args()
    s=Session('defold_typhoon_balloon_v2',a.output,a.candidate);checks=[];model=None
    try:
        s.start();s.capture('menu');s.click('menu_new_campaign');s.wait(lambda v:v['phase']=='playing');model=Model(s.spec['world'])
        s.mark('D2.MENU','D2.WORLD','D5.MENU','D5.HUD')
        s.delay(1.2);before=copy.deepcopy(s.state());assert abs(balloon(before)['position'][1]-80)<.6
        hold(s,['right','action'],.5);after=copy.deepcopy(s.state())
        assert after['slots']['velocity_x']>0 and after['slots']['velocity_y']>0
        toggle(s,'paused');frozen=copy.deepcopy(s.state());s.delay(.35);hold(s,['left','action'],.2)
        assert s.state()['slots']==frozen['slots'] and s.state()['entities']==frozen['entities']
        checks.append('combined thrust, stable platform collision and pause freeze use normal keys');s.mark('D2.FLIGHT','D3.FLIGHT','D3.SOLID','D3.PAUSE','D5.PAUSE')
        retry(s,0)
        for index,level in enumerate(s.spec['levels'],1):
            assert s.state()['slots']['level_index']==index;s.capture('chapter-'+str(index)+'-initial')
            if index==1:
                target=model.checkpoints[0];pilot(s,model,target,'checkpoint-1',stop=lambda v:v['phase']=='level_clear')
            elif index==2:
                station=level['stations'][0];use_station(s,model,station,1)
                before_hazard=s.state()['slots']['stars_collected'];cause_hazard(s,model)
                assert s.state()['slots']['stars_collected']==before_hazard
                committed=s.state()['slots']['committed_star_count'];retry(s,committed)
                assert s.state()['slots']['stars_collected']==committed
                use_station(s,model,station,1)
                pilot(s,model,model.checkpoints[3],'checkpoint-4',stop=lambda v:v['phase']=='level_clear')
                checks.append('hazard respawns at latest checkpoint preserving attempt state; Retry restores chapter baseline');s.mark('D2.CHECKPOINTS','D3.HAZARD','D4.RESPAWN','D4.RETRY','D5.FEEDBACK')
            else:
                use_station(s,model,level['stations'][0],1)
                collect_all_stars(s,model);assert s.state()['slots']['stars_collected']==99
                assert s.state()['slots']['station_used_mask']==1
                state=use_station(s,model,level['stations'][1],2)
                assert state['slots']['station_used_mask']==3 and state['slots']['station_power_mask']==2
                finish=(model.finishes[0][0],model.finishes[0][1]+16)
                pilot(s,model,finish,'finish',stop=lambda v:v['phase']=='campaign_won',timeout=240)
                checks.append('third chapter collects every remaining star before B; A/B used persist while power remains mutually exclusive');s.mark('D2.STATIONS','D3.STARS','D3.STATIONS')
            expected='campaign_won' if index==3 else 'level_clear';s.wait(lambda v:v['phase']==expected)
            state=s.state();s.capture('chapter-'+str(index)+'-complete')
            profile=json.loads((s.profile/'campaign-v2.json').read_text());result=profile['completed_results'][-1]
            assert profile['cleared_levels']==index and len(profile['completed_results'])==index
            assert all(station in result['stations_used'] for station in level['goal']['required_stations'])
            assert state['slots']['committed_star_count']==sum(r['stars_delta'] for r in profile['completed_results'])
            checks.append('chapter '+str(index)+': public target and station requirements commit exactly once')
            if index==1:s.mark('D3.CHAPTERS','D5.RESULT')
            elif index==2:s.mark('D2.CHAPTERS')
            else:s.mark('D3.RANK','D4.CHAPTERS','D4.SUCCESS')
            print('TYPHOON CHAPTER',index,'stars',state['slots']['committed_star_count'],'elapsed',round(result['elapsed'],1),flush=True)
            if index==1:
                target=next(t for t in state['targets'] if t['kind']=='next_level');rect=target['rect'];v=state['slots']
                s.click('next_level');s.desktop.call('click',pid=s.process.pid,x=rect[0]+rect[2]/2,y=rect[1]+rect[3]/2,
                    width=v['client_width'],height=v['client_height']);s.event('stale_next_click',rect=rect);s.delay(.2)
                assert s.state()['slots']['level_index']==2 and s.state()['slots']['cleared_levels']==1
                checks.append('double Next does not skip chapter 2');s.mark('D4.ORDER')
            elif index==2:
                s.click('return_menu');s.click('menu_exit',exit_expected=True);s.process.wait(timeout=5);assert s.process.returncode==0
                s.launch();assert s.state()['slots']['run_serial']==0 and s.state()['slots']['saved_levels']==2
                s.click('menu_continue');s.wait(lambda v:v['phase']=='playing' and v['slots']['level_index']==3)
                checks.append('close/reopen Continue restores chapter 3 with committed stars and clean station state');s.mark('D4.REOPEN')
        profile=json.loads((s.profile/'campaign-v2.json').read_text());assert len(profile['committed_star_cells'])==99
        total_time=sum(r['elapsed'] for r in profile['completed_results']);total_retries=sum(r['retries'] for r in profile['completed_results'])
        expected_rank=3 if total_retries==0 and total_time<600 else 2 if total_retries<=4 and total_time<900 else 1
        assert s.state()['slots']['rank']==expected_rank
        s.click('return_menu');s.click('menu_continue');assert s.state()['phase']=='campaign_won'
        s.click('campaign_new');s.click('new_cancel');assert s.state()['phase']=='campaign_won' and s.state()['slots']['saved_levels']==3
        s.click('campaign_new');s.click('new_confirm');s.wait(lambda v:v['phase']=='playing')
        cause_hazard(s,model);assert s.state()['phase']=='paused' and s.state()['slots']['retries']==1
        retry(s,0);assert s.state()['slots']['cleared_levels']==0 and s.state()['slots']['stars_collected']==0
        checks.append('completed Continue/cancel preserve summary; New Campaign and Retry clear the correct scope');s.mark('D4.RESET')
        write(s.output/'acceptance.json',{'sample':s.sample.name,'status':'passed','scope':'native candidate playtest, not scoring',
            'checks':checks,'committed_stars':99,'campaign_elapsed':total_time,'campaign_retries':total_retries,'rank':expected_rank})
        print('TYPHOON NATIVE ACCEPTANCE PASSED',flush=True)
    finally:s.close()

if __name__=='__main__':main()
