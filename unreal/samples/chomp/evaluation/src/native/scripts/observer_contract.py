"""Fast read-only guard for the exact published schema's keyword subset.

PowerShell Test-Json remains the authoritative offline schema check. This guard
classifies malformed runtime candidate output before a predicate dereferences it.
"""
from pathlib import Path
import json,math
SCHEMA=json.loads((Path(__file__).resolve().parents[2]/'input/contracts/game-state.schema.json').read_text(encoding='utf-8'))

def error(value,spec=None,path='$'):
    spec=SCHEMA if spec is None else spec
    if '$ref' in spec:
        ref=SCHEMA
        for key in spec['$ref'][2:].split('/'):ref=ref[key]
        problem=error(value,ref,path)
        if problem:return problem
    if 'anyOf' in spec and not any(error(value,s,path) is None for s in spec['anyOf']):return path+':anyOf'
    for s in spec.get('allOf',[]):
        problem=error(value,s,path)
        if problem:return problem
    if 'if' in spec and error(value,spec['if'],path) is None:
        problem=error(value,spec.get('then',{}),path)
        if problem:return problem
    kinds={'object':isinstance(value,dict),'array':isinstance(value,list),'string':isinstance(value,str),'boolean':type(value)is bool,'integer':type(value)is int,'number':type(value) in [int,float] and math.isfinite(value),'null':value is None}
    if spec.get('type') and not kinds[spec['type']]:return path+':type'
    if 'const' in spec and (value!=spec['const'] or type(value)!=type(spec['const'])):return path+':const'
    if 'enum' in spec and value not in spec['enum']:return path+':enum'
    if type(value) in [int,float]:
        if value<spec.get('minimum',-math.inf) or value>spec.get('maximum',math.inf):return path+':range'
    if isinstance(value,str) and len(value)<spec.get('minLength',0):return path+':length'
    if isinstance(value,dict):
        if any(k not in value for k in spec.get('required',[])):return path+':required'
        properties=spec.get('properties',{})
        if spec.get('additionalProperties') is False and set(value)-set(properties):return path+':additionalProperties'
        for key,child in properties.items():
            if key in value:
                problem=error(value[key],child,path+'.'+key)
                if problem:return problem
    if isinstance(value,list) and 'items' in spec:
        for i,item in enumerate(value):
            problem=error(item,spec['items'],path+'['+str(i)+']')
            if problem:return problem
    return None
