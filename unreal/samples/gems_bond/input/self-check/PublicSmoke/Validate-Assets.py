"""Load project packages and report broken project dependencies in the actual editor."""
import json
from pathlib import Path
import unreal

registry = unreal.AssetRegistryHelpers.get_asset_registry()
registry.search_all_assets(True)
options = unreal.AssetRegistryDependencyOptions(True, True, False, False, False)
rows = registry.get_assets_by_path('/Game', recursive=True)
packages = {str(row.package_name) for row in rows}
checked = set()
errors = []
classes = {}
dependencies = {}
for row in rows:
    package = str(row.package_name)
    if package in checked:
        continue
    checked.add(package)
    cls = str(row.asset_class_path.asset_name)
    classes[package] = cls
    if cls == 'World':
        continue
    obj = unreal.load_asset(package)
    if not obj:
        errors.append({'package': package, 'error': 'load_failed'})
    deps = sorted(str(dep) for dep in registry.get_dependencies(row.package_name, options))
    dependencies[package] = deps
    for dep in deps:
        if dep.startswith('/Game/') and dep not in packages:
            errors.append({'package': package, 'dependency': dep, 'error': 'missing_project_package'})
report = {'status': 'passed' if not errors else 'failed', 'checked_packages': len(checked),
          'classes': classes, 'dependencies': dependencies, 'errors': errors,
          'scope': 'Editor package load and dependency health; no gameplay or rendering verdict.'}
path = Path(unreal.Paths.project_saved_dir()) / 'Benchmark/asset-validation.json'
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(report, indent=2), encoding='utf-8')
if errors:
    raise RuntimeError('Project asset validation failed; inspect Saved/Benchmark/asset-validation.json')
unreal.log('Project asset validation passed: ' + str(len(checked)) + ' packages.')
