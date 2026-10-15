"""Save public default setup bundles with external whole-transaction history witnesses.

Only the root operator runs this client against the editor. No numeric gait speed
or duration is supplied; setup provenance remains independently inspectable.
"""
from __future__ import annotations
import argparse
import asyncio
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
from uuid import uuid4
from fixture_copy import copy_scene
from mcp_character_quality_baseline import RIGS
from mcp_motion_remaining_cycles import inspect
from mcp_presets_audit import call
from mcp_rig_modifier_ui_history import connected_editor
from review_receipts import write_json


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


async def run(a):
    a.output.mkdir(parents=True, exist_ok=False)
    folder = a.project_root / 'repair_setup_quality' / uuid4().hex
    folder.mkdir(parents=True)
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=a.repo, text=True).strip()
    report = dict(passed=False, state='running', source_head=head, groups=[],
                  created_utc=datetime.now(timezone.utc).isoformat())
    receipt = a.output / 'setup-matrix.json'
    def save(): write_json(receipt, report)
    try:
        async with connected_editor(a) as (client, connection):
            report['connection'] = connection
            save()
            for style in a.styles:
                for mode, distance in [('extracted-stationary', 0.0), ('in-place-stationary', 0.0), ('extracted-forward', 0.5)]:
                    for turn in a.turns:
                        label = f'{style}-{mode}-' + ('turn' if turn else 'no-turn')
                        output = a.output / label
                        output.mkdir()
                        route_path = output / 'route.json'
                        route = dict(passed=False, source_head=head, revision='setup-' + label,
                                     operation='character_setup', cases=[])
                        for rig_id, rig_label, fixture, root_name, skeleton, player, synthetic in RIGS:
                            target = folder / f'{label}-{rig_id}.tscn'
                            copy_scene(a.project_root / fixture, target)
                            text = target.read_text(encoding='utf-8-sig')
                            block = re.search(r'(?ms)^\[node name="' + re.escape(player) + r'"[^\n]*\].*?(?=^\[node|\Z)', text)
                            if not block: raise ValueError('Missing fixture player')
                            binding = re.search(r'root_motion_track = NodePath\("([^"]*)"\)', block.group())
                            before_root = binding.group(1) if binding else ''
                            names = ['idle', 'walk', 'run', 'jump'] + (['turn_left'] if turn else [])
                            with target.open('a', encoding='utf-8') as stream:
                                stream.write('\n[node name="PublicSetupBundleHistory" type="Node" parent="."]\n'
                                    f'metadata/player_path = NodePath("{player}")\n'
                                    'metadata/tree_path = NodePath("AnimationTree")\n'
                                    f'metadata/before_root_motion_track = NodePath("{before_root}")\n'
                                    'metadata/clip_names = PackedStringArray(' + ', '.join(json.dumps(n) for n in names) + ')\n')
                            scene = 'res://' + target.relative_to(a.project_root).as_posix()
                            request = dict(op='character_setup', player_path=f'/{root_name}/{player}',
                                skeleton_path=f'/{root_name}/{skeleton}', include_jump=True,
                                include_turn=turn, active=False, root_motion=not mode.startswith('in-place'))
                            if style != 'responsive': request['style'] = style
                            if distance: request['distance'] = distance
                            row = dict(id=rig_id, label=rig_label, scene=scene, player=player,
                                       skeleton=skeleton, synthetic=synthetic, request=request, params=request.copy())
                            route['cases'].append(row)
                            async def stage(key, tool, params):
                                value = await call(client, tool, params)
                                row[key] = value
                                write_json(route_path, route)
                                if value.get('error'): raise RuntimeError(f'{key}: {value}')
                                return value
                            async def summaries():
                                return {name: await inspect(client, name, request['player_path']) for name in names}
                            pose = dict(op='pose_save', skeleton_path=request['skeleton_path'])
                            binding_request = dict(path=request['player_path'], fields=['root_motion_track'])
                            await stage('open', 'scene_open', dict(path=scene, force_reload=True))
                            profile = await stage('profile', 'custom_animation_inspect', dict(op='rig_profile', skeleton_path=request['skeleton_path'], save=False))
                            row['roles'] = profile['roles']
                            row['roles_source'] = 'public animation_inspect rig_profile(save=false)'
                            row['before'] = await summaries()
                            await stage('pose_before', 'custom_animation_rig', pose)
                            await stage('binding_before', 'node_get_properties', binding_request)
                            if row['binding_before']['properties'][0]['value'] != before_root: raise ValueError('Fixture binding mismatch')
                            await stage('dry', 'custom_manage', dict(op='invoke', params=dict(tool_name='animation_motion', params={**request, 'dry_run': True})))
                            row['after_dry'] = await summaries()
                            await stage('pose_after_dry', 'custom_animation_rig', pose)
                            await stage('binding_after_dry', 'node_get_properties', binding_request)
                            await stage('setup_response', 'custom_manage', dict(op='invoke', params=dict(tool_name='animation_motion', params=request)))
                            row['write'] = row['setup_response']
                            row['after'] = await summaries()
                            await stage('pose_after', 'custom_animation_rig', pose)
                            await stage('binding_after', 'node_get_properties', binding_request)
                            await stage('history', 'test_run', dict(suite='animation_motion', test_name='test_public_setup_bundle_undo_redo', verbose=True))
                            await stage('save', 'scene_save', {})
                            await stage('reopen', 'scene_open', dict(path=scene, force_reload=True))
                            row['persisted'] = await summaries()
                            await stage('binding_persisted', 'node_get_properties', binding_request)
                            row['scene_sha256'] = digest(target)
                            row['passed'] = (row['before'] == row['after_dry'] and
                                row['pose_before'] == row['pose_after_dry'] == row['pose_after'] and
                                row['binding_before'] == row['binding_after_dry'] and row['after'] == row['persisted'] and
                                row['binding_after'] == row['binding_persisted'] and
                                all(not value.get('error') and value.get('clips') for value in row['after'].values()) and
                                row['history'].get('passed') == 1 and row['history'].get('failed') == 0 and row['history'].get('skipped') == 0)
                            write_json(route_path, route)
                            if not row['passed']: raise RuntimeError('Setup public history/persistence failed: ' + label + '/' + rig_id)
                        route['passed'] = len(route['cases']) == 4 and all(r['passed'] for r in route['cases'])
                        write_json(route_path, route)
                        group = dict(route=str(route_path), route_sha256=digest(route_path), passed=route['passed'])
                        report['groups'].append(group)
                        save()
                        if a.godot:
                            native_path = output / 'native.json'
                            command = [str(a.godot), '--headless', '--path', str(a.project_root), '--script',
                                       'res://tools/check_setup_tree_quality.gd', '--', str(route_path), str(native_path)]
                            with (output / 'native.log').open('w', encoding='utf-8') as log:
                                subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=180, check=True)
                            native = json.loads(native_path.read_text(encoding='utf-8-sig'))
                            if not native.get('passed') or native.get('engine_errors'): raise RuntimeError('Setup native checker failed')
                            group['native'] = str(native_path)
                            group['native_sha256'] = digest(native_path)
                            save()
                        print('Public setup bundle: ' + label, flush=True)
        report.update(state='complete', passed=len(report['groups']) == len(a.styles) * 3 * len(a.turns))
    except Exception as error:
        report.update(state='failed', error=f'{type(error).__name__}: {error}')
        raise
    finally:
        save()
    return int(not report['passed'])


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for field in ('repo', 'core-root', 'project-root', 'output'):
        p.add_argument('--' + field, type=Path, required=True)
    p.add_argument('--godot', type=Path, help='Optional native checker after each completed group')
    p.add_argument('--port', type=int, default=8000)
    p.add_argument('--ws-port', type=int, default=9500)
    p.add_argument('--styles', nargs='+', choices=['responsive', 'grounded', 'relaxed', 'heavy', 'sneaky'], default=['responsive', 'grounded', 'relaxed', 'heavy', 'sneaky'])
    p.add_argument('--turn-mode', choices=['both', 'with', 'without'], default='both')
    a = p.parse_args()
    a.turns = [False, True] if a.turn_mode == 'both' else [a.turn_mode == 'with']
    raise SystemExit(asyncio.run(run(a)))
