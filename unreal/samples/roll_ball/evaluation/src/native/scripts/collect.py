"""Isolated short player cases and one complete journey, with local attribution."""
import argparse
import math
import shutil
import time
from pathlib import Path
from catalog import catalog
from navigation import Navigator, TRAPS, route, dot
from evidence import image_info
from runtime import (ROOT, INPUT, Player, CandidateError, InfrastructureError, ObservationUncertain,
    cell, load, norm, position, sub, vec, velocity, interval_verdict, sha, write)

CASE_CHECKS={
 'entry':['D2-board','D2-traps','D2-exit','D3-initial','D5-running'],
 'direction-W':['D2-ball','D3-directions','D3-coast','D5-roll'],
 'direction-A':['D3-directions'],'direction-S':['D3-directions'],'direction-D':['D3-directions'],
 'countersteer':['D3-countersteer'],'perimeter':['D3-perimeter'],'internal':['D3-internal'],
 'rim':['D3-safe-rim'],
 'trap':['D2-recovery','D3-opening','D3-hit-count','D3-hit-time','D3-hit-lock','D3-reset','D4-resume','D5-trap'],
 'repeat-trap':['D3-repeat-hit'],
 'journey':['D3-goal','D3-terminal','D4-journey','D5-complete'],
 'restart-running':['D4-restart-running','D5-restart'],
 'restart-trap':['D4-restart-trap'],'restart-terminal':['D4-restart-terminal'],
 'restart-repeat':['D4-restart-repeat'],'reopen':['D4-reopen'],
 'exit-running':['D4-exit-running'],'exit-trap':['D4-exit-trap'],'exit-terminal':['D4-exit-terminal'],
 'camera':['D5-camera']}

# Public diagnostic contract for each independent trajectory.  These bounds
# make the legacy runner auditable under the current evaluator rules while
# keeping the existing gameplay assertions and weights unchanged.
CASE_CONTRACT={name:dict(max_actions=24,max_serial_seconds=45,setup_method='normal_input') for name in CASE_CHECKS}
for _name in ('entry','direction-W','direction-A','direction-S','direction-D','countersteer','perimeter','internal','rim','trap','repeat-trap','restart-running','restart-trap','restart-terminal','restart-repeat','reopen','exit-running','exit-trap','exit-terminal','camera'):
    CASE_CONTRACT[_name]=dict(max_actions=32,max_serial_seconds=60,setup_method='normal_input')
CASE_CONTRACT['journey']=dict(max_actions=64,max_serial_seconds=120,setup_method='normal_input')

# Each direction is exercised from a public cell where that edge is open.
# This avoids treating a blocked start edge as proof of a direction mapping.
DIRECTION_SETUP={
 'W':((0,0),(0,1)),
 'D':((0,2),(1,2)),
 'S':((2,2),(2,1)),
 'A':((2,2),(1,2)),
}

def fresh(s,origin=None):
    g=s.get('game_state') if isinstance(s,dict) else None
    b=g.get('ball') if isinstance(g,dict) else None
    if not isinstance(g,dict) or not isinstance(b,dict) or not all(k in g for k in ('status','trap_hits','input_enabled')): return False
    good=g['status']=='running' and g['trap_hits']==0 and g['input_enabled'] and cell(s)==(0,0)
    # Floating point noise tolerance, not a private speed or ball-height rule.
    good=good and norm(velocity(s))<1e-4 and norm(vec(b['angular_velocity']))<1e-4
    if origin:good=good and norm(sub(position(s),origin))<1e-3
    return good

def snapshots(p,start):return [r['snapshot'] for r in p.samples[start:]]
def _sample_motion(samples):
    """Return whether a candidate produced real ball translation in samples.

    Navigation calibration can time out after the input has already moved the
    ball.  Preserve that positive evidence for the independent movement
    checkpoint instead of replacing it with a blanket review verdict.
    """
    points=[]
    for row in samples:
        try: points.append(position(row))
        except Exception: pass
    if len(points)<2: return False
    origin=points[0]
    return any(norm(sub(point,origin))>1e-3 for point in points[1:])

def _sample_rebound(samples,axis):
    values=[]
    for row in samples:
        try: values.append(velocity(row)[axis])
        except Exception: pass
    return any(v>1e-3 for v in values) and any(v<-1e-3 for v in values)
def gfield(s,key,default=None):
    g=s.get('game_state') if isinstance(s,dict) else None
    return g.get(key,default) if isinstance(g,dict) else default

