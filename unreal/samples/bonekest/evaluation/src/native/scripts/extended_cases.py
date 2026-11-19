from cases import *

def audio(c):
    c.restart();c.p.observe(.2);s,n,k=c.snap('music');music=[a for a in n['playing_audio'] if '/A_Music.' in a['asset'] and not a['paused']];ok=len(music)==1
    c.p.press('Escape',70);c.p.wait(lambda s:s['phase']=='paused',3);n=c.native();ok &=not any('/A_Music.' in a['asset'] and not a['paused'] for a in n['playing_audio'])
    c.p.click_target('resume');c.p.wait(lambda s:s['phase']=='exploring',3);c.restart();n=c.native();ok &=len([a for a in n['playing_audio'] if '/A_Music.' in a['asset'] and not a['paused']])==1
    c.to_menu();c.p.observe(.2);ok &=not any('/A_Music.' in a['asset'] for a in c.native()['playing_audio']);c.snap('music-stopped');c.check('D2-music',ok,'MUSIC_MISSING_STACKED_OR_BAD_LIFECYCLE')

def presentation(c):
    clips=set();audio_assets=set();effects=set();all_assets=set()
    def gather(label,seconds=.35):
        end=time.perf_counter()+seconds
        while time.perf_counter()<end:
            n=c.native();audio_assets.update(a['asset'].split('.')[-1] for a in n['playing_audio'])
            for obj in n['rendered_components']:
                if obj['recently_rendered']:
                    all_assets.add(obj['asset']);
                    if obj.get('animation'):clips.add(obj['animation'].split('.')[-1])
            effects.update(e['attributes']['effect_kind'] for e in entities(c.state(),'effect'))
            c.p.observe(.045)
        c.snap(label)
    c.restart();gather('spawn',.15);c.p.observe(.8);gather('idle',.1)
    with c.p.holding(['D']):gather('run',.25)
    c.p.press('Q',50);gather('cast',.3)
    for kind in ['coin','heart','scroll','key']:
        c.restart();s=c.state();p=next(p for p in entities(s,'pickup','available') if p['attributes']['pickup_kind']==kind);safe_setup(c,p['cell'],anchor='pickup',pickup_id=p['id']);c.pickup(p);gather(kind,.15)
    c.restart();s=c.state();g=find_gate(s,'red');rr,x=side(s,g);safe_setup(c,rr,anchor='gate',slot=x['slot'],keys=['red']);c.p.press('E',50);gather('gate',.2)
    c.restart();s=c.state();x=exit_slot(s);c.setup(monster_room=x['destination_cell'],anchor='passage',slot=x['slot']);c.cross(x['slot']);gather('hit',.2)
    for win in [True,False]:establish_outcome(c,win);gather('won' if win else 'lost',.15)
    c.restart();s=c.state();origin=cell(s);edge=exit_slot(s);dest=tuple(edge['destination_cell']);d=distances(s,dest);origin_d=distances(s,origin)
    precursor=next(v for v in d if d[v]==2 and origin_d[v]>1)
    for attempt in range(12):
        c.setup(room=list(origin),monster_room=list(precursor),anchor='passage',slot=edge['slot']);c.cross(edge['slot']);gather('danger-entry',.15)
        if c.state()['slots']['danger_nearby']:break
    expected_clips={f'A_PlayerCharacter_{x}' for x in ['Idle_Loop','Run_Loop','Spawn','Default_Attack','Blast','Hit_Front','Die']}
    expected_audio={f'A_{x}' for x in ['CastMagic','Coin','GetKey','IncreaseLives','TakeMagic','OpenDoor','Teleport','Monster','Bonk','Win','Lose']}
    required_effects={'FX_GhostSmoke','P_ky_magicCircle1','P_ky_healAura','P_ky_lightning1','P_ky_lightning2'}
    assetnames={p.split('.')[-1] for p in all_assets}
    c.check('D2-animations',expected_clips<=clips,'REQUIRED_EVENT_CLIP_NOT_OBSERVED',{'clips':sorted(clips),'missing':sorted(expected_clips-clips)})
    c.check('D2-effects',required_effects<=assetnames and {'cast','hit','pickup','win','lose'}<=effects,'REQUIRED_EVENT_EFFECT_NOT_OBSERVED',{'effects':sorted(effects),'rendered_assets':sorted(all_assets),'missing_assets':sorted(required_effects-assetnames)})
    c.check('D2-sounds',expected_audio<=audio_assets,'REQUIRED_EVENT_SOUND_NOT_OBSERVED',{'playing_sound_assets':sorted(audio_assets),'missing':sorted(expected_audio-audio_assets)})

