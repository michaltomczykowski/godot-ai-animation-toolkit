"""Compose idle/start/walk/stop/idle through the public Godot AI custom tool."""
from __future__ import annotations
import argparse
import asyncio
import hashlib
import json
from pathlib import Path
import subprocess
from uuid import uuid4
from fixture_copy import copy_scene
from mcp_character_quality_baseline import RIGS
from mcp_motion_remaining_cycles import inspect
from mcp_presets_audit import call
from mcp_rig_modifier_ui_history import connected_editor
from review_receipts import write_json


async def run(a):
    a.output.mkdir(parents=True, exist_ok=False)
    folder = a.project_root / 'repair_transition_sequence' / uuid4().hex
    folder.mkdir(parents=True)
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=Path(__file__).resolve().parents[1], text=True).strip()
    report = {'passed': False, 'operation': 'animation_sequence', 'profile': 'responsive',
        'revision': 'start-stop-sequence-r001', 'source_head': source, 'cases': [], 'failures': []}
    receipt = a.output / 'route.json'
    def save(): write_json(receipt, report)
    async with connected_editor(a) as (client, connection):
        report['connection'] = connection; save()
        async def invoke(tool, params):
            value = await call(client, 'custom_manage', {'op': 'invoke', 'params': {'tool_name': tool, 'params': params}})
            if value.get('error'): raise RuntimeError(value)
            return value
        for rig_id, label, fixture, root, rig, player, synthetic in RIGS:
            target = folder / (rig_id + '.tscn'); copy_scene(a.project_root / fixture, target)
            with target.open('a', encoding='utf-8') as stream:
                stream.write(f'\n[node name="PublicSequenceHistory" type="Node" parent="."]\nmetadata/player_path = NodePath("{player}")\n')
            scene = 'res://' + target.relative_to(a.project_root).as_posix()
            common = {'player_path': f'/{root}/{player}', 'skeleton_path': f'/{root}/{rig}'}
            row = {'id': rig_id, 'label': label, 'scene': scene, 'skeleton': rig, 'player': player,
                   'synthetic': synthetic, 'sources': {}, 'passed': False}
            report['cases'].append(row); save()
            row['open'] = await call(client, 'scene_open', {'path': scene, 'force_reload': True})
            for operation in ('idle_cycle', 'walk_start', 'walk_cycle', 'walk_stop'):
                row['sources'][operation] = await invoke('animation_motion', {**common,
                    'op': operation, 'animation_name': operation, 'root_motion': True})
                save()
            start_length = float(row['sources']['walk_start']['capture_duration'])
            stop_length = float(row['sources']['walk_stop']['capture_duration'])
            idle_length = float(row['sources']['idle_cycle']['length'])
            walk_length = float(row['sources']['walk_cycle']['length'])
            segments = []; clock = 0.0
            for op, length in [('idle_cycle', idle_length), ('walk_start', start_length),
                    ('walk_cycle', walk_length), ('walk_cycle', walk_length), ('walk_stop', stop_length), ('idle_cycle', idle_length)]:
                # Gait joins already match moving references. Standing joins
                # exercise a short timed blend; stationary extraction tails
                # are excluded from every source range.
                fade = .05 if segments and op in ('walk_start', 'idle_cycle') else 0.0
                segments.append({'start': clock, 'duration': length, 'source_animation': op,
                    'source_start': 0.0, 'source_end': length, 'fade_in': fade,
                    'contacts': [{'name': f'{op}_{len(segments)}_begin', 'time': 0.0}]})
                clock += length
            params = {**common, 'op': 'compose', 'animation_name': 'quality_locomotion',
                'duration': clock, 'samples': 60, 'segments': segments}
            row['params'] = params
            row['pose_before'] = await call(client, 'custom_animation_rig', {'op': 'pose_save', 'skeleton_path': common['skeleton_path']})
            row['before'] = await inspect(client, params['animation_name'], common['player_path'])
            row['dry'] = await invoke('animation_sequence', {**params, 'dry_run': True})
            row['after_dry'] = await inspect(client, params['animation_name'], common['player_path'])
            row['pose_after_dry'] = await call(client, 'custom_animation_rig', {'op': 'pose_save', 'skeleton_path': common['skeleton_path']})
            row['write'] = await invoke('animation_sequence', params)
            row['roles'] = row['sources']['walk_start']['roles']
            row['after'] = await inspect(client, params['animation_name'], common['player_path'])
            row['history'] = await call(client, 'test_run', {'suite': 'animation_sequence',
                'test_name': 'test_compose_playback_contact_dry_run_and_undo', 'verbose': True})
            row['after_history'] = await inspect(client, params['animation_name'], common['player_path'])
            row['pose_after'] = await call(client, 'custom_animation_rig', {'op': 'pose_save', 'skeleton_path': common['skeleton_path']})
            row['save'] = await call(client, 'scene_save', {})
            row['reopen'] = await call(client, 'scene_open', {'path': scene, 'force_reload': True})
            row['persisted'] = await inspect(client, params['animation_name'], common['player_path'])
            row['scene_sha256'] = hashlib.sha256(target.read_bytes()).hexdigest()
            row['passed'] = (row['before'] == row['after_dry'] and row['after'] == row['after_history'] == row['persisted']
                and row['pose_before'] == row['pose_after_dry'] == row['pose_after']
                and row['history'].get('passed') == 1 and row['history'].get('failed') == 0
                and row['history'].get('skipped') == 0 and not any(row[k].get('error') for k in ('open', 'save', 'reopen')))
            if not row['passed']: report['failures'].append(rig_id)
            save(); print(f'Public sequence {rig_id}: pass={row["passed"]}', flush=True)
    report['passed'] = len(report['cases']) == 4 and not report['failures']; save()
    return int(not report['passed'])

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('core-root', 'project-root', 'output'): p.add_argument('--' + name, type=Path, required=True)
    p.add_argument('--port', type=int, default=8000); p.add_argument('--ws-port', type=int, default=9500)
    raise SystemExit(asyncio.run(run(p.parse_args())))
