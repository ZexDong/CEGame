"""Additional evidence for previously under-tested public requirements.

No new score owners or weights. Setup only, followed by real player input.
"""
import math
from spec import TOWERS,units,enemies,buildings
from support import CandidateError,InfrastructureError,write

def unit(kind,position,tier=1,**kw):return {'kind':kind,'position':position,'tier':tier,**kw}
def state(items=None,**kw):return {'coins':170,'crystal_health':500,'resume_phase':'combat','wave':1,'completed':0,'wave_total':20,'wave_spawned':20,'countdown':0,'units':items or [],**kw}
REVIEW_FIXTURES={}
for kind in ['archer','cannon']:
    # This lower-board path stays outside the normal pause-overlay rectangle.
    REVIEW_FIXTURES['review_visible_'+kind]=state([unit(kind,[0,0,0]),unit('slime',[4.9,0,0],3)])
    REVIEW_FIXTURES['review_nearest_'+kind]=state([unit(kind,[6,6,0]),unit('slime',[1.5,6,0],3),unit('slime',[5,4,0],3)])
    for action in ['upgrade','sale']:
        items=[unit(kind,[6,6,0],paid=20 if kind=='archer' else 25),unit('slime',[6,1.05,0],3)]
        if kind=='cannon':items.append(unit('slime',[7.15,1.05,0],3))
        REVIEW_FIXTURES['review_projectile_'+action+'_'+kind]=state(items,coins=200,selected_entity=0)
for reason in ['unaffordable','maximum','construction','mine','wall']:
    k=reason if reason in ['mine','wall'] else 'archer'
    items=[unit(k,[4,3,0] if k=='mine' else [8,8,0],3 if reason=='maximum' else 1,
        construction_remaining=.6 if reason=='construction' else 0)]
    if k in ['mine','wall'] or reason=='maximum':items.append(unit('archer',[12,8,0]))
    REVIEW_FIXTURES['review_reject_'+reason]=state(items,coins=0 if reason=='unaffordable' else 2000,
        selected_entity=0,resume_phase='rest',wave=11,completed=10,wave_total=0,wave_spawned=0,countdown=8)
REVIEW_FIXTURES['review_income_purchase']=state(resume_phase='preparing',wave=0,wave_total=0,wave_spawned=0)
REVIEW_FIXTURES['review_upgrade_single_click']=state([unit('archer',[8,8,0])],coins=1000,selected_entity=0,
    resume_phase='rest',wave=11,completed=10,wave_total=0,wave_spawned=0,countdown=8)

def visible_target(snapshot,kind):
    rows=[x for x in snapshot['targets'] if x['kind']==kind and x.get('visible')]
    if not rows:raise InfrastructureError('REVIEW_VISIBLE_CONTROL_NOT_ESTABLISHED:'+kind)
    return max(rows,key=lambda x:x['rect'][2]*x['rect'][3])

def raw_click(c,target):
    r=target['rect'];c.p.rpc('click',x=r[0]+r[2]/2,y=r[1]+r[3]/2,button='Left',ms=20)
    return c.fresh_observation()

def freeze_projectile(c,kind):
    projectile='arrow' if kind=='archer' else 'cannonball'
    c.wait(lambda s:bool(units(s,projectile)),3)
    c.p.press('P',20);s=c.wait(lambda x:x['phase']=='paused',1)
    if not units(s,projectile):raise InfrastructureError('CAPTURE_INTERCEPTION_MISSED_PROJECTILE')
    c.capture('airborne-paused');return s,units(s,projectile)[0]

