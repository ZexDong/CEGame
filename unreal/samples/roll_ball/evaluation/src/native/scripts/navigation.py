"""Topology-aware, closed-loop normal-key steering with empirical world axes.

Controller thresholds are sampling/steering parameters, never acceptance rules.
A failure to calibrate or steer is reviewable evidence, not proof of bad gameplay.
"""
import collections
import math
import time
from runtime import INPUT, CandidateError, ObservationUncertain, cell, load, norm, position, sub, velocity

LAYOUT=load(INPUT/'project/Config/FixedRollBallLayout.json')
WALL_V={tuple(c[k] for k in ('x','y')) for c in LAYOUT['vertical_walls']}
WALL_H={tuple(c[k] for k in ('x','y')) for c in LAYOUT['horizontal_walls']}
TRAPS={tuple(c[k] for k in ('x','y')) for c in LAYOUT['trap_cells']}

def neighbours(c):
    x,y=c
    for other,key,blocked in [((x+1,y),'D',(x+1,y) in WALL_V),((x-1,y),'A',(x,y) in WALL_V),
                              ((x,y+1),'W',(x,y+1) in WALL_H),((x,y-1),'S',(x,y) in WALL_H)]:
        if not blocked and 0<=other[0]<10 and 0<=other[1]<10:yield other,key

def route(start,end,avoid_traps=True):
    pending=collections.deque([(start,[])]);seen={start}
    while pending:
        current,path=pending.popleft()
        if current==end:return path
        for nxt,key in neighbours(current):
            if nxt not in seen and (not avoid_traps or nxt not in TRAPS or nxt==end):
                seen.add(nxt);pending.append((nxt,path+[(nxt,key)]))
    raise ValueError('NO_PUBLIC_ROUTE')

def dot(a,b):return sum(x*y for x,y in zip(a,b))

