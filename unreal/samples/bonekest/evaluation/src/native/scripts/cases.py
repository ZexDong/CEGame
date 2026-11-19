"""Dynamic cases. Predicates use only public semantics and engine evidence."""
from pathlib import Path
from collections import Counter,deque
import math,time,json,hashlib
from semantics import *
from runtime import write,CandidateError,InfrastructureError

def trial(f):
    try:return bool(f())
    except (AssertionError,KeyError,ValueError,IndexError):return False
def exit_slot(s,c=None,ungated=True):
    r=rooms(s)[tuple(c or cell(s))]
    return next(x for x in r['attributes']['exits'] if not ungated or not x.get('gate_id'))
def image_ok(c,key):
    # The physical capture is bound to input/state; image health is checked by the
    # engine capture stage. Similarity and reference images are never used here.
    return key in c.captures and bool(c.captures[key]['sha256'])
def mesh_present(n,needle):return any(needle in x['asset'] and x['recently_rendered'] for x in n.get('rendered_components',[]))
def all_text(c,n=None):return ' '.join(c.strings(n))
def state_position(c):
    s=c.state();e=one(s,'player');p=e.get('position')
    if p is None:p=c.native().get('position')
    if p is None:raise InfrastructureError('MOVEMENT_POSITION_MAPPING_REQUIRED')
    return p
def length(a,b):return math.dist(a,b)
def safe_setup(c,room,**kw):
    s=c.state();return c.setup(room=list(room),monster_room=list(c.safe_monster(s,room)),**kw)
def find_gate(s,color):return next(g for g in entities(s,'gate') if g['attributes']['key_color']==color)
def side(s,gate):
    for r in entities(s,'room'):
        for x in r['attributes']['exits']:
            if x.get('gate_id')==gate['id']:return tuple(r['cell']),x
    raise CandidateError('GATE_WITHOUT_PUBLIC_CONNECTION')

def initial(c):
    s=c.restart();c.baseline=world_signature(s);a,n,k=c.snap('initial')
    c.check('D3-initial',fresh(a) and image_ok(c,k),'FRESH_INVENTORY_OR_SAFE_PLACEMENT')

def modes(c):
    snapshots=[];menu_ok=True;entered=True
    for name,size in [('easy',6),('medium',10),('hard',15)]:
        c.to_menu();s,n,k=c.snap(name+'-menu');kinds={t['kind'] for t in s['targets'] if t['visible'] and t['interactable']}
        menu_ok &= {'easy','medium','hard','exit_app','seed_input'}<=kinds
        c.p.click_target(name);s=c.p.wait(lambda s:s['phase']=='exploring',20,stable=.15);s,n,k=c.snap(name+'-play');snapshots.append(s);entered &=s['slots']['maze_size']==size and image_ok(c,k)
    c.check('D2-menu',menu_ok and entered,'DIFFICULTY_MENU_CONTENT')
    c.check('D2-rooms',all(len(entities(s,'room'))==s['slots']['maze_size']**2 for s in snapshots),'ROOM_POPULATION_INCOMPLETE')
    c.check('D2-resources',all(trial(lambda:content(s)) for s in snapshots),'RESOURCE_DISTRIBUTION_MINIMUM')
    c.check('D3-graph',all(trial(lambda:graph_valid(s)) for s in snapshots),'GRAPH_INVARIANT')
    c.check('D3-locks',all(trial(lambda:locks_valid(s)) for s in snapshots),'LOCK_REACHABILITY')
    c.check('D4-entry',entered,'DIFFICULTY_ENTRY_FLOW')
    c.to_menu();c.p.click_target('easy');c.p.wait(lambda s:s['phase']=='exploring',15)

def content_case(c):
    s=c.restart();ok=True
    for rname in ['start','red_key','green_key','blue_key','exit']:
        rr=[r for r in entities(s,'room') if r['state']==rname];ok &=len(rr)==1
        if not rr:continue
        room=rr[0]['cell'];safe_setup(c,room,anchor='center');c.p.hold(['D'],.08);a,n,k=c.snap(rname)
        ok &=cell(a)==tuple(room) and any(r['visible'] for r in entities(a,'room') if r['cell']==room) and image_ok(c,k)
        if rname.endswith('_key'):ok &=len([p for p in entities(a,'pickup') if p['cell']==room and p['attributes'].get('key_color')==rname[:-4]])==1
        if rname=='exit':ok &=one(a,'exit')['cell']==room and one(a,'exit')['visible']
    c.check('D2-roles',ok,'ROLE_ROOM_CONTENT_OR_PRESENTATION')

