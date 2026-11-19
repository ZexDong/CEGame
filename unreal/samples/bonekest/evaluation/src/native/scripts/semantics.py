"""Architecture-independent public-state queries and graph predicates."""
from collections import deque,Counter
import hashlib,json,math

COLORS=('red','green','blue')
def entities(s,kind=None,state=None):return [e for e in s.get('entities',[]) if (kind is None or e.get('kind')==kind) and (state is None or e.get('state')==state)]
def one(s,kind):
    found=entities(s,kind)
    if len(found)!=1:raise ValueError('EXPECTED_ONE_'+kind.upper())
    return found[0]
def cell(s):return (s['slots']['room_x'],s['slots']['room_y'])
def monster(s):return (s['slots']['monster_x'],s['slots']['monster_y'])
def rooms(s):return {tuple(e['cell']):e for e in entities(s,'room')}
def neighbors(s,c):return [tuple(x['destination_cell']) for x in rooms(s)[tuple(c)]['attributes']['exits']]
def distances(s,origin):
    graph=rooms(s);origin=tuple(origin);result={origin:0};q=deque([origin])
    while q:
        c=q.popleft()
        for x in graph[c]['attributes']['exits']:
            n=tuple(x['destination_cell'])
            if n not in result:result[n]=result[c]+1;q.append(n)
    return result
def role(s,name):return tuple(next(e['cell'] for e in entities(s,'room') if e['state']==name))
def gate_map(s):return {e['id']:e for e in entities(s,'gate')}
def graph_valid(s):
    graph=rooms(s);n=s['slots']['maze_size'];assert len(graph)==n*n,'room count'
    assert set(graph)=={(x,y) for x in range(1,n+1) for y in range(1,n+1)},'coordinate coverage'
    nonlocal_edge=False;gates=gate_map(s)
    for c,r in graph.items():
        xs=r['attributes']['exits'];assert len(xs)==4 and {x['slot'] for x in xs}=={'north','east','south','west'},'exit slots'
        ns=[tuple(x['destination_cell']) for x in xs];assert len(set(ns))==4 and c not in ns,'distinct neighbours'
        for x in xs:
            d=tuple(x['destination_cell']);assert d in graph,'dangling'
            back=[b for b in graph[d]['attributes']['exits'] if b['slot']==x['destination_slot']]
            assert len(back)==1 and tuple(back[0]['destination_cell'])==c and back[0]['destination_slot']==x['slot'],'reciprocity'
            assert back[0].get('gate_id')==x.get('gate_id'),'shared gate identity'
            if x.get('gate_id'):assert x['gate_id'] in gates,'missing gate entity'
            nonlocal_edge |= abs(c[0]-d[0])+abs(c[1]-d[1])>1
    assert len(distances(s,next(iter(graph))))==n*n,'connectivity'
    assert nonlocal_edge,'non-geometric connection';return True
def locks_valid(s):
    graph=rooms(s);gates=gate_map(s);start=role(s,'start');known=set();reachable={start}
    for _ in range(5):
        changed=True
        while changed:
            changed=False
            for c in list(reachable):
                for x in graph[c]['attributes']['exits']:
                    g=gates.get(x.get('gate_id'));d=tuple(x['destination_cell'])
                    if d not in reachable and (not g or g['attributes']['key_color'] in known):reachable.add(d);changed=True
        for col in COLORS:
            if role(s,col+'_key') in reachable:known.add(col)
    assert known==set(COLORS) and len(reachable)==len(graph),'lock cycle or unreachable content'
    assert {g['attributes']['key_color'] for g in gates.values()}==set(COLORS),'gate colours';return True
def world_signature(s):
    graph=rooms(s);gates=gate_map(s)
    rows=[]
    for c,r in sorted(graph.items()):
        rows.append([c,r['state'],r['attributes']['layout_id'],sorted([(x['slot'],x['destination_cell'],x['destination_slot'],gates.get(x.get('gate_id'),{}).get('attributes',{}).get('key_color')) for x in r['attributes']['exits']])])
    pickups=sorted([(p['cell'],p['attributes']['pickup_kind'],p['attributes'].get('key_color'),p.get('local_position')) for p in entities(s,'pickup')],key=str)
    return hashlib.sha256(json.dumps([rows,pickups,monster(s)],sort_keys=True).encode()).hexdigest()
def fresh(s):
    a=s['slots'];return s['phase']=='exploring' and [a[k] for k in ['lives','scrolls','coins','keys_owned','room_changes','reveal_active']]==[5,5,0,0,0,0] and cell(s)==role(s,'start') and distances(s,cell(s))[monster(s)]>=2 and all(p['state']=='available' for p in entities(s,'pickup')) and all(g['state']=='locked' for g in entities(s,'gate'))
def content(s):
    size=s['slots']['maze_size'];counts=Counter(p['attributes']['pickup_kind'] for p in entities(s,'pickup') if rooms(s)[tuple(p['cell'])]['state']=='ordinary')
    required={6:(60,5,3),10:(167,14,9),15:(375,32,19)}[size]
    return all(counts[k]>=v for k,v in zip(('coin','scroll','heart'),required)) and len({tuple(p['cell']) for p in entities(s,'pickup') if p['attributes']['pickup_kind']!='key'})>=12
def centre(rect):return (rect[0]+rect[2]/2,rect[1]+rect[3]/2)
def invariant(s):
    return {'phase':s['phase'],'slots':s['slots'],'entities':sorted([(e['id'],e['state'],e.get('cell'),e.get('position'),e.get('local_position'),e.get('attributes')) for e in s['entities'] if e['kind']!='effect'],key=lambda e:e[0]),'simulation_seconds':s['simulation_seconds']}