class Case:
    def __init__(self,name,p):self.name=name;self.p=p;self.findings={};self.captures=[];self.details={}
    def put(self,ids,condition=True,reason='Observed public result',**facts):
        if isinstance(ids,str):ids=[ids]
        for key in ids:self.findings[key]=dict(machine_verdict='supported' if condition else 'fail',reason=reason,facts=facts)
    def review(self,ids,reason,**facts):
        if isinstance(ids,str):ids=[ids]
        for key in ids:self.findings[key]=dict(machine_verdict='review',reason=reason,facts=facts)
    def frame(self,label):
        result=self.p.capture(label);self.captures.append(result);return result
    def pulse(self,key,seconds):
        self.p.keys([key])
        try:return self.p.observe(seconds)
        finally:self.p.keys([])
    def nav(self):
        nav=Navigator(self.p);nav.calibrate();self.details['calibration']=nav.events;return nav
    def hit(self,nav):
        candidates=[]
        for t in TRAPS:
            try:candidates.append((len(route(cell(self.p.read()),t)),t))
            except ValueError:pass
        if not candidates:raise ObservationUncertain('NO_SAFE_APPROACH_TO_TRAP')
        target=min(candidates)[1];self.details.setdefault('trap_targets',[]).append(target)
        return nav.follow(target,stop_status='trap_hit')
    def restart(self,label):
        before=self.p.read();self.frame(label+'-before');start=len(self.p.samples);pressed_at=time.monotonic();self.p.press('R')
        before_round=gfield(before,'round_id')
        if before_round is None: raise ObservationUncertain('RESTART_ROUND_ID_UNAVAILABLE')
        self.p.wait(lambda s:gfield(s,'round_id') is not None and gfield(s,'round_id')!=before_round,2.5,'RESTART_NO_NEW_RUN')
        # Inspect the immediate reset samples before any fresh movement input.
        series=snapshots(self.p,start);self.frame(label+'-after')
        restored=next((s for s in series if fresh(s)),None)
        elapsed=time.monotonic()-pressed_at
        self.details[label]=dict(before=before,after=self.p.read(),fresh_observed=bool(restored),wall_seconds=elapsed,public_deadline_seconds=2.0)
        # The wall interval includes only the public input press, executor
        # transport and fresh authoritative snapshot.  A result over 2 s is a
        # candidate outcome; transport failures raise separately.
        return restored is not None and elapsed<=2.0
    def quit(self):
        self.frame('before-escape');self.p.keys(['Escape'])
        end=time.monotonic()+12
        while time.monotonic()<end:
            if not self.p.rpc('alive',pid=self.p.pid)['alive']:
                # The owned session cleanup releases any remaining key after exit.
                self.p.held.clear();return True
            time.sleep(.05)
        self.p.keys([]);return False

