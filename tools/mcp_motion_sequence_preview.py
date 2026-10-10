"""Build a start/walk/stop review clip through the public Godot AI suite."""
import argparse
import asyncio
import json
from pathlib import Path
import shutil
import uuid
from mcp_presets_audit import call
from mcp_rig_modifier_ui_history import connected_editor
from mcp_rig_bake_restoration import ready

async def run(args):
    checkpoint = json.loads(args.checkpoint.read_text(encoding='utf-8'))
    manifest = Path(checkpoint['runtime']['manifest_path'])
    # The checkpoint manifest is also archived before other suites reset it.
    rows = json.loads(manifest.read_text(encoding='utf-8'))['cases']
    selected = {row['id']: row for row in rows}
    row = dict(selected['motion_walk_start_local_60'])
    folder = args.project_root / 'repair_motion_sequence_preview' / uuid.uuid4().hex
    folder.mkdir(parents=True, exist_ok=True)
    source_file = folder / 'start_walk_stop_source.tscn'
    reference_file = folder / 'start_walk_stop_reference.tscn'
    output_file = folder / 'start_walk_stop_output.tscn'
    shutil.copyfile(manifest.parent / row['source'].removeprefix('user://'), source_file)
    async with connected_editor(args) as (client, _):
        opened = await call(client, 'scene_open', {
            'path': 'res://' + source_file.relative_to(args.project_root).as_posix(),
            'force_reload': True})
        if opened.get('error') or opened.get('switched') is not True: raise RuntimeError(opened)
        await ready(client)
        p = dict(row['params'])
        p.update(player_path='/Main/MotionSequenceHistory/Playback/AnimationPlayer',
                 skeleton_path='/Main/MotionSequenceHistory/Character/Skeleton')
        made = []
        for name, op, duration, loop in (
                ('review_start', 'walk_start', 0.35, 'none'),
                ('review_walk', 'walk_cycle', 1.0, 'linear'),
                ('review_stop', 'walk_stop', 0.35, 'none')):
            result = await call(client, 'custom_manage', {'op': 'invoke', 'params': {
                'tool_name': 'animation_motion', 'params': {
                    **p, 'op': op, 'duration': duration, 'animation_name': name,
                    'loop_mode': loop, 'phase': 0.0}}})
            if result.get('error'): raise RuntimeError(result)
            made.append(result)
        saved = await call(client, 'scene_save', {})
        if saved.get('error'): raise RuntimeError(saved)
        shutil.copyfile(source_file, reference_file)
        params = {'op': 'compose', 'player_path': p['player_path'],
            'skeleton_path': p['skeleton_path'], 'animation_name': 'review_sequence',
            'duration': 1.7, 'samples': 60, 'segments': [
                {'start': 0.0, 'duration': 0.35, 'source_animation': 'review_start', 'source_end': 0.35},
                {'start': 0.35, 'duration': 1.0, 'source_animation': 'review_walk', 'source_end': 1.0},
                {'start': 1.35, 'duration': 0.35, 'source_animation': 'review_stop', 'source_end': 0.35}]}
        result = await call(client, 'custom_manage', {'op': 'invoke', 'params': {
            'tool_name': 'animation_sequence', 'params': params}})
        if result.get('error'): raise RuntimeError(result)
        saved = await call(client, 'scene_save', {})
        if saved.get('error'): raise RuntimeError(saved)
        shutil.copyfile(source_file, output_file)
    row.update(id='review_start_walk_stop', group='sequence', variant='start_walk_stop',
               params=params, source='res://' + reference_file.relative_to(args.project_root).as_posix(),
               states={'redo': 'res://' + output_file.relative_to(args.project_root).as_posix()},
               reported=result)
    review = {'cases': [row, selected['motion_jump_local_60'],
        selected['secondary_branches_local_60'], selected['sequence_rooted_local_60']],
        'public_calls': made + [result]}
    args.record.write_text(json.dumps(review, indent=2), encoding='utf-8')
    print('MOTION_SEQUENCE_PREVIEW=' + json.dumps({'cases': 4, 'public_calls': 4, 'record': str(args.record)}))

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--core-root', type=Path, required=True)
    p.add_argument('--project-root', type=Path, required=True)
    p.add_argument('--session-hint', required=True)
    p.add_argument('--port', type=int, required=True)
    p.add_argument('--ws-port', type=int, required=True)
    p.add_argument('--checkpoint', type=Path, required=True)
    p.add_argument('--record', type=Path, required=True)
    asyncio.run(run(p.parse_args()))
if __name__ == '__main__': main()