def route(s,destination,safe_first=True):
    start=cell(s);graph=rooms(s);gm=gate_map(s);owned={x for x in COLORS if s['slots'][x+'_key']};q=deque([start]);seen={start:None};via={}
    while q:
        here=q.popleft()
        if here==tuple(destination):break
        for e in graph[here]['attributes']['exits']:
            g=gm.get(e.get('gate_id'))
            if g and g['state']!='open' and g['attributes']['key_color'] not in owned:continue
            there=tuple(e['destination_cell'])
            if safe_first and here==start and distances(s,monster(s)).get(there,0)<=1:continue
            if there not in seen:seen[there]=here;via[there]=e;q.append(there)
    if tuple(destination) not in seen:
        if safe_first:return route(s,destination,False)
        raise CandidateError('NO_LEGAL_ROUTE_TO_REQUIRED_CONTENT')
    result=[];p=tuple(destination)
    while seen[p] is not None:result.append(via[p]);p=seen[p]
    return list(reversed(result))

def journey(c):
    # This one lifecycle case deliberately has no fixture setup at all.
    c.to_menu();c.p.click_target('easy');c.p.wait(lambda s:s['phase']=='exploring',20);crossings=0
    deadline=time.perf_counter()+1600
    while time.perf_counter()<deadline:
        s=c.state()
        if s['phase']=='lost':raise CandidateError('NORMAL_JOURNEY_ENDED_IN_DEFEAT')
        if s['phase']=='recovering':c.p.wait(lambda s:s['phase']=='exploring',3);continue
        if s['phase']=='won':break
        # Route through the observed room's centre before choosing another exit.
        # This avoids cutting diagonally through corner dressing; it sends only
        # movement keys and uses independently projected semantic floor anchors.
        def centered(t):
            n=c.native().get('navigation',{})
            return n.get('player') is not None and n.get('center') is not None and math.dist(n['player'],n['center'])<.025
        c.move(lambda t:{'kind':'center','rect':rooms(t)[cell(t)].get('rect')},centered,8)
        s=c.state()
        missing=[col for col in COLORS if not s['slots'][col+'_key']]
        goals=[role(s,x+'_key') for x in missing] if missing else [role(s,'exit')]
        legal=[]
        for goal in goals:
            try:legal.append((len(route(s,goal)),goal))
            except CandidateError:pass
        if not legal:raise CandidateError('KEY_ROUTE_NOT_REACHABLE')
        _,goal=min(legal)
        if cell(s)==goal:
            if missing:
                p=next(p for p in entities(s,'pickup','available') if p['cell']==list(goal) and p['attributes']['pickup_kind']=='key');c.pickup(p);c.snap('key')
            else:c.final();c.snap('escaped');break
            continue
        path=route(s,goal);edge=path[0]
        if edge.get('gate_id') and gate_map(s)[edge['gate_id']]['state']!='open':
            def target(t):return next((v for v in t['targets'] if v['kind']=='gate' and v.get('entity_id')==edge['gate_id']),None)
            c.move(target,lambda t:any(v['kind']=='gate' and v.get('entity_id')==edge['gate_id'] and v['interactable'] for v in t['targets']),12)
            c.p.press('E',60);c.p.wait(lambda s:gate_map(s)[edge['gate_id']]['state']=='open',3.5)
        c.cross(edge['slot'],12);crossings+=1
        if crossings%5==0:c.snap('progress')
    a,n,k=c.snap('journey-end');c.check('D4-journey',a['phase']=='won' and a['slots']['keys_owned']==3,'NORMAL_COMPLETE_JOURNEY_NOT_CONNECTED',{'crossings':crossings,'terminal_phase':a['phase'],'input_receipts':'actions.json','captures':[x for x in c.captures if x.startswith('journey')]})

CASES.update({'audio':audio,'presentation':presentation,'journey':journey})
