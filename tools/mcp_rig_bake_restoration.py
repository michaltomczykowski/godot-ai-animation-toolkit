"""Require isolated bake matrices and direct custom-tool calls around core reload."""
from __future__ import annotations
import argparse
import asyncio
import json
from pathlib import Path
import subprocess
import shutil
import sys
from mcp_presets_audit import call
from mcp_preset_library_history import valid_suite
from mcp_rig_modifier_ui_history import connected_editor

SUITES = {
    'rig_bake_graph': {name: 30 for name in (
        'test_state_machine', 'test_blend_space_1d', 'test_blend_space_2d',
        'test_filtered_additive_timescale', 'test_one_shot_timescale',
        'test_nested_state_machine', 'test_grouped_state_machine',
        'test_inactive_tree', 'test_graph_preflight_is_atomic')},
    'rig_bake_root_motion': {'test_preserve': 3660, 'test_pose_only': 3660,
        'test_apply': 3660, 'test_explicit_output_carrier_history': 19,
        'test_root_preflight_is_atomic': 21},
    'rig_bake_modifiers': {'test_all_native_modifiers': 864,
                           'test_reordered_fractional_stacks': 234},
    'rig_bake_storage': {'test_graph_output_storage': 216},
    'rig_bake_continuation': {'test_clip_spring_continuation': 633,
                              'test_graph_spring_continuation': 5064},
    'rig_bake_refusals': {'test_track_semantics': 44,
                         'test_animated_scripted_modifier_refusal': 12,
                         'test_scripted_resource_refused_before_duplication': 12,
                         'test_short_final_spacing_refusal': 11},
}
SUITES['rig_bake_graph']['test_event_does_not_preblend'] = 12
DIRECT_IDS = ('graph_state_60', 'root_preserve_true_true_true_60',
              'root_pose_only_true_true_true_60', 'root_apply_true_true_true_60')

async def ready(client) -> None:
    stable = 0
    for _ in range(80):
        state = await call(client, 'editor_state', {})
        stable = stable + 1 if state.get('readiness') == 'ready' else 0
        if stable == 3: return
        await asyncio.sleep(0.25)
    raise RuntimeError('Editor did not finish importing before bake calls')

def runtime(args: argparse.Namespace) -> dict:
    result = subprocess.run([args.godot, '--headless', '--path', str(args.project_root),
        '--script', 'res://tools/check_rig_bake_restoration.gd'],
        capture_output=True, text=True, timeout=90, check=False)
    prefix = 'RIG_BAKE_RESTORATION_RUNTIME='
    payload = next((s[len(prefix):] for s in result.stdout.splitlines() if s.startswith(prefix)), '')
    report = json.loads(payload) if payload else {}
    if (result.returncode or 'ERROR:' in result.stdout + result.stderr
            or report.get('cases') != 201 or report.get('saved_states') != 603
            or report.get('played_states') != 402 or report.get('failures') != []
            or report.get('engine_errors') != [] or report.get('key_samples', 0) < 10000
            or report.get('intermediate_samples', 0) < 10000):
        raise RuntimeError('Saved bake playback gate failed: ' + (result.stdout + result.stderr)[-7000:])
    return report

