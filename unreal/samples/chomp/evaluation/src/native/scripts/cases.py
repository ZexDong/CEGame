"""Chomp rules expressed exclusively in public coordinates and observations.

Private adapters establish preconditions. Every tested effect is caused by real
input and the game's ordinary simulation; no candidate symbols occur here.
"""
from common import *
import time

class Cases:
    def __init__(self,p,fixture,record):self.p=p;self.f=fixture;self.record=record;self.evidence={};self.loss_seen=False
    def check(self,id,ok,reason,details=None):self.record(id,bool(ok),reason,details)
    def setup(self,**kwargs):
        self.p.action_phase='setup'
        try:
            self.p.start_run();self.p.pause();return self.f.setup(fixture_base(**kwargs))
        finally:self.p.action_phase='test'
    def finish(self,label=None):
        self.p.capture(label or self.p.case+'-after');return self.p.game()
    def samples(self,start):
        out=[];seen=set()
        for r in self.p.samples[start:]:
            s=r['state'];key=(s['process_token'],s['snapshot_id'])
            if key not in seen and s.get('game_state'):out.append(s['game_state']);seen.add(key)
        return out
    def active(self,seconds):
        t=self.p.game()['active_seconds'];return self.p.wait_game(lambda s:s['active_seconds']>=t+seconds,seconds+2)
    def trigger(self,seconds=.25):self.p.resume();return self.active(seconds)
    def entry(self):
        s=self.p.game();self.p.capture('entry-menu')
        self.check('D2-title',s['phase']=='menu' and {'start','options','quit'}<={t['id'] for t in s['targets']},'TITLE_CONTENT')
        old=s['run_id'];start=len(self.p.samples);self.p.click_target('start');s=self.p.wait_game(lambda s:s['phase']=='playing',3);self.p.capture('entry-live');self.p.pause();s=self.p.game()
        self.check('D4-start',s['run_id'] and s['run_id']!=old,'NORMAL_START_TRANSITION')
        observed=self.samples(start);initial=[x for x in observed if x['run_id']==s['run_id'] and x['active_seconds']==0]
        # Initial exact publication is a boundary contract; retain any record the
        # external reader acquired, without requiring every rendered frame.
        if initial:
            i=initial[0];initial_ok=i['score']==0 and i['lives']==3 and i['ordinary_remaining']==299 and i['energizers_remaining']==4 and cell(i['player']['cell'])==(14,13) and i['timers']['wave_index']==0
        else:
            i=min((x for x in observed if x['run_id']==s['run_id']),key=lambda x:x['active_seconds']);initial_ok=i['lives']==3 and i['score']==i['ordinary_consumed']*10 and i['ordinary_remaining']+i['ordinary_consumed']==299 and i['active_seconds']<.25 and i['energizers_remaining']==4 and i['timers']['wave_index']==0
        self.check('D3-initial',initial_ok,'INITIAL_RESOURCES',{'exact_initial_observed':bool(initial),'earliest':i})
        remaining={cell(c) for c in i['ordinary_cells']};expected={cell(c) for c in ALL_DOTS}
        self.check('D2-maze',len(remaining)>=290 and remaining<=expected and {cell(c) for c in i['energizer_cells']}=={cell(c) for c in ALL_ORBS},'FULL_MAZE_CONTENT')
        self.check('D2-actors',sorted(g['id'] for g in s['ghosts'])==sorted(COLORS) and s['player'] is not None,'LIVE_PLAYER_AND_FOUR_GHOSTS')
        self.check('D5-title',any(a['operation']=='click' and a['result'].get('input_dispatched') for a in self.p.actions) and s['run_id'] is not None,'TITLE_CLICK_RECEIPT')
        self.check('D5-hud',str(s['score']) in s['hud']['score_text'] and s['hud']['life_icon_count']==s['lives'],'LIVE_HUD_SYNC')
        if self.f:write(self.p.root/'entry-native-renderer.json',self.f.request('probe'))
    def speed(self):
        self.setup(player=motion(4,6,1));self.p.resume();a=self.p.game();b=self.active(.25);self.finish()
        distance=b['player']['position']['x']-a['player']['position']['x'];dt=b['active_seconds']-a['active_seconds'];speed=distance/dt
        self.check('D2-movement',distance>.5,'MOVEMENT_PRESENT')
        self.check('D3-speed',5.7<=speed<=6.3 and abs(b['player']['position']['y']-6)<.01,'PLAYER_SPEED',{'speed':speed})
    def blocked(self):
        results=[]
        for n,(x,y,d) in enumerate([(5,7,1),(14,9,2)]):
            self.p.case=f'blocked-{n}';self.setup(player=motion(x,y,d));a=self.trigger(.3);self.finish()
            results.append(math.dist((a['player']['position']['x'],a['player']['position']['y']),(x,y))<.01)
        self.check('D3-blocked',all(results),'WALL_AND_GATE_REJECTION')
    def buffer(self):
        self.setup(player=motion(4,6,1,.25));self.p.down('Down')
        # A key held from pause must not leak. Resume, release and re-press is the
        # normal boundary, while the tested early request occurs before x=5.
        self.p.up('Down');self.p.resume()
        with self.p.holding('Down'):s=self.p.wait_game(lambda s:s['player']['position']['y']>6.25,1.5)
        self.finish();self.check('D3-buffer',abs(s['player']['position']['x']-5)<.03 and s['player']['heading']=='down','BUFFERED_LEGAL_TURN')
    def buffer_expiry(self):
        self.setup(player=motion(9,6,1));self.p.resume();self.p.press('Down');self.active(.8);s=self.finish()
        self.check('D3-buffer_expiry',abs(s['player']['position']['y']-6)<.03,'RELEASED_TURN_EXPIRES_BEFORE_X14')
    def reverse(self):
        self.setup(player=motion(3,6,1,.25));self.p.resume();a=self.p.game();t=a['active_seconds'];self.p.press('Left');b=self.p.wait_game(lambda s:s['player']['heading']=='left',.4);self.active(.12);c=self.finish()
        self.check('D3-reverse',b['active_seconds']-t<=.10 and c['player']['position']['x']<b['player']['position']['x'] and abs(c['player']['position']['y']-6)<.01,'MID_EDGE_REVERSAL',{'latency':b['active_seconds']-t})
    def wrap(self):
        ok=[]
        for n,(x,y,d,expected) in enumerate([(0,12,3,(29,12)),(29,15,1,(0,15)),(14,0,0,(14,27))]):
            self.p.case=f'wrap-{n}';self.setup(player=motion(x,y,d,.2));self.p.resume();s=self.p.wait_game(lambda s:cell(s['player']['cell'])==expected,.7);self.finish();ok.append(s['player']['heading']==NAMES[d])
        self.check('D3-wrap',all(ok),'THREE_WRAP_PAIRS')
    def dot(self):
        self.setup(player=motion(14,13,1),ordinary_cells=keep_dots(2,[(15,13),(1,1)]));self.p.resume();s=self.p.wait_game(lambda s:s['ordinary_consumed']==298,1);self.p.press('Left');self.active(.18);self.p.press('Right');s=self.active(.20);self.finish()
        self.check('D3-dot',s['score']==10 and s['ordinary_consumed']==298 and s['ordinary_remaining']==1,'DOT_SINGLE_REWARD')
    def power(self):
        self.setup(player=motion(1,2,2),ordinary_cells=[c for c in ALL_DOTS if cell(c)!=(1,2)])
        start=len(self.p.samples);self.p.resume();s=self.p.wait_game(lambda s:s['timers']['frightened_remaining_seconds']>0,1);self.finish('power-active');first=s;self.active(.45);end=self.finish('power-settled')
        ss=self.samples(start);self.check('D2-power',s['player']['empowered'],'POWER_EXISTS')
        self.check('D3-power',s['score']==50 and s['energizers_remaining']==3 and s['ordinary_consumed']==1 and 4.8<s['timers']['frightened_remaining_seconds']<=5 and ghost(s,'red')['state']=='frightened','ENERGIZER_SEMANTICS')
        self.check('D5-power',any(x['effects']['camera_impulse_active'] and x['player']['empowered'] for x in ss) and not end['effects']['camera_impulse_active'],'EMPOWERMENT_FEEDBACK_BOUNDED')
    def refresh(self):
        self.setup(player=motion(1,2,2),ordinary_cells=[c for c in ALL_DOTS if cell(c)!=(1,2)],frightened_remaining_seconds=.8,capture_chain=2,wave_remaining_seconds=3.2)
        self.p.resume();s=self.p.wait_game(lambda s:s['score']==50,1);self.finish('refresh-active');self.active(1);b=self.p.game();self.p.wait_game(lambda s:s['timers']['frightened_remaining_seconds']==0,5);e=self.finish('refresh-expired')
        self.check('D3-refresh',s['capture_chain']==2 and s['timers']['frightened_remaining_seconds']>4.8 and b['timers']['frightened_remaining_seconds']>3.7 and e['capture_chain']==0 and 2.8<e['timers']['wave_remaining_seconds']<=3.2,'REFRESH_CHAIN_AND_WAVE')
    def ghost_speed(self):
        speeds=[]
        for n,(kind,fright,expected) in enumerate([('normal',0,2),('normal',4,2),('returning',0,4)]):
            self.p.case=f'ghost-speed-{n}';self.setup(player=motion(28,26,2),ghosts=[gstate(c,3+i,6,1,kind) for i,c in enumerate(COLORS)],frightened_remaining_seconds=fright)
            self.p.resume();a=self.p.game();b=self.active(.15);self.finish();dt=b['active_seconds']-a['active_seconds'];v=[]
            for color in COLORS:
                pa=ghost(a,color)['position'];pb=ghost(b,color)['position'];v.append(math.dist((pa['x'],pa['y']),(pb['x'],pb['y']))/dt)
            speeds.append({'expected':expected,'actual':v})
        self.check('D2-pursuit',all(any(v>.2 for v in s['actual']) for s in speeds),'FOUR_ROLES_MOVE')
        self.check('D3-ghost_speed',all(all(abs(v-r['expected'])<=.05*r['expected']+.03 for v in r['actual']) for r in speeds),'GHOST_SPEEDS',speeds)
    def release(self):
        results=[]
        for n in [30,60,90]:
            self.p.case=f'release-{n}';color=COLORS[n//30];self.setup(player=motion(14,13,1),ordinary_cells=keep_dots(300-n,[(15,13)]))
            before=self.p.game();self.p.resume();s=self.p.wait_game(lambda s:s['ordinary_consumed']>=n,1);deadline=s['active_seconds'];s=self.p.wait_game(lambda s:ghost(s,color)['state']!='waiting',.4);self.finish()
            results.append(ghost(before,color)['state']=='waiting' and ghost(s,color)['state'] in ['leaving','normal'] and s['active_seconds']-deadline<=.15)
        self.check('D2-release',any(results),'HOME_DEPARTURE_PRESENT');self.check('D3-release',all(results),'ORDINARY_RELEASE_THRESHOLDS')
    def inactivity(self):
        self.setup(player=motion(14,13,0),inactivity_remaining_seconds=.35);self.p.resume();a=self.p.game();s=self.p.wait_game(lambda s:ghost(s,'cyan')['state']=='leaving',1);self.finish('inactivity-first')
        order=ghost(s,'pink')['state']=='waiting' and ghost(s,'orange')['state']=='waiting';t=s['active_seconds'];s=self.p.wait_game(lambda s:ghost(s,'pink')['state']=='leaving',5.5);self.finish('inactivity-second')
        self.check('D3-inactivity',order and abs(s['active_seconds']-t-5)<=.15 and ghost(s,'orange')['state']=='waiting','ONE_FORCED_RELEASE_PER_INTERVAL')
    def waves(self):
        results=[]
        for w in range(7):
            self.p.case=f'waves-{w}';self.setup(player=motion(28,26,2),wave_index=w,wave_remaining_seconds=.3,ghosts=safe_ghosts())
            self.p.resume();s=self.p.wait_game(lambda s:s['timers']['wave_index']==w+1,.8);self.finish();results.append(s['timers']['wave_mode']==('chase' if (w+1)%2 else 'scatter') and (s['timers']['wave_remaining_seconds'] is None if w==6 else 4.8<s['timers']['wave_remaining_seconds']<=5))
        self.p.case='waves-fright';self.setup(player=motion(28,26,2),wave_index=2,wave_remaining_seconds=2.8,frightened_remaining_seconds=.45);self.p.resume();a=self.active(.2);self.p.wait_game(lambda s:s['timers']['frightened_remaining_seconds']==0,1);b=self.active(.2);self.finish()
        self.check('D3-waves',all(results) and abs(a['timers']['wave_remaining_seconds']-2.8)<.02 and 2.3<b['timers']['wave_remaining_seconds']<2.8,'WAVE_SEQUENCE_AND_SUSPENSION')
    def pursuit(self,color):
        gs=safe_ghosts();index=COLORS.index(color);gs[index]=gstate(color,8,6,1);gs[0]=gstate('red',20,6,1) if color!='red' else gs[0]
        self.setup(player=motion(14,13,0),ghosts=gs,wave_index=7,wave_remaining_seconds=0);self.p.resume();self.active(.05);s=self.finish();g=ghost(s,color);target=cell(g['intent_cell'])
        if color=='red':allowed={cell(s['player']['cell'])}
        elif color=='pink':allowed={ahead(s['player'],4)}
        elif color=='cyan':
            a=ahead(s['player'],2);r=cell(ghost(s,'red')['cell']);ref=(2*a[0]-r[0],2*a[1]-r[1]);cells=[(x,y) for y in range(28) for x in range(30) if legal((x,y))];best=min(math.dist(c,ref) for c in cells);allowed={c for c in cells if abs(math.dist(c,ref)-best)<1e-6}
        else:allowed={tuple(c) for c in LAYOUT['scatter_pairs'][color]}
        self.check('D3-'+color,target in allowed,'PUBLIC_PURSUIT_DESTINATION',{'actual':target,'allowed':sorted(allowed)})
    def red(self):self.pursuit('red')
    def pink(self):self.pursuit('pink')
    def cyan(self):self.pursuit('cyan')
    def orange(self):
        results=[]
        for n,(player,enemy,near) in enumerate([((8,6),(1,6),True),((9,6),(1,6),False)]):
            self.p.case=f'orange-{n}';gs=safe_ghosts();gs[3]=gstate('orange',*enemy,1);self.setup(player=motion(*player,0),ghosts=gs,wave_index=7,wave_remaining_seconds=0);self.p.resume();s=self.active(.03);self.finish();target=cell(ghost(s,'orange')['intent_cell']);results.append(target==player if near else target in {tuple(x) for x in LAYOUT['scatter_pairs']['orange']})
        self.check('D3-orange',all(results),'STRICT_EIGHT_CELL_ORANGE_BOUNDARY')
    def flee(self):
        gs=safe_ghosts();gs[0]=gstate('red',8,6,1);self.setup(player=motion(5,6,0),ghosts=gs,frightened_remaining_seconds=4);self.p.resume();s=self.active(.03);self.finish();g=ghost(s,'red');origin=(8,6);dist=distances(cell(s['player']['cell']));choices=[neighbor(origin,d) for d in range(4) if neighbor(origin,d)!=origin];far=[c for c in choices if dist[c]>dist[origin]];allowed=far or [c for c in choices if dist[c]==max(dist[x] for x in choices)]
        self.check('D3-flee',cell(g['intent_cell']) in allowed and g['state']=='frightened','FRIGHTENED_DISTANCE_CHOICE')
    def capture(self):
        gs=[gstate(c,15,13,3,progress=.15) for c in COLORS];self.setup(player=motion(14,13,1),ghosts=gs,frightened_remaining_seconds=4,ordinary_cells=keep_dots(1,[(1,1)]));start=len(self.p.samples)
        self.p.resume();s=self.p.wait_game(lambda s:s['capture_chain']>=4,1);self.finish('capture-returning');self.active(.3);b=self.finish('capture-later');ss=self.samples(start)
        self.check('D2-capture',any(g['state']=='returning' for g in s['ghosts']),'RETURNING_FORM_PRESENT')
        self.check('D3-capture',s['score']==3000 and s['lives']==3 and b['score']==3000 and b['capture_chain']==4,'CAPTURE_CHAIN_SINGLE_CONTACT')
        self.check('D5-capture',any(x['effects']['camera_impulse_active'] for x in ss) and all(g['state']=='returning' for g in s['ghosts']),'CAPTURE_FEEDBACK')
    def return_(self):
        gs=safe_ghosts();gs[0]=gstate('red',14,9,2,state='returning');self.setup(player=motion(14,13,0),ghosts=gs,frightened_remaining_seconds=4);self.p.resume();start=len(self.p.samples)
        s=self.p.wait_game(lambda s:ghost(s,'red')['state']=='leaving',2);self.finish('return-home');s=self.p.wait_game(lambda s:ghost(s,'red')['state']=='frightened',2);self.finish('return-roaming');ss=self.samples(start)
        self.check('D3-return',s['lives']==3 and s['capture_chain']==0 and any(ghost(x,'red')['state']=='returning' for x in ss) and ghost(s,'red')['state']=='frightened','RETURN_HOME_AND_IMMEDIATE_REJOIN')
    def death_setup(self,lives=3):
        return self.setup(player=motion(14,13,1),ghosts=[gstate(c,15,13,3,progress=.15) for c in COLORS],lives=lives,ordinary_cells=keep_dots(2,[(1,1),(1,2)]),score=120,extra_life_progress=100,fruit_remaining_seconds=6,fruit_thresholds=[70])
    def death(self):
        self.death_setup();self.p.resume();s=self.p.wait_game(lambda s:s['phase']=='dying',1);self.finish('death-immediate');self.p.press('P');self.p.observe(.25);b=self.finish('death-frozen')
        self.check('D3-death',s['lives']==2 and b['lives']==2 and s['score']==b['score']==120 and b['active_seconds']==s['active_seconds'] and b['phase']=='dying','SINGLE_DAMAGE_AND_FROZEN_DYING')
        self.check('D5-death',not s['player']['visible'] and any(t['id']=='restart' and t['enabled'] and t['visible'] for t in s['targets']),'DEATH_RESTART_AND_FEEDBACK')
    def recovery(self):
        before=self.death_setup();self.p.resume();a=self.p.wait_game(lambda s:s['phase']=='dying',1);t=time.perf_counter();s=self.p.wait_game(lambda s:s['phase']=='playing' and s['life_index']==1,3.5);elapsed=time.perf_counter()-t;self.finish()
        self.check('D2-recovery',s['phase']=='playing' and s['life_index']==1,'RECOVERY_PRESENT')
        self.check('D3-recovery',2.8<=elapsed<=3.2 and s['score']==120 and s['lives']==2 and s['ordinary_cells']==before['ordinary_cells'] and not s['fruit']['present'] and s['fruit']['spawned_thresholds']==[70] and s['capture_chain']==0 and s['extra_life_progress']==0 and s['timers']['wave_index']==0 and s['player']['heading']=='right','PARTIAL_MAZE_RECOVERY',{'elapsed':elapsed})
    def loss(self):
        self.death_setup(1);self.p.resume();s=self.p.wait_game(lambda s:s['phase']=='dying',1);t=time.perf_counter();s=self.p.wait_game(lambda s:s['phase']=='lost',3.5);elapsed=time.perf_counter()-t;self.finish('loss-terminal');self.p.press('Right');self.p.observe(.25);b=self.finish('loss-frozen');self.loss_seen=True
        self.check('D3-loss',2.8<=elapsed<=3.2 and s['lives']==0 and b['phase']=='lost' and b['score']==s['score'] and b['active_seconds']==s['active_seconds'],'SINGLE_FINAL_DEATH_DEADLINE',{'elapsed':elapsed})
    def extra_life(self):
        self.setup(player=motion(14,13,1),lives=2,extra_life_progress=1990,ordinary_cells=keep_dots(2,[(15,13),(1,1)]));self.p.resume();s=self.p.wait_game(lambda s:s['score']==10,1);self.finish();self.check('D2-extra_life',s['lives']>2,'EXTRA_LIFE_EXISTS');self.check('D3-extra_life',s['lives']==3 and s['extra_life_progress']==0,'EXTRA_LIFE_RESET')
    def fruit_spawn(self):
        outcomes=[]
        for n,active in [(70,False),(170,False),(170,True)]:
            self.p.case=f'fruit-spawn-{n}-{active}';self.setup(player=motion(14,13,1),ordinary_cells=keep_dots(300-n,[(15,13)]),fruit_remaining_seconds=6 if active else 0,fruit_thresholds=[70] if n==170 else [])
            self.p.resume();s=self.p.wait_game(lambda s:s['ordinary_consumed']>=n,1);self.finish();outcomes.append(s['fruit']['present'] and n in s['fruit']['spawned_thresholds'] and (5.5<s['fruit']['remaining_seconds']<6 if active else 9.8<s['fruit']['remaining_seconds']<=10))
        self.check('D3-fruit_spawn',all(outcomes),'FRUIT_THRESHOLD_AND_SKIP')
    def fruit_reward(self):
        self.setup(player=motion(14,16,2),fruit_remaining_seconds=5,fruit_thresholds=[70],ordinary_cells=keep_dots(1,[(1,1)]));start=len(self.p.samples);self.p.resume();self.p.capture('fruit-visible');s=self.p.wait_game(lambda s:s['score']==1000,1);self.finish('fruit-reward');self.active(1.4);b=self.finish('fruit-settled');ss=self.samples(start)
        write(self.p.root/'fruit-native-renderer.json',self.f.request('probe'))
        self.check('D2-fruit',not s['fruit']['present'] and s['score']>=1000,'FRUIT_PRESENT_AND_COLLECTIBLE')
        self.check('D3-fruit_reward',s['score']==b['score']==1000 and s['ordinary_consumed']==298 and not s['fruit']['present'],'FRUIT_SINGLE_REWARD')
        self.check('D5-fruit',any(x['effects']['fruit_overlay_visible'] and x['effects']['camera_impulse_active'] for x in ss) and not b['effects']['fruit_overlay_visible'] and not b['effects']['camera_impulse_active'],'FRUIT_FEEDBACK_DEADLINES')
    def fruit_expiry(self):
        self.setup(player=motion(14,13,0),fruit_remaining_seconds=.3,fruit_thresholds=[70]);self.p.resume();self.p.wait_game(lambda s:not s['fruit']['present'],1);s=self.finish();self.check('D3-fruit_expiry',s['score']==0 and s['fruit']['remaining_seconds']==0 and s['fruit']['spawned_thresholds']==[70],'EXPIRY_WITHOUT_REWARD')
    def victory(self):
        self.setup(player=motion(14,13,1),ordinary_cells=keep_dots(1,[(15,13)]),ghosts=[gstate(c,16,13,3) for c in COLORS]);self.p.resume();s=self.p.wait_game(lambda s:s['phase']=='won',1);self.finish('victory-terminal');self.p.press('Right');self.p.observe(.3);b=self.finish('victory-frozen')
        self.check('D3-victory',s['score']==10 and s['ordinary_remaining']==0 and s['energizers_remaining']==4 and s['lives']==3 and b['phase']=='won' and b['score']==s['score'],'FINAL_DOT_PRIORITY_AND_LOCK')
        self.check('D2-results',self.loss_seen and s['phase']=='won','WIN_AND_LOSS_EXIST')
        self.check('D5-results',b['hud']['result_title']=='YOU WIN' and {'restart','main_menu','quit'}<={t['id'] for t in b['targets']},'TERMINAL_FEEDBACK_AND_ACTIONS')
    def pause(self):
        self.setup(player=motion(3,6,1),frightened_remaining_seconds=3,fruit_remaining_seconds=4,fruit_thresholds=[70]);self.p.resume();self.active(.15);self.p.pause();a=self.p.game();self.p.down('Down');self.p.observe(.4);b=self.finish('pause-frozen');self.p.press('P');self.active(.2);c=self.p.game();self.p.up('Down');self.finish('pause-resumed')
        frozen=all(a[k]==b[k] for k in ['score','lives','active_seconds','timers','fruit','player','ghosts'])
        self.check('D2-pause',{'resume','restart','options','main_menu','quit'}<={t['id'] for t in a['targets']},'PAUSE_ACTIONS_PRESENT')
        self.check('D3-pause',frozen and c['phase']=='playing' and c['player']['heading']=='right','PAUSE_CLOCKS_AND_HELD_INPUT_ISOLATION')
    def restart(self,variant):
        if variant in ['dying','lost']:
            self.death_setup(1 if variant=='lost' else 3);self.p.resume();self.p.wait_game(lambda s:s['phase']==('lost' if variant=='lost' else 'dying'),4)
        elif variant=='won':
            self.setup(player=motion(14,13,1),ordinary_cells=keep_dots(1,[(15,13)]));self.p.resume();self.p.wait_game(lambda s:s['phase']=='won',1)
        else:
            gs=safe_ghosts()
            if variant=='return':gs[0]=gstate('red',14,9,2,state='returning')
            self.setup(player=motion(14,13,1),ghosts=gs,frightened_remaining_seconds=3 if variant=='fright' else 0,fruit_remaining_seconds=6 if variant=='fruit' else 0,capture_chain=2 if variant=='fright' else 0,score=350,lives=2)
        old=self.p.game()['run_id'];self.p.click_target('restart');s=self.p.wait_game(lambda s:s['run_id']!=old and s['phase']=='playing',2);self.p.pause();s=self.finish()
        self.check('D4-restart_'+variant,s['lives']==3 and s['score']==s['ordinary_consumed']*10 and s['ordinary_remaining']+s['ordinary_consumed']==299 and s['energizers_remaining']==4 and s['capture_chain']==0 and not s['fruit']['present'] and s['life_index']==0 and s['timers']['wave_index']==0,'RESTART_FULL_RESET')
    def menu_navigation(self):
        self.p.start_run();self.p.pause();rid=self.p.game()['run_id'];self.p.click_target('options');a=self.p.wait_game(lambda s:s['phase']=='options');self.finish('menu-options');self.p.click_target('back');b=self.p.wait_game(lambda s:s['phase']=='paused');self.p.click_target('main_menu');c=self.p.wait_game(lambda s:s['phase']=='menu');self.p.click_target('options');self.p.wait_game(lambda s:s['phase']=='options');self.p.click_target('back');self.p.wait_game(lambda s:s['phase']=='menu');self.finish()
        self.check('D4-menu',a['options_origin']=='paused' and b['run_id']==rid and c['run_id'] is None and c['score']==0 and not c['ghosts'],'MENU_ORIGIN_AND_ABANDON')
        self.check('D2-menus',{'start','options','quit'}<={t['id'] for t in c['targets']},'MENUS_DYNAMICALLY_AVAILABLE')
    def options(self):
        self.p.start_run();self.p.pause();self.p.click_target('options');a=self.p.wait_game(lambda s:s['phase']=='options');original=a['settings']['applied'];self.p.click_target('vsync_next');self.p.wait_game(lambda s:s['settings']['pending']!=original);b=self.p.game();self.p.click_target('revert');c=self.p.wait_game(lambda s:s['settings']['pending']==original);self.finish('options-reverted')
        self.check('D3-options',b['settings']['applied']==original and c['settings']['pending']==original,'PENDING_REVERT_DOES_NOT_APPLY')
        self.p.click_target('vsync_next');self.p.click_target('graphics_next');self.p.click_target('resolution_next');self.p.wait_game(lambda s:s['settings']['pending']!=original);pending=self.p.game()['settings']['pending'];self.p.click_target('apply');d=self.p.wait_game(lambda s:s['settings']['applied']==pending and s['viewport']==pending['resolution'],8,stable=.3);self.finish('options-applied')
        native=self.f.request('probe')['state']['native']['engine_settings'];write(self.p.root/'options-engine-settings.json',native)
        self.check('D4-options',d['viewport']==pending['resolution'] and d['settings']['pending']==pending and native['vsync']==pending['vsync'] and native['quality']==['low','medium','high','epic','cinematic'].index(pending['graphics']) and native['window_mode']==pending['window_mode'],'ACTUAL_ENGINE_AND_VIEWPORT_APPLY')
        self.check('D5-options',len(d['targets'])>=11 and all(t['rect'] and t['rect']['x']+t['rect']['width']<=1.00001 and t['rect']['y']+t['rect']['height']<=1.00001 for t in d['targets']),'RESIZED_CONTROLS_IN_CLIENT')
        self.p.click_target('back');self.p.wait_game(lambda s:s['phase']=='paused')
    def persistence(self):
        self.p.start_run();self.p.wait_game(lambda s:s['score']>=20,2);self.p.pause();a=self.p.game();self.finish('persistence-before-close');old_pid=self.p.pid;old_token=self.p.token;self.p.reopen();b=self.p.game();self.finish('persistence-reopened');self.p.start_run();self.p.wait_game(lambda s:s['score']>=20,2);self.p.pause();c=self.p.game();self.finish('persistence-new-run')
        self.check('D4-save',b['high_score']>=a['score'] and b['high_score']==a['high_score'] and c['high_score']>=b['high_score'],'PERSISTENT_BEST')
        self.check('D4-reopen',self.p.pid!=old_pid and self.p.token!=old_token and b['phase']=='menu' and b['run_id'] is None and b['score']==0 and c['run_id']!=a['run_id'] and b['settings']['applied']==a['settings']['applied'],'NEW_PROCESS_FRESH_STATE')
        self.check('D4-repeat',c['lives']==3 and c['score']==c['ordinary_consumed']*10 and c['ordinary_remaining']+c['ordinary_consumed']==299,'REPEATED_INITIAL_BEHAVIOR')
        self.p.click_target('quit');end=time.perf_counter()+5;alive=True
        while time.perf_counter()<end:
            alive=self.p.rpc('process_status')['result']['alive']
            if not alive:break
            time.sleep(.05)
        self.check('D4-quit',not alive,'NORMAL_QUIT_PROCESS_EXIT')
    def presentation(self):
        self.setup(player=motion(4,6,1));self.p.resume();start=len(self.p.samples);self.active(.3);a=self.finish('presentation-motion');self.p.press('Left');self.active(.15);self.finish('presentation-reverse');ss=self.samples(start)
        rects=[s['player']['screen_rect'] for s in ss if s['player']['visible'] and s['player']['screen_rect']]
        centers=[(r['x']+r['width']/2,r['y']+r['height']/2) for r in rects]
        self.check('D5-camera',centers and all(.25<=x<=.75 and .25<=y<=.75 for x,y in centers) and len({s['player']['mouth_open'] for s in ss})==2,'FOLLOW_CAMERA_AND_CHOMP')
        native=self.f.request('probe')['state'];public=self.p.game();n=native.get('native',{});pos=n.get('player_world_cm',{})
        rendered=n.get('rendered_player_grid',{});observed=native['observation']['player']['position']
        consistent=n.get('score')==native['observation']['score'] and n.get('lives')==native['observation']['lives'] and all(abs(rendered.get(k,1e9)-observed[k])<.01 for k in ['x','y'])
        self.check('D5-honesty',consistent and len(ss)>3 and len({(s['player']['position']['x'],s['player']['position']['y']) for s in ss})>2,'NATIVE_PUBLIC_INPUT_CAUSALITY')
    def run(self,id):
        if id.startswith('restart_'):return self.restart(id[8:])
        if id=='return':return self.return_()
        return getattr(self,id)()
