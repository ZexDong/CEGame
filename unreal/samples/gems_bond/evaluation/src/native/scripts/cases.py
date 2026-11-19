"""Atomic public-semantic cases. No candidate class, field layout or Gold imports."""
import collections,math,time
from spec import *
from support import CandidateError,select,write

NORMAL=['opening','selection','gate']+['build_'+k for k in ['mine','archer','cannon','wall']]+['repeat_build','placement','sale','speed','pause','lifecycle','restart_preparing','restart_countdown','restart_combat','restart_paused','restart_defeated','restart_inflight','reopen','seed','resolution','audio']
def entity(k,pos,tier=1,**kwargs):return {'kind':k,'position':pos,'tier':tier,**kwargs}
def state(units_=None,**kwargs):return {'coins':170,'crystal_health':500,'resume_phase':'combat','wave':1,'completed':0,'wave_total':20,'wave_spawned':20,'countdown':0,'units':units_ or [],**kwargs}
FIXTURES={
 'exact_funds':state(coins=20,resume_phase='rest',wave=11,completed=10,wave_total=0,wave_spawned=0,countdown=8),
 'unaffordable':state(coins=0,resume_phase='rest',wave=11,completed=10,wave_total=0,wave_spawned=0,countdown=8),
 'income':state([entity('mine',[4,3,0],income_remaining=.8),entity('mine',[12,8,0],income_remaining=2.8,paid=600)],resume_phase='rest',wave=11,completed=10,wave_total=0,wave_spawned=0,countdown=8),
 'income_removed':state([entity('mine',[4,3,0],income_remaining=2)],resume_phase='rest',wave=11,completed=10,wave_total=0,wave_spawned=0,countdown=8),
 'regeneration':state([entity('wall',[8,9,0],health=449),entity('mine',[4,3,0],health=1400,income_remaining=10)],crystal_health=450,resume_phase='rest',wave=11,completed=10,wave_total=0,wave_spawned=0,countdown=8),
 'destruction':state([entity('wall',[10,7,0],health=3,paid=5),entity('slime',[10,6.32,0],attack_remaining=.4)]),
 'upgrade_reject':state([entity('archer',[8,8,0],3),entity('cannon',[12,8,0],1,construction_remaining=.3),entity('wall',[11,9,0])],coins=0),
 'clear':state([entity('archer',[10,7,0]),entity('slime',[10,5,0],health=1)]),
 'rest':state(resume_phase='countdown',wave=11,completed=10,countdown=.6,wave_total=0,wave_spawned=0),
 'restart_rest':state(resume_phase='rest',wave=11,completed=10,countdown=8,wave_total=0,wave_spawned=0),
 'enemy_matrix':state([entity(k,[2+i*3,2,t and 0],t) for i,(k,t) in enumerate([])]),
 'obstruction':state([entity('wall',[10,5,0]),entity('slime',[10,3.9,0])]),
 'flight':state([entity('wall',[10,5,0]),entity('bat',[10,3.9,1.25])],wave=4,wave_total=70,wave_spawned=70),
 'melee':state([entity('slime',[10,9.32,0])]),
 'death':state([entity('archer',[10,8,0]),entity('slime',[10,5,0],health=1)]),
 'archer_combat':state([entity('archer',[10,9,0]),entity('slime',[10,5,0],3)]),
 'cannon_combat':state([entity('cannon',[10,9,0]),entity('slime',[10,5,0],3),entity('slime',[10.4,5,0],3)]),
 'archer_flight':state([entity('archer',[10,9,0]),entity('bat',[10,5,1.25],3)],wave=20,wave_total=50,wave_spawned=50),
 'cannon_flight':state([entity('cannon',[10,9,0]),entity('bat',[10,5,1.25],3)],wave=20,wave_total=50,wave_spawned=50),
 'range':state([entity('archer',[10,10-2,0]),entity('slime',[10,2,0],3)]),
 'projectile_block':state([entity('archer',[10,9,0]),entity('wall',[10,7,0]),entity('slime',[10,5,0],3)]),
 'projectile_sale':state([entity('cannon',[10,9,0],paid=25,cooldown_remaining=.8),entity('slime',[10,4.1,0],3)]),
 'cooldown_upgrade':state([entity('cannon',[10,9,0],cooldown_remaining=1.8),entity('slime',[10,5,0],3)],coins=1000),
 'splash_boundary':state([entity('cannon',[10,9,0]),entity('slime',[10,5,0],3),entity('slime',[10.7,5,0],3),entity('slime',[12.5,5,0],3),entity('bat',[10,5,1.25],3)]),
 'terminal_priority':state([entity('slime',[10,9.32,0]),entity('mine',[4,3,0],income_remaining=0)],crystal_health=1),
}
# Every supplied species/tier appears in one isolated live matrix, away from the crystal.
FIXTURES['enemy_matrix']=state([entity(k,[1+i%5*3,1+i//5*2,1.25 if k in ['bat','dragon'] else 0],t) for i,(k,t) in enumerate(ENEMIES)],wave=25,wave_total=101,wave_spawned=101)
for k in ['archer','cannon']:
    for tier in [2,3]:
        FIXTURES[f'upgrade_{k}_{tier}']=state([entity(k,[8,8,0],tier-1,health=TOWERS[k,tier-1]['health']/2,paid=20 if k=='archer' else 25)],coins=200 if tier==2 else 600,resume_phase='rest',wave=11,completed=10,wave_total=0,wave_spawned=0,countdown=8)
for n in list(range(1,26))+[26,30]:FIXTURES['wave_'+str(n)]=state(resume_phase='countdown',wave=n,completed=n-1,countdown=.6,wave_total=0,wave_spawned=0)
for (k,t),stats in ENEMIES.items():
    FIXTURES[f'contact_{k}_{t}']=state([entity(k,[10,9.5-.2*stats['scale'],1.25 if k in ['bat','dragon'] else 0],t,health=1,attack_remaining=.2),entity('archer',[8,9,0],cooldown_remaining=1.8)],crystal_health=300)
for k in ['archer','cannon']:
    for tier in [2,3]:FIXTURES[f'weapon_{k}_{tier}']=state([entity(k,[10,9,0],tier),entity('orc',[10,5,0],3)],wave=25,wave_total=101,wave_spawned=101)
FIXTURES['refund_upgrade']=state([entity('archer',[8,8,0],3,paid=35)])
for operation in ['sell','upgrade']:
    FIXTURES['destroy_during_'+operation]=state([entity('archer',[10,7,0],health=1,paid=20,cooldown_remaining=2),entity('slime',[10,6.32,0],attack_remaining=1)],coins=200)
FIXTURES['enemy_placement']=state([entity('slime',[8,8,0],3),entity('bat',[13,8,1.25],3)])
NORMAL.append('input_boundaries')

def freeze_values(s):
    return {'clock':s['simulation_seconds'],'slots':{k:v for k,v in s['slots'].items() if k!='speed_multiplier'},'entities':[{k:v for k,v in e.items() if k not in ['rect','attributes']} for e in s['entities']]}
def normal(c):
    name=c.name;p=c.p;s=c.state();start=s
    if name=='input_boundaries':
        c.click('build_wall');c.move('board_cell',cell=[8,8]);p.rpc('mouse_down',button='Left');c.observe(.4);before=c.state();p.rpc('mouse_up',button='Left');c.observe(.2);after=c.state()
        c.vote('purchase_rules',not buildings(before) and len(units(after,'wall'))==1 and after['slots']['coins']==165,'A held mouse button does not repeat; the matching release performs one purchase.')
        p.rpc('click',x=.5,y=.5,button='Right',ms=40);c.observe(.1);no_preview=not units(c.state(),'preview');c.key('Escape');c.vote('selection_rules',no_preview and c.state()['slots']['coins']==165,'Right-click and repeated Escape cancel without spending.')
        p.rpc('down',key='F');p.held.add('F');c.wait(lambda x:x['slots']['speed_multiplier']==3);c.key('P',400);paused=c.state();c.observe(.2);c.key('P');resumed=c.state();c.vote('pause_rules',paused['phase']=='paused' and resumed['phase']=='preparing','Holding P triggers one edge, and the next press resumes.')
        c.vote('speed_rules',resumed['slots']['speed_multiplier']==1,'Resuming with F still held does not reactivate fast speed.');p.rpc('up',key='F');p.held.discard('F');return
    if name=='opening':
        c.observe(.3);c.vote('initial_rules',fresh(s),'All specified opening values, coordinates and absent combat objects.');c.vote('opening_content',len(units(s,'crystal'))==1 and len(units(s,'deposit'))==4,'Live entities corroborated by opening frame.');c.capture();return
    if name=='gate':
        c.click('build_mine');c.observe(2.3);c.vote('gate_rules',c.state()['phase']=='preparing' and c.state()['slots']['wave']==0,'Waiting and mine selection do not start the gate.');return
    if name=='selection':
        c.click('build_archer');c.move('board_cell',cell=[8,8]);c.capture('valid-preview');a=c.state();c.click('build_wall');c.move('board_cell',cell=[10,10]);c.capture('invalid-preview');c.key('Escape');c.key('Escape');b=c.state();
        c.vote('selection_rules',a['slots']==b['slots']==start['slots'] and not buildings(b),'Replacing selection, preview and repeated cancel have no economy or ownership effect.');c.vote('ui_build',True,'Frames and receipts for selected, valid, invalid and cancelled states require rendered review.');return
    if name.startswith('build_'):
        k=name[6:];cell=[4,3] if k=='mine' else [8,7];before=c.state();c.build(k,cell);a=c.wait(lambda x:len(units(x,k))==1);c.capture('construction');b=c.wait(lambda x:units(x,k)[0]['state']!='constructing',2)
        c.vote('content_'+k,True,'Real icon and board clicks created a visible structure.');c.vote('purchase_rules',b['slots']['coins']==before['slots']['coins']-before['slots'][k+'_price'] and len(units(b,k))==1,'One purchase, one deduction and completed construction.')
        if k=='mine':c.vote('gate_rules',a['phase']=='countdown' and a['slots']['wave']==1 and 1.6<a['slots']['countdown_seconds']<=2,'First mine starts the countdown immediately.');
        if k=='archer':c.vote('ui_build',True,'Built/selected icon and updated price require rendered review.');c.vote('ui_feedback',bool(units(a,'feedback')),'Positive build feedback follows the receipt.');c.vote('feedback_content',bool(units(a,'feedback')),'Construction and transient feedback were observed.');
        return
    if name=='repeat_build':
        c.build('archer',[8,7]);c.observe(.35);one=c.state();c.click('board_cell',cell=[8,7]);reject=c.state();c.click('board_cell',cell=[9,7]);two=c.wait(lambda x:len(units(x,'archer'))==2)
        c.vote('purchase_rules',one['slots']['coins']==reject['slots']['coins'] and two['slots']['coins']==115 and len(units(two,'archer'))==2,'Held selection supports a second legal cell; occupied click adds no charge.');c.vote('price_rules',two['slots']['archer_price']==50 and two['slots']['cannon_price']==25,'Living archer count affects only archer price.');return
    if name=='placement':
        c.build('mine',[8,8]);a=c.state();c.capture('soil-rejection');c.click('build_archer');c.click('board_cell',cell=[4,3]);b=c.state();c.click('board_cell',cell=[10,10]);d=c.state();
        c.vote('placement_rules',all(x['slots']['coins']==170 and not buildings(x) for x in [a,b,d]),'Mine on soil, tower on deposit and crystal occupation are rejected.');c.vote('ui_build',True,'Invalid preview/rejection captured.');c.vote('ui_feedback',bool(units(d,'feedback')),'Invalid click produces transient public feedback and visible reason.');return
    if name=='sale':
        c.build('archer',[8,7]);c.observe(.35);e=units(c.state(),'archer')[0];a=c.state();c.inspect(e);b=c.state();c.capture('details');c.vote('inspect_rules',a['slots']==b['slots'] and len(buildings(b))==1,'Inspection does not purchase, upgrade or sell.');c.click('sell');d=c.wait(lambda x:not units(x,'archer'))
        c.vote('inspection_content',True,'Real inspection and sale controls completed.');c.vote('refund_rules',d['slots']['coins']==160,'Refund is floor(20/2).');c.vote('price_rules',d['slots']['archer_price']==20,'Sale updates living-count price.');c.vote('ui_context',True,'Details and sale capture require rendered review.');return
    if name=='speed':
        a=c.state();t=time.perf_counter();p.rpc('down',key='F');p.held.add('F');b=c.wait(lambda x:x['slots']['speed_multiplier']==3);c.observe(.7);d=c.state();elapsed=time.perf_counter()-t;p.rpc('up',key='F');p.held.discard('F');c.wait(lambda x:x['slots']['speed_multiplier']==1)
        ratio=(d['simulation_seconds']-a['simulation_seconds'])/elapsed;c.vote('speed_rules',2.6<ratio<3.4,{'observed_clock_ratio':ratio});c.vote('pause_speed_content',True,'Real held/released speed key changes simulation rate.');return
    if name=='pause':
        c.build('mine',[4,3]);c.wait(lambda x:x['phase']=='combat',4);c.key('P');a=c.wait(lambda x:x['phase']=='paused');c.capture('paused');c.observe(.7);b=c.state();c.vote('pause_rules',freeze_values(a)==freeze_values(b) and b['slots']['speed_multiplier']==0,'Simulation, counters, positions and health remain unchanged.');c.vote('regeneration_rules',freeze_values(a)==freeze_values(b),'No regeneration while paused.');c.vote('pause_speed_content',True,'Normal P toggles pause.');c.vote('ui_lifecycle',True,'Pause overlay and Resume target observed.');c.click('resume');c.wait(lambda x:x['phase']!='paused');return
    if name in ['lifecycle','restart_defeated']:
        c.build('mine',[4,3]);p.rpc('down',key='F');p.held.add('F');c.wait(lambda x:x['phase']=='defeated',100);p.rpc('up',key='F');p.held.discard('F');a=c.state();c.capture('defeat');c.observe(.7);b=c.state()
        if name=='lifecycle':
            c.vote('defeat_content',True,'Ordinary mine-to-wave play reached Game Over.');c.vote('flow',True,'Normal entry, purchase, countdown, combat and loss connected.');c.vote('defeat_rules',a['slots']['crystal_health']==0 and freeze_values(a)==freeze_values(b),'Zero health and terminal gameplay lock.');c.vote('ui_lifecycle',True,'Game Over, progress and Restart/Exit require rendered review.');return
    if name.startswith('restart_'):
        phase=name[8:]
        if phase in ['countdown','combat','paused','inflight']:
            if phase=='inflight':c.build('archer',[10,4]);c.key('Escape')
            c.build('mine',[4,3])
            if phase in ['combat','inflight']:c.wait(lambda x:x['phase']=='combat',4)
            if phase=='inflight':c.wait(lambda x:bool(units(x,'arrow')),15)
            if phase=='paused':c.key('P')
        before=c.state();c.key('R');after=c.wait(fresh,1);c.observe(.8);end=c.state();ok=fresh(end) and before['round_id']!=after['round_id'] and before['process_id']==after['process_id']
        c.vote(name,ok,'Normal R creates a distinct clean round in the same process, stable after old work.');return
    if name=='reopen':
        c.build('wall',[8,8]);before=c.state();p.case_budget=None;p.reopen();after=c.wait(fresh,3);c.vote('reopen',before['process_id']!=after['process_id'] and before['session_id']!=after['session_id'],'Normal Stop then new PID and fresh state.');return
    if name=='seed':
        sequences=[];rounds=[]
        for i in range(2):
            c.key('R');c.wait(fresh,1);rounds.append(c.state()['round_id']);c.build('mine',[4,3]);c.wait(lambda x:x['slots']['wave_spawned']>=20,9)
            seen={}
            for row in c.samples():
                if row['round_id']!=rounds[-1]:continue
                for e in enemies(row):seen.setdefault(e['id'],(e['kind'],e['tier'],tuple(round(x,2) for x in e['position'][:2])))
            # Earliest positions can differ by one rendered sample; compare identities
            # of groups and the unchanging along-edge coordinate (north-only wave 1).
            sequences.append([(k,t,round(pos[0],1)) for k,t,pos in seen.values()])
        c.vote('seed_rules',len(sequences[0])==20 and sequences[0]==sequences[1],{'sequence_a':sequences[0],'sequence_b':sequences[1]});c.vote('repeat_round',rounds[0]!=rounds[1],'Repeated real R presses create distinct round identities.');return
    if name=='resolution':
        from window import WindowHost
        checks=[]
        for w,h in [(1280,720),(1920,1080)]:
            write(p.root/f'window-{w}.json',WindowHost(p.process_id).resize(w,h));c.observe(.2);c.capture(str(w));s=c.state();cells={tuple(t['cell']) for t in s['targets'] if t['kind']=='board_cell' and t['interactable']};checks.append(len(cells)==400)
        c.vote('ui_resolutions',all(checks),'All 400 public board targets and control rectangles remain within client; rendered review also required.');return
    if name=='audio':
        p.rpc('audio_start',path=str(p.root/'audio.wav'));c.observe(.5);c.build('wall',[8,8]);c.observe(.5)
        c.click('board_cell',cell=[10,10]);c.observe(.5);c.capture('rejected')
        c.inspect(units(c.state(),'wall')[0]);c.click('sell');c.observe(.5);c.capture('sold')
        c.click('mute');before=c.state();c.observe(.5);c.build('wall',[8,8]);c.observe(.5);c.capture('muted')
        muted_gameplay=len(units(c.state(),'wall'))==1
        c.click('mute');c.observe(1.2);c.capture('unmuted');p.rpc('audio_stop')
        c.vote('audio_mute',before['phase']==c.state()['phase'] and muted_gameplay,'Loopback captures build/reject/sale, mute with a real accepted purchase, and resumed music; signal/listening review required.')
        c.vote('feedback_content',muted_gameplay,'Loopback audio and visible feedback captured, including a purchase while muted.');return
    raise RuntimeError('UNKNOWN_NORMAL_CASE:'+name)

def fixture(c):
    if c.name in REVIEW_FIXTURES:return review_fixture(c)
    name=c.name;p=c.p;setup=c.state();c.key('P');s=c.state()
    if name.startswith('contact_'):
        _,kind,tier=name.split('_');stats=ENEMIES[kind,int(tier)]
        try:c.wait(lambda x:not enemies(x),4)
        except CandidateError as error:
            if str(error)!='CONDITION_TIMEOUT':raise
        c.capture('enemy-outcome');c.observe(.4);drops=melee_damage_intervals(c.samples())
        c.vote('melee_rules',len(drops)>=2 and all(low-.001<=stats['damage']<=high+.001 for _,low,high in drops) and all(abs(b[0]-a[0]-1)<=.15 for a,b in zip(drops,drops[1:])),{'kind':kind,'tier':tier,'damage_intervals':drops})
        c.vote('death_rules',c.state()['slots']['coins']==170+stats['bounty'] and not enemies(c.state()),{'kind':kind,'tier':tier,'bounty':stats['bounty'],'wallet':c.state()['slots']['coins']});return
    if name.startswith('weapon_'):
        _,kind,tier=name.split('_');stats=TOWERS[kind,int(tier)];projectile='arrow' if kind=='archer' else 'cannonball';initial=enemies(setup)[0]['health'];c.wait(lambda x:bool(units(x,projectile)),2);c.capture('flight');c.wait(lambda x:enemies(x)[0]['health']<=initial-2*stats['damage'],4);c.capture('impact');rows=c.samples();drops=[]
        for a,b in zip(rows,rows[1:]):
            aa=enemies(a);bb=enemies(b)
            if aa and bb and aa[0]['health']>bb[0]['health']:drops.append((b['simulation_seconds'],aa[0]['health']-bb[0]['health']))
        damage_ok=len(drops)>=2 and all(value==stats['damage'] for _,value in drops)
        # Moving targets shorten the second projectile flight. Inspect release cadence separately.
        first={}
        for row in rows:
            for e in units(row,projectile):first.setdefault(e['id'],row['simulation_seconds'])
        releases=sorted(first.values());cadence=len(releases)>=2 and all(abs(b-a-stats['cooldown'])<=.15 for a,b in zip(releases,releases[1:]))
        c.vote('upgrade_rules',damage_ok and cadence,{'kind':kind,'tier':tier,'impact_damages':drops,'release_times':releases,'cooldown':stats['cooldown']});return
    if name=='refund_upgrade':
        c.inspect(units(c.state(),'archer')[0]);c.click('sell');a=c.wait(lambda x:not units(x,'archer'));c.observe(.3);c.vote('refund_rules',a['slots']['coins']==187 and c.state()['slots']['coins']==187,'Odd placement price 35 refunds floor(35/2)=17 even at maximum tier; upgrade costs are excluded.');return
    if name.startswith('destroy_during_'):
        c.inspect(units(c.state(),'archer')[0]);operation=name[len('destroy_during_'):];target=select(c.state(),operation);r=target['rect'];p.rpc('move',x=r[0]+r[2]/2,y=r[1]+r[3]/2);p.rpc('mouse_down',button='Left');c.wait(lambda x:not units(x,'archer'),2);p.rpc('mouse_up',button='Left');c.observe(.2);a=c.state();c.capture('stale-release');c.vote('destruction_rules',not units(a,'archer') and a['slots']['coins']==200,'Destruction invalidates a pending real mouse transaction; stale release cannot charge or refund.');return
    if name=='enemy_placement':
        c.build('wall',[8,8]);a=c.state();c.click('board_cell',cell=[13,8]);b=c.state();c.vote('placement_rules',not units(a,'wall') and len(units(b,'wall'))==1 and b['slots']['coins']==165,'Ground enemy overlap rejects construction; a flyer does not occupy a ground cell.');return
    if name.startswith('wave_'):
        n=int(name[5:]);expected=wave(n);c.wait(lambda x:x['phase'] in ['combat','rest'],3);c.capture('start');p.rpc('down',key='F');p.held.add('F')
        if n==11:
            c.wait(lambda x:x['phase']=='countdown' and x['slots']['wave']==12,5);c.vote('schedule_content',True,'Rest wave entered naturally.');c.vote('wave_schedule_rules',all(not enemies(x) for x in c.samples()),'Rest emits no enemies.');
        else:
            total=sum(a for a,k,t in expected['groups']);c.wait(lambda x:x['slots']['wave_spawned']>=total or x['phase']=='defeated',expected['duration']/3+5);c.capture('spawned');seen={};times=[]
            for x in c.samples():
                if x['phase']!='combat':continue
                for e in enemies(x):
                    if e['id'] not in seen:seen[e['id']]=e;times.append(x['simulation_seconds'])
            got=collections.Counter((e['kind'],e['tier']) for e in seen.values());want=collections.Counter({(k,t):a for a,k,t in expected['groups']});sides=[]
            for e in seen.values():
                x,y=e['position'][:2];side=min([('west',abs(x+1)),('east',abs(x-20)),('north',abs(y+1)),('south',abs(y-20))],key=lambda a:a[1])[0];sides.append(side)
            counts=collections.Counter(sides);balanced=not counts or max(counts.values())-min(counts.get(s,0) for s in expected['sides'])<=1
            emission_start=setup['simulation_seconds']+setup['slots']['countdown_seconds']
            interval=expected['duration']/total
            timing=[]
            for sample in c.samples():
                if sample['phase']!='combat' or sample['slots']['wave']!=n:continue
                elapsed=sample['simulation_seconds']-emission_start
                low=max(0,min(total,math.floor((elapsed-.15)/interval+1e-7)))
                high=max(0,min(total,math.floor((elapsed+.15)/interval+1e-7)))
                if not low<=sample['slots']['wave_spawned']<=high:timing.append({'elapsed':elapsed,'spawned':sample['slots']['wave_spawned'],'allowed':[low,high]})
            ok=got==want and set(sides)<=set(expected['sides']) and balanced and not timing
            key='endless' if n>25 else 'schedule';c.vote(key+'_content',len(seen)>0,{'observed_species_tiers':list(map(list,got))});c.vote('endless_rules' if n>25 else 'wave_schedule_rules',ok,{'expected':dict((str(k),v)for k,v in want.items()),'actual':dict((str(k),v)for k,v in got.items()),'edge_counts':dict(counts),'emission_sample_times':times,'timing_violations':timing[:8]})
        p.rpc('up',key='F');p.held.discard('F');return
    if name in ['exact_funds','unaffordable']:
        before=c.state();c.build('archer',[8,8]);c.observe(.35);a=c.state();ok=len(units(a,'archer'))==(1 if name=='exact_funds' else 0) and a['slots']['coins']==0;c.vote('placement_rules',ok,'Affordability includes exact equality and rejects zero wallet.');return
    if name.startswith('upgrade_') and name!='upgrade_reject':
        _,k,t=name.split('_');tier=int(t);e=units(s,k)[0];c.click('inspect',entity_id=e['id']);c.capture('before-upgrade');before=c.state();c.click('upgrade');a=c.wait(lambda x:units(x,k)[0]['tier']==tier);new=units(a,k)[0];expected=TOWERS[k,tier];old=next(x for x in before['entities'] if x['id']==e['id']);
        c.vote('tiers_'+k,True,'Real upgrade reached the next visible tier.');c.vote('upgrade_rules',a['slots']['coins']==0 and new['max_health']==expected['health'],'Exact upgrade cost and new maximum health.');
        if tier==2:c.vote('upgrade_health',abs(new['health']/new['max_health']-old['health']/old['max_health'])<.02,'Damage fraction preserved with bounded regeneration during input.');
        if k=='archer' and tier==2:c.vote('feedback_content',bool(units(a,'feedback')),'Spatial upgrade feedback observed.');
        c.capture('upgraded');c.observe(.5)
        return
    if name=='upgrade_reject':
        unchanged=True
        for e in buildings(s):
            c.click('inspect',entity_id=e['id']);a=c.state();buttons=[t for t in a['targets'] if t['kind']=='upgrade' and t['interactable']];unchanged&=not buttons;c.capture(e['kind']);
        c.vote('upgrade_rejection',unchanged and c.state()['slots']['coins']==0,'Maximum level, zero funds and non-tower expose no enabled upgrade.');c.vote('ui_context',True,'Disabled or absent upgrade and explanatory details require visible review.');return
    if name=='income':
        a=c.state();c.wait(lambda x:x['slots']['coins']>=275,2);first=c.state();c.capture('first-payout');c.wait(lambda x:x['slots']['coins']>=380,4);second=c.state();c.vote('income_content',True,'Both mines produced spendable coins.');c.vote('income_rules',first['slots']['coins']==275 and second['slots']['coins']==380,'Independent pending cycles each pay 25+8*10=105 once.');c.vote('feedback_content',bool(units(first,'feedback')),'Income text/effect captured.');return
    if name=='income_removed':
        e=units(c.state(),'mine')[0];c.click('inspect',entity_id=e['id']);c.click('sell');a=c.state();c.observe(2.3);b=c.state();c.vote('income_rules',a['slots']['coins']==b['slots']['coins']==170,'Removed mine cannot pay its pending income.');c.vote('refund_rules',not units(b,'mine') and units(b,'deposit')[0]['state']=='free','The free mine returns zero and exposes the same deposit.');return
    if name=='regeneration':
        a=c.state();c.observe(1);b=c.state();dt=b['simulation_seconds']-a['simulation_seconds'];c.vote('regeneration_rules',abs(b['slots']['crystal_health']-a['slots']['crystal_health']-2*dt)<.02 and units(b,'wall')[0]['health']==450,'Continuous regeneration and max-health clamp.');c.vote('ui_health',True,'Damaged bars sampled alongside exact values.');return
    if name=='destruction':
        c.wait(lambda x:not units(x,'wall'),2);c.capture('removed');a=c.state();c.observe(.6);b=c.state();c.vote('destruction_rules',not units(b,'wall') and b['slots']['coins']==170 and enemies(b)[0]['position'][1]>enemies(a)[0]['position'][1],'Destroyed wall leaves no refund or movement obstruction.');c.vote('price_rules',b['slots']['wall_price']==5,'Destroyed ownership leaves the base wall price.');c.vote('ui_health',True,'Removed object has no lingering detail/health target.');return
    if name in ['clear','death']:
        before=c.state()['slots']['coins'];c.wait(lambda x:not enemies(x),5);a=c.state();c.capture('death');c.observe(1);b=c.state()
        if name=='clear':c.vote('wave_clear_rules',a['slots']['waves_cleared']==1 and a['slots']['wave']==2 and a['phase']=='countdown','Final living enemy clears exactly once after all spawns.');
        else:c.vote('death_rules',b['slots']['coins']==before+1 and not enemies(b),'Slime 1 pays one bounty; corpse completion does not pay again.');
        return
    if name=='rest':
        c.wait(lambda x:x['phase']=='rest',2);a=c.state();c.capture('rest');p.rpc('down',key='F');p.held.add('F');c.wait(lambda x:x['phase']=='countdown' and x['slots']['wave']==12,5);b=c.state();p.rpc('up',key='F');p.held.discard('F');c.vote('wave_clear_rules',7.8<=b['simulation_seconds']-a['simulation_seconds']<=8.2 and b['slots']['waves_cleared']==11 and not enemies(b),'Rest lasts eight simulation seconds and clears once.');return
    if name=='restart_rest':
        before=c.state();c.key('R');a=c.wait(fresh,1);c.vote('restart_rest',before['round_id']!=a['round_id'] and before['process_id']==a['process_id'],'Rest restart is a real R input.');return
    if name=='enemy_matrix':
        a=c.state();c.capture('moving');c.observe(.5);b=c.state();stats=True;ground=True;flight=True
        for e in enemies(a):
            q=next(x for x in enemies(b) if x['id']==e['id']);stats&=q['max_health']==ENEMIES[e['kind'],e['tier']]['health'];dist=math.dist(e['position'][:2],q['position'][:2])*200;expected=ENEMIES[e['kind'],e['tier']]['speed']*(b['simulation_seconds']-a['simulation_seconds']);ok=abs(dist-expected)<=max(3,expected*.02)
            if e['kind'] in ['bat','dragon']:flight&=ok and q['position'][2]>0
            else:ground&=ok
        c.capture('moving-later');c.vote('enemy_content',len(enemies(a))==15,'All species and tier variants are live; animation/material review required.');c.vote('ground_rules',stats and ground,'Ground tier health and motion match the public table.');c.vote('flight_rules',stats and flight,'Flying tier health, speed and elevation match.');return
    if name in ['obstruction','flight']:
        a=c.state();c.observe(1.8);b=c.state();e=enemies(b)[0]
        if name=='obstruction':c.vote('ground_rules',e['position'][1]<4.4 and units(b,'wall')[0]['health']<450,'Ground enemy stops and attacks the blocking wall.');
        else:c.vote('flight_rules',e['position'][1]>5 and units(b,'wall')[0]['health']==450,'Flying enemy crosses a wall without damaging it.');
        return
    if name=='melee':
        c.observe(2.2);rows=c.samples();drops=melee_damage_intervals(rows)
        c.vote('melee_rules',len(drops)>=2 and all(low-.001<=5<=high+.001 for _,low,high in drops) and all(b[0]-a[0]>=.85 for a,b in zip(drops,drops[1:])),{'damage_intervals':drops});return
    if name=='cannon_flight':
        c.observe(2.3);rows=c.samples();c.vote('cannon_targeting',all(not units(x,'cannonball') for x in rows) and all(e['health']==180 for x in rows for e in enemies(x)),'Cannon ignores an in-range living flyer.');return
    if name=='range':
        c.observe(.5);outside=c.state();c.vote('archer_targeting',not units(outside,'arrow') and all(e['health']==110 for e in enemies(outside)),'Out-of-range enemy receives no shot.');return
    if name=='projectile_block':
        c.observe(.65);a=c.state();c.vote('arrow_rules',enemies(a)[0]['health']==110 and units(a,'wall')[0]['health']==450,'Living wall blocks the released arrow without friendly damage, before the enemy reaches melee contact.');return
    if name=='projectile_sale':
        c.click('inspect',entity_id=units(s,'cannon')[0]['id']);c.wait(lambda x:bool(units(x,'cannonball')),3);before=enemies(c.state())[0]['health'];c.click('sell');c.wait(lambda x:any(e['health']<before for e in enemies(x)),3);c.vote('projectile_lifecycle',not units(c.state(),'cannon'),'Already released cannonball resolves after its source is sold.');return
    if name=='cooldown_upgrade':
        c.click('inspect',entity_id=units(s,'cannon')[0]['id']);start=s['simulation_seconds'];c.click('upgrade');a=c.wait(lambda x:bool(units(x,'cannonball')),3);elapsed=a['simulation_seconds']-start;c.vote('cooldown_upgrade',1.45<=elapsed<=1.95,{'pending_cooldown_elapsed':elapsed});return
    if name=='terminal_priority':
        c.wait(lambda x:x['phase']=='defeated',2);a=c.state();c.observe(1.5);b=c.state();c.vote('defeat_rules',a['slots']['crystal_health']==0 and a['slots']['coins']==170 and a['slots']['waves_cleared']==0 and freeze_values(a)==freeze_values(b),'Terminal hit suppresses simultaneous mine payout and future simulation.');return
    if name in ['archer_combat','cannon_combat','archer_flight','splash_boundary']:
        projectile='arrow' if name.startswith('archer') else 'cannonball';base={e['id']:e['health'] for e in enemies(setup)}
        a=c.wait(lambda x:bool(units(x,projectile)),3);c.capture('flight');undamaged=all(e['health']==base[e['id']] for e in enemies(a));c.wait(lambda x:any(e['health']<base[e['id']] for e in enemies(x)),3);b=c.state();c.capture('impact');rows=c.samples()
        if name=='archer_combat':c.vote('weapons_content',True,'Arrow release and impact visible.');c.vote('archer_targeting',True,'An eligible nearest living target was engaged.');c.vote('arrow_rules',undamaged and min(base[e['id']]-e['health'] for e in enemies(b))==6,'Arrow damage follows observed finite travel, one tier-1 hit.');c.vote('feedback_content',True,'Arrow and spatial impact captured.');
        if name=='archer_flight':c.vote('archer_targeting',undamaged and enemies(b)[0]['health']<base[enemies(b)[0]['id']],'Archer can hit a flyer using ground-plane range.');
        if name=='cannon_combat':c.vote('weapons_content',True,'Cannonball release and impact visible.');c.vote('cannon_targeting',True,'Eligible ground target was engaged.');c.vote('splash_rules',undamaged and all(base[e['id']]-e['health']==8 for e in enemies(b)),'One tier-1 explosion applies eight damage to each nearby ground enemy.');c.vote('feedback_content',True,'Cannon impact and spatial burst captured.');
        if name=='splash_boundary':
            health={e['id']:e['health'] for e in enemies(b)};ground=[e for e in enemies(setup) if e['kind']=='slime'];fly=next(e for e in enemies(setup) if e['kind']=='bat');c.vote('splash_rules',all(base[e['id']]-health[e['id']]==8 for e in ground[:2]) and health[ground[2]['id']]==110 and health[fly['id']]==180,'Nearby ground targets receive one hit; distant ground target and flyer remain unchanged.');
        return
    raise RuntimeError('UNKNOWN_FIXTURE_CASE:'+name)

def melee_damage_events(rows):
    """Undo only the public 2/s regeneration between the actual sample times."""
    # Keep the paused baseline: the first hit may occur before the first live
    # public sample. Dropping it silently discards a real, already observed hit.
    health=[(x['simulation_seconds'],x['slots']['crystal_health'],x['slots']['crystal_max_health']) for x in rows]
    return [(t,min(maximum,a+2*(t-pt))-b) for (pt,a,_),(t,b,maximum) in zip(health,health[1:]) if a-b>1]

def melee_damage_intervals(rows):
    """Bound regeneration lost at full health without assuming intra-sample order.

    Below the health cap these bounds coincide. At the cap, some regeneration
    may occur before the hit and be discarded, and some after it. Sample times
    bound that ambiguity; they do not justify treating the lower bound as exact.
    """
    health=[(x['simulation_seconds'],x['slots']['crystal_health'],x['slots']['crystal_max_health']) for x in rows]
    return [(t,min(maximum,a+2*(t-pt))-b,a+2*(t-pt)-b)
            for (pt,a,_),(t,b,maximum) in zip(health,health[1:]) if a-b>1]

from review_cases import REVIEW_FIXTURES,review_fixture
FIXTURES.update(REVIEW_FIXTURES)