def arrangements(c):
    s=c.restart();selected={}
    for r in entities(s,'room'):
        if r['state']=='ordinary':selected.setdefault(r['attributes']['layout_id'],r['cell'])
    geometry=set();assets=set()
    for label,room in list(selected.items())[:24]:
        safe_setup(c,room,anchor='center');c.p.hold(['D'],.05);c.p.observe(.12);a,n,k=c.snap('layout')
        objs=[x for x in n['rendered_components'] if '/SimpleDungeons/' in x['asset'] and x['recently_rendered']]
        if objs:
            x0=min(o['position'][0] for o in objs);y0=min(o['position'][1] for o in objs)
            signature=sorted((o['asset'],round(o['position'][0]-x0,0),round(o['position'][1]-y0,0),round(o['position'][2],0)) for o in objs)
            geometry.add(hashlib.sha256(json.dumps(signature).encode()).hexdigest());assets|={o['asset'].split('.')[-1] for o in objs}
    c.check('D2-arrangements',len(selected)>=20 and len(geometry)>=20,'TWENTY_ACTUAL_GEOMETRIC_ARRANGEMENTS',{'observed_layouts':len(selected),'geometry_signatures':len(geometry),'captures':[k for k in c.captures if k.startswith('arrangements')]})
    required={'SM_Env_Floor_Stone_01','SM_Env_Wall_01','SM_Env_Doorway_01','SM_Env_Pillar_Stone_01','SM_Prop_Stone_Coffin_01','SM_Prop_Skull_01','SM_Prop_Torch_01'}
    c.check('D2-architecture',required<=assets,'REQUIRED_ENVIRONMENT_NOT_RENDERED',{'missing':sorted(required-assets),'assets':sorted(assets)})

def seed(c):
    c.to_menu();c.set_seed('48');c.p.click_target('easy');a=c.p.wait(lambda s:s['phase']=='exploring',15);sig=world_signature(a)
    b=c.restart();same=world_signature(b)==sig
    c.to_menu();c.set_seed('49');c.p.click_target('easy');d=c.p.wait(lambda s:s['phase']=='exploring',15);different=world_signature(d)!=sig
    c.to_menu();c.set_seed('4294967296');c.p.click_target('easy');c.p.observe(.25);invalid=c.state()['phase']=='menu' and '4294967295' in all_text(c)
    c.snap('invalid');c.to_menu();c.set_seed('48');c.p.click_target('easy');c.p.wait(lambda s:s['phase']=='exploring',15)
    c.check('D3-seed',same and different and invalid,'SEED_REPRODUCTION_VARIATION_OR_INVALID_INPUT')

def movement(c):
    c.restart()
    with c.p.holding(['D']):
        c.p.observe(.25);a0=state_position(c);t0=c.state()['simulation_seconds'];c.p.observe(.3);a1=state_position(c);t1=c.state()['simulation_seconds']
    c.p.observe(.15);released=state_position(c);c.p.observe(.2);still=state_position(c);s,n,k=c.snap('axial')
    axial=length(a0,a1)/max(.01,t1-t0)
    c.restart()
    with c.p.holding(['D','W']):
        c.p.observe(.25);b0=state_position(c);u0=c.state()['simulation_seconds'];c.p.observe(.3);b1=state_position(c);u1=c.state()['simulation_seconds']
    diag=length(b0,b1)/max(.01,u1-u0)
    c.restart();z=state_position(c);c.p.hold(['A','D'],.3);cancel=length(z,state_position(c))<2
    c.check('D3-movement',axial>0 and abs(diag/axial-1)<=.02 and length(released,still)<2 and cancel,'CONTINUOUS_MOTION_DIAGONAL_RELEASE_OR_OPPOSITE_KEYS',{'axial_speed':axial,'diagonal_speed':diag,'measurement':'Two complete position/time samples after settled movement; public 2 percent tolerance','release_drift':length(released,still),'captures':[k]})
    c.check('D2-mage',mesh_present(n,'SK_PlayerCharacter') and length(a0,a1)>0 and image_ok(c,k),'REQUIRED_MAGE_OR_LOCOMOTION_ABSENT')

