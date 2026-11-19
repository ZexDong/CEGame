#!/usr/bin/env python3
"""Check public input dependency/scaffold integrity; does not test gameplay."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET

def check_input(root):
    required = ['INITIAL_AGENT_PROMPT.md','GDD.md','CONTENT.json','tools/TOOL_GUIDE.md',
                'tools/tool-config.example.json','assets/ASSET_CATALOG.json',
                'starter-project/TideLockStart.rbxlx','starter-project/project/default.project.json',
                'starter-project/project/build.ps1','contracts/GAME_SESSION_SPEC.md',
                'contracts/SESSION_MODEL.json','contracts/src/TideLockSchema.luau','legal/LICENSE.txt']
    for relative in required:
        target = root/relative
        assert target.is_file() and target.stat().st_size>0, 'Missing/empty input file: '+relative
    model = json.loads((root/'contracts/SESSION_MODEL.json').read_text(encoding='utf-8'))
    assert model['contract_version']=='tide-lock-v1'
    catalog = json.loads((root/'assets/ASSET_CATALOG.json').read_text(encoding='utf-8'))
    for asset in catalog['assets']:
        assert (root/asset['path']).is_file(), 'Missing catalog asset'
        assert (root/asset['license_path']).is_file(), 'Missing license'
    project_file = root/'starter-project/project/default.project.json'
    project = json.loads(project_file.read_text(encoding='utf-8'))
    mapped = []
    def visit(node):
        if isinstance(node,dict):
            if '$path' in node:
                target = (project_file.parent/node['$path']).resolve()
                assert target.is_relative_to(root.resolve()) and target.exists(), 'Broken/outside-input Rojo path'
                mapped.append(target)
            for value in node.values(): visit(value)
        elif isinstance(node,list):
            for value in node: visit(value)
    visit(project)
    assert mapped, 'No public constants mapping'
    place = ET.parse(root/'starter-project/TideLockStart.rbxlx').getroot()
    scripts = [node for node in place.iter('Item') if node.get('class') in {'Script','LocalScript'}]
    assert not scripts, 'Starter must not contain completed gameplay scripts'
    assert project['tree']['Workspace']['$properties']['StreamingEnabled'] is False
    print('PASS: public dependency/scaffold checks. Gameplay and live contract behavior were not tested.')

if __name__=='__main__':
    check_input(Path(__file__).resolve().parents[1])
