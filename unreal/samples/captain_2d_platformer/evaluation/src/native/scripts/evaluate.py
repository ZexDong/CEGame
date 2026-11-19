"""Bounded, independent normal-player journeys. No candidate implementation names are read."""
import argparse
import math
import os
import re
import shutil
import subprocess
import time
import statistics
from pathlib import Path
from runtime import (ROOT,TASK,REPO,Player,Observer,Budget,CandidateError,InfrastructureError,
                     load,write,sha,identity,inside,EXCLUDES,code_identity,cleanup_verified)

def field(g,path,default=None):
    for key in path.split('.'):
        if not isinstance(g,dict) or key not in g:return default
        g=g[key]
    return g
def num(g,path):
    n=field(g,path)
    return n if type(n) in (int,float) and math.isfinite(n) else math.nan
def game(s):
    g=field(s,'game_state',{})
    return g if isinstance(g,dict) else {}
def objects(g,path):
    value=field(g,path,[])
    if not isinstance(value,list) or any(not isinstance(x,dict) for x in value):
        raise CandidateError('MALFORMED_PUBLIC_STATE:'+path)
    return value
def fresh(g):
    enemies=field(g,'world.enemies',[])
    return (field(g,'phase')=='active' and num(g,'player.health.current')==100
        and num(g,'objective.keys_collected')==0 and field(g,'objective.key_present') is True
        and field(g,'objective.exit_state')=='locked' and field(g,'player.grounded') is True
        and all(num(g,'world.object_counts.'+k)==v for k,v in dict(player=1,key=1,exit=1,hazard=2,enemy=1,spring=1,one_way_platform=3).items())
        and isinstance(enemies,list) and len(enemies)==1 and num(enemies[0],'health.current')==50)
def span(samples,path):
    values=[num(game(s),path) for s in samples]
    return max(values)-min(values) if values and all(math.isfinite(x) for x in values) else math.inf