def spell(c):
    c.restart();before=c.state();c.p.press('Q',80);a=c.p.wait(lambda s:s['slots']['scrolls']<before['slots']['scrolls'],3);a,n,k=c.snap('cast')
    with c.p.holding(['Q']):c.p.observe(.8);b=c.state()
    no_turn=before['slots']['room_changes']==b['slots']['room_changes'] and monster(before)==monster(b)
    c.check('D3-spell_cost',a['slots']['scrolls']==4 and b['slots']['scrolls']==3,'Q_PRESS_HOLD_COST')
    c.check('D3-turns',no_turn,'LOCAL_ACTION_ADVANCED_MONSTER')
    c.check('D2-spell',a['slots']['reveal_active']==1 and any(e['attributes'].get('effect_kind')=='cast' for e in entities(a,'effect')) and image_ok(c,k),'REVEAL_OR_CAST_PRESENTATION_MISSING')

def reveal(c):
    c.restart();c.p.press('Q',60);a=c.p.wait(lambda s:s['slots']['reveal_active']==1,3);sample=one(a,'player')['attributes'].get('revealed_cell');start=a['simulation_seconds'];c.p.observe(1.1)
    old_rem=one(c.state(),'player')['attributes']['reveal_remaining_seconds'];c.p.press('Q',60);b=c.p.wait(lambda s:one(s,'player')['attributes']['reveal_remaining_seconds']>old_rem,2)
    d=c.p.wait(lambda s:s['slots']['reveal_active']==0,3.6);elapsed=d['simulation_seconds']-b['simulation_seconds']
    c.snap('expired');c.check('D3-reveal_timer',sample==list(monster(a)) and one(b,'player')['attributes']['reveal_remaining_seconds']>=2.7 and 2.8<=elapsed<=3.12,'REVEAL_SAMPLE_REFRESH_OR_DURATION')

def depleted(c):
    c.restart();c.setup(scrolls=0);before=c.state();c.p.press('Q',80);c.p.observe(.2);a,n,k=c.snap('rejected');c.p.observe(1.1);b=c.state()
    ok=a['slots']['scrolls']==0 and not a['slots']['reveal_active'] and monster(a)==monster(before) and not any(e['attributes'].get('effect_kind')=='cast' for e in entities(a,'effect'))
    c.check('D3-depleted',ok,'DEPLETED_CAST_WAS_ACCEPTED')

def passage(c):
    c.restart();s=c.state();x=exit_slot(s);origin=cell(s);dest=tuple(x['destination_cell']);safe_setup(c,origin,anchor='passage',slot=x['slot']);before=c.state();t0=before['simulation_seconds']
    after=c.cross(x['slot']);c.p.observe(.2);after=c.state();c.snap('arrival')
    exact=cell(after)==dest and after['slots']['room_changes']==before['slots']['room_changes']+1
    if after['phase']=='recovering':c.p.wait(lambda s:s['phase']=='exploring',3)
    if cell(after)==dest:
        safe_setup(c,dest,anchor='passage',slot=x['destination_slot']);back=c.cross(x['destination_slot']);exact &=cell(back)==origin
    c.check('D3-passages',exact,'TRANSFER_DESTINATION_RECIPROCITY_OR_DUPLICATE')

def encounter(c):
    c.restart();s=c.state();x=exit_slot(s);dest=x['destination_cell'];origin=cell(s);c.setup(room=list(origin),monster_room=dest,lives=5,scrolls=7,coins=17,keys=['red'],anchor='passage',slot=x['slot']);b=c.state()
    a=c.cross(x['slot']);hit=c.p.wait(lambda s:s['slots']['lives']==4,2);hit_time=hit['simulation_seconds'];c.snap('hit');settled=c.p.wait(lambda s:s['phase']=='exploring',2.3);c.snap('recovered')
    c.check('D3-hit',hit['slots']['lives']==4 and monster(hit)==tuple(dest) and hit['slots']['room_changes']==b['slots']['room_changes']+1,'DIRECT_ENTRY_DAMAGE_OR_EXTRA_MONSTER_MOVE')
    c.check('D3-recovery',cell(settled)==role(settled,'start') and settled['simulation_seconds']-hit_time<=2.1 and [settled['slots'][k] for k in ['lives','scrolls','coins','red_key']]==[4,7,17,1] and distances(settled,cell(settled))[monster(settled)]>=2,'RECOVERY_TIMING_RETENTION_OR_SAFETY')