class Navigator:
    def __init__(self,player):
        self.p=player;self.origin=position(player.read());self.axes={};self.accel={};self.unit=[400.,400.]
        self.events=[];self.last_snapshot=None
        self.scale_samples={0:[],1:[]}
    def calibrate(self):
        # Acceleration differences remove existing drift and accommodate rotated
        # world planes, elevated boards and anisotropic controls.
        for axis,key,opposite in [(0,'D','A'),(1,'W','S')]:
            s=self.p.read();v0=velocity(s);t0=s['monotonic_ms'];self.p.keys([key])
            try:
                s=self.p.wait(lambda t:t['snapshot_id']>s['snapshot_id'] and norm(sub(velocity(t),v0))>1e-6,
                              8,'CONTROL_UNOBSERVED')
                self.p.observe(.12);s=self.p.read()
            finally:self.p.keys([])
            dv=sub(velocity(s),v0);length=norm(dv)
            if length<1e-6:raise ObservationUncertain('CALIBRATION_NO_MEASURABLE_ACCELERATION')
            self.axes[axis]=tuple(v/length for v in dv)
            self.accel[axis]=length/max(.001,(s['monotonic_ms']-t0)/1000)
            self.brake(axis,opposite)
        if abs(dot(self.axes[0],self.axes[1]))>.8:raise ObservationUncertain('CALIBRATION_AXES_AMBIGUOUS')
        # A planar rectangular board has perpendicular layout axes. Remove the
        # small passive drift during the second drive measurement.
        along=dot(self.axes[1],self.axes[0]);orth=sub(self.axes[1],tuple(along*x for x in self.axes[0]));length=norm(orth)
        self.axes[1]=tuple(x/length for x in orth)
        self.events.append(dict(kind='calibration',origin=self.origin,axes=self.axes,accel=self.accel,units_source='public layout; refined by observed transitions'))
        self.move((0,0))
    def coords(self,s):return tuple(dot(sub(position(s),self.origin),self.axes[i])/self.unit[i] for i in (0,1))
    def speeds(self,s):return tuple(dot(velocity(s),self.axes[i])/self.unit[i] for i in (0,1))
    def refine(self,s):
        old=self.last_snapshot;self.last_snapshot=s
        if not old:return
        a,b=cell(old),cell(s)
        for axis in (0,1):
            if abs(a[axis]-b[axis])==1 and a[1-axis]==b[1-axis]:
                boundary=min(a[axis],b[axis])+.5
                midpoint=tuple((u+v)/2 for u,v in zip(position(old),position(s)))
                measured=dot(sub(midpoint,self.origin),self.axes[axis])/boundary
                if measured>0:
                    self.scale_samples[axis].append(measured)
                    self.unit[axis]=sorted(self.scale_samples[axis])[len(self.scale_samples[axis])//2]
                    self.events.append(dict(kind='observed_grid_scale',axis=axis,unit=self.unit[axis],boundary=boundary))
    def brake(self,axis,key):
        end=time.monotonic()+5
        while time.monotonic()<end:
            s=self.p.read();speed=dot(velocity(s),self.axes[axis])
            if abs(speed)<self.accel[axis]*.025:break
            self.p.keys([('A' if speed>0 else 'D') if axis==0 else ('S' if speed>0 else 'W')])
            self.p.observe(.025)
        self.p.keys([])
    def move(self,target,timeout=40,stop_status=None):
        start=time.monotonic();last_progress=start;best=math.inf;last=None;stable=0
        while time.monotonic()-start<timeout:
            s=self.p.read()
            if stop_status and s['game_state']['status']==stop_status:self.p.keys([]);return s
            if s['game_state']['status']!='running':
                self.p.keys([]);raise CandidateError('UNEXPECTED_STATE_DURING_NAVIGATION:'+s['game_state']['status'])
            if last==s['snapshot_id']:time.sleep(.012);continue
            last=s['snapshot_id'];self.refine(s);p=self.coords(s);v=self.speeds(s)
            error=[target[i]-p[i] for i in (0,1)];distance=math.hypot(*error)
            if distance<best-.01:best=distance;last_progress=time.monotonic()
            if distance<.055 and norm(v)<.075:stable+=1
            else:stable=0
            if stable>=2:
                expected=tuple(math.floor(t+.5) for t in target)
                if cell(s)==expected:self.p.keys([]);return s
                for axis in (0,1):
                    if cell(s)[axis]!=expected[axis] and not self.scale_samples[axis]:self.unit[axis]*=1.25
                stable=0;best=math.inf
            desired=[];priorities=[]
            for i in (0,1):
                a=max(.001,self.accel[i]/self.unit[i])
                # Slow near corners; braking distance comes from observed drive.
                wanted=math.copysign(min(.65, math.sqrt(max(0,2*a*abs(error[i])))*.68),error[i]) if abs(error[i])>.02 else 0
                gap=wanted-v[i]
                if abs(gap)>.025:
                    desired.append(('D' if gap>0 else 'A') if i==0 else ('W' if gap>0 else 'S'));priorities.append(abs(gap))
            # The public task does not prescribe diagonal-key arbitration.
            self.p.keys([desired[priorities.index(max(priorities))]] if desired else [])
            self.p.observe(.035)
            # Progress exhaustion is controller uncertainty. It is only candidate
            # failure if independent evidence shows a wall/lock/control defect.
            if time.monotonic()-last_progress>12:
                self.p.keys([]);raise ObservationUncertain('STEERING_STALLED_REQUIRES_PLAYER_REVIEW')
        self.p.keys([]);raise ObservationUncertain('STEERING_BUDGET_REQUIRES_PLAYER_REVIEW')
    def follow(self,end,stop_status=None):
        for target,key in route(cell(self.p.read()),end):
            self.events.append(dict(kind='waypoint',cell=target,key=key))
            s=self.move(target,stop_status=stop_status)
            if stop_status and s['game_state']['status']==stop_status:return s
        return self.p.read()

if __name__=='__main__':
    print('Start neighbours:',list(neighbours((0,0))))
    print('Nearest trap:',min((len(route((0,0),t,False)),t) for t in TRAPS))
    print('Safe completion route:',route((0,0),(9,9)))
