#!/usr/bin/env python3
"""Standalone read-only validator for campaign Dashboard contract v3."""
import argparse
import json
import math
from pathlib import Path

PHASES={'not_ready','menu','playing','paused','level_clear','campaign_won','lost'}

def number(v):return not isinstance(v,bool) and isinstance(v,(int,float)) and math.isfinite(v)

def require(ok,message):
    if not ok:raise ValueError(message)

def validate_naming_tables(t):
    require(t.get('schema_version')==3,'naming schema_version must be 3')
    require(isinstance(t.get('task_id'),str) and t['task_id'],'missing task_id')
    require(set(t['phases'])<=PHASES and {'not_ready','menu','playing'}<=set(t['phases']),'invalid phases')
    require(len(t['slots'])==len(set(t['slots'])) and {'client_width','client_height'}<=set(t['slots']),'invalid slots')
    require(t['target_rect_space']=={'width_slot':'client_width','height_slot':'client_height','origin':'bottom-left','units':'client coordinates'},'invalid target coordinate space')
    for name in ('entities','targets'):
        kinds=[v['kind'] for v in t[name]];require(len(kinds)==len(set(kinds)),'duplicate '+name)
    for e in t['entities']:
        require(e['geometry'] in ('cell','position','rect','none') and bool(e['states']),'invalid entity declaration')
    require(isinstance(t['controls']['keys'],dict),'missing normal key bindings')
    return t

def vector(v,n=None):
    return isinstance(v,list) and len(v) in ((n,) if n else (2,3)) and all(number(x) for x in v)

def rect(v,s):
    require(vector(v,4) and v[2]>=0 and v[3]>=0,'invalid rectangle')
    require(v[0]>=-.001 and v[1]>=-.001 and v[0]+v[2]<=s['client_width']+.001 and v[1]+v[3]<=s['client_height']+.001,'target outside actual client')

def validate_snapshot(s,t,previous=0):
    require(set(s)=={'revision','phase','slots','entities','targets'},'unexpected snapshot fields')
    require(type(s['revision']) is int and s['revision']>previous,'revision must increase')
    require(s['phase'] in t['phases'],'phase not declared')
    require(set(s['slots'])==set(t['slots']) and all(number(v) for v in s['slots'].values()),'invalid numeric slots')
    require(s['slots']['client_width']>0 and s['slots']['client_height']>0,'client dimensions must be positive')
    require(isinstance(s['entities'],list) and isinstance(s['targets'],list),'entities/targets must be arrays')
    kinds={e['kind']:e for e in t['entities']};ids=set()
    for e in s['entities']:
        require({'id','kind','state','visible'}<=set(e) and set(e)<={'id','kind','state','visible','cell','position','size','rect'},'invalid entity fields')
        require(isinstance(e['id'],str) and e['id'] and e['id'] not in ids,'entity id must be unique');ids.add(e['id'])
        require(e['kind'] in kinds and e['state'] in kinds[e['kind']]['states'] and type(e['visible']) is bool,'entity kind/state/visibility invalid')
        geometry=kinds[e['kind']]['geometry'];present=set(e)&{'cell','position','rect'}
        require(present==(set() if geometry=='none' else {geometry}),'entity geometry mismatch')
        if geometry=='cell':
            require(vector(e['cell'],2) and all(type(x)is int for x in e['cell']),'invalid cell')
            require(0<=e['cell'][0]<t['grid_size'][0] and 0<=e['cell'][1]<t['grid_size'][1],'cell outside grid')
        elif geometry=='position':require(vector(e['position'],2),'invalid position')
        elif geometry=='rect':rect(e['rect'],s['slots'])
        if 'size' in e:require(geometry=='position' and vector(e['size'],2) and all(x>0 for x in e['size']),'invalid size')
    allowed={e['kind'] for e in t['targets']};seen=set()
    for e in s['targets']:
        require(set(e)=={'kind','rect','visible','interactable'},'invalid target fields')
        require(e['kind'] in allowed and e['kind'] not in seen,'invalid/duplicate target');seen.add(e['kind'])
        require(type(e['visible'])is bool and type(e['interactable'])is bool and (not e['interactable'] or e['visible']),'target visibility invalid')
        rect(e['rect'],s['slots'])
    return s

def main():
    p=argparse.ArgumentParser();p.add_argument('trace',type=Path);p.add_argument('tables',type=Path);a=p.parse_args()
    t=validate_naming_tables(json.loads(a.tables.read_text()));previous=0;payload=None;count=0
    for line in a.trace.read_text().splitlines():
        s=json.loads(line);validate_snapshot(s,t,previous)
        current={k:v for k,v in s.items() if k!='revision'}
        require(current!=payload,'revision changed without payload change')
        previous=s['revision'];payload=current;count+=1
    require(count>0,'empty trace');print(json.dumps({'contract':'v3','snapshots':count,'valid':True}))

if __name__=='__main__':main()