def monster_case(c):
    c.restart();s=c.state();x=exit_slot(s);dest=tuple(x['destination_cell']);m=c.safe_monster(s,dest);c.setup(room=list(cell(s)),monster_room=list(m),anchor='passage',slot=x['slot']);a=c.cross(x['slot']);c.snap('step');new=monster(a)
    c.check('D3-monster_step',new in neighbors(s,m),'MONSTER_DID_NOT_TAKE_ONE_CONNECTED_STEP')

def danger(c):
    c.restart();s=c.state();origin=cell(s);near=neighbors(s,origin)[0];c.setup(monster_room=list(near));c.p.press('Q',60);c.p.wait(lambda s:s['slots']['reveal_active']==1,3);a,n,k=c.snap('near-revealed');both=a['slots']['danger_nearby']==1 and a['slots']['reveal_active']==1 and any('nearby' in t.lower() for t in c.strings(n))
    c.p.wait(lambda s:s['slots']['reveal_active']==0,3.5);b=c.state();safe_setup(c,origin,anchor='center');c.p.press('E',60);d=c.state();c.snap('safe')
    c.check('D3-danger',both and b['slots']['danger_nearby']==1 and d['slots']['danger_nearby']==0,'DANGER_GRAPH_DISTANCE_OR_REVEAL_CLEAR')

def distribution(c):
    c.restart();s=c.state();origin=cell(s);x=exit_slot(s);dest=tuple(x['destination_cell']);m=c.safe_monster(s,dest);ns=neighbors(s,m);ds=distances(s,dest);short=[v for v in ns if ds[v]<ds[m]]
    counts=Counter();series=[]
    # Probability tests are statistical, never an exact finite 6:5 quota.
    for i in range(128):
        c.setup(room=list(origin),monster_room=list(m),anchor='passage',slot=x['slot']);before=c.state();a=c.cross(x['slot']);counts[monster(a)]+=1;series.append(monster(a))
    n=len(series);observed=sum(counts[k] for k in short);p=6/11+5/11*len(short)/4
    tolerance=5*math.sqrt(n*p*(1-p))+2
    legal=all(k in ns for k in counts) and abs(observed-n*p)<=tolerance
    for k in ns:
        if k not in short:legal &= abs(counts[k]-n*5/44)<=5*math.sqrt(n*5/44*(1-5/44))+2
    c.check('D3-monster_distribution',legal,'MONSTER_DISTRIBUTION_INCONSISTENT',{'samples':n,'shortening':observed,'expected_probability':p,'counts':{str(k):v for k,v in counts.items()},'false_rejection_policy':'five standard deviations plus two observations; no exact frequency requirement','raw_sequence':series})

def pickups(c):
    seen={};key_ok=True;once=True;scroll=True;heart=True
    for kind,color in [('coin',None),('scroll',None),('heart',None)]+[('key',x) for x in COLORS]:
        c.restart();s=c.state();p=next(p for p in entities(s,'pickup','available') if p['attributes']['pickup_kind']==kind and (color is None or p['attributes'].get('key_color')==color));safe_setup(c,p['cell'],anchor='pickup',pickup_id=p['id']);b=c.state();a=c.pickup(p);a,n,k=c.snap(kind+(color or ''));c.p.observe(.25);d=c.state();seen[(kind,color)]=a['slots']!=b['slots'] and image_ok(c,k)
        once &=a['slots']==d['slots'] and next(e for e in entities(d,'pickup') if e['id']==p['id'])['visible']==False
        if kind=='scroll':scroll &=a['slots']['scrolls']==6 and a['slots']['lives']==5
        if kind=='heart':heart &=a['slots']['lives']==6 and a['slots']['scrolls']==5
        if color:key_ok &=a['slots']['keys_owned']==1 and a['slots'][color+'_key']==1
        # Leave through fixture setup only, then genuinely walk over the consumed
        # location after restoring the same persistent room. No reward setter.
        room=tuple(p['cell']);other=neighbors(d,room)[0];safe_setup(c,other,anchor='center');safe_setup(c,room,anchor='center');c.p.hold(['D'],.1);e=c.state();once &=next(q for q in entities(e,'pickup') if q['id']==p['id'])['state']=='consumed'
    c.check('D2-pickups',all(seen.values()),'PICKUP_KIND_NOT_USABLE')
    c.check('D3-keys',key_ok,'KEY_COLOR_OR_DUPLICATE_OWNERSHIP')
    c.check('D3-pickup_once',once,'PICKUP_DUPLICATE_OR_ROOM_RESPAWN')
    c.check('D3-scroll_uncapped',scroll,'SCROLL_INCREMENT_OR_CAP')
    c.check('D3-heart_uncapped',heart,'HEART_INCREMENT_OR_CAP')

