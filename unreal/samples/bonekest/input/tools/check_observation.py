"""Validate a read-only snapshot's public format; never score gameplay."""
import argparse
import json
import math
import sys
import time
from pathlib import Path


def require(condition, message):
    if not condition:
        raise ValueError(message)


def finite(value):
    return ((isinstance(value, int) and not isinstance(value, bool)) or
            (isinstance(value, float) and math.isfinite(value)))


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate JSON property: ' + key)
        result[key] = value
    return result


def read_snapshot(path):
    return json.loads(path.read_text(encoding='utf-8-sig'), object_pairs_hook=unique_object)


def finite_tree(value):
    if isinstance(value, dict):
        for item in value.values():
            finite_tree(item)
    elif isinstance(value, list):
        for item in value:
            finite_tree(item)
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        require(finite(value), 'non-finite JSON number')


def shape(value, schema, path='$'):
    kind = schema.get('type')
    if kind == 'object':
        require(isinstance(value, dict), path + ' must be an object')
        require(set(schema.get('required', [])).issubset(value), path + ' lacks required fields')
        props = schema.get('properties', {})
        if schema.get('additionalProperties') is False:
            require(set(value).issubset(props), path + ' contains undeclared fields')
        for key, item in value.items():
            if key in props:
                shape(item, props[key], path + '.' + key)
    elif kind == 'array':
        require(isinstance(value, list), path + ' must be an array')
        require(len(value) >= schema.get('minItems', 0), path + ' is too short')
        require(len(value) <= schema.get('maxItems', float('inf')), path + ' is too long')
        for index, item in enumerate(value):
            shape(item, schema.get('items', {}), path + '[' + str(index) + ']')
    elif kind == 'string':
        require(isinstance(value, str), path + ' must be a string')
        require(len(value) >= schema.get('minLength', 0), path + ' is empty')
    elif kind == 'boolean':
        require(isinstance(value, bool), path + ' must be boolean')
    elif kind in ('number', 'integer'):
        require(finite(value), path + ' must be finite numeric data')
        if kind == 'integer':
            require(value == int(value), path + ' must be an integer')
        require(value >= schema.get('minimum', -float('inf')), path + ' is below its minimum')
        require(value <= schema.get('maximum', float('inf')), path + ' exceeds its maximum')
    if 'enum' in schema:
        require(value in schema['enum'], path + ' has an invalid value')
    if 'const' in schema:
        require(value == schema['const'], path + ' has an unsupported version')


def validate(snapshot, root, previous=None):
    schema = json.loads((root / 'contracts/observation.schema.json').read_text(encoding='utf-8'))
    tables = json.loads((root / 'naming-tables.json').read_text(encoding='utf-8'))
    finite_tree(snapshot)
    shape(snapshot, schema)
    ids = set()
    for entity in snapshot['entities']:
        require(entity['id'] not in ids, 'duplicate entity ID')
        ids.add(entity['id'])
        require(entity['state'] in tables['entity_states'][entity['kind']], 'invalid entity state')
    target_ids = set()
    for target in snapshot['targets']:
        require(target['id'] not in target_ids, 'duplicate target ID')
        target_ids.add(target['id'])
        require(not target['interactable'] or target['visible'], 'hidden target is interactable')
        if 'entity_id' in target:
            require(target['entity_id'] in ids, 'target references an absent entity')
    for obj in snapshot['entities'] + snapshot['targets']:
        if 'rect' in obj:
            x, y, w, h = obj['rect']
            require(x + w <= 1.000001 and y + h <= 1.000001, 'rectangle exceeds game client')
            if obj.get('visible'):
                require(w > 0 and h > 0, 'visible target has an empty rectangle')
    for key, value in snapshot['slots'].items():
        require(finite(value) and value == int(value), key + ' must be integral')
    require(snapshot['slots']['keys_owned'] == sum(snapshot['slots'][key] for key in ['red_key','green_key','blue_key']), 'key count and ownership disagree')
    if snapshot['phase'] not in ['not_ready','menu']:
        size = snapshot['slots']['maze_size']
        require(size in [6,10,15], 'invalid active maze size')
        for key in ['room_x','room_y','monster_x','monster_y']:
            require(1 <= snapshot['slots'][key] <= size, key + ' outside the maze')
        for entity in snapshot['entities']:
            if 'cell' in entity:
                require(all(1 <= v <= size for v in entity['cell']), 'entity cell outside the maze')
    if snapshot['phase'] in ['not_ready', 'menu']:
        require(not snapshot['entities'], 'inactive phase has gameplay entities')
        require(all(value == 0 for value in snapshot['slots'].values()), 'inactive phase has nonzero round slots')
    if snapshot['phase'] == 'not_ready':
        require(not snapshot['targets'], 'unfinished phase has gameplay targets')
    if previous:
        if snapshot['session_id'] == previous['session_id']:
            require(snapshot['process_id'] == previous['process_id'], 'session PID changed')
            require(snapshot['snapshot_id'] > previous['snapshot_id'], 'snapshot did not advance')
            require(snapshot['monotonic_seconds'] >= previous['monotonic_seconds'], 'clock went backwards')
            if snapshot['round_id'] == previous['round_id']:
                require(snapshot['simulation_seconds'] >= previous['simulation_seconds'], 'round time went backwards')
        else:
            require(snapshot['round_id'] != previous['round_id'], 'new session reused round identity')
    return {'status': 'conformant', 'schema_version': snapshot['schema_version'],
            'phase': snapshot['phase'], 'snapshot_id': snapshot['snapshot_id'], 'gameplay_verified': False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', type=Path)
    parser.add_argument('--previous', type=Path)
    parser.add_argument('--max-age', type=float)
    args = parser.parse_args()
    try:
        data = read_snapshot(args.snapshot)
        previous = read_snapshot(args.previous) if args.previous else None
        if args.max_age is not None:
            require(time.time() - args.snapshot.stat().st_mtime <= args.max_age, 'snapshot file is stale')
        report = validate(data, Path(__file__).resolve().parents[1], previous)
        print(json.dumps(report))
        return 0
    except (ValueError, KeyError, TypeError) as error:
        print(json.dumps({'status': 'invalid', 'error': str(error), 'gameplay_verified': False}))
        return 1
    except OSError as error:
        print(json.dumps({'status': 'io_error', 'error': str(error), 'gameplay_verified': False}))
        return 2


if __name__ == '__main__':
    sys.exit(main())
