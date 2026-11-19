from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
for path in ['INITIAL_AGENT_PROMPT.md','GDD.md','CONTENT.json','contracts/GAME_SESSION_SPEC.md','contracts/SESSION_MODEL.json','tools/TOOL_GUIDE.md','tools/tool-config.example.json','assets/ASSET_CATALOG.json']:
    assert (root/path).is_file() and (root/path).stat().st_size>0,path
projects=list((root/'starter-project/native').rglob('default.project.json'))
assert projects,'Blank project configuration missing'
for project in projects:
    def visit(node):
        if isinstance(node,dict):
            if '$path' in node:
                path=(project.parent/node['$path']).resolve()
                assert path.is_relative_to(root.resolve()) and path.exists(),str(path)
            for value in node.values():visit(value)
        elif isinstance(node,list):
            for value in node:visit(value)
    visit(json.loads(project.read_text(encoding='utf-8-sig')))
print('PASS: public input and original project mappings are self-contained. Gameplay was not re-evaluated.')