def economy(c):
    c.restart();s=c.state();p=next(p for p in entities(s,'pickup','available') if p['attributes']['pickup_kind']=='coin');safe_setup(c,p['cell'],anchor='pickup',pickup_id=p['id'],coins=49,lives=5);a=c.pickup(p);c.snap('exchange');c.p.observe(.3);b=c.state();c.check('D3-coin_exchange',[a['slots'][k] for k in ['lives','coins']]==[6,0] and [b['slots'][k] for k in ['lives','coins']]==[6,0],'COIN_THRESHOLD_REMAINDER_OR_REPEAT')

def gate_range(c):
    c.restart();s=c.state();g=find_gate(s,'red');room,x=side(s,g);safe_setup(c,room,anchor='center');b=c.state();c.p.press('E',60);c.p.observe(.2);remote=gate_map(c.state())[g['id']]['state']=='locked'
    safe_setup(c,room,anchor='gate',slot=x['slot'],keys=['blue']);b=c.state();c.p.press('E',60);c.p.observe(.2);a,n,k=c.snap('wrong-key');locked=gate_map(a)[g['id']]['state']=='locked' and a['slots']==b['slots'] and 'red' in all_text(c,n).lower()
    c.check('D3-gate_range',remote and any(t['kind']=='gate' and t['interactable'] and t.get('entity_id')==g['id'] for t in a['targets']),'REMOTE_OR_MISSING_GATE_TARGET')
    c.check('D3-gate_locked',locked,'WRONG_KEY_GATE_REJECTION')

def gates(c):
    usable=True;timed=True;shared=True
    for color in COLORS:
        c.restart();s=c.state();g=find_gate(s,color);room,x=side(s,g);safe_setup(c,room,anchor='gate',slot=x['slot'],keys=[color]);b=c.state();c.p.press('E',80);a=c.p.wait(lambda s:gate_map(s)[g['id']]['state'] in ('opening','open'),3);start=a['simulation_seconds'];c.snap(color+'-opening');c.p.press('E',60);c.p.observe(.25);mid=c.state();remaining=gate_map(mid)[g['id']]['attributes']['opening_remaining_seconds']
        o=c.p.wait(lambda s:gate_map(s)[g['id']]['state']=='open',3.5);elapsed=o['simulation_seconds']-start;usable &=o['slots'][color+'_key']==1;timed &=0<remaining<3 and 2.8<=elapsed<=3.12
        safe_setup(c,x['destination_cell'],anchor='gate',slot=x['destination_slot'],keys=[color]);c.p.press('E',60);d=c.state();shared &=gate_map(d)[g['id']]['state']=='open' and d['slots'][color+'_key']==1;c.snap(color+'-other-side')
    c.check('D2-gates',usable,'COLOURED_GATE_OPERATION')
    c.check('D3-gate_time',timed,'GATE_OPENING_DURATION_OR_REPEAT')
    c.check('D3-gate_shared',shared,'PAIRED_GATE_STATE_DIVERGED')

def collision(c):
    c.restart();s=c.state();g=find_gate(s,'red');room,x=side(s,g);safe_setup(c,room,anchor='gate',slot=x['slot']);b=c.state();target=lambda s:next(t for t in s['targets'] if t['kind']=='passage' and t.get('attributes',{}).get('slot')==x['slot'])
    try:c.move(target,lambda s:s['slots']['room_changes']>b['slots']['room_changes'],1)
    except CandidateError:pass
    a=c.state();blocked=a['slots']['room_changes']==b['slots']['room_changes'];c.snap('closed-gate')
    c.restart();z=state_position(c)
    with c.p.holding(['D']):
        deadline=time.perf_counter()+7;still_since=None;previous=state_position(c)
        while time.perf_counter()<deadline:
            c.p.observe(.12);now=state_position(c)
            if length(previous,now)<1:
                if still_since is None:still_since=time.perf_counter()
                if time.perf_counter()-still_since>.35:break
            else:still_since=None
            previous=now
        p=state_position(c);c.p.observe(.4);q=state_position(c)
    c.snap('wall')
    c.check('D3-collision',blocked and length(p,q)<4,'SOLID_BOUNDARY_OR_CLOSED_GATE_PASSED')

