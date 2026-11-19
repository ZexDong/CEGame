"""Public-data path and short-horizon input predictor, not a game-state API."""
import heapq
import math
from dataclasses import dataclass,replace
from functools import lru_cache


@dataclass
class State:
    x:float
    y:float
    vx:float
    vy:float
    time:float


class Model:
    def __init__(self,level):
        self.level=level;self.rows=level['rows'][::-1];self.cell=level['cell_pixels']
        self.physics=level['physics'];self.spikes=set(map(tuple,level['spike_cells']))
        self.checkpoints=[((x+.5)*self.cell,(y+.5)*self.cell) for x,y in level['checkpoints_cells']]
        self.finishes=[((x+.5)*self.cell,(y+.5)*self.cell) for y,row in enumerate(self.rows) for x,c in enumerate(row) if c=='F']

    def body_hits(self,x,y,left,bottom,w,h=None,padding=0):
        h=w if h is None else h
        shape=self.level['balloon_collision'];ox,oy=shape['circle_center_offset']
        cx,cy=x+ox,y+oy;radius=shape['circle_radius']+padding
        dx=cx-min(max(cx,left),left+w);dy=cy-min(max(cy,bottom),bottom+h)
        bx,by=shape['basket_center_offset'];bw,bh=shape['basket_half_extents']
        return dx*dx+dy*dy<radius*radius or (x+bx+bw+padding>left and x+bx-bw-padding<left+w
            and y+by+bh+padding>bottom and y+by-bh-padding<bottom+h)

    def nearby(self,x,y,padding=0):
        c=self.cell
        for iy in range(max(0,math.floor((y-18-padding)/c)),min(self.level['height']-1,math.floor((y+18+padding)/c))+1):
            for ix in range(max(0,math.floor((x-13-padding)/c)),min(self.level['width']-1,math.floor((x+13+padding)/c))+1):
                yield ix,iy

    def solid(self,x,y,padding=0):
        w=self.level['width']*self.cell;h=self.level['height']*self.cell
        if not 11+padding<=x<=w-11-padding or not 16+padding<=y<=h-16-padding:return True
        return any(self.rows[iy][ix] in '#P' and self.body_hits(x,y,ix*self.cell,iy*self.cell,self.cell,padding=padding)
                   for ix,iy in self.nearby(x,y,padding))

    def hazard(self,x,y,padding=0):
        return any((ix,iy) in self.spikes and self.body_hits(x,y,ix*self.cell+2,iy*self.cell+2,12,padding=padding)
                   for ix,iy in self.nearby(x,y,padding))

    @lru_cache(maxsize=300000)
    def valid(self,gx,gy,padding):
        return not self.solid(gx*4,gy*4,padding) and not self.hazard(gx*4,gy*4,padding)

    def route(self,start,goal,padding=4):
        source=tuple(round(v/4) for v in start);dest=tuple(round(v/4) for v in goal)
        if not self.valid(*dest,padding):return None
        queue=[(0,source)];distance={source:0};parent={}
        while queue:
            _,at=heapq.heappop(queue)
            if at==dest:break
            for dx,dy in ((0,1),(0,-1),(-1,0),(1,0),(-1,1),(1,1),(-1,-1),(1,-1)):
                nxt=(at[0]+dx,at[1]+dy)
                if not self.valid(*nxt,padding):continue
                if dx and dy and (not self.valid(at[0]+dx,at[1],padding) or not self.valid(at[0],at[1]+dy,padding)):continue
                cost=distance[at]+math.hypot(dx,dy)
                if cost>=distance.get(nxt,math.inf):continue
                parent[nxt]=at;distance[nxt]=cost
                heapq.heappush(queue,(cost+math.hypot(nxt[0]-dest[0],nxt[1]-dest[1]),nxt))
        if dest not in distance:return None
        path=[dest]
        while path[-1]!=source:path.append(parent[path[-1]])
        return [(x*4,y*4) for x,y in path[::-1]]

    def path(self,start,goal):
        for padding in (4,2,0):
            path=self.route(start,goal,padding)
            if path:return path
        raise ValueError('NO_PUBLIC_GEOMETRY_PATH')

    def wind(self,time):
        t=time%self.level['wind']['period_seconds']
        return next(s['acceleration'] for s in self.level['wind']['segments'] if s['start']<=t<s['end'])

    def step(self,state,horizontal,lift,dt=1/60):
        p=self.physics;state.time+=dt;wx,wy=self.wind(state.time)
        state.vx-=math.copysign(min(abs(state.vx),p['horizontal_drag']*dt),state.vx)
        state.vx=max(-p['max_horizontal_speed'],min(p['max_horizontal_speed'],state.vx+(horizontal*p['horizontal_thrust']+wx)*dt))
        state.vy=max(-p['max_downward_speed'],min(p['max_upward_speed'],state.vy+(int(lift)*p['lift']-p['gravity']+wy)*dt))
        for axis,delta in (('x',state.vx*dt),('y',state.vy*dt)):
            steps=max(1,math.ceil(abs(delta)))
            for _ in range(steps):
                x=state.x+delta/steps if axis=='x' else state.x
                y=state.y+delta/steps if axis=='y' else state.y
                if self.solid(x,y):
                    if axis=='x':state.vx=0
                    else:state.vy=0
                    break
                state.x,state.y=x,y
        return not self.hazard(state.x,state.y)

    def choose(self,state,target,speed=20):
        vx=max(-speed,min(speed,(target[0]-state.x)*1.5))
        vy=max(-speed,min(speed,(target[1]-state.y)*1.5))
        preferred=(1 if state.vx<vx-1 else -1 if state.vx>vx+1 else 0,state.vy<vy)
        options=[preferred]+[(h,lift) for h in (0,-1,1) for lift in (False,True) if (h,lift)!=preferred]
        safe=[]
        for h,lift in options:
            trial=replace(state)
            if all(self.step(trial,h,lift) for _ in range(24)):
                error=math.hypot(trial.x-target[0],trial.y-target[1])+.25*math.hypot(trial.vx-vx,trial.vy-vy)
                safe.append((error,(h,lift)))
        if not safe:return preferred
        if any(action==preferred for _,action in safe):return preferred
        return min(safe)[1]
