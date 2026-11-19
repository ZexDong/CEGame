"""Independent planning model from v2 public Match3 data, never Gold Lua."""
from dataclasses import dataclass
from functools import lru_cache
from framework.defold_native_tasks.match3_spec import matches,line_at,at,DIRECTIONS

@dataclass(frozen=True)
class State:
    board:tuple
    rng:int
    colors:tuple
    ice:tuple
    moves:int=0

class Model:
    def __init__(self,spec,index):
        self.spec=spec;self.level=spec['levels'][index-1]
        self.stones={tuple(p) for p in self.level['stones']};self.names=spec['world']['colors']
    def initial(self):
        b=[[None]*10 for _ in range(15)];seed=self.level['seed'];ice=[0]*150
        for item in self.level['ice']:ice[item['cell'][0]+15*item['cell'][1]]=item['layers']
        for y in range(10):
            for x in range(15):
                if (x,y) in self.stones:continue
                while True:
                    seed=seed*16807%2147483647;c=seed%6
                    if x>=2 and b[x-1][y]==b[x-2][y]==c:continue
                    if y>=2 and b[x][y-1]==b[x][y-2]==c:continue
                    b[x][y]=c;break
        return State(tuple(map(tuple,b)),seed,(0,)*6,tuple(ice))
    def won(self,s):
        goals=self.level['goals']
        return sum(s.colors)*10>=goals['minimum_score'] and (not goals['clear_all_ice'] or not any(s.ice)) and all(s.colors[self.names.index(c)]>=n for c,n in goals['color_quotas'].items())
    @lru_cache(maxsize=30000)
    def step(self,s,direction):
        b=[list(c) for c in s.board];rng=s.rng;colors=list(s.colors);ice=list(s.ice);used=set()
        dx,dy={'left':(-1,0),'right':(1,0),'up':(0,1),'down':(0,-1)}[direction]
        for x in (range(14,-1,-1) if direction=='left' else range(15)):
            for y in (range(9,-1,-1) if direction=='down' else range(10)):
                nx,ny=x+dx,y+dy
                if at(b,x,y) is None or at(b,nx,ny) is None or (x,y) in used or (nx,ny) in used:continue
                b[x][y],b[nx][ny]=b[nx][ny],b[x][y]
                if line_at(b,x,y) or line_at(b,nx,ny):used.update(((x,y),(nx,ny)))
                else:b[x][y],b[nx][ny]=b[nx][ny],b[x][y]
        pending=set()
        for _ in range(1000):
            if pending:
                cells={((i,n) if horizontal else (n,i)) for horizontal,n in pending for i in range(15 if horizontal else 10)};pending=set()
            else:cells,pending=matches(b)
            cells={p for p in cells if p not in self.stones}
            if not cells:break
            for x,y in cells:
                if b[x][y] is None:continue
                colors[b[x][y]]+=1;b[x][y]=None;ice[x+15*y]=max(0,ice[x+15*y]-1)
            for x in range(15):
                lo=0
                while lo<10:
                    if (x,lo) in self.stones:lo+=1;continue
                    hi=lo
                    while hi+1<10 and (x,hi+1) not in self.stones:hi+=1
                    kept=[b[x][y] for y in range(lo,hi+1) if b[x][y] is not None]
                    for y in range(lo,hi+1):
                        if y-lo<len(kept):b[x][y]=kept[y-lo]
                        else:rng=rng*16807%2147483647;b[x][y]=rng%6
                    lo=hi+1
        else:raise ValueError('planning model did not settle')
        return State(tuple(map(tuple,b)),rng,tuple(colors),tuple(ice),s.moves+1)
    def utility(self,s):
        goals=self.level['goals'];score=min(sum(s.colors)*10,goals['minimum_score'])
        quota=sum(min(s.colors[self.names.index(c)],n) for c,n in goals['color_quotas'].items())
        return -sum(s.ice)*10000+quota*100+score+sum(s.colors)*.01
    def route(self,width=96):
        frontier=[(self.initial(),())]
        for depth in range(self.level['moves']):
            choices={}
            for s,path in frontier:
                for direction in DIRECTIONS:
                    nxt=self.step(s,direction);route=path+(direction,)
                    if self.won(nxt):return route,nxt
                    choices.setdefault(nxt,route)
            frontier=sorted(choices.items(),key=lambda pair:self.utility(pair[0]),reverse=True)[:width]
        raise ValueError('bounded planner did not find a complete public-goal route')