def establish_outcome(c,win):
    c.restart();s=c.state()
    if win:
        rr=role(s,'exit');safe_setup(c,rr,anchor='final_portal',keys=list(COLORS));before=c.state();c.p.press('E',60);c.p.observe(.15);premature=c.state()['phase']!='exploring';a=c.final();return before,a,not premature
    x=exit_slot(s);c.setup(monster_room=x['destination_cell'],lives=1,anchor='passage',slot=x['slot']);before=c.state();a=c.cross(x['slot']);a=c.p.wait(lambda s:s['phase']=='lost',3);return before,a,True

def outcomes(c):
    locked=True
    for missing in COLORS:
        c.restart();s=c.state();rr=role(s,'exit');safe_setup(c,rr,anchor='final_portal',keys=[x for x in COLORS if x!=missing]);b=c.state()
        try:c.final(rejection_color=missing)
        except CandidateError:pass
        a,n,k=c.snap('missing-'+missing);locked &=a['phase']=='exploring' and missing in all_text(c,n).lower() and a['slots']['keys_owned']==2
    c.check('D3-exit_lock',locked,'EXIT_ACCEPTED_INCOMPLETE_KEYS_OR_MISSING_FEEDBACK')
    terminal=True;usable=True;titles=True;win_correct=False;lost_correct=False
    for win in [True,False]:
        b,a,normal=establish_outcome(c,win);a,n,k=c.snap('win' if win else 'lose');result_phase='won' if win else 'lost';usable &=a['phase']==result_phase and image_ok(c,k)
        if win:win_correct=normal and a['phase']=='won' and one(a,'exit')['state']=='completed'
        else:lost_correct=a['phase']=='lost' and a['slots']['lives']==0
        title='You escaped' if win else 'You were bonked';titles &=title.lower() in all_text(c,n).lower() and {'restart','main_menu'}<={t['kind'] for t in a['targets'] if t['interactable'] and t['visible']}
        frozen=invariant(a);c.p.hold(['W','D'],.3);c.p.press('Q',60);c.p.press('E',60);c.p.press('Escape',60);c.p.observe(.5);d=c.state();terminal &=invariant(d)==frozen;c.snap('terminal-input')
        old=d['round_id'];c.p.click_target('restart');e=c.p.wait(lambda s:s['round_id']!=old and s['phase']=='exploring',15);titles &=fresh(e)
    c.check('D2-outcomes',usable,'RESULT_CONTENT_MISSING')
    c.check('D3-exit_trigger',win_correct,'FINAL_PORTAL_TRIGGER_INCORRECT')
    c.check('D3-fatal',lost_correct,'LAST_LIFE_DID_NOT_LOSE_ONCE')
    c.check('D3-terminal',terminal,'POST_RESULT_GAMEPLAY_MUTATION')
    c.check('D4-failure',lost_correct and titles,'DEFEAT_TO_RESTART_FLOW')
    c.check('D5-results',titles,'RESULT_TEXT_CONTROLS_OR_CLICK_RESPONSE')

def restart(c):
    c.restart();s=c.state();sig=world_signature(s);c.p.press('Q',60);safe_setup(c,role(s,'red_key'),anchor='center',lives=2,coins=40,keys=['red']);old=c.state()['round_id'];a=c.restart();c.snap('fresh');ok=fresh(a) and world_signature(a)==sig and a['round_id']!=old
    for win in [True,False]:establish_outcome(c,win);b=c.restart();ok &=fresh(b) and world_signature(b)==sig
    c.check('D4-restart',ok,'RESTART_FAILED_TO_RESTORE_CURRENT_SEED_WORLD')

def cancel(c):
    ok=True
    for precursor in ['cast','gate','crossing','recovery']:
        c.restart();s=c.state()
        if precursor=='cast':c.p.press('Q',60)
        elif precursor=='gate':
            g=find_gate(s,'red');room,x=side(s,g);safe_setup(c,room,anchor='gate',slot=x['slot'],keys=['red']);c.p.press('E',60)
        else:
            x=exit_slot(s)
            if precursor=='recovery':c.setup(monster_room=x['destination_cell'],anchor='passage',slot=x['slot'])
            else:safe_setup(c,cell(s),anchor='passage',slot=x['slot'])
            c.cross(x['slot'])
        before=c.state();a=c.restart();ids={e['id'] for e in before['entities']};c.p.observe(3.25);b=c.state();ok &=fresh(b) and not ids.intersection(e['id'] for e in b['entities']);c.snap(precursor+'-cancelled')
    c.check('D4-cancel',ok,'OLD_ROUND_ACTIVITY_SURVIVED_RESTART')

