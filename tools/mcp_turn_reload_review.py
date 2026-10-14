"""Dry-invoke all preserved ordinary turns across an actual core-addon reload."""
from __future__ import annotations
import argparse
import asyncio
import hashlib
import json
from pathlib import Path
from uuid import uuid4
from fixture_copy import copy_scene
from mcp_motion_remaining_cycles import inspect
from mcp_presets_audit import call
from mcp_probe import EXPECTED_CATALOG, EXPECTED_PROMOTED
from mcp_rig_modifier_ui_history import connected_editor
from review_receipts import write_json


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


async def run(a):
    a.output.mkdir(parents=True, exist_ok=False)
    folder = a.project_root / 'repair_turn_reload' / uuid4().hex
    folder.mkdir(parents=True)
    report = {'passed': False, 'state': 'running', 'phases': [], 'routes': []}
    receipt = a.output / 'core-reload.json'
    def save(): write_json(receipt, report)
    routes = []
    keys = set()
    for candidate in a.candidates:
        for path in sorted(candidate.glob('*/**/route.json')):
            route = json.loads(path.read_text(encoding='utf-8-sig'))
            assert route['passed'] and route['operation'] == 'turn_cycle' and len(route['cases']) == 4
            key = (path.relative_to(candidate).parts[0], route['profile'], route['root_mode'])
            assert key not in keys, ('Duplicate ordinary case', key)
            keys.add(key)
            routes.append((path, route))
            report['routes'].append({'path': str(path), 'sha256': digest(path), 'source_head': route['source_head']})
    expected = {(v, s, m) for v in ('left90', 'right90', 'left180', 'right180')
                for s in ('responsive', 'grounded', 'relaxed', 'heavy', 'sneaky') for m in ('extracted', 'in_place')}
    assert keys == expected, 'Require exactly the full 160 ordinary turn cases'
    save()
    old_session = ''
    try:
        for phase in ('before_reload', 'after_reload'):
            async with connected_editor(a, old_session) as (client, connection):
                catalog = await call(client, 'custom_manage', {'op': 'list'})
                names = {t['name'] for t in catalog.get('tools', [])}
                choices = {t['name']: t.get('params_schema', {}).get('properties', {}).get('op', {}).get('enum', [])
                           for t in catalog.get('tools', [])}
                tools = {t.name for t in await client.list_tools()}
                section = {'phase': phase, 'connection': connection, 'catalog': catalog,
                           'promoted': sorted(tools & EXPECTED_PROMOTED), 'choices': choices, 'rows': []}
                report['phases'].append(section); save()
                assert names == EXPECTED_CATALOG and sum(map(len, choices.values())) == 103
                assert all(t.get('enabled') is True for t in catalog['tools']) and EXPECTED_PROMOTED <= tools
                for path, route in routes:
                    for row in route['cases']:
                        original = a.project_root / row['scene'].removeprefix('res://')
                        assert digest(original) == row['scene_sha256']
                        target = folder / f'{phase}-{len(section["rows"]):03d}-{row["id"]}.tscn'
                        copy_scene(original, target)
                        scene = 'res://' + target.relative_to(a.project_root).as_posix()
                        opened = await call(client, 'scene_open', {'path': scene, 'force_reload': True})
                        normalized = await call(client, 'scene_save', {})
                        before_hash = digest(target)
                        before = await inspect(client, row['params']['animation_name'], row['params']['player_path'])
                        pose_params = {'op': 'pose_save', 'skeleton_path': row['params']['skeleton_path']}
                        pose_before = await call(client, 'custom_animation_rig', pose_params)
                        binding_params = {'path': row['params']['player_path'], 'fields': ['root_motion_track']}
                        binding_before = await call(client, 'node_get_properties', binding_params)
                        dry = await call(client, 'custom_manage', {'op': 'invoke', 'params': {
                            'tool_name': 'animation_motion', 'params': {**row['params'], 'overwrite': True, 'dry_run': True}}})
                        pose_after = await call(client, 'custom_animation_rig', pose_params)
                        binding_after = await call(client, 'node_get_properties', binding_params)
                        after = await inspect(client, row['params']['animation_name'], row['params']['player_path'])
                        saved = await call(client, 'scene_save', {})
                        passed = (before == after == row['persisted'] and pose_before == pose_after
                                  and binding_before == binding_after and before_hash == digest(target)
                                  and dry.get('dry_run') is True and not any(v.get('error') for v in
                                  (opened, normalized, pose_before, pose_after, binding_before, binding_after, dry, saved)))
                        section['rows'].append({'id': row['id'], 'route': str(path), 'scene': scene,
                            'before_sha256': before_hash, 'after_sha256': digest(target),
                            'pose_unchanged': pose_before == pose_after, 'binding_unchanged': binding_before == binding_after,
                            'dry': dry, 'passed': passed})
                        save()
                        if not passed: raise RuntimeError('Reload dry call failed: ' + str(path))
                print(f'{phase}: 160/160 saved turn dry calls', flush=True)
                if phase == 'before_reload':
                    old_session = connection['session_id']
                    report['reload'] = await call(client, 'editor_reload_plugin', {}); save()
        report.update(state='complete', passed=not report['reload'].get('error') and
            report['phases'][0]['connection']['session_id'] != report['phases'][1]['connection']['session_id'] and
            all(len(p['rows']) == 160 and all(r['passed'] for r in p['rows']) for p in report['phases']))
    except Exception as error:
        report.update(state='failed', error=f'{type(error).__name__}: {error}')
        raise
    finally: save()
    return int(not report['passed'])


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for n in ('core-root', 'project-root', 'output'): p.add_argument('--' + n, type=Path, required=True)
    p.add_argument('--candidates', type=Path, nargs='+', required=True)
    p.add_argument('--port', type=int, default=8000); p.add_argument('--ws-port', type=int, default=9500)
    raise SystemExit(asyncio.run(run(p.parse_args())))
