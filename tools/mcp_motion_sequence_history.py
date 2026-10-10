"""Require public motion/sequence history, native saved playback and core reload."""
from __future__ import annotations
import argparse
import asyncio
import json
from pathlib import Path
import shutil
import subprocess
import uuid
from mcp_presets_audit import call
from mcp_preset_library_history import valid_suite
from mcp_rig_modifier_ui_history import connected_editor
from mcp_rig_bake_restoration import ready
from mcp_edit_audit import equivalent

SUITES = {
    'motion_sequence_guards': {name: 3 for name in (
        'test_active_tree_and_playing_guards', 'test_incompatible_extraction_refusal',
        'test_late_secondary_failure_cleans_private_scene',
        'test_malformed_numeric_inputs_are_atomic', 'test_native_nearest_and_easing_sources',
        'test_secondary_events_and_short_endpoint_refusal',
        'test_secondary_rotation_frame_covariance',
        'test_sequence_abrupt_boundaries_use_native_holds',
        'test_sequence_boundaries_and_extraction_refusals',
        'test_rooted_sequence_delivers_last_native_delta',
        'test_scripted_sources_refused_before_construction',
        'test_source_payload_refused_before_duplication',
        'test_secondary_extreme_and_degenerate_sources')},
    'motion_sequence_continuation': {
        'test_clip_spring_continuation': 7938, 'test_tree_spring_continuation': 7938},
    'motion_sequence_history': {name: 4 for name in (
        'test_busy_destination_is_atomic', 'test_motion_editable', 'test_motion_local',
        'test_motion_locked', 'test_motion_missing_library', 'test_motion_overwrite',
        'test_secondary_editable', 'test_secondary_local', 'test_secondary_locked',
        'test_secondary_rotated_rest_keeps_native_initial_pose',
        'test_sequence_editable', 'test_sequence_local', 'test_sequence_locked',
        'test_sequence_missing_channel_enters_from_authored_pose',
        'test_sequence_missing_library', 'test_sequence_overwrite')},
}
SUITES['motion_sequence_history']['test_registry_writers_covered'] = 2
DIRECT_IDS = ('motion_walk_start_local_60', 'secondary_branches_local_60',
              'sequence_rooted_local_60', 'sequence_inline_pose_local_60')

def runtime(args) -> dict:
    result = subprocess.run([args.godot, '--headless', '--path', str(args.project_root),
        '--script', 'res://tools/check_motion_sequence_history.gd'],
        capture_output=True, text=True, timeout=240, check=False)
    prefix = 'MOTION_SEQUENCE_HISTORY_RUNTIME='
    payload = next((s[len(prefix):] for s in result.stdout.splitlines() if s.startswith(prefix)), '')
    report = json.loads(payload) if payload else {}
    if (result.returncode or 'ERROR:' in result.stdout + result.stderr
            or report.get('cases') != 273 or report.get('saved_states') != 819
            or report.get('playback_runs') != 2457 or report.get('failures') != []
            or report.get('engine_errors') != [] or report.get('key_samples', 0) < 100000
            or report.get('intermediate_samples', 0) < 100000
            or report.get('travel_runs', 0) < 100
            or report.get('approximation_samples', 0) < 1000):
        raise RuntimeError('Native history gate failed: ' + (result.stdout + result.stderr)[-7000:])
    return report