def pause(c):
    c.restart();c.p.press('Q',60);c.p.wait(lambda s:s['slots']['reveal_active']==1,3);c.p.press('Escape',60);a=c.p.wait(lambda s:s['phase']=='paused',3);remaining=one(a,'player')['attributes']['reveal_remaining_seconds'];clock=a['simulation_seconds'];c.p.hold(['W','Q'],.4);c.p.observe(.6);b=c.state();c.snap('paused');ok=b['simulation_seconds']==clock and b['slots']==a['slots'] and one(b,'player')['attributes']['reveal_remaining_seconds']==remaining
    c.p.click_target('resume');c.p.wait(lambda s:s['phase']=='exploring',3);c.p.observe(.25);d=c.state();ok &=d['simulation_seconds']>clock and d['slots']['scrolls']==a['slots']['scrolls'];c.snap('resumed')
    c.check('D4-pause',ok,'PAUSE_OR_RESUME_CLOCK_AND_INPUT')

def menu(c):
    c.restart();c.p.press('Q',60);old=c.state();c.to_menu();a,n,k=c.snap('discarded');c.p.click_target('easy');b=c.p.wait(lambda s:s['phase']=='exploring',15);c.snap('new-run')
    c.check('D4-menu',a['phase']=='menu' and not a['entities'] and all(v==0 for v in a['slots'].values()) and fresh(b) and b['round_id']!=old['round_id'],'MENU_DISCARD_OR_NEW_RUN')

def reopen(c):
    c.restart();c.p.press('Q',60);a=c.state();pid=a['process_id'];c.p.reopen();b=c.state();c.snap('reopened')
    c.check('D4-reopen',b['phase']=='menu' and not b['entities'] and b['process_id']!=pid and b['session_id']!=a['session_id'],'REOPEN_NOT_FRESH_PROCESS_MENU')

def honesty(c):
    c.restart();c.setup(lives=7,scrolls=8,coins=13);a,n,k=c.snap('precursor');c.p.press('Q',60);c.p.wait(lambda s:s['slots']['scrolls']==7,3);b,m,j=c.snap('after-input')
    ok=all(a['slots'][q]==n[q] and b['slots'][q]==m[q] for q in ('lives','scrolls','coins','room_changes')) and a['round_id']==n['round_id'] and b['round_id']==m['round_id']
    c.check('D3-observation_truth',ok and a['slots']['scrolls']-b['slots']['scrolls']==1 and image_ok(c,j),'OBSERVATION_NATIVE_OR_INPUT_DIVERGENCE')

def interface(c):
    c.to_menu();a,n,k=c.snap('menu');text=all_text(c,n);menu_text=all(word.lower() in text.lower() for word in ['BoneMaze','Easy','Medium','Hard','Exit','Seed','WASD','Q','E','R'])
    assets=c.assets(n);fonts={p for p in assets if '/Fonts/' in p};textures={p for p in assets if '/Buttons/' in p};hover=False;pressed=False
    t=c.p.target('easy')['rect'];c.p.rpc('move',x=t[0]+t[2]/2,y=t[1]+t[3]/2);c.p.observe(.15);hover=any('T_Button_Hover' in p for p in c.assets())
    c.p.rpc('mouse_down',button='Left');c.p.observe(.15);c.snap('pressed');pressed=any('T_Button_Pressed' in p for p in c.assets());c.p.rpc('mouse_up',button='Left');b=c.p.wait(lambda s:s['phase']=='exploring',15);c.p.observe(.2);b,m,j=c.snap('hud');assets|=c.assets(m)
    required=['HeartImage_UI','AttemptsIcon','CoinIcon','KeyRedInactive','KeyGreenInactive','KeyBlueInactive','MonsterGreen']
    hasicons=all(any(name in p for p in assets) for name in required)
    proof={'menu_text':menu_text,'hover':hover,'pressed':pressed,'has_icons':hasicons,'fonts':sorted(fonts),'assets':sorted(assets),'captures':[k,j]}
    c.check('D5-controls',menu_text and hover and pressed and b['phase']=='exploring','MENU_TEXT_HOVER_PRESS_OR_CLICK',proof)
    c.check('D2-interface_assets',hasicons and any('Font_Logo_Font' in p for p in fonts) and any('Font_Main_Font' in p for p in assets) and hover and pressed,'REQUIRED_RUNTIME_UI_ASSET_ROLES',proof)

