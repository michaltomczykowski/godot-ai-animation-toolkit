"""Preserve public character_setup turns and compare them to dedicated calls.

Setup reports bundle summaries, not contact/reach detail. Native quality uses
the dedicated metadata only after exact saved-channel parity is established.
"""
from __future__ import annotations
import argparse
import asyncio
from datetime import datetime, timezone
import hashlib
import json
import re
from pathlib import Path
import subprocess
from uuid import uuid4
from fixture_copy import copy_scene
from mcp_character_quality_baseline import RIGS
from mcp_motion_remaining_cycles import inspect
from mcp_presets_audit import call
from mcp_rig_modifier_ui_history import connected_editor
from review_receipts import write_json


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))


async def run(a):
    a.output.mkdir(parents=True, exist_ok=False)
    folder = a.project_root / 'repair_turn_setup' / uuid4().hex
    folder.mkdir(parents=True)
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=a.repo, text=True).strip()
    report = {'passed': False, 'state': 'running', 'source_head': source, 'groups': [],
              'created_utc': datetime.now(timezone.utc).isoformat()}
    receipt = a.output / 'setup-matrix.json'
    def save(): write_json(receipt, report)
    groups = [(s, 'left', .7, a.references / 'left' / (s + '-in-place') / 'route.json')
              for s in ('responsive', 'grounded', 'relaxed', 'heavy', 'sneaky')]
    groups.append(('responsive', 'right', .9, a.references / 'right' / 'responsive-in-place' / 'route.json'))
    try:
        async with connected_editor(a) as (client, connection):
            report['connection'] = connection; save()
            for style, direction, period, reference_path in groups:
                reference = read(reference_path)
                assert reference['passed'] and len(reference['cases']) == 4
                label = f'{style}-{direction}'
                output = a.output / label
                output.mkdir()
                route = {'passed': False, 'source_head': source, 'revision': 'turn-setup-' + label,
                         'operation': 'character_setup', 'cases': [], 'reference': str(reference_path)}
                route_path = output / 'route.json'
                reused = False
                if a.reuse_complete and (a.reuse_complete / label / 'route.json').exists():
                    previous_path = a.reuse_complete / label / 'route.json'
                    previous = read(previous_path)
                    assert previous['passed'] and len(previous['cases']) == 4
                    assert subprocess.run(['git', 'diff', '--quiet', previous['source_head'], 'HEAD', '--',
                        'addons/godot_ai_animation'], cwd=a.repo).returncode == 0
                    route = {**previous, 'reused_from': str(previous_path), 'reused_from_sha256': digest(previous_path)}
                    write_json(route_path, route)
                    reused = True
                for rig_id, rig_label, fixture, root_name, skeleton, player, synthetic in RIGS:
                    if reused:
                        row = next(r for r in route['cases'] if r['id'] == rig_id)
                        assert row['passed'] and digest(a.project_root / row['scene'].removeprefix('res://')) == row['scene_sha256']
                        continue
                    ref = next(r for r in reference['cases'] if r['id'] == rig_id)
                    assert digest(a.project_root / ref['scene'].removeprefix('res://')) == ref['scene_sha256']
                    target = folder / f'{label}-{rig_id}.tscn'
                    copy_scene(a.project_root / fixture, target)
                    player_block = re.search(r'(?ms)^\[node name="' + re.escape(player) + r'"[^\n]*\].*?(?=^\[node|\Z)',
                                             target.read_text(encoding='utf-8-sig'))
                    assert player_block, 'Fixture player block is required'
                    root_binding = re.search(r'root_motion_track = NodePath\("([^"]*)"\)', player_block.group())
                    before_root = root_binding.group(1) if root_binding else ''
                    with target.open('a', encoding='utf-8') as stream:
                        stream.write(f'\n[node name="PublicSetupHistory" type="Node" parent="."]\n'
                            f'metadata/player_path = NodePath("{player}")\n'
                            'metadata/tree_path = NodePath("AnimationTree")\n'
                            f'metadata/before_root_motion_track = NodePath("{before_root}")\n'
                            f'metadata/direction = "{direction}"\n')
                    scene = 'res://' + target.relative_to(a.project_root).as_posix()
                    # Keep unrelated locomotion reachable on all proportions.
                    # This is explicit bundle configuration, not an implicit-default claim.
                    leg = a.leg_lengths[rig_id]
                    request = {'op': 'character_setup', 'player_path': f'/{root_name}/{player}',
                        'skeleton_path': f'/{root_name}/{skeleton}', 'include_turn': True,
                        'include_jump': False, 'active': False, 'root_motion': True,
                        'run_speed': 2.0 * leg, 'direction': direction}
                    if style != 'responsive': request['style'] = style
                    if direction == 'right': request['turn_duration'] = period
                    name = 'turn_' + direction
                    row = {'id': rig_id, 'label': rig_label, 'scene': scene, 'player': player,
                        'skeleton': skeleton, 'synthetic': synthetic, 'request': request,
                        'params': {'animation_name': name, 'angle': 90, 'direction': direction},
                        'roles': ref['roles'], 'write': ref['write'],
                        'quality_metadata_source': {'route': str(reference_path), 'scene': ref['scene'],
                            'policy': 'Require exact saved channel parity before using dedicated contacts/reach for setup playback'}}
                    route['cases'].append(row)
                    async def stage(key, tool, params):
                        value = await call(client, tool, params)
                        row[key] = value; write_json(route_path, route)
                        return value
                    pose = {'op': 'pose_save', 'skeleton_path': request['skeleton_path']}
                    binding = {'path': request['player_path'], 'fields': ['root_motion_track']}
                    await stage('open', 'scene_open', {'path': scene, 'force_reload': True})
                    row['before'] = await inspect(client, name, request['player_path'])
                    await stage('pose_before', 'custom_animation_rig', pose)
                    await stage('binding_before', 'node_get_properties', binding)
                    assert row['binding_before']['properties'][0]['value'] == before_root, 'History fixture must match the actual caller binding'
                    await stage('dry', 'custom_manage', {'op': 'invoke', 'params': {
                        'tool_name': 'animation_motion', 'params': {**request, 'dry_run': True}}})
                    row['after_dry'] = await inspect(client, name, request['player_path'])
                    await stage('pose_after_dry', 'custom_animation_rig', pose)
                    await stage('binding_after_dry', 'node_get_properties', binding)
                    await stage('setup_response', 'custom_manage', {'op': 'invoke', 'params': {
                        'tool_name': 'animation_motion', 'params': request}})
                    if row['setup_response'].get('error'): raise RuntimeError(row['setup_response'])
                    row['after'] = await inspect(client, name, request['player_path'])
                    await stage('pose_after', 'custom_animation_rig', pose)
                    await stage('history', 'test_run', {'suite': 'animation_motion',
                        'test_name': 'test_turn_undo_redo_restores_written_turn', 'verbose': True})
                    await stage('save', 'scene_save', {})
                    await stage('reopen', 'scene_open', {'path': scene, 'force_reload': True})
                    row['persisted'] = await inspect(client, name, request['player_path'])
                    row['scene_sha256'] = digest(target)
                    row['passed'] = (not any(row[k].get('error') for k in ('open', 'dry', 'pose_before',
                        'pose_after_dry', 'binding_before', 'binding_after_dry', 'setup_response', 'save', 'reopen'))
                        and row['before'] == row['after_dry'] and row['pose_before'] == row['pose_after_dry'] == row['pose_after']
                        and row['binding_before'] == row['binding_after_dry'] and row['after'] == row['persisted']
                        and row['history'].get('passed') == 1 and row['history'].get('failed') == 0
                        and row['history'].get('skipped') == 0)
                    write_json(route_path, route)
                    if not row['passed']: raise RuntimeError('Public setup mutation/history failure: ' + label + '/' + rig_id)
                route['passed'] = all(r['passed'] for r in route['cases']); write_json(route_path, route)
                parity_path = output / 'parity.json'
                command = [str(a.godot), '--headless', '--path', str(a.project_root), '--script',
                           'res://tools/check_turn_contract_parity.gd', '--', str(reference_path), str(route_path), str(parity_path)]
                with (output / 'parity.log').open('w', encoding='utf-8') as log:
                    subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
                parity = read(parity_path)
                assert parity['passed'] and len(parity['runs']) == 24
                native_path = output / 'native.json'
                command = [str(a.godot), '--headless', '--path', str(a.project_root), '--script',
                           'res://tools/check_turn_quality.gd', '--', str(route_path), str(native_path)]
                with (output / 'native.log').open('w', encoding='utf-8') as log:
                    subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)
                native = read(native_path)
                assert native['passed'] and len(native['runs']) == 24 and not native['engine_errors']
                report['groups'].append({'style': style, 'direction': direction, 'turn_duration': period,
                    'route': str(route_path), 'parity': str(parity_path), 'native': str(native_path), 'passed': True})
                save(); print('Public setup parity/playback: ' + label, flush=True)
        report.update(state='complete', passed=len(report['groups']) == 6)
    except Exception as error:
        report.update(state='failed', error=f'{type(error).__name__}: {error}')
        raise
    finally: save()
    return int(not report['passed'])


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for n in ('repo', 'core-root', 'project-root', 'output', 'references', 'godot', 'leg-matrix'):
        p.add_argument('--' + n, type=Path, required=True)
    p.add_argument('--port', type=int, default=8000); p.add_argument('--ws-port', type=int, default=9500)
    p.add_argument('--reuse-complete', type=Path, help='Preserve successful public groups after a checker-only retry')
    a = p.parse_args()
    a.leg_lengths = {r['id']: r['leg_length_m'] for r in read(a.leg_matrix)['runs']}
    raise SystemExit(asyncio.run(run(a)))