def review_fixture(c):
    name=c.name;p=c.p;setup=c.state();c.key('P')
    if name.startswith('review_visible_'):
        kind=name.removeprefix('review_visible_');s,shot=freeze_projectile(c,kind)
        c.observe(.6);c.capture('airborne-paused-later')
        write(p.root/'visual-observation.json',{'projectile_id':shot['id'],'projectile_kind':shot['kind'],
            'stable_projectile_before':shot,'stable_projectile_after':next(e for e in c.state()['entities'] if e['id']==shot['id']),
            'phase':'paused','rendered_review_required':True,'source_creation_is_not_visibility_proof':True})
        with p.clip('firing',seconds=2.5,fps=16) as frames:
            c.key('P');c.observe(1.7)
        c.captures.extend(x['path'] for x in frames)
        # Provisional collection fact only; rendered review decides visibility.
        c.vote('weapons_content',True,{'projectile_observed':shot,'visual_review_pending':True})
        c.vote('feedback_content',True,{'firing_clip_frames':len(frames),'visual_review_pending':True})
        return
    if name.startswith('review_reject_'):
        reason=name.removeprefix('review_reject_');original=buildings(setup)[0]
        if reason in ['mine','wall','maximum']:
            other=next(e for e in buildings(c.state()) if e['kind']=='archer' and e['id']!=original['id'])
            c.click('inspect',entity_id=other['id']);slot=visible_target(c.state(),'upgrade')
            c.click('inspect',entity_id=original['id'])
            if any(t['kind']=='upgrade' and t.get('interactable') for t in c.state()['targets']):
                c.vote('upgrade_rejection',False,'Non-tower exposes enabled upgrade')
        else:slot=visible_target(c.state(),'upgrade')
        attempts=[]
        for attempt in range(2):
            a=c.state();old=next(e for e in buildings(a) if e['id']==original['id'])
            if reason=='construction' and old['state']!='constructing':
                raise InfrastructureError('CONSTRUCTION_PRECONDITION_EXPIRED_BEFORE_INPUT')
            b=raw_click(c,slot);new=next(e for e in buildings(b) if e['id']==original['id'])
            attempts.append({'before':old,'after':new,'coins_before':a['slots']['coins'],'coins_after':b['slots']['coins']})
        c.capture('after-two-attempts')
        ok=all(a['coins_before']==a['coins_after'] and a['before'].get('tier')==a['after'].get('tier')
            and a['before']['max_health']==a['after']['max_health'] and a['before']['health']==a['after']['health'] for a in attempts)
        c.vote('upgrade_rejection',ok,{'reason':reason,'real_clicks':2,'attempts':attempts,
            'non_tower_policy':'Absent control plus real click in previously observed upgrade slot; no hidden upgrade API invoked.' if reason in ['mine','wall'] else None})
        return
    if name.startswith('review_nearest_'):
        kind=name.removeprefix('review_nearest_');tower=units(setup,kind)[0]
        ranked=sorted(enemies(setup),key=lambda e:math.dist(e['position'][:2],tower['position'][:2]))
        expected=ranked[0];before={e['id']:e['health'] for e in enemies(setup)}
        hit=c.wait(lambda s:any(e['health']<before[e['id']] for e in enemies(s)),3)
        changed=[e['id'] for e in enemies(hit) if e['health']<before[e['id']]]
        c.capture('nearest-hit');c.observe(2.2 if kind=='cannon' else .7)
        releases={}
        for s in c.samples():
            for shot in units(s,'arrow' if kind=='archer' else 'cannonball'):releases.setdefault(shot['id'],s['simulation_seconds'])
        times=sorted(releases.values());cooldown=TOWERS[kind,1]['cooldown']
        c.vote(kind+'_targeting',changed==[expected['id']] and len(times)>=2 and all(b-a>=cooldown-.15 for a,b in zip(times,times[1:])),
            {'nearest':expected['id'],'first_damaged':changed,'farther_was_inserted_first':True,'release_times':times,'expected_cooldown':cooldown})
        return
    if name.startswith('review_projectile_'):
        _,_,action,kind=name.split('_');projectile='arrow' if kind=='archer' else 'cannonball'
        s=c.wait(lambda x:bool(units(x,projectile)),3);shot=units(s,projectile)[0]
        target=visible_target(s,'upgrade' if action=='upgrade' else 'sell')
        before={e['id']:e['health'] for e in enemies(s)};r=target['rect']
        # Submit a real transaction immediately after the public release sample;
        # no capture or fixed sleep consumes the remaining flight time.
        p.rpc('click',x=r[0]+r[2]/2,y=r[1]+r[3]/2,button='Left',ms=20)
        changed=c.wait(lambda x:(units(x,kind) and units(x,kind)[0]['tier']==2) if action=='upgrade' else not units(x,kind),1)
        still_airborne=any(e['id']==shot['id'] for e in units(changed,shot['kind']))
        untouched=all(e['health']==before[e['id']] for e in enemies(changed))
        if not (still_airborne and untouched):
            raise InfrastructureError('TRANSACTION_ORDER_NOT_RESOLVED_BEFORE_IMPACT')
        c.capture('transaction-before-impact')
        hit=c.wait(lambda x:any(e['health']<before[e['id']] for e in enemies(x)),3)
        damage={e['id']:before[e['id']]-e['health'] for e in enemies(hit)}
        ordered=list(before);expected=TOWERS[kind,1]['damage']
        ok=damage[ordered[0]]==expected and all(damage[i]==0 for i in ordered[1:])
        separation=None
        if kind=='cannon':
            positions={e['id']:e['position'] for e in enemies(hit)}
            separation=200*math.dist(positions[ordered[0]][:2],positions[ordered[1]][:2])
            if not 204<separation<245:raise InfrastructureError('SPLASH_DISCRIMINATOR_POSITION_NOT_ESTABLISHED')
        c.capture('old-shot-impact')
        c.vote('projectile_lifecycle',ok,{'operation':action,'source_kind':kind,'original_shot':shot['id'],
            'transaction_observed_while_original_shot_airborne':still_airborne,'damage':damage,'expected_old_damage':expected,
            'cannon_second_enemy_between_old_new_splash_radii':kind=='cannon','measured_enemy_separation':separation,'release_radius':TOWERS[kind,1]['splash']})
        return
    if name=='review_upgrade_single_click':
        a=c.state();c.click('upgrade');c.observe(.2);b=c.state();c.capture('one-click')
        c.vote('upgrade_rules',units(b,'archer')[0]['tier']==2 and b['slots']['coins']==800,
            {'real_upgrade_clicks':1,'before_tier':units(a,'archer')[0]['tier'],'after_tier':units(b,'archer')[0]['tier'],
             'before_coins':a['slots']['coins'],'after_coins':b['slots']['coins'],'expected_tier':2,'expected_coins':800})
        return
    if name=='review_income_purchase':
        c.build('mine',[4,3]);c.wait(lambda s:s['slots']['coins']>=195,13);c.capture('first-payout')
        data=c.samples();birth=next(i for i,s in enumerate(data) if units(s,'mine'))
        payout=next(i for i,s in enumerate(data) if s['slots']['coins']>=195)
        if birth==0 or payout==0:raise InfrastructureError('PURCHASE_OR_PAYOUT_BASELINE_MISSING')
        low=data[payout-1]['simulation_seconds']-data[birth]['simulation_seconds']
        high=data[payout]['simulation_seconds']-data[birth-1]['simulation_seconds']
        c.vote('income_rules',low<=10.15 and high>=9.85,{'birth_bracket':[data[birth-1]['simulation_seconds'],data[birth]['simulation_seconds']],
            'payout_bracket':[data[payout-1]['simulation_seconds'],data[payout]['simulation_seconds']],
            'payout_age_interval':[low,high],'required_first_payout_age':10,'tolerance':.15,
            'accepted_purchase_includes_construction':True})
        return
    raise InfrastructureError('UNKNOWN_REVIEW_CASE:'+name)
