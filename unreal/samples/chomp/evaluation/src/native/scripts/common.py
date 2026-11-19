from pathlib import Path
import sys, json, hashlib, math
TASK=Path(__file__).resolve().parents[2]
REPO=TASK.parents[1]
sys.path.insert(0,str(REPO/'engine/atomic-player/1.0'))
from runtime import Player, CandidateError, InfrastructureError, identity, write, load, sha, GENERATED
LAYOUT=load(TASK/'input/contracts/maze-layout.json')
BOARD=LAYOUT['cells']
DIRS=[(0,-1),(1,0),(0,1),(-1,0)]
KEYS=['Up','Right','Down','Left']
NAMES=['up','right','down','left']
COLORS=['red','cyan','pink','orange']
ALL_DOTS=[{'x':x,'y':y} for y,row in enumerate(BOARD) for x,c in enumerate(row) if c in '.TF']
ALL_ORBS=[{'x':x,'y':y} for y,row in enumerate(BOARD) for x,c in enumerate(row) if c=='E']
def cell(c):return (c['x'],c['y'])
def legal(c,home=False):return 0<=c[0]<30 and 0<=c[1]<28 and BOARD[c[1]][c[0]] not in ('#X' if home else '#XH=')
def neighbor(c,d,home=False):
    x,y=c;dx,dy=DIRS[d];n=(x+dx,y+dy)
    if (c,d)==((14,0),0):n=(14,27)
    if (c,d)==((14,27),2):n=(14,0)
    if y in [12,15] and x==0 and d==3:n=(29,y)
    if y in [12,15] and x==29 and d==1:n=(0,y)
    return n if legal(n,home) else c
def distances(target,home=False):
    result={target:0};queue=[target]
    for c in queue:
        for d in range(4):
            n=neighbor(c,d,home)
            if n not in result:result[n]=result[c]+1;queue.append(n)
    return result
def ahead(player,n):
    c=cell(player['cell']);d=NAMES.index(player['heading'])
    for _ in range(n):
        v=(c[0]+DIRS[d][0],c[1]+DIRS[d][1])
        if not legal(v):break
        c=v
    return c
def ghost(s,color):return next(g for g in s['ghosts'] if g['id']==color)
def motion(x,y,d=1,progress=0):return {'x':x,'y':y,'direction':d,'progress':progress}
def gstate(color,x,y,d=1,state='normal',progress=0):return {'id':color,'state':state,'motion':motion(x,y,d,progress)}
def safe_ghosts():return [gstate('red',1,26,0)]+[gstate(c,*LAYOUT['ghost_homes'][c],d=0,state='waiting') for c in COLORS[1:]]
def keep_dots(count,keep=()):
    keep=set(keep);head=[c for c in ALL_DOTS if cell(c) in keep];rest=[c for c in ALL_DOTS if cell(c) not in keep]
    return head+rest[:count-len(head)]
def fixture_base(**changes):
    data={'player':motion(14,13,1),'ghosts':safe_ghosts(),'ordinary_cells':ALL_DOTS,'energizer_cells':ALL_ORBS,'score':0,'lives':3,'extra_life_progress':0,'capture_chain':0,'active_seconds':0,'wave_index':0,'wave_remaining_seconds':5,'frightened_remaining_seconds':0,'inactivity_remaining_seconds':5,'fruit_remaining_seconds':0,'fruit_thresholds':[]}
    data.update(changes);return data
def require(condition,reason):
    if not condition:raise CandidateError(reason)

class GamePlayer(Player):
    def __init__(self,project,engine,root,**kwargs):super().__init__(REPO,project,engine,root,'ChompStatePath',seed_argument='-ChompSeed=1337',**kwargs)
    def state(self):
        s=super().state();key=(s['process_token'],s['snapshot_id'])
        if key!=getattr(self,'validated_snapshot',None):
            from observer_contract import error
            issue=error(s)
            if issue:raise CandidateError('PUBLIC_SCHEMA_INVALID:'+issue)
            self.validated_snapshot=key
        return s
    def game(self):
        s=self.state()
        if not s.get('provider_ready') or not isinstance(s.get('game_state'),dict):raise CandidateError('GAMEPLAY_PROVIDER_UNAVAILABLE')
        return s['game_state']
    def wait_game(self,predicate,seconds=3,**kwargs):return self.wait(lambda s:s.get('provider_ready') and predicate(s['game_state']),seconds,**kwargs)['game_state']
    def click_target(self,id):
        items=[t for t in self.game()['targets'] if t['id']==id and t['visible'] and t['enabled'] and t['topmost']]
        require(len(items)==1,'VISIBLE_TARGET_UNAVAILABLE:'+id);return self.click(items[0]['rect'])
    def start_run(self):
        s=self.game()
        if s['phase']=='options':self.click_target('back');s=self.wait_game(lambda s:s['phase']!='options')
        if s['phase']=='playing':self.press('P');s=self.wait_game(lambda s:s['phase']=='paused')
        old=s['run_id'];self.click_target('start' if s['phase']=='menu' else 'restart')
        self.wait_game(lambda s:s['phase']=='playing' and s['run_id']!=old)
        return self.game()
    def pause(self):
        if self.game()['phase']=='playing':self.press('P');self.wait_game(lambda s:s['phase']=='paused')
    def resume(self):
        require(self.game()['phase']=='paused','RESUME_REQUIRES_PAUSE');rid=self.game()['run_id'];self.press('P');return self.wait_game(lambda s:s['run_id']==rid and s['phase']!='paused')
    def navigate(self,target,seconds=30):
        # Closed-loop corridor navigation uses only public board coordinates.
        import time
        dist=distances(tuple(target));end=time.perf_counter()+seconds;last=None
        try:
            while time.perf_counter()<end:
                s=self.game();require(s['phase']=='playing','NAVIGATION_INTERRUPTED:'+s['phase']);c=cell(s['player']['cell'])
                if c==tuple(target):return s
                allowed=[(dist.get(neighbor(c,d),9999),d) for d in range(4) if neighbor(c,d)!=c]
                d=min(allowed)[1]
                if last!=d:
                    if last is not None:self.up(KEYS[last])
                    self.down(KEYS[d]);last=d
                self.observe(.015)
            raise CandidateError('NAVIGATION_TIMEOUT')
        finally:
            if last is not None:self.up(KEYS[last])