def feedback(c):
    c.restart();a,n,k=c.snap('before-cast');c.p.press('Q',60);c.p.wait(lambda s:s['slots']['scrolls']==4,3);b,m,j=c.snap('cast-hud')
    text0=all_text(c,n);text1=all_text(c,m);hud='5' in text0 and '4' in text1 and text0!=text1
    exact=f"{b['slots']['monster_x']}-{b['slots']['monster_y']}";reveal=exact in text1 and any('MonsterRed' in p for p in c.assets(m))
    c.p.wait(lambda s:s['slots']['reveal_active']==0,3.5);d=c.native();reveal &=exact not in all_text(c,d)
    c.setup(scrolls=0);c.p.press('Q',60);c.p.observe(.2);a,n,k=c.snap('no-scroll');no_scroll='no scrolls' in all_text(c,n).lower();c.p.observe(1.05);no_scroll &= 'no scrolls' in all_text(c).lower()
    c.restart();s=c.state();g=find_gate(s,'red');rr,x=side(s,g);safe_setup(c,rr,anchor='gate',slot=x['slot']);a,n,k=c.snap('prompt');prompt='red' in all_text(c,n).lower() and any('E' in t for t in c.strings(n));c.p.press('E',60);c.p.observe(.2);a,n,k=c.snap('missing-red');missing='red' in all_text(c,n).lower() and any(q in all_text(c,n).lower() for q in ['requires','need','missing','locked'])
    safe_setup(c,rr,anchor='center');c.p.press('E',60);a,n,k=c.snap('out-of-range');prompt &=not any(t['kind']=='gate' and t['interactable'] for t in a['targets'])
    c.check('D5-hud',hud,'HUD_COUNTER_NOT_UPDATED_WITH_LIVE_TRANSACTION')
    c.check('D5-danger',reveal,'REVEAL_ICON_OR_COORDINATE_TEXT_STALE')
    c.check('D5-rejection',no_scroll and missing,'REJECTION_TEXT_ABSENT_WRONG_OR_TOO_SHORT')
    c.check('D5-gate_prompt',prompt,'GATE_PROMPT_TARGET_OR_RANGE')

def resolution(c):
    from window import WindowHost
    c.restart();ok=True;receipts=[]
    for width,height in [(1280,720),(1920,1080)]:
        r=WindowHost(c.p.process_id).resize(width,height);receipts.append(r);c.p.observe(.2);s,n,k=c.snap(str(width));commands=n['renderer']['commands']
        ok &=bool(commands) and all(v['rect'][0]>=-.002 and v['rect'][1]>=-.002 and v['rect'][0]+v['rect'][2]<=1.002 and v['rect'][1]+v['rect'][3]<=1.002 for v in commands if v['kind']=='text')
    WindowHost(c.p.process_id).resize(1280,720);write(c.root/'resolution-receipts.json',receipts);c.check('D5-resolution',ok,'ESSENTIAL_RENDERED_TEXT_OUTSIDE_PHYSICAL_CLIENT')

def focus(c):
    from window import WindowHost
    c.restart();host=WindowHost(c.p.process_id);c.p.rpc('down',key='D');c.p.held.add('D');c.p.observe(.2);r=host.minimize();c.p.observe(.15);a=state_position(c);c.p.observe(.4);b=state_position(c);host.restore();c.p.rpc('acknowledge_focus_release');c.p.rpc('up',key='D');c.p.held.discard('D');c.p.observe(.2);d=c.state();c.snap('restored');write(c.root/'focus-receipt.json',r)
    c.check('D5-focus',length(a,b)<2 and d['slots']['scrolls']==5,'FOCUS_LOSS_DRIFT_OR_SYNTHETIC_ACTION')

CASES={'initial':initial,'modes':modes,'content':content_case,'arrangements':arrangements,'seed':seed,'movement':movement,'spell':spell,'reveal':reveal,'depleted':depleted,'passage':passage,'encounter':encounter,'monster':monster_case,'danger':danger,'distribution':distribution,'pickups':pickups,'economy':economy,'gate_range':gate_range,'gates':gates,'collision':collision,'outcomes':outcomes,'restart':restart,'cancel':cancel,'pause':pause,'menu':menu,'reopen':reopen,'honesty':honesty,'interface':interface,'feedback':feedback,'resolution':resolution,'focus':focus}
