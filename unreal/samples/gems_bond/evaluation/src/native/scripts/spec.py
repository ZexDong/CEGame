"""Expected facts are parsed from public GDD tables, never from Gold code."""
import re
from pathlib import Path
TASK=Path(__file__).resolve().parents[2]
REPO=TASK.parents[1]
GDD=(TASK/'input/GDD.md').read_text(encoding='utf-8-sig')
REQUIREMENTS=dict(re.findall(r'^\| ([A-Z]+-\d+) \| (.+) \|$',GDD,re.M))
WAVES={}
for n,groups,duration,sides in re.findall(r'^\| (\d+) \| (.+?) \| ([\d.]+) \| (.+?) \|$',GDD,re.M):
    WAVES[int(n)]={'groups':[(int(c),k.lower(),int(t)) for c,k,t in re.findall(r'(\d+) x (\w+) (\d)',groups)],'duration':float(duration),'sides':sides.replace(' ','').lower().split(',') if sides!='None' else []}
TOWERS={}
for line in GDD.splitlines():
    p=[x.strip() for x in line.strip('|').split('|')]
    if len(p)==7 and p[0] in ['Archer','Cannon'] and p[1].isdigit():
        TOWERS[p[0].lower(),int(p[1])]={'health':float(p[2]),'damage':float(p[3]),'cooldown':float(p[4]),'splash':float(p[5])}
ENEMIES={}
for line in GDD.splitlines():
    p=[x.strip() for x in line.strip('|').split('|')]
    if len(p)==8 and p[0] in ['Slime','Skeleton','Orc','Bat','Dragon'] and p[1].isdigit():
        ENEMIES[p[0].lower(),int(p[1])]={'health':float(p[2]),'speed':float(p[3]),'damage':float(p[4]),'bounty':int(p[5]),'scale':float(p[6]),'material':p[7]}
DEPOSITS=[[4,3],[12,8],[6,13],[17,17]]
DIMENSIONS={'D1':10,'D2':30,'D3':20,'D4':20,'D5':10,'D6':10}
def wave(n):
    base=WAVES[min(n,25)]
    return {**base,'groups':[(int(c*(1+.2*max(0,n-25))+.5),k,t) for c,k,t in base['groups']]}
def units(s,kind=None,living=True):
    return [e for e in s['entities'] if (kind is None or e['kind']==kind) and (not living or e.get('state') not in ['dead','destroyed'])]
def enemies(s,living=True):return [e for e in units(s,living=living) if e['kind'] in ['slime','skeleton','orc','bat','dragon']]
def buildings(s):return [e for e in units(s) if e['kind'] in ['mine','archer','cannon','wall']]
def fresh(s):
    v=s['slots'];return s['phase']=='preparing' and all(v[k]==x for k,x in {'coins':170,'crystal_health':500,'crystal_max_health':500,'wave':0,'waves_cleared':0,'speed_multiplier':1,'enemies_alive':0,'enemies_remaining':0,'mine_count':0,'archer_count':0,'cannon_count':0,'wall_count':0}.items()) and sorted(e.get('cell') for e in units(s,'deposit'))==sorted(DEPOSITS) and not buildings(s) and not enemies(s) and not units(s,'arrow') and not units(s,'cannonball')
