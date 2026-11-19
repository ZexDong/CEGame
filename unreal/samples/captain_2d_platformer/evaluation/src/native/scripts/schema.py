"""Offline validator for the exact JSON Schema vocabulary used by the public contract.

Unknown validation keywords fail closed. No third-party installation is necessary.
"""
import math
import re

ANNOTATIONS = {'$schema', '$id', 'title', 'description', '$defs', 'default', 'examples', '$comment'}
KEYWORDS = ANNOTATIONS | {'$ref','type','const','enum','required','properties','additionalProperties',
    'items','minItems','maxItems','uniqueItems','minimum','maximum','exclusiveMinimum','exclusiveMaximum',
    'minLength','maxLength','pattern','oneOf','anyOf','allOf','if','then','else','not'}

def errors(value, spec, root=None, path=''):
    root = spec if root is None else root
    if spec is True: return []
    if spec is False: return [path + ': forbidden']
    unknown = set(spec) - KEYWORDS
    if unknown: raise ValueError('UNSUPPORTED_SCHEMA_KEYWORD:' + ','.join(sorted(unknown)))
    result=[]
    if '$ref' in spec:
        ref=spec['$ref']
        if not ref.startswith('#/'):raise ValueError('EXTERNAL_SCHEMA_REF')
        target=root
        for key in ref[2:].split('/'):target=target[key.replace('~1','/').replace('~0','~')]
        result += errors(value,target,root,path)
    types={'null':value is None,'boolean':type(value) is bool,'object':type(value) is dict,
        'array':type(value) is list,'string':type(value) is str,
        'number':type(value) in (int,float) and math.isfinite(value),
        'integer':type(value) in (int,float) and math.isfinite(value) and int(value)==value}
    if 'type' in spec:
        wanted=spec['type'] if isinstance(spec['type'],list) else [spec['type']]
        if not any(types[t] for t in wanted):return [path+': type']
    def equal(a,b):
        if type(a) is bool or type(b) is bool:return type(a) is type(b) and a==b
        return a==b
    if 'const' in spec and not equal(value,spec['const']):result.append(path+': const')
    if 'enum' in spec and not any(equal(value,x) for x in spec['enum']):result.append(path+': enum')
    if type(value) is dict:
        for key in spec.get('required',[]):
            if key not in value:result.append(path+'.'+key+': required')
        properties=spec.get('properties',{})
        for key,child in value.items():
            if key in properties:result+=errors(child,properties[key],root,path+'.'+key)
            elif 'additionalProperties' in spec:result+=errors(child,spec['additionalProperties'],root,path+'.'+key)
    if type(value) is list:
        if len(value)<spec.get('minItems',0) or len(value)>spec.get('maxItems',math.inf):result.append(path+': array length')
        if spec.get('uniqueItems') and any(value[i] in value[:i] for i in range(len(value))):result.append(path+': duplicates')
        if 'items' in spec:
            for i,child in enumerate(value):result+=errors(child,spec['items'],root,path+f'[{i}]')
    if type(value) is str:
        if len(value)<spec.get('minLength',0) or len(value)>spec.get('maxLength',math.inf):result.append(path+': string length')
        if 'pattern' in spec and not re.search(spec['pattern'],value):result.append(path+': pattern')
    if type(value) in (int,float):
        if not math.isfinite(value):result.append(path+': nonfinite')
        for key,good in [('minimum',lambda x:value>=x),('maximum',lambda x:value<=x),
                         ('exclusiveMinimum',lambda x:value>x),('exclusiveMaximum',lambda x:value<x)]:
            if key in spec and not good(spec[key]):result.append(path+': '+key)
    for keyword in ('allOf','anyOf','oneOf'):
        if keyword in spec:
            good=sum(not errors(value,s,root,path) for s in spec[keyword])
            if (keyword=='allOf' and good!=len(spec[keyword])) or (keyword=='anyOf' and good==0) or (keyword=='oneOf' and good!=1):result.append(path+': '+keyword)
    if 'not' in spec and not errors(value,spec['not'],root,path):result.append(path+': not')
    if 'if' in spec:
        branch='else' if errors(value,spec['if'],root,path) else 'then'
        if branch in spec:result+=errors(value,spec[branch],root,path)
    return result