async def direct(client, row: dict, phase: str, args: argparse.Namespace) -> dict:
    # The editor opens project resources; runtime user:// exports stay intact.
    folder = args.project_root / 'repair_bake_route'
    folder.mkdir(exist_ok=True)
    target = folder / (row['id'] + '_' + phase + '.tscn')
    shutil.copyfile(row['_disk_path'], target)
    scene_path = 'res://repair_bake_route/' + target.name
    opened = await call(client, 'scene_open', {'path': scene_path})
    if opened.get('error'): raise RuntimeError(opened)
    p = dict(row['params'])
    p.update(player_path='/Main/' + row['source_player'],
             skeleton_path='/Main/' + row['skeleton'],
             source_tree_path='/Main/' + row['tree'],
             animation_name='external_baked_' + phase)
    p.pop('output_player_path', None)
    if p.get('root_motion_target_path'):
        p['root_motion_target_path'] = '/Main/' + row['movement_owner']
    # Scene opening is deferred by the editor. Wait for its actual fixture
    # before dispatching the bake against the previous scene's root.
    for _ in range(40):
        found = await call(client, 'node_get_properties',
                           {'path': p['skeleton_path'], 'fields': ['name']})
        if not found.get('error'): break
        await asyncio.sleep(0.1)
    else: raise RuntimeError('Source fixture did not open: ' + repr(opened))
    await ready(client)
    async def invoke(params):
        return await call(client, 'custom_manage', {'op': 'invoke', 'params': {
            'tool_name': 'animation_rig', 'params': params}})
    before = await call(client, 'custom_animation_rig', {'op': 'pose_save',
                         'skeleton_path': p['skeleton_path']})
    dry = await invoke({**p, 'dry_run': True})
    made = await invoke(p)
    after = await call(client, 'custom_animation_rig', {'op': 'pose_save',
                        'skeleton_path': p['skeleton_path']})
    if (dry.get('error') or made.get('error') or before != after
            or not made.get('evaluation_isolated') or not made.get('live_state_untouched')
            or made.get('samples', 0) < 10 or made.get('track_count', 0) < 1
            or dry.get('player_path') != made.get('player_path')):
        raise RuntimeError({'id': row['id'], 'dry': dry, 'made': made, 'source_changed': before != after})
    refused = await invoke({**p, 'output_player_path': made['player_path']})
    error = refused.get('error', {})
    code = error.get('code') if isinstance(error, dict) else str(error).split(':', 1)[0]
    if code not in ('INVALID_PARAMS', 'VALUE_OUT_OF_RANGE'): raise RuntimeError('Missing typed overwrite refusal: ' + repr(refused))
    saved = await call(client, 'scene_save', {})
    reopened = await call(client, 'scene_open', {'path': scene_path, 'force_reload': True})
    inspected = await call(client, 'custom_animation_inspect', {'op': 'describe',
                       'player_path': made['player_path'], 'animation_name': p['animation_name']})
    if saved.get('error') or reopened.get('error') or inspected.get('error'):
        raise RuntimeError({'save': saved, 'reopen': reopened, 'library': inspected})
    clips = inspected.get('clips', [])
    if (len(clips) != 1 or clips[0].get('track_count') != made['track_count']
            or any(not t.get('node_resolved') or t.get('keys') != made['samples'] for t in clips[0].get('tracks', []))):
        raise RuntimeError('Saved bake is missing resolved tracks or keys: ' + repr(inspected))
    return {'id': row['id'], 'passed': True, 'dry': dry, 'made': made,
            'refused': refused, 'save': saved, 'reopen': reopened, 'inspected': inspected}

async def run(args: argparse.Namespace) -> int:
    suites = {}
    phases = []
    reload_result = {}
    async with connected_editor(args) as (client, connection):
        await call(client, 'scene_open', {'path': 'res://main.tscn'})
        for name, expected in SUITES.items():
            await ready(client)
            result = await call(client, 'test_run', {'suite': name, 'verbose': True})
            suites[name] = result
            if not valid_suite(result, expected): raise RuntimeError('Invalid suite ' + name + ': ' + repr(result))
        played = runtime(args)
        manifest = json.loads(Path(played['manifest_path']).read_text(encoding='utf-8'))
        rows = {row['id']: row for row in manifest['cases']}
        for key in DIRECT_IDS:
            rows[key]['_disk_path'] = str(Path(played['manifest_path']).parent / rows[key]['source'].removeprefix('user://'))
        results = [await direct(client, rows[key], 'before_reload', args) for key in DIRECT_IDS]
        phases.append({'phase': 'before_reload', 'connection': connection, 'rows': results})
        reload_result = await call(client, 'editor_reload_plugin', {})
        if reload_result.get('error'): raise RuntimeError(reload_result)
    async with connected_editor(args, phases[0]['connection']['session_id']) as (client, connection):
        results = [await direct(client, rows[key], 'after_reload', args) for key in DIRECT_IDS]
        phases.append({'phase': 'after_reload', 'connection': connection, 'rows': results})
    report = {'passed': True, 'suites': suites, 'runtime': played,
              'phases': phases, 'reload': reload_result}
    print('MCP_RIG_BAKE_RESTORATION=' + json.dumps(report, sort_keys=True))
    if args.record: args.record.write_text(json.dumps(report, indent=2), encoding='utf-8')
    return 0

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--core-root', type=Path, required=True)
    parser.add_argument('--project-root', type=Path, required=True)
    parser.add_argument('--session-hint', required=True)
    parser.add_argument('--port', type=int, required=True)
    parser.add_argument('--ws-port', type=int, required=True)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--record', type=Path)
    return asyncio.run(run(parser.parse_args()))
if __name__ == '__main__': raise SystemExit(main())