async def direct(client, row, phase, args) -> dict:
    folder = args.project_root / 'repair_motion_sequence_route' / args.route_id
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / (row['id'] + '_' + phase + '.tscn')
    shutil.copyfile(row['_disk_path'], target)
    scene = 'res://' + target.relative_to(args.project_root).as_posix()
    opened = await call(client, 'scene_open', {'path': scene, 'force_reload': True})
    if opened.get('error') or opened.get('switched') is not True: raise RuntimeError(opened)
    await ready(client)
    p = dict(row['params'])
    p.update(player_path='/Main/MotionSequenceHistory/Playback/AnimationPlayer',
             skeleton_path='/Main/MotionSequenceHistory/Character/Skeleton')
    if row['group'] != 'secondary': p['animation_name'] = 'external_' + phase
    family = 'animation_sequence' if row['group'] == 'sequence' else 'animation_motion'
    async def invoke(params):
        return await call(client, 'custom_manage', {'op': 'invoke', 'params': {
            'tool_name': family, 'params': params}})
    async def pose():
        return await call(client, 'custom_animation_rig', {
            'op': 'pose_save', 'skeleton_path': p['skeleton_path']})
    before = await pose()
    dry = await invoke({**p, 'dry_run': True})
    after_dry = await pose()
    made = await invoke(p)
    after = await pose()  # Separate RPC observes deferred library refresh.
    if (dry.get('error') or made.get('error') or before != after or before != after_dry
            or made.get('track_count', 0) < 1 or made.get('key_count', 0) < 2):
        raise RuntimeError({'id': row['id'], 'dry': dry, 'made': made,
                            'source_changed': before != after or before != after_dry})
    refused = await invoke(p)
    if not refused.get('error'): raise RuntimeError('Missing overwrite refusal: ' + repr(refused))
    if await pose() != before: raise RuntimeError('Refusal changed source pose')
    saved = await call(client, 'scene_save', {})
    reopened = await call(client, 'scene_open', {'path': scene, 'force_reload': True})
    inspected = await call(client, 'custom_animation_inspect', {'op': 'describe',
        'player_path': p['player_path'], 'animation_name': p['animation_name']})
    clips = inspected.get('clips', [])
    if (saved.get('error') or reopened.get('error') or inspected.get('error')
            or len(clips) != 1 or clips[0].get('track_count') != made['track_count']
            or not all(t.get('node_resolved') and t.get('keys', 0) >= 2 for t in clips[0].get('tracks', []))):
        raise RuntimeError({'save': saved, 'reopen': reopened, 'inspect': inspected})
    later_file = folder / (row['id'] + '_' + phase + '_later.tscn')
    shutil.copyfile(row['_disk_path'], later_file)
    opened = await call(client, 'scene_open', {
        'path': 'res://' + later_file.relative_to(args.project_root).as_posix(), 'force_reload': True})
    if opened.get('error') or opened.get('switched') is not True: raise RuntimeError(opened)
    await ready(client)
    later = await call(client, 'batch_execute', {'undo': False, 'commands': [
        {'command': 'custom_tool:' + family, 'params': p},
        {'command': 'custom_tool:animation_rig', 'params': {
            'op': 'pose_apply', 'skeleton_path': p['skeleton_path'], 'pose': {
                'bones': {'hand_L': {'position': {
                    'kind': 'vector3', 'x': 0.4, 'y': -0.3, 'z': 0.0}}}}}},
    ]})
    later_pose = await pose()
    actual_position = later_pose.get('pose', {}).get('bones', {}).get('hand_L', {}).get('position')
    if (later.get('succeeded') != 2 or not equivalent(actual_position, {
            'kind': 'vector3', 'x': 0.4, 'y': -0.3, 'z': 0.0})):
        raise RuntimeError({'later_action': later, 'later_pose': later_pose})
    return {'id': row['id'], 'passed': True, 'dry': dry, 'made': made,
            'refused': refused, 'save': saved, 'reopen': reopened, 'inspect': inspected,
            'source_pose_preserved': True, 'later_pose_preserved': True}

async def run(args):
    args.route_id = uuid.uuid4().hex
    suites, phases = {}, []
    async with connected_editor(args) as (client, connection):
        await call(client, 'scene_open', {'path': 'res://main.tscn'})
        for name, expected in SUITES.items():
            await ready(client)
            result = await call(client, 'test_run', {'suite': name, 'verbose': True})
            suites[name] = result
            if args.record:
                args.record.parent.mkdir(parents=True, exist_ok=True)
                args.record.with_suffix('.progress.json').write_text(
                    json.dumps({'suites': suites}, indent=2), encoding='utf-8')
            if not valid_suite(result, expected): raise RuntimeError('Invalid suite ' + name + ': ' + repr(result))
        played = runtime(args)
        if args.record:
            args.record.with_suffix('.progress.json').write_text(
                json.dumps({'suites': suites, 'runtime': played}, indent=2), encoding='utf-8')
        manifest = Path(played['manifest_path'])
        rows = {row['id']: row for row in json.loads(manifest.read_text(encoding='utf-8'))['cases']}
        for key in DIRECT_IDS:
            rows[key]['_disk_path'] = str(manifest.parent / rows[key]['source'].removeprefix('user://'))
        results = [await direct(client, rows[key], 'before_reload', args) for key in DIRECT_IDS]
        phases.append({'phase': 'before_reload', 'connection': connection, 'rows': results})
        reload_result = await call(client, 'editor_reload_plugin', {})
        if reload_result.get('error'): raise RuntimeError(reload_result)
    async with connected_editor(args, phases[0]['connection']['session_id']) as (client, connection):
        results = [await direct(client, rows[key], 'after_reload', args) for key in DIRECT_IDS]
        phases.append({'phase': 'after_reload', 'connection': connection, 'rows': results})
    report = {'passed': True, 'suites': suites, 'runtime': played, 'phases': phases, 'reload': reload_result}
    if args.record:
        args.record.parent.mkdir(parents=True, exist_ok=True)
        args.record.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('MCP_MOTION_SEQUENCE_HISTORY=' + json.dumps(report, sort_keys=True))
    return 0

def main():
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
