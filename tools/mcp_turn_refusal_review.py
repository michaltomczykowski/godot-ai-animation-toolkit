"""Verify typed public turn refusals preserve saved scenes, poses and bindings."""
from __future__ import annotations
import argparse
import asyncio
import hashlib
from pathlib import Path
import subprocess
from uuid import uuid4
from fixture_copy import copy_scene
from mcp_character_quality_baseline import RIGS
from mcp_motion_remaining_cycles import inspect
from mcp_presets_audit import call
from mcp_rig_modifier_ui_history import connected_editor
from review_receipts import write_json


CASES = (('zero-angle', {'angle': 0}), ('fractional-steps', {'steps': 1.5}),
         ('too-many-steps', {'steps': 9}), ('too-large-pivot', {'angle': 180, 'steps': 1}),
         ('no-release', {'foot_lift': 0}), ('too-fast', {'duration': .3}),
         ('sample-budget', {'duration': 11}))


def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()


async def run(a):
    a.output.mkdir(parents=True, exist_ok=False)
    folder = a.project_root / 'repair_turn_refusals' / uuid4().hex
    folder.mkdir(parents=True)
    report = {'passed': False, 'state': 'running', 'rows': [],
              'source_head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=a.repo, text=True).strip()}
    def save(): write_json(a.output / 'refusals.json', report)
    try:
        async with connected_editor(a) as (client, connection):
            report['connection'] = connection; save()
            for rig, label, fixture, root, skeleton, player, synthetic in RIGS:
                target = folder / (rig + '.tscn'); copy_scene(a.project_root / fixture, target)
                scene = 'res://' + target.relative_to(a.project_root).as_posix()
                opened = await call(client, 'scene_open', {'path': scene, 'force_reload': True})
                normalized = await call(client, 'scene_save', {})
                assert not opened.get('error') and not normalized.get('error')
                params = {'op': 'turn_cycle', 'player_path': f'/{root}/{player}',
                          'skeleton_path': f'/{root}/{skeleton}', 'animation_name': 'refused_turn', 'root_motion': True}
                before_hash = digest(target)
                before = await inspect(client, 'refused_turn', params['player_path'])
                pose_params = {'op': 'pose_save', 'skeleton_path': params['skeleton_path']}
                binding_params = {'path': params['player_path'], 'fields': ['root_motion_track']}
                pose_before = await call(client, 'custom_animation_rig', pose_params)
                binding_before = await call(client, 'node_get_properties', binding_params)
                for name, extra in CASES:
                    row = {'id': rig, 'case': name, 'scene': scene, 'params': {**params, **extra}, 'stages': []}
                    report['rows'].append(row); save()
                    for dry in (True, False):
                        reply = await call(client, 'custom_manage', {'op': 'invoke', 'params': {
                            'tool_name': 'animation_motion', 'params': {**params, **extra, 'dry_run': dry}}})
                        after = await inspect(client, 'refused_turn', params['player_path'])
                        pose_after = await call(client, 'custom_animation_rig', pose_params)
                        binding_after = await call(client, 'node_get_properties', binding_params)
                        saved = await call(client, 'scene_save', {})
                        passed = (str(reply.get('error', '')).startswith('VALUE_OUT_OF_RANGE:')
                            and before == after and pose_before == pose_after and binding_before == binding_after
                            and before_hash == digest(target) and not any(v.get('error') for v in
                            (pose_before, pose_after, binding_before, binding_after, saved)))
                        row['stages'].append({'dry_run': dry, 'reply': reply, 'scene_sha256': digest(target),
                            'clip_unchanged': before == after, 'pose_unchanged': pose_before == pose_after,
                            'binding_unchanged': binding_before == binding_after, 'passed': passed})
                        save()
                        if not passed: raise RuntimeError(f'Unexpected/mutating refusal {rig}/{name}/{dry}')
                    row['passed'] = row['stages'][0]['reply'] == row['stages'][1]['reply']; save()
                    if not row['passed']: raise RuntimeError('Dry and write refusal disagree')
                print('Public typed nonmutating refusals: ' + rig, flush=True)
        report.update(state='complete', passed=len(report['rows']) == 28 and all(r['passed'] for r in report['rows']))
    except Exception as error:
        report.update(state='failed', error=f'{type(error).__name__}: {error}')
        raise
    finally: save()
    return int(not report['passed'])


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for n in ('repo', 'core-root', 'project-root', 'output'): p.add_argument('--' + n, type=Path, required=True)
    p.add_argument('--port', type=int, default=8000); p.add_argument('--ws-port', type=int, default=9500)
    raise SystemExit(asyncio.run(run(p.parse_args())))