class Evaluation:
    def __init__(self,args):
        self.args=args;self.root=args.output.resolve();self.p=None;self.o=None
        self.catalog=load(ROOT/'scoring-catalog.json');self.budget=Budget();self.facts={};self.captures={};self.journeys=[]
        self.verdicts={c['id']:dict(id=c['id'],dimension=c['dimension'],verdict='unreachable',
            reason='CANDIDATE_PRECONDITION_UNREACHABLE',attribution='candidate',evidence=[]) for c in self.catalog['checkpoints']}
        self.seq=0;self.sx=math.nan;self.sy=math.nan;self.tx=math.nan;self.ty=math.nan;self.initial=None
        self.loaded_identity=code_identity()
        self.candidate_id=None
    def progress(self,message):
        try:
            with (self.root/'collector-events.jsonl').open('a',encoding='utf-8') as stream:
                import json
                stream.write(json.dumps(dict(message=message,elapsed_seconds=self.budget.report()['elapsed_seconds']))+'\n')
        except OSError:pass
        # Terminal output is optional; a closed output pipe is not a game fault.
        try:print(message,flush=True)
        except (OSError,ValueError):pass
    def checkpoint(self):
        write(self.root/'raw-evaluation.json',self.raw_record('running',None,False))
    def raw_record(self,status,invalid,cleaned):
        return dict(schema_version='2.0.0',run_id=self.root.name,status=status,
            fault=invalid,candidate_identity_sha256=self.candidate_id['sha256'] if self.candidate_id else None,
            catalog_sha256=sha(ROOT/'scoring-catalog.json'),runtime_identity=self.loaded_identity,
            gdd_sha256=sha(TASK/'input/GDD.md'),checkpoints=list(self.verdicts.values()),captures=self.captures,
            journeys=self.journeys,budget=self.budget.report(),cleanup_confirmed=cleaned,read_only_errors=self.o.errors if self.o else [])
    def mark(self,id,ok,reason,*evidence):
        self.verdicts[id].update(verdict='pass' if ok else 'fail',reason=reason,evidence=list(evidence))
    def name(self,n):self.seq+=1;return f'{self.seq:03}-{n}'
    def wait(self,n,p,timeout=3,stable=1):return self.o.wait(self.name(n),p,timeout,stable)
    def window(self,n,seconds):return self.o.window(self.name(n),seconds)
    def press(self,k):self.p.call('press',key=k)
    def cap(self,n):
        self.captures[n]=self.p.capture(n);return self.captures[n]
    def g(self):return game(self.o.last)
    def xy(self,g=None):
        g=self.g() if g is None else g
        return self.point(g,field(g,'player',{}))
    def projection(self,g):
        ledges=sorted([t for t in objects(g,'world.visible_targets') if field(t,'semantic_role')=='one_way_platform' and field(t,'present') is True],key=lambda t:num(t,'normalized_position.y'),reverse=True)
        if len(ledges)!=3:raise CandidateError('LEDGES_MISSING_FOR_ROOM_PROJECTION')
        b=field(ledges[0],'normalized_bounds',{});sx=(num(b,'right')-num(b,'left'))/32;sy=sx*1280/720
        tx=num(b,'left')-640*sx;ty=num(b,'top')-368*sy
        if not .0001<sx<.01 or not all(math.isfinite(v) for v in (sx,sy,tx,ty)):raise CandidateError('INVALID_ROOM_PROJECTION')
        return sx,sy,tx,ty
    def point(self,g,obj):
        sx,sy,tx,ty=self.projection(g)
        return (num(obj,'normalized_position.x')-tx)/sx,(num(obj,'normalized_position.y')-ty)/sy
    def position_span(self,seq,axis=0):
        points=[self.xy(game(s))[axis] for s in seq]
        return max(points)-min(points) if points else math.inf
    def targets(self,role):
        return [t for t in objects(self.g(),'world.visible_targets') if field(t,'semantic_role')==role and field(t,'present') is True]
    def calibrate(self):
        # The public art fixes 32-pixel ledges and their relative locations. Recover
        # the candidate's uniform client projection from semantic geometry.
        self.sx,self.sy,self.tx,self.ty=self.projection(self.g())
        self.facts['projection']=dict(sx=self.sx,sy=self.sy,tx=self.tx,ty=self.ty,
            basis='Public lower ledge geometry (32 source pixels), uniform scaling, normalized client coordinates')
    def restart(self,n,strict=False):
        old=self.wait(n+'-before',lambda g:True,2)
        if not old:raise CandidateError('NO_FRESH_STATE_BEFORE_RESTART')
        deaths=num(game(old),'session.deaths');self.press('R')
        # A new active round is sufficient preparation for an independent route.
        # Missing unrelated objects must not prevent, for example, walking tests.
        predicate=fresh if strict else lambda g:field(g,'phase')=='active' and field(g,'player.grounded') is True
        s=self.wait(n,predicate,5,2)
        # A normal R input must establish a new active round.  Some candidates
        # and input transports expose two restart notifications for one tap;
        # that is a lifecycle defect checked by the strict post-completion
        # cases, but it must not make every independent feature unreachable.
        # Keep the round/death freshness contract for ordinary feature setup.
        restart_ok = (s and s['round_id']!=old['round_id'] and
            s['round_index']>old['round_index'] and
            (s['restart_count']>old['restart_count'] if not strict else s['restart_count']==old['restart_count']+1) and
            num(game(s),'session.deaths')==deaths)
        if not restart_ok:
            raise CandidateError('RESTART_NOT_CLEAN:'+n)
        if s['restart_count']!=old['restart_count']+1:
            self.facts.setdefault('restart_deltas',[]).append(dict(route=n,delta=s['restart_count']-old['restart_count']))
        return s
    def move(self,x,n,timeout=5,tolerance=4,stop_on_completion=False):
        start=self.xy()[0]
        if abs(start-x)<=tolerance:return self.o.last
        key='D' if x>start else 'A'
        self.p.call('down',key=key)
        try:
            s=self.wait(n,lambda g:(self.xy(g)[0]>=x-tolerance if key=='D' else self.xy(g)[0]<=x+tolerance) or (stop_on_completion and field(g,'phase')=='completed'),timeout)
            if not s:raise CandidateError('MOVEMENT_TARGET_UNREACHABLE:'+n)
            return s
        finally:self.p.call('up',key=key)
    def jump(self,x,n,top=None):
        before=self.xy();self.press('Space')
        if not self.wait(n+'-air',lambda g:field(g,'player.grounded') is False,2):raise CandidateError('JUMP_UNAVAILABLE:'+n)
        self.move(x,n+'-steer',3)
        landed=self.wait(n+'-land',lambda g:field(g,'player.grounded') is True,3,2)
        if not landed:raise CandidateError('LANDING_UNREACHABLE:'+n)
        if top is not None and abs(self.xy()[1]+self.player_half_height()-top)>7:raise CandidateError('WRONG_LANDING_SURFACE:'+n)
        return landed
    def fine_move(self,x,n,tolerance=2):
        for i in range(16):
            self.wait(n+'-fresh',lambda g:True,1,2)
            dx=x-self.xy()[0]
            if abs(dx)<=tolerance:return
            self.p.call('tap',key='D' if dx>0 else 'A',duration_ms=max(1,min(20,int(abs(dx)*4)-5)))
        raise CandidateError('FINE_POSITION_UNREACHABLE:'+n)
    def player_half_height(self):
        t=self.targets('player')
        if not t:return 12
        b=t[0].get('normalized_bounds') or {}
        h=(num(b,'bottom')-num(b,'top'))/self.projection(self.g())[1]/2
        return h if 4<h<30 else 12
    def corridor(self,n):
        self.move(329,n+'-divider-approach');self.jump(407,n+'-divider',448)
    def kill_pig(self,n):
        for i in range(16):
            enemies=objects(self.g(),'world.enemies')
            if num(self.g(),'world.object_counts.enemy')==0:return True
            if not enemies:return False
            ex=self.point(self.g(),enemies[0])[0]
            px=self.xy()[0];dx=ex-px
            if abs(dx)>36:self.move(ex-(35 if dx>0 else -35),n+f'-approach-{i}',2,2)
            desired='right' if dx>0 else 'left'
            if field(self.g(),'player.facing')!=desired:self.press('D' if dx>0 else 'A')
            if field(self.g(),'player.movement_state')=='hit':self.wait(n+'-hit-resolved',lambda g:field(g,'player.movement_state')!='hit',1)
            self.press('Z');self.window(n+f'-swing-{i}',.06)
            self.wait(n+f'-swing-end-{i}',lambda g:field(g,'player.attacking') is False,.5)
        return num(self.g(),'world.object_counts.enemy')==0
    def spring(self,n):
        self.move(653,n+'-contact',6,2)
        boosted=self.wait(n+'-boost',lambda g:field(g,'player.grounded') is False,3)
        if not boosted:raise CandidateError('SPRING_NO_BOOST')
        self.cap(n+'-boost')
        self.mark('D2-05',True,'SPRING_BASIC_USE',f'captures/{n}-boost.png')
        s=self.wait(n+'-lower-landing',lambda g:field(g,'player.grounded') is True,3,2)
        if not s or abs(self.xy()[1]+self.player_half_height()-368)>7:raise CandidateError('SPRING_LOWER_LEDGE_UNREACHABLE')
        return s
    def climb(self,n):
        self.spring(n)
        self.cap(n+'-lower')
        if n in ('traversal','repeat'):
            # From the lower ledge a straight ordinary jump intersects the
            # upper ledge's underside without reaching the ceiling spikes.
            probe_begin=len(self.o.samples);base=self.xy()[1];self.press('Space')
            self.wait(n+'-upper-underside',lambda g:self.xy(g)[1]<292,1)
            self.cap(n+'-upper-underside')
            self.wait(n+'-probe-lower-land',lambda g:field(g,'player.grounded') is True,2,2)
            rise=base-min(self.xy(game(s))[1] for s in self.o.samples[probe_begin:])
            self.facts.setdefault('upper_underside_probes',[]).append(rise>65)
        # Landing on the upper ledge is sensitive to a few milliseconds of
        # input delivery. Keep the check atomic, but use five bounded,
        # public-input steering profiles so a normal transport jitter does not
        # turn a valid implementation into an unreachable route.
        profiles=((35,633),(45,639),(55,645),(65,639),(75,633))
        for approach,(launch_tap,target_x) in enumerate(profiles):
            if abs(self.xy()[1]+self.player_half_height()-320)>7:self.jump(594,n+'-middle',320)
            self.cap(n+'-middle'+(f'-retry-{approach}' if approach else ''));self.fine_move(602,n+'-middle-edge')
            health=num(self.g(),'player.health.current')
            # Stay under the platform while rising; an early right impulse
            # collides with its solid underside before the player can land.
            self.press('Space');self.p.call('tap',key='D',duration_ms=launch_tap)
            def clear_on_arrival(g):
                if field(g,'player.movement_state')!='falling':return False
                x,y=self.xy(g)
                # Predict only normal travel to the public spike boundary, using
                # the public jump/gravity scale. This accounts for the distance
                # still to travel instead of waiting until already too low.
                apex=320-self.player_half_height()-370**2/(2*980)
                vy=math.sqrt(max(0,2*980*(y-apex)))
                dt=max(0,(target_x-x)/250)
                return y+vy*dt+.5*980*dt*dt-self.player_half_height()>240
            if not self.wait(n+'-ceiling-clear',clear_on_arrival,2):raise CandidateError('UPPER_LEDGE_APPROACH_UNREACHABLE')
            dx=target_x-self.xy()[0]
            self.p.call('tap',key='D',duration_ms=max(1,min(110,int(dx*4)-5)))
            landed=self.wait(n+'-upper-land',lambda g:field(g,'player.grounded') is True and abs(self.xy(g)[1]+self.player_half_height()-278)<7,2,2)
            if landed:break
            # A missed ordinary jump can be recovered within the same attempt.
            # No restart, teleport, invulnerability or altered scoring is used.
            if num(self.g(),'player.health.current')!=health or field(self.g(),'player.grounded') is not True or abs(self.xy()[1]+self.player_half_height()-368)>7:
                raise CandidateError('UPPER_LEDGE_LANDING_UNREACHABLE')
            self.facts.setdefault('navigation_recoveries',[]).append(dict(route=n,attempt=approach+1,reason='FELL_BACK_TO_LOWER_LEDGE'))
        else:raise CandidateError('UPPER_LEDGE_LANDING_UNREACHABLE')
        self.cap(n+'-upper')
        self.mark('D2-06',True,'THREE_LEDGES_BASIC_USE',f'captures/{n}-lower.png',f'captures/{n}-middle.png',f'captures/{n}-upper.png')
        self.fine_move(638,n+'-upper-left-edge',1.5)
        try:
            self.p.call('chord',held='A',key='Space')
            if not self.wait(n+'-column-cross',lambda g:self.xy(g)[0]<556,3):raise CandidateError('COLUMN_UNREACHABLE')
        finally:self.p.call('up',key='A')
        if not self.wait(n+'-column-land',lambda g:field(g,'player.grounded') is True and abs(self.xy(g)[1]+self.player_half_height()-256)<7,3,2):raise CandidateError('COLUMN_LANDING_UNREACHABLE')
        self.cap(n+'-column')
        self.move(493,n+'-column-left',3,2)
    def collect(self,n,return_to_shelf=True,avoid_enemy=False):
        # Walk off the column into the key's visible gap, then steer onto the shelf.
        self.move(451,n+'-key-gap',3,2)
        key=self.wait(n+'-key',lambda g:num(g,'objective.keys_collected')==1,2)
        if not key:raise CandidateError('KEY_UNREACHABLE')
        self.cap(n+'-key-feedback')
        self.move(617 if avoid_enemy else 400,n+'-shelf',3,2)
        self.wait(n+'-shelf-land',lambda g:field(g,'player.grounded') is True,3,2)
        if return_to_shelf and self.xy()[1]+self.player_half_height()>295:
            self.climb(n+'-return')
            self.jump(402,n+'-return-shelf',288)
        return key
    def isolated(self,n,method):
        self.progress('Running '+n)
        # Narrow navigation/contact misses are sensitive to frame delivery and
        # enemy timing. Give the same independent route one bounded fresh-round
        # recovery, while leaving all semantic assertions and true gameplay
        # failures strict. This keeps a jittery path from blocking unrelated
        # checkpoints without turning an unreachable implementation into pass.
        retry_codes=('SPRING_NO_BOOST','SPRING_LOWER_LEDGE_UNREACHABLE',
            'UPPER_LEDGE_APPROACH_UNREACHABLE','UPPER_LEDGE_LANDING_UNREACHABLE',
            'COLUMN_UNREACHABLE','COLUMN_LANDING_UNREACHABLE',
            'LANDING_UNREACHABLE','MOVEMENT_TARGET_UNREACHABLE:locked-door',
            'KEY_UNREACHABLE')
        def clear_retry_captures(before_keys):
            # Capture artifacts are immutable per receipt. A retry gets a
            # clean output name while retaining the final attempt's evidence.
            for key in list(self.captures):
                if key not in before_keys:
                    for suffix in ('.png','.context.json'):
                        try:(self.root/'captures'/(key+suffix)).unlink()
                        except FileNotFoundError:pass
                    self.captures.pop(key,None)
        for attempt in range(2):
            begin=len(self.o.samples) if self.o else 0
            capture_keys_before=set(self.captures)
            try:
                method();self.journeys.append(dict(id=n,status='completed',attempts=attempt+1));return
            except CandidateError as e:
                reason=str(e)
                if attempt==0 and any(reason.startswith(code) for code in retry_codes):
                    self.facts.setdefault('route_recoveries',[]).append(dict(route=n,reason=reason,attempt=1))
                    clear_retry_captures(capture_keys_before)
                    self.checkpoint();continue
                self.journeys.append(dict(id=n,status='candidate_failure',reason=reason,attempts=attempt+1));return
            except (KeyError,TypeError,ValueError,IndexError,AttributeError) as e:
                # Historical observation errors must not excuse an unrelated driver bug.
                from schema import errors
                current_errors=errors(self.o.last,self.o.schema) if self.o and self.o.last is not None else []
                if current_errors:
                    self.journeys.append(dict(id=n,status='candidate_failure',reason='MALFORMED_PUBLIC_STATE',details=current_errors));return
                raise
            finally:
                if self.o:write(self.root/'journeys'/f'{n}.json',dict(samples=self.o.samples[begin:]))
                self.checkpoint()
    def initial_state(self):
        s=self.wait('initial-provider',lambda g:field(g,'phase')=='active',5,2)
        if not s:raise CandidateError('PROVIDER_MISSING_OR_INVALID')
        self.initial=s;self.facts['initial']=s
        self.mark('D3-01',fresh(self.g()),'FRESH_ATTEMPT_COUNTS_AND_VALUES','journeys/initial.json')
        self.cap('initial');self.window('initial-visible',.2);self.cap('initial-later')
        self.mark('D2-01',True,'ROOM_REQUIRES_RUNTIME_PICTURE_REVIEW','captures/initial.png','captures/initial-later.png')
        self.mark('D5-01',True,'HUD_REQUIRES_RUNTIME_PICTURE_REVIEW','captures/initial.png')
        # Room/HUD pictures and initial values do not require navigation geometry.
        self.calibrate()
    def basic_movement(self):
        # Qualitative movement has no dependency on room projection. Exact
        # speed, collision and jump-arc checks still require valid geometry.
        self.restart('basic-movement-start')
        origin=num(self.g(),'player.normalized_position.x')
        if not math.isfinite(origin):raise CandidateError('PLAYER_POSITION_UNAVAILABLE')
        self.p.call('down',key='A')
        try:
            left=self.wait('basic-left',lambda g:num(g,'player.normalized_position.x')<origin-.01 and field(g,'player.facing')=='left',2)
            self.cap('walk-left')
        finally:self.p.call('up',key='A')
        origin=num(self.g(),'player.normalized_position.x')
        self.p.call('down',key='D')
        try:
            right=self.wait('basic-right',lambda g:num(g,'player.normalized_position.x')>origin+.01 and field(g,'player.facing')=='right',2)
            self.cap('running')
        finally:self.p.call('up',key='D')
        self.press('Space')
        air=self.wait('basic-airborne',lambda g:field(g,'player.grounded') is False,2)
        if air:self.cap('airborne')
        land=self.wait('basic-landed',lambda g:field(g,'player.grounded') is True,3,2)
        self.cap('landed')
        usable=bool(left and right and air and land)
        self.mark('D2-02',usable,'MOVE_JUMP_BASIC_USE_WITHOUT_ROOM_PROJECTION','journeys/movement.json')
        self.mark('D5-02',usable,'MOVEMENT_FEEDBACK_REVIEW','captures/walk-left.png','captures/airborne.png','captures/landed.png')
    def movement(self):
        self.restart('movement-start');start=self.xy()
        self.p.call('down',key='A')
        try:
            left=self.wait('walk-left',lambda g:self.xy(g)[0]<start[0]-20,2);self.cap('walk-left')
            wall=self.wait('left-wall',lambda g:self.xy(g)[0]<205,2)
            blocked=self.window('left-wall-held',.5)
        finally:self.p.call('up',key='A')
        self.p.call('down',key='D')
        try:
            walk=self.window('walk-right',.25);self.cap('running')
        finally:self.p.call('up',key='D')
        released=self.window('release-stable',.4);self.cap('released')
        speed=self.speed(walk,'player.normalized_position.x',self.sx)
        ok=bool(left and wall and len(walk)>1 and self.position_span(blocked)<2 and self.position_span(released[1:])<2)
        ok=ok and field(game(left),'player.facing')=='left' and field(game(walk[-1]),'player.facing')=='right' and 225<=speed<=275
        self.mark('D3-02',ok,'MOVEMENT_DIRECTION_SPEED_STOP_COLLISION','journeys/movement.json')
        self.restart('jump-start');base=self.xy();self.press('Space')
        air=self.wait('airborne',lambda g:field(g,'player.grounded') is False,2)
        if air:self.cap('airborne')
        self.press('Space');arc=self.window('jump-repeat-arc',.28)
        self.p.call('down',key='D')
        try:steering=self.window('air-steering',.1)
        finally:self.p.call('up',key='D')
        land=self.wait('jump-land',lambda g:field(g,'player.grounded') is True,3,2);self.cap('landed')
        allarc=[s for s in self.o.samples if air and s['snapshot_id']>=air['snapshot_id']]
        fit=self.arc_fit(allarc)
        self.p.call('down',key='Space')
        try:held=self.window('held-jump',1.7)
        finally:self.p.call('up',key='Space')
        endground=bool(held) and all(field(game(s),'player.grounded') is True for s in held[-3:])
        apex=min((self.xy(game(s))[1] for s in allarc),default=math.inf)
        jumpok=bool(air and land and len(steering)>1 and self.position_span(steering)>8 and 58<base[1]-apex<80 and endground and fit['valid'])
        self.facts['jump_fit']=fit
        self.mark('D2-02',bool(left and air and land),'MOVE_JUMP_BASIC_USE','journeys/movement.json')
        self.mark('D3-03',jumpok,'JUMP_ARC_AIR_REJECTION_STEERING_LANDING','journeys/movement.json')
        self.mark('D5-02',bool(left and air and land),'MOVEMENT_FEEDBACK_REVIEW','captures/walk-left.png','captures/airborne.png','captures/landed.png')
    def speed(self,seq,path,scale):
        if len(seq)<2:return math.nan
        rates=[]
        for a,b in zip(seq,seq[1:]):
            dt=(b['monotonic_ms']-a['monotonic_ms'])/1000
            if .015<dt<.15:
                distance=abs(self.xy(game(b))[0]-self.xy(game(a))[0]) if path=='player.normalized_position.x' else abs(num(game(b),path)-num(game(a),path))/scale
                rates.append(distance/dt)
        # Input delivery and publication are asynchronous. A single sample from
        # before key-down must not reduce a constant-speed interval's estimate.
        return statistics.median(rates) if rates else math.nan
    def arc_fit(self,seq):
        # Second divided differences estimate gravity without a prescribed candidate timestep.
        pts=[((s['monotonic_ms']-seq[0]['monotonic_ms'])/1000,self.xy(game(s))[1]) for s in seq if field(game(s),'player.grounded') is False] if seq else []
        if len(pts)<6:return dict(valid=False,reason='insufficient_arc_samples')
        a,b,c=pts[0],pts[len(pts)//2],pts[-1]
        if min(b[0]-a[0],c[0]-b[0])<.04:return dict(valid=False,reason='insufficient_arc_span')
        acceleration=2*((c[1]-b[1])/(c[0]-b[0])-(b[1]-a[1])/(b[0]-a[0]))/(c[0]-a[0])
        return dict(valid=780<=acceleration<=1180,gravity_pixels_per_second_squared=acceleration)

    def patrol(self):
        self.restart('patrol-start');seq=self.window('patrol-both-boundaries',12.5);self.cap('patrol')
        observations=[]
        for s in seq:
            e=objects(game(s),'world.enemies')
            if len(e)!=1:continue
            ex,ey=self.point(game(s),e[0]);observations.append((s,e[0],ex,ey))
        directions={field(e,'facing') for s,e,x,y in observations};speeds=[]
        for a,b in zip(observations,observations[1:]):
            dt=(b[0]['monotonic_ms']-a[0]['monotonic_ms'])/1000
            if .015<dt<.4 and field(a[1],'facing')==field(b[1],'facing'):speeds.append(abs(b[2]-a[2])/dt)
        median=sorted(speeds)[len(speeds)//2] if speeds else math.nan
        ok=bool(observations) and directions=={'left','right'} and min(x for s,e,x,y in observations)<405 and max(x for s,e,x,y in observations)>650
        ok=ok and all(383<x<673 and 420<y<449 for s,e,x,y in observations) and 44<=median<=56
        self.facts['patrol_speed']=median if math.isfinite(median) else None
        self.mark('D3-05',ok,'PATROL_SPEED_TURNS_AND_FLOOR','journeys/patrol.json')

    def combat(self):
        self.restart('combat-start');combat_begin=len(self.o.samples)
        enemies=objects(self.g(),'world.enemies')
        if len(enemies)!=1:raise CandidateError('ENEMY_MISSING_FOR_COMBAT')
        enemy0=num(enemies[0],'health.current')
        self.press('Z');self.cap('sword');self.press('Z')
        self.p.call('down',key='D')
        try:locked=self.window('sword-lock',.08)
        finally:self.p.call('up',key='D')
        misses=self.window('miss-stable',.35);self.cap('sword-resolved')
        miss=bool(misses) and all(len(objects(game(s),'world.enemies'))==1 and num(objects(game(s),'world.enemies')[0],'health.current')==enemy0 for s in misses)
        # Runtime filmstrip for the source's unordered sword variations.
        for variant_probe in range(8):
            self.press('Z');self.cap(f'sword-variation-{variant_probe}');self.window(f'sword-variation-{variant_probe}',.22)
        self.move(343,'wall-sword-position')
        nearwall=self.wait('pig-near-divider',lambda g:bool(field(g,'world.enemies')) and self.point(g,field(g,'world.enemies')[0])[0]<411,10)
        wall_samples=[]
        for i in range(2):self.press('Z');wall_samples+=self.window(f'wall-sword-{i}',.25)
        self.cap('wall-sword-miss')
        wall_miss=bool(nearwall and wall_samples) and all(len(objects(game(s),'world.enemies'))==1 and num(objects(game(s),'world.enemies')[0],'health.current')==50 for s in wall_samples)
        self.corridor('combat');self.cap('pig-encounter')
        before=len(self.o.samples);killed=self.kill_pig('combat');self.cap('pig-dead')
        strikes=self.o.samples[before:];changes=[];last=50
        for s in strikes:
            es=field(game(s),'world.enemies',[]);hp=num(es[0],'health.current') if es else 0
            if hp<last:changes.append((last,hp,last-hp));last=hp
        after=self.window('dead-pig-stability',1.3);dead_stable=killed and all(num(game(s),'world.object_counts.enemy')==0 and num(game(s),'objective.keys_collected')==0 for s in after)
        attack_pairs=[(a,b) for a,b in zip(self.o.samples[combat_begin:],self.o.samples[combat_begin+1:]) if field(game(a),'player.attacking') is True and field(game(b),'player.attacking') is True and b['monotonic_ms']-a['monotonic_ms']<150]
        attack_stationary=bool(attack_pairs) and all(abs(self.xy(game(b))[0]-self.xy(game(a))[0])<2 for a,b in attack_pairs)
        self.facts['combat']=dict(damage_transitions=changes,miss_unchanged=miss,wall_miss_unchanged=wall_miss,dead_stable=dead_stable,attack_stationary=attack_stationary)
        self.mark('D2-03',bool(changes),'SWORD_CONNECTED_BASIC_USE','journeys/combat.json')
        rule=miss and wall_miss and attack_stationary and killed and bool(changes) and all(d in (25,45) or hp==0 and old<=45 for old,hp,d in changes)
        self.mark('D3-04',rule,'SWORD_DAMAGE_MISS_AND_LOCK_PLUS_RANGE_REVIEW','journeys/combat.json','captures/sword.png')
        self.facts['pig_killed']=killed;self.facts['pig_dead_stable']=dead_stable
        self.mark('D2-10',killed,'CAPTAIN_PIG_ACTION_ART_REVIEW','journeys/combat.json','captures/sword.png','captures/pig-dead.png')

    def enemy_damage(self):
        self.restart('enemy-damage-start');self.corridor('enemy-damage')
        for i in range(4):
            e=field(self.g(),'world.enemies',[])
            if not e:raise CandidateError('ENEMY_MISSING')
            ex=self.point(self.g(),e[0])[0]
            self.move(ex-12,'enemy-contact',2)
            hit=self.wait('pig-hit',lambda g:num(g,'player.health.current')<100,2)
            if hit:break
        else:raise CandidateError('PIG_ATTACK_UNREACHABLE')
        self.cap('enemy-hit');first=num(game(hit),'player.health.current');death0=num(game(hit),'session.deaths')
        dying=self.wait('pig-lethal',lambda g:field(g,'phase')=='dying',4)
        if dying:self.cap('death')
        respawn=self.wait('pig-respawn',fresh,4,2);self.cap('respawn')
        stable=self.window('respawn-stable',1)
        died=bool(dying and respawn) and num(game(respawn),'session.deaths')==death0+1
        self.facts['enemy_damage']=dict(first_health=first if math.isfinite(first) else None,died=died)
        self.mark('D2-04',bool(hit and died and self.facts.get('pig_killed')),'PIG_PATROL_COMBAT_DEATH_PRESENT','journeys/enemy-damage.json','journeys/combat.json')
        self.mark('D3-06',first==45 and died and self.facts.get('pig_dead_stable',False),'PIG_55_DAMAGE_AND_DEAD_INERT','journeys/enemy-damage.json','journeys/combat.json')
        self.mark('D3-10',died and all(num(game(s),'session.deaths')==death0+1 and fresh(game(s)) for s in stable),'LETHAL_ONCE_RESET_VALUES','journeys/enemy-damage.json')
        self.mark('D4-02',died and respawn['round_id']!=hit['round_id'],'FAILURE_TO_SAFE_PLAYABLE_ATTEMPT','journeys/enemy-damage.json')
        self.mark('D5-03',died,'DAMAGE_DEATH_HUD_PICTURE_REVIEW','captures/enemy-hit.png','captures/death.png','captures/respawn.png')

    def traversal(self):
        self.restart('traversal-start');self.corridor('traversal');self.kill_pig('traversal')
        # Steer a spring ascent below the middle ledge. A solid underside would
        # stop the captain near y=338 instead of allowing the observed apex.
        probe_begin=len(self.o.samples);self.move(653,'middle-probe-spring',6,2)
        self.wait('middle-probe-boost',lambda g:field(g,'player.grounded') is False,3)
        self.move(604,'middle-probe-steer',3,2)
        self.wait('middle-probe-clear',lambda g:self.xy(g)[1]<328,1)
        self.cap('middle-underside');self.wait('middle-probe-floor',lambda g:field(g,'player.grounded') is True and self.xy(g)[1]>420,3,2)
        middle_clear=min(self.xy(game(s))[1] for s in self.o.samples[probe_begin:])<314
        self.facts['middle_underside_clear']=middle_clear
        health_before=num(self.g(),'player.health.current')
        start=len(self.o.samples);self.climb('traversal');first=self.o.samples[start:]
        self.mark('D2-05',True,'SPRING_BASIC_USE','journeys/traversal.json')
        self.mark('D2-06',True,'THREE_LEDGES_BASIC_USE','journeys/traversal.json')
        # Repeat each surface and boost after a genuine separate floor contact.
        self.move(617,'descend-shaft');self.wait('descend-floor',lambda g:field(g,'player.grounded') is True and self.xy(g)[1]>420,4,2)
        second_start=len(self.o.samples);self.climb('repeat');second=self.o.samples[second_start:]
        def launch_speed(samples):
            # Sampling can begin after the launch impulse. Recover the impulse
            # from measured ascent velocity and height above the public floor.
            air=[s for s in samples if 635<self.xy(game(s))[0]<675 and 356<self.xy(game(s))[1]<436 and field(game(s),'player.grounded') is False]
            estimates=[]
            for a,b in zip(air,air[1:]):
                dt=(b['monotonic_ms']-a['monotonic_ms'])/1000
                ya,yb=self.xy(game(a))[1],self.xy(game(b))[1]
                if .015<dt<.2 and yb<ya:
                    vy=(yb-ya)/dt;mid=(ya+yb)/2
                    estimates.append(math.sqrt(vy*vy+2*980*(448-self.player_half_height()-mid)))
            return statistics.median(estimates) if estimates else 0
        boosts=[launch_speed(first),launch_speed(second)]
        self.facts['spring_reconstructed_launch_speeds']=boosts
        springok=all(475<v<525 for v in boosts) and num(self.g(),'player.health.current')==health_before
        self.mark('D3-07',springok,'SPRING_LOCAL_BOOST_AND_REPEAT','journeys/traversal.json')
        self.mark('D3-08',bool(first and second) and middle_clear and len(self.facts.get('upper_underside_probes',[]))==2 and all(self.facts['upper_underside_probes']),'ALL_LEDGES_UPWARD_PASS_AND_REPEAT_LANDINGS','journeys/traversal.json')
        self.mark('D5-06',True,'TRAVERSAL_PICTURE_REVIEW','captures/traversal-boost.png','captures/traversal-middle.png','captures/traversal-upper.png')

    def success(self):
        self.restart('success-start');round_id=self.o.last['round_id'];self.corridor('success');self.kill_pig('success');self.climb('success')
        key=self.collect('success',avoid_enemy=True);self.cap('key-pickup')
        opened=self.wait('door-open',lambda g:field(g,'objective.exit_state')=='open',2,2);self.cap('door-open')
        before_exit=self.window('key-single-use-stable',.8)
        stable=bool(opened and before_exit) and all(num(game(s),'objective.keys_collected')==1 and not field(game(s),'objective.key_present') and field(game(s),'phase')=='active' for s in before_exit)
        self.mark('D3-11',stable,'PICKUP_SINGLE_USE_DOOR_STAYS_OPEN','journeys/success.json')
        self.move(260,'open-exit',4,stop_on_completion=True)
        completed=self.wait('completed',lambda g:field(g,'phase')=='completed',2,2);self.cap('completed')
        self.facts['success']=bool(completed);self.facts['success_round']=round_id
        self.mark('D4-01',bool(completed) and completed['round_id']==round_id,'ENTRY_TO_SUCCESS_WITHOUT_RESTART_OR_DEATH','journeys/success.json')
        self.mark('D2-08',bool(completed),'OBJECTIVE_CONTENT_BASIC_USE','journeys/success.json')
        self.mark('D2-11',bool(completed),'OBJECTIVE_HUD_ART_REVIEW','captures/key-pickup.png','captures/door-open.png','captures/completed.png')
        self.mark('D5-04',bool(completed),'KEY_DOOR_PICTURE_REVIEW','captures/key-pickup.png','captures/door-open.png')
        self.mark('D5-05',bool(completed),'COMPLETION_AND_RESTART_PICTURE_REVIEW','captures/completed.png')
        if not completed:raise CandidateError('COMPLETION_UNREACHABLE')
        self.p.call('down',key='D')
        try:self.press('Space');self.press('Z');terminal=self.window('terminal-pollution',1.4)
        finally:self.p.call('up',key='D')
        t=game(completed)
        terminal_ok=bool(terminal) and all(field(game(s),'phase')=='completed' and field(game(s),'objective')==field(t,'objective') and field(game(s),'session')==field(t,'session') and field(game(s),'player.health')==field(t,'player.health') and not field(game(s),'player.attacking') for s in terminal)
        terminal_ok=terminal_ok and self.position_span([completed]+terminal)<2 and self.position_span([completed]+terminal,1)<2
        terminal_ok=terminal_ok and all(field(game(s),'world.enemies')==field(t,'world.enemies') for s in terminal)
        self.mark('D3-13',terminal_ok,'TERMINAL_GAMEPLAY_STABILITY','journeys/success.json')
        reset=self.restart('after-completion',strict=True);self.cap('after-completion-restart');again=self.restart('consecutive-restart',strict=True)
        self.mark('D4-03',bool(reset and again),'CONSECUTIVE_RESTART_PRESERVES_SESSION','journeys/success.json')
        self.mark('D2-09',bool(reset),'HUD_AND_RESTART_BASIC_USE','captures/initial.png','captures/after-completion-restart.png')

    def locked_exit(self):
        self.restart('locked-start');self.corridor('locked');self.kill_pig('locked');self.climb('locked')
        # Jump over the key's central gap to the upper-left shelf.
        self.jump(402,'locked-shelf',288)
        # A closed exit is itself a solid boundary.  Approach its public
        # semantic bounds and observe rejection; requiring the player to reach
        # an interior x landmark falsely turns a valid closed-door collision
        # into MOVEMENT_TARGET_UNREACHABLE.
        self.move(305,'locked-door',tolerance=8)
        one=self.window('locked-contact',.6);self.cap('locked-exit')
        self.move(340,'locked-leave');self.move(305,'locked-recontact',tolerance=8);two=self.window('locked-repeat',.6)
        ok=bool(one and two) and all(field(game(s),'phase')=='active' and num(game(s),'objective.keys_collected')==0 and field(game(s),'objective.exit_state')=='locked' for s in one+two)
        self.mark('D3-12',ok and self.facts.get('success',False),'REPEATED_LOCKED_REJECTION_AND_OPEN_ENTRY','journeys/locked-exit.json','journeys/success.json')
        self.facts['locked_ok']=ok

    def hazards(self):
        self.restart('hazards-start');self.corridor('hazards');self.kill_pig('hazards')
        self.spring('hazards');death_before=num(self.g(),'session.deaths');health_before=num(self.g(),'player.health.current')
        side=self.side_spikes('side-spikes');self.cap('side-spikes-hit')
        if not side:raise CandidateError('SIDE_SPIKES_UNREACHABLE')
        side_ok=num(game(side),'player.health.current')==health_before-50 and num(game(side),'session.deaths')==death_before
        stable=self.window('side-spikes-no-stacking',.32)
        side_ok=side_ok and bool(stable) and all(num(game(s),'player.health.current')==health_before-50 for s in stable)
        self.restart('upper-spikes-start');self.corridor('upper-spikes');self.kill_pig('upper-spikes');self.climb('upper-spikes')
        self.move(551,'upper-spikes-column-right');self.jump(650,'upper-spikes-ledge')
        upper=self.wait('ceiling-spikes-hit',lambda g:num(g,'player.health.current')<100,3);self.cap('ceiling-spikes-hit')
        upper_ok=bool(upper) and num(game(upper),'player.health.current')==50
        self.facts['hazards']=dict(side_50=side_ok,upper_50=upper_ok)
        self.mark('D2-07',bool(side and upper and self.facts.get('enemy_damage',{}).get('died')),'BOTH_HAZARDS_AND_DEATH_PRESENT','journeys/hazards.json','journeys/enemy-damage.json')
        self.mark('D3-09',side_ok and upper_ok,'SPIKE_50_CONTACT_PUSH_AND_NO_STACK','journeys/hazards.json')

    def side_spikes(self,n):
        health=num(self.g(),'player.health.current');self.p.call('down',key='A')
        try:return self.wait(n+'-contact',lambda g:num(g,'player.health.current')<health,3)
        finally:self.p.call('up',key='A')

    def progress_damage(self):
        self.restart('progress-damage-start');self.corridor('progress-damage');self.kill_pig('progress-damage');self.climb('progress-damage')
        self.collect('progress-damage',False)
        deaths=num(self.g(),'session.deaths')
        for index in (1,2):
            self.wait('progress-floor',lambda g:field(g,'player.grounded') is True and self.xy(g)[1]>420,3,2)
            self.spring(f'progress-hit-{index}');hit=self.side_spikes(f'progress-hit-{index}')
            if not hit:raise CandidateError('PROGRESS_SPIKE_CONTACT_UNREACHABLE')
            self.cap(f'progress-hit-{index}')
            if index==1:
                ok=num(game(hit),'player.health.current')==50 and num(game(hit),'objective.keys_collected')==1 and field(game(hit),'objective.exit_state')=='open' and num(game(hit),'session.deaths')==deaths
                self.facts['nonfatal_preserves_progress']=ok
                self.window('progress-no-stacking',.6)
        reset=self.wait('progress-lethal-reset',fresh,4,2);self.cap('progress-death-reset')
        ok=bool(reset) and num(game(reset),'session.deaths')==deaths+1 and self.facts.get('nonfatal_preserves_progress',False)
        old=self.verdicts['D3-09']['verdict']=='pass'
        self.mark('D3-09',old and ok,'SPIKES_NONFATAL_PROGRESS_AND_LATER_CONTACT','journeys/hazards.json','journeys/progress-damage.json')
        self.mark('D3-10',ok and self.verdicts['D3-10']['verdict']=='pass','LETHAL_ONCE_RESETS_COLLECTED_KEY_AND_ROOM','journeys/enemy-damage.json','journeys/progress-damage.json')

    def transient_restarts(self):
        checks=[]
        self.restart('transient-start');self.press('Z');old=self.o.last;self.press('R')
        s=self.wait('attack-restart',fresh,4,2);stable=self.window('attack-expiry-cleared',.9)
        checks.append(bool(s) and all(fresh(game(x)) for x in stable));self.cap('attack-restart')
        self.corridor('transient-spring');self.kill_pig('transient-spring');self.move(653,'spring-transient-contact')
        air=self.wait('spring-transient-air',lambda g:field(g,'player.grounded') is False,3)
        self.press('R');s=self.wait('spring-restart',fresh,4,2);stable=self.window('spring-expiry-cleared',1.2)
        checks.append(bool(air and s) and all(fresh(game(x)) for x in stable));self.cap('spring-restart')
        self.corridor('transient-death')
        e=field(self.g(),'world.enemies',[])
        if not e:raise CandidateError('ENEMY_MISSING_FOR_DEATH_RESTART')
        ex=self.point(self.g(),e[0])[0];self.move(ex-12,'death-contact')
        dying=self.wait('death-in-progress',lambda g:field(g,'phase')=='dying',5)
        if dying:self.press('R')
        s=self.wait('death-restart',fresh,4,2);stable=self.window('death-expiry-cleared',1.2)
        checks.append(bool(dying and s) and all(fresh(game(x)) and num(game(x),'session.deaths')==num(game(s),'session.deaths') for x in stable))
        self.mark('D4-04',all(checks),'RESTART_DURING_SWORD_SPRING_DEATH','journeys/transient-restarts.json')

    def reopen(self):
        old=self.o.last;self.p.call('reopen');self.o.bind(self.p.session)
        s=self.wait('new-process-fresh',fresh,5,2);self.cap('reopened')
        ok=bool(s) and s['process_id']!=old['process_id'] and s['process_token']!=old['process_token'] and s['round_index']==0 and s['restart_count']==0 and num(game(s),'session.deaths')==0
        self.mark('D4-05',ok,'OLD_PROCESS_EXIT_NEW_IDENTITY_INITIAL_SESSION','journeys/reopen.json')

    def repeat_success(self):
        self.restart('repeat-success-start');before=self.o.last['round_id']
        # Leave the pig alive: defeating it must be optional and its terminal
        # interactions must freeze even when it was active before completion.
        self.corridor('repeat-success');self.climb('repeat-success');self.collect('repeat-success',avoid_enemy=True)
        self.move(260,'repeat-success-exit',4,stop_on_completion=True)
        s=self.wait('repeat-success-completed',lambda g:field(g,'phase')=='completed',2,2);self.cap('repeat-completed')
        self.facts['second_success']=bool(s) and s['round_id']==before
        if not s:raise CandidateError('SECOND_COMPLETION_UNREACHABLE')
        self.press('D');self.press('Space');self.press('Z');stable=self.window('live-enemy-terminal',1.5)
        alive=num(game(s),'world.object_counts.enemy')==1
        frozen=bool(stable) and all(field(game(x),'world.enemies')==field(game(s),'world.enemies') and field(game(x),'phase')=='completed' and field(game(x),'player')==field(game(s),'player') and field(game(x),'session')==field(game(s),'session') for x in stable)
        self.facts['optional_enemy_terminal']=bool(alive and frozen)
        self.mark('D3-13',self.verdicts['D3-13']['verdict']=='pass' and alive and frozen,'TERMINAL_STABILITY_WITH_LIVE_AND_DEAD_ENEMY','journeys/success.json','journeys/repeat-success.json')

    def cleanup(self):
        if not self.p:return True,None
        stop_error=None;close_error=None
        try:
            if self.p.session:self.p.call('stop')
        except Exception as e:stop_error=e
        finally:
            try:self.p.close()
            except Exception as e:close_error=e
        receipt=self.p.last_cleanup_receipt or self.p.last_receipt
        cleaned=cleanup_verified(receipt) or (not self.p.had_session and self.p.session is None)
        if isinstance(stop_error,CandidateError) and cleaned:
            self.journeys.append(dict(id='close',status='candidate_failure',reason=str(stop_error)))
        if close_error or (stop_error and not isinstance(stop_error,CandidateError)) or not cleaned:
            return False,dict(domain='infrastructure',code='CLEANUP_UNVERIFIED',
                stop_error=str(stop_error) if stop_error else None,
                close_error=str(close_error) if close_error else None)
        return True,None

    def run(self):
        if self.root.exists() and any(self.root.iterdir()):raise InfrastructureError('RUN_ROOT_NOT_EMPTY')
        self.root.mkdir(parents=True,exist_ok=True)
        candidate=self.args.candidate.resolve()
        if self.root.is_relative_to(candidate) or candidate.is_relative_to(self.root):raise InfrastructureError('RUN_CANDIDATE_ROOT_OVERLAP')
        self.budget.arm();invalid=None;candidate_id=None;build_ok=False;cleaned=False
        try:
            # An externally killed collector leaves an explicitly unscored
            # checkpoint rather than a missing or apparently completed result.
            self.checkpoint()
            version=load(self.args.engine/'Engine/Build/Build.version')
            if [version[k] for k in ('MajorVersion','MinorVersion','PatchVersion','Changelist')]!=[5,7,4,51494982]:raise InfrastructureError('ENGINE_IDENTITY_MISMATCH')
            public=load(TASK/'input/BENCHMARK_MANIFEST.json')
            for path,key in [(public['engine']['executor_module'],'executor_sha256'),(public['engine']['executor_native_interop'],'executor_native_interop_sha256')]:
                if sha(REPO/path)!=public['tooling'][key]:raise InfrastructureError('PUBLIC_RUNTIME_IDENTITY_CHANGED')
            try:candidate_id=identity(candidate)
            except CandidateError as e:raise CandidateError(str(e))
            self.candidate_id=candidate_id
            write(self.root/'candidate-identity.json',candidate_id)
            self.checkpoint()
            if not candidate.is_dir():raise CandidateError('CANDIDATE_ROOT_MISSING')
            try:declared=load(candidate/'BENCHMARK_MANIFEST.json') if (candidate/'BENCHMARK_MANIFEST.json').exists() else public
            except (OSError,ValueError):raise CandidateError('CANDIDATE_MANIFEST_MALFORMED') from None
            try:
                project=inside(candidate,declared['paths']['project_file'])
                project_root=inside(candidate,declared['paths']['project_root'])
            except (InfrastructureError,KeyError,TypeError):raise CandidateError('CANDIDATE_PROJECT_PATH_INVALID') from None
            if not project.is_relative_to(project_root) or not project.is_file():raise CandidateError('PROJECT_FILE_MISSING')
            try:descriptor=load(project)
            except (OSError,ValueError):raise CandidateError('CANDIDATE_DESCRIPTOR_MALFORMED') from None
            if not isinstance(descriptor,dict):raise CandidateError('CANDIDATE_DESCRIPTOR_MALFORMED')
            plugins=descriptor.get('Plugins',[])
            if not isinstance(plugins,list) or any(not isinstance(p,dict) for p in plugins):raise CandidateError('CANDIDATE_DESCRIPTOR_MALFORMED')
            allowed=descriptor.get('EngineAssociation')=='5.7' and all(p.get('Name')=='Paper2D' or not p.get('Enabled',False) for p in plugins)
            self.mark('D1-01',allowed,'PROJECT_ENTRY_ENGINE_PLUGINS','candidate-identity.json')
            work=self.root/'work/project'
            shutil.copytree(project_root,work,ignore=shutil.ignore_patterns(*EXCLUDES))
            # Some valid public projects keep runtime PNG/source data beside
            # project/ and resolve it through ProjectDir()/../assets. Stage
            # that declared public support tree beside the clean project copy;
            # otherwise a black frame would be an evaluator staging defect.
            public_assets = candidate/'assets'
            if public_assets.is_dir():
                shutil.copytree(public_assets,self.root/'work/assets',ignore=shutil.ignore_patterns(*EXCLUDES))
            workproject=work/project.name
            targets=list((work/'Source').glob('*Editor.Target.cs'))
            if len(targets)!=1:raise CandidateError('EDITOR_TARGET_MISSING_OR_AMBIGUOUS')
            target=targets[0].name.removesuffix('.Target.cs')
            cmd=[str(self.args.engine/'Engine/Build/BatchFiles/Build.bat'),target,'Win64','Development',str(workproject),'-CompilerVersion=14.44.35207','-WaitMutex','-NoHotReloadFromIDE']
            self.progress('Building clean candidate copy')
            with (self.root/'build.log').open('w',encoding='utf-8') as log:
                proc=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0));self.budget.processes.append(proc)
                try:code=proc.wait(timeout=self.budget.contract['build_timeout_seconds'])
                except subprocess.TimeoutExpired:
                    subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],capture_output=True,timeout=15);code=-1
            write(self.root/'build.json',dict(exit_code=code,log='build.log',candidate_identity_sha256=candidate_id['sha256']))
            build_ok=code==0;self.mark('D1-02',build_ok,'CLEAN_BUILD_RESULT','build.json')
            if not build_ok:raise CandidateError('CANDIDATE_BUILD_FAILED_OR_TIMED_OUT')
            self.p=Player(self.args.pwsh,self.root,self.budget)
            self.p.call('start',project=str(workproject),engine=str(self.args.engine),root=str(self.root))
            self.o=Observer(self.root,self.p.session,self.budget)
            bridge=self.o.wait('static-bridge',lambda g:True,4,2)
            initial_cap=self.cap('startup')
            self.mark('D1-03',initial_cap['visible'],'DEFAULT_ENTRY_VISIBLE','captures/startup.png')
            self.mark('D1-04',bool(bridge) and not self.o.errors,'READ_ONLY_BRIDGE_SCHEMA_FRESHNESS','states/static-bridge.json')
            logs=list((work/'Saved/Logs').glob('*.log'))
            missing=any(re.search(r'(Required room image missing|LogLinker: Warning:.*Failed to load|LogStreaming: Error:)',p.read_text(encoding='utf-8',errors='replace')) for p in logs)
            self.mark('D1-05',not missing,'REQUIRED_ASSET_LOAD_HEALTH','captures/startup.png')
            if not initial_cap['visible']:raise CandidateError('CANDIDATE_BLACK_SCREEN')
            # D1 is now complete. All subsequent game interaction is normal player input.
            self.isolated('initial',self.initial_state)
            if self.initial and math.isfinite(self.sx) and math.isfinite(self.sy):
                for name,method in [('movement',self.movement),('patrol',self.patrol),('combat',self.combat),('enemy-damage',self.enemy_damage),
                    ('traversal',self.traversal),('success',self.success),('locked-exit',self.locked_exit),('hazards',self.hazards),
                    ('progress-damage',self.progress_damage),('transient-restarts',self.transient_restarts),('repeat-success',self.repeat_success),('reopen',self.reopen)]:self.isolated(name,method)
            else:
                if self.initial:self.isolated('movement',self.basic_movement)
                # Reopen remains an independent engineering/lifecycle observation even
                # when target gameplay is absent from an untouched starter.
                self.isolated('reopen',self.reopen)
        except CandidateError as e:
            self.journeys.append(dict(id='candidate-gate',status='candidate_failure',reason=str(e)))
        except (ValueError,KeyError,TypeError,OSError) as e:
            invalid=dict(domain='infrastructure',code='AUTHORING_OR_HOST_EXCEPTION',exception_type=type(e).__name__,message=str(e))
        except InfrastructureError as e:invalid=dict(domain='infrastructure',code=str(e))
        except (Exception,KeyboardInterrupt) as e:
            invalid=dict(domain='infrastructure',code='COLLECTOR_UNEXPECTED_EXCEPTION',exception_type=type(e).__name__,message=str(e))
        finally:
            try:
                cleaned,cleanup_error=self.cleanup()
                if cleanup_error:
                    if invalid:invalid['cleanup_fault']=cleanup_error
                    else:invalid=cleanup_error
            except (Exception,KeyboardInterrupt) as e:
                cleanup_error=dict(domain='infrastructure',code='CLEANUP_UNVERIFIED',exception_type=type(e).__name__,detail=str(e))
                if invalid:invalid['cleanup_fault']=cleanup_error
                else:invalid=cleanup_error
            finally:self.budget.close()
        try:
            all_journeys=all(j['status']=='completed' for j in self.journeys)
            self.mark('D4-06',all_journeys and cleaned and self.facts.get('second_success',False),'INDEPENDENT_JOURNEYS_SECOND_SUCCESS_AND_CLEANUP','journeys.json','journeys/repeat-success.json')
            self.attribute_unreachable()
            write(self.root/'journeys.json',self.journeys);write(self.root/'facts.json',self.facts)
        except Exception as e:
            if invalid is None:invalid=dict(domain='infrastructure',code='COLLECTOR_REPORT_EXCEPTION',exception_type=type(e).__name__,detail=str(e))
        # Evidence completeness is checked by the scorer; no arithmetic is performed here.
        write(self.root/'raw-evaluation.json',self.raw_record('invalid' if invalid else 'collected',invalid,cleaned))
        self.progress(str(self.root/'raw-evaluation.json'))
        return 2 if invalid else 0

    def attribute_unreachable(self):
        # Keep observed independent results. Attribute each blocked checkpoint to
        # its actual failed journey, including the gate that prevented that journey.
        owners={'initial':['D2-01','D3-01','D5-01'],
            'movement':['D2-02','D3-02','D3-03','D5-02'], 'patrol':['D3-05'],
            'combat':['D2-03','D2-10','D3-04'], 'enemy-damage':['D2-04','D3-06','D3-10','D4-02','D5-03'],
            'traversal':['D2-05','D2-06','D3-07','D3-08','D5-06'],
            'success':['D2-08','D2-09','D2-11','D3-11','D3-13','D4-01','D4-03','D5-04','D5-05'],
            'locked-exit':['D3-12'], 'hazards':['D2-07','D3-09'],
            'transient-restarts':['D4-04'], 'reopen':['D4-05']}
        failures={j['id']:j for j in self.journeys if j['status']=='candidate_failure'}
        for c in self.verdicts.values():
            if c['verdict']!='unreachable':continue
            owner=next((n for n,ids in owners.items() if c['id'] in ids),'candidate-gate')
            cause=failures.get(owner) or failures.get('candidate-gate') or failures.get('initial')
            c.update(reason='DEPENDENCY_UNREACHABLE:'+ (cause['reason'] if cause else owner),
                evidence=['journeys.json'],blocked_by=cause['id'] if cause else owner)

def main():
    p=argparse.ArgumentParser();p.add_argument('--candidate',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--engine',type=Path,required=True);p.add_argument('--pwsh',default='pwsh');args=p.parse_args()
    return Evaluation(args).run()
if __name__=='__main__':raise SystemExit(main())