def execute(c):
    p=c.p;name=c.name;initial=p.read();origin=position(initial)
    c.frame('initial')
    if name=='entry':
        c.pulse('W',.12);c.frame('after-input')
        g=initial.get('game_state') or {}
        initial_cell=cell(initial) if isinstance(g.get('ball'),dict) and isinstance(g['ball'].get('grid_cell'),dict) else None
        c.put('D3-initial',initial_cell==(0,0) and g.get('status')=='running' and g.get('trap_hits')==0,initial=initial)
        c.review(['D2-board','D2-traps','D2-exit','D5-running'],'Inspect actual board, supplied mesh roles and current HUD; state alone cannot establish presentation.')
        # Runtime presentation gate: verify captured frame is non-black and
        # public state exposes an active sphere plus visible HUD.
        frame_ok=False; frame_black=None
        try: _,frame_black=image_info(c.p.root/'initial.png'); frame_ok=not frame_black
        except Exception: pass
        ball=g.get('ball') if isinstance(g,dict) else None; hud=g.get('hud') if isinstance(g,dict) else None
        ball_active=bool(isinstance(ball,dict) and ball.get('active'))
        hud_visible=bool(isinstance(hud,dict) and hud.get('visible'))
        c.details['runtime_presentation']=dict(initial_frame_nonblack=frame_ok,initial_frame_black=frame_black,ball_active=ball_active,hud_visible=hud_visible)
        presentation_facts=dict(runtime_frame_nonblack=frame_ok,ball_active=ball_active,hud_visible=hud_visible)
        if not frame_ok:
            c.put(['D2-board','D2-traps','D2-exit','D5-running'],False,'Captured runtime frame is black or unavailable; required scene cannot be visible.',**presentation_facts)
        else:
            c.review(['D2-board','D2-traps','D2-exit','D5-running'],'Inspect actual board, supplied mesh roles and current HUD; state alone cannot establish presentation.',**presentation_facts)
    elif name.startswith('direction-'):
        key=name[-1];nav=c.nav();setup,target=DIRECTION_SETUP[key]
        try:
            nav.follow(setup)
            setup_observed=cell(p.read())
            nav.move(target)
            target_observed=cell(p.read())
        except (CandidateError,ObservationUncertain) as exc:
            c.review('D3-directions','The public topology could not establish an open edge for this key; inspect the independent direction attempt.',key=key,setup=setup,target=target,error=str(exc))
            try: setup_observed=cell(p.read())
            except CandidateError: setup_observed=None
            target_observed=setup_observed
        start=len(p.samples);c.pulse(key,.28);released=p.read();c.frame('released')
        p.observe(.25);c.frame('coast');series=snapshots(p,start)
        direction_ok=setup_observed==setup and target_observed==target
        if 'D3-directions' not in c.findings:
            c.put('D3-directions',direction_ok,'The key reached the adjacent public cell in its prescribed direction.',key=key,setup=setup,target=target,setup_observed=setup_observed,target_observed=target_observed)
        if key=='W':
            c.put('D2-ball',norm(sub(position(released),origin))>1e-6,'A sphere translates after a real input; verify supplied mesh and visible motion.')
            c.review('D3-coast','Check continuous translation and post-release momentum; no private minimum travel/speed.',samples=len(series))
            c.review('D5-roll','Inspect successive actual frames for 3D shading and horizontal-axis rolling.')
    elif name=='countersteer':
        c.pulse('W',.35);c.frame('before-countersteer');v=velocity(p.read());start=len(p.samples)
        p.keys(['S'])
        try:
            p.wait(lambda s:dot(velocity(s),v)<0,8,'COUNTERSTEER_REVERSAL_UNOBSERVED')
            c.frame('after-countersteer')
        finally:p.keys([])
        series=snapshots(p,start)
        c.put('D3-countersteer',any(dot(velocity(s),v)>0 for s in series),'Reverse input initially opposes existing momentum.',sample_count=len(series))
    elif name in ('perimeter','internal'):
        nav=c.nav();key='S' if name=='perimeter' else 'D';axis=1 if key=='S' else 0;sign=-1 if key=='S' else 1
        start=len(p.samples);at=position(p.read());p.keys([key])
        try:
            p.wait(lambda s:sign*dot(sub(position(s),at),nav.axes[axis])>.25*nav.unit[axis],10,'IMPACT_APPROACH_UNOBSERVED')
            c.frame('before-impact')
        finally:p.keys([])
        p.wait(lambda s:sign*dot(velocity(s),nav.axes[axis])<0,8,'REBOUND_UNOBSERVED',consecutive=2)
        c.frame('after-impact');p.observe(.10);c.frame('rebounded')
        c.pulse('W' if name=='perimeter' else 'A',.25);c.frame('continued-control')
        c.put('D3-'+name,True,'Inward motion reversed after an approach with real input; verify wall contact and no penetration.',samples=len(p.samples)-start)
    elif name=='rim':
        nav=c.nav();target=(1,1);path=route((0,0),target)
        for waypoint,_ in path[:-1]:nav.move(waypoint)
        entry=path[-1][1];dx,dy={'W':(0,-.36),'S':(0,.36),'D':(-.36,0),'A':(.36,0)}[entry]
        c.frame('rim-approach');before=gfield(p.read(),'trap_hits')
        if before is None: raise ObservationUncertain('TRAP_COUNT_UNAVAILABLE')
        try:
            nav.move((target[0]+dx,target[1]+dy));c.frame('rim-contact');p.observe(.35);c.frame('rim-stable')
            current_hits=gfield(p.read(),'trap_hits')
            if current_hits is None: c.review('D3-safe-rim','Trap count was unavailable in the public snapshot; inspect paired frames.')
            else: c.put('D3-safe-rim',current_hits==before,'Only score this probe after visible ball-to-opening clearance is confirmed.')
        except CandidateError:
            c.frame('rim-response');c.review('D3-safe-rim','A proposed rim waypoint caused a hit. Verify actual sphere/opening clearance before assigning failure; probe coordinates are not requirements.')
    elif name=='trap':
        nav=c.nav();start=len(p.samples);before=gfield(p.read(),'trap_hits')
        if before is None: raise ObservationUncertain('TRAP_COUNT_UNAVAILABLE')
        hit=c.hit(nav);c.frame('trap-hit')
        c.put('D2-recovery',True);c.put('D3-opening',True,'Match first trap state with visible opening contact.')
        p.keys(['D']);p.observe(.13);c.frame('trap-lock');p.keys([])
        p.wait(lambda s:gfield(s,'status')=='running',2.5,'RECOVERY_UNFINISHED');after=p.read();c.frame('recovered')
        series=snapshots(p,start);hits=[s for s in series if gfield(s,'status')=='trap_hit']
        first=series.index(hits[0]);last=series.index(hits[-1]);prior=series[max(0,first-1)];following=series[min(len(series)-1,last+1)]
        lower=(hits[-1]['monotonic_ms']-hits[0]['monotonic_ms'])/1000
        upper=(following['monotonic_ms']-prior['monotonic_ms'])/1000
        timing=interval_verdict(lower,upper,.75,2.)
        if timing=='review':c.review('D3-hit-time','Sampling interval overlaps a public timing boundary.',lower=lower,upper=upper)
        else:c.put('D3-hit-time',timing=='pass',lower=lower,upper=upper)
        after_hits=gfield(after,'trap_hits'); hit_counts=[gfield(s,'trap_hits') for s in hits]
        if after_hits is None or any(v is None for v in hit_counts): c.review('D3-hit-count','Trap count was unavailable in one or more authoritative snapshots.')
        else: c.put('D3-hit-count',after_hits==before+1 and max(hit_counts)<=before+1,before=before,after=after_hits)
        locks=[gfield(s,'input_enabled') for s in hits]
        if any(v is None for v in locks): c.review('D3-hit-lock','Input-enabled field was unavailable during recovery.')
        else: c.put('D3-hit-lock',all(not v for v in locks),'Passive ball motion is permitted during recovery.')
        recovered=[s for s in series[last+1:] if gfield(s,'status')=='running']
        reset=any(cell(s)==(0,0) and norm(sub(position(s),origin))<1e-3 and norm(velocity(s))<1e-4 and norm(vec(s['game_state']['ball']['angular_velocity']))<1e-4 for s in recovered)
        if reset:c.put('D3-reset',True)
        else:c.review('D3-reset','The public publisher may have sampled after the reset frame. Check recovery evidence before inferring preserved momentum.')
        c.pulse('W',.25);c.frame('resumed');c.put('D4-resume',norm(sub(position(p.read()),origin))>1e-6)
        c.review('D5-trap','Read contemporaneous trap HUD and count, allowing one rendered frame of update latency.')
    elif name=='repeat-trap':
        nav=c.nav();c.hit(nav);c.frame('first-hit');p.wait(lambda s:gfield(s,'status')=='running',2.5,'RECOVERY_UNFINISHED')
        before=gfield(p.read(),'trap_hits')
        if before is None: raise ObservationUncertain('TRAP_COUNT_UNAVAILABLE')
        c.hit(nav);c.frame('second-hit');p.wait(lambda s:gfield(s,'status')=='running',2.5,'SECOND_RECOVERY_UNFINISHED')
        c.put('D3-repeat-hit',gfield(p.read(),'trap_hits')==before+1)
    elif name in ('journey','restart-terminal','exit-terminal'):
        nav=c.nav();start=len(p.samples);nav.follow((9,9),stop_status='maze_complete');c.frame('completed')
        completed=p.read()
        if name=='journey':
            c.put('D4-journey',True,'Normal input reached the fixed exit without a hidden state setter.')
            c.review('D3-goal','Confirm first terminal sample coincides with visible exit contact. Center may still be in an adjacent cell.')
            for key in ('W','A','S','D'):c.pulse(key,.15)
            p.observe(.35);c.frame('terminal-lock');after=p.read()
            c.put('D3-terminal',gfield(after,'status')=='maze_complete' and gfield(after,'trap_hits')==gfield(completed,'trap_hits') and norm(sub(position(after),position(completed)))<1e-3)
            c.review('D5-complete','Inspect persistent completion HUD and retained board after ordinary movement attempts.')
        elif name=='restart-terminal':
            c.put('D4-restart-terminal',c.restart('restart-terminal'));c.pulse('W',.2);c.frame('resumed')
        else:c.put('D4-exit-terminal',c.quit())
    elif name in ('restart-running','restart-repeat','restart-trap'):
        if name=='restart-trap':nav=c.nav();c.hit(nav);c.frame('trap-before-restart')
        else:c.pulse('W',.25)
        ok=c.restart(name)
        if name=='restart-repeat':
            for index in range(2):ok=c.restart('repeat-'+str(index)) and ok
        # Pass beyond the longest public recovery window, with fresh movement.
        c.pulse('W',.2);moved=position(p.read());p.observe(2.2);c.frame('after-old-deadline')
        s=p.read();ok=ok and gfield(s,'status')=='running' and gfield(s,'trap_hits')==0 and norm(sub(position(s),origin))>1e-6
        c.put('D4-'+name,ok)
        if name=='restart-running':c.review('D5-restart','Verify R - RESTART visibility and reset HUD at the captured fresh frame.')
    elif name=='exit-running':c.put('D4-exit-running',c.quit())
    elif name=='exit-trap':nav=c.nav();c.hit(nav);c.put('D4-exit-trap',c.quit())
    elif name=='camera':
        nav=c.nav();nav.move((0,1));c.frame('moved');p.rpc('pointer');p.observe(.15);c.frame('mouse-moved')
        c.review('D5-camera','Compare full-board orientation/framing/readability across these and restart/recovery/reopen frames; no fixed HUD placement.')
    elif name=='reopen':
        c.pulse('W',.3);c.frame('played');c.details['old_pid']=p.pid
    else:raise InfrastructureError('UNKNOWN_CASE')

def collect(args):
    root=Path(args.root).resolve();root.mkdir(parents=True,exist_ok=False)
    data=dict(version='4.0.0',catalog_sha256=sha(ROOT/'catalog/checkpoints.json'),cases=[],faults=[])
    names=args.cases.split(',') if args.cases else list(CASE_CHECKS)
    for name in names:
        print('Case:',name,flush=True)
        p=Player(args.pwsh,args.tools,args.engine,args.project,root/name);c=Case(name,p)
        try:
            p.start();execute(c)
        except ObservationUncertain as exc:
            c.details['uncertainty']=str(exc)
            # A calibration/waypoint timeout is not proof that the ball was
            # immobile.  If the synchronized samples already contain a real
            # displacement or velocity reversal, retain that positive result
            # for the independent movement/collision checkpoint and leave only
            # the unproven semantic assertion for review.
            sampled=snapshots(p,0)
            if name=='direction-W' and _sample_motion(sampled):
                c.put('D2-ball',True,'Synchronized samples show the supplied ball translated after input.')
            if name=='perimeter' and _sample_rebound(sampled,1):
                c.put('D3-perimeter',True,'Synchronized samples show perimeter-axis velocity reversal after approach.')
            if name=='internal' and _sample_rebound(sampled,0):
                c.put('D3-internal',True,'Synchronized samples show internal-axis velocity reversal after approach.')
            for key in CASE_CHECKS[name]:
                if key not in c.findings:c.review(key,str(exc))
        except CandidateError as exc:
            for key in CASE_CHECKS[name]:
                if key not in c.findings:c.findings[key]=dict(machine_verdict='unreachable',reason=str(exc),facts={})
        except Exception as exc:
            data['faults'].append(dict(case=name,code=type(exc).__name__,reason=str(exc)))
        finally:
            try:p.close()
            except CandidateError as exc:
                # A launch/stop timeout after the candidate already failed to
                # render is part of that candidate case, not host transport.
                c.details['candidate_cleanup']=str(exc)
            except InfrastructureError as exc:data['faults'].append(dict(case=name,reason=str(exc)))
        if name=='reopen' and not data['faults'] and 'old_pid' in c.details:
            newer=Player(args.pwsh,args.tools,args.engine,args.project,root/'reopen-new');second=Case('reopen-new',newer)
            try:
                s=newer.start();second.frame('fresh-process');second.pulse('W',.2);second.frame('new-input')
                c.put('D4-reopen',newer.pid!=c.details['old_pid'] and fresh(s) and norm(sub(position(newer.read()),position(s)))>1e-6)
                c.details['new_pid']=newer.pid
                # Keep the second process' captures in the parent case record
                # so reopen evidence is addressable and hash-bound by review
                # and D6 without treating it as a separate score row.
                for x in second.captures:
                    shutil.copyfile(newer.root/x['path'],c.p.root/x['path'])
                    context=dict(x); context['path']=x['path']; c.captures.append(context)
            except CandidateError as exc:c.put('D4-reopen',False,str(exc))
            finally:newer.close()
        entry=dict(id=name,findings=c.findings,captures=c.captures,details=c.details,
                   contract=CASE_CONTRACT.get(name,dict(max_actions=24,max_serial_seconds=45,setup_method='normal_input')),
                   samples_sha256=sha(p.root/'samples.json'),receipts_sha256=sha(p.root/'receipts.json'))
        data['cases'].append(entry);write(root/'collection.json',data)
        # Infrastructure invalidates score publication, but independent case
        # preparation bugs do not erase evidence already collected elsewhere.
    return data

if __name__=='__main__':
    p=argparse.ArgumentParser()
    for key in ('pwsh','tools','engine','project','root'):p.add_argument('--'+key,required=True)
    p.add_argument('--cases')
    result=collect(p.parse_args());raise SystemExit(2 if result['faults'] else 0)




