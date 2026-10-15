"""Plan immutable saved FX comparisons. Does not launch Godot or qualify evidence."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
FX = 'shake zoom_punch hit_flash damage_bar typewriter progress_fill counter dialog_pop transition wave spring pendulum path_follow flipbook sprite_frames audio_cue'.split()
TARGETS = dict(zip(FX, [['Camera2D'],['Camera2D'],['Flash'],['DamageBar'],['TypeLabel'],['FillBar'],['ScoreLabel'],['DialogPanel'],['FadeOverlay'],['Card1','Card2','Card3'],['SpringTarget'],['PendulumTarget'],['Drone','PatrolPath'],['Sprite2D'],['SheetSprite'],['CuePlayer']]))
TOOLS = ['tools/plan_saved_effects.py', 'test_project/tools/render_saved_effects.gd', 'tools/check_saved_effects.py']

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def plan(inventory, project, operations=None):
    rows = {row['key']: row for row in inventory['operations']}
    cases = []
    for op in operations or FX:
        key = 'animation_fx.' + op
        row = rows[key]
        candidates = [s for s in row['representative_saved_scenes'] if not s['archive']]
        if not candidates:
            raise ValueError(f'{key}: no loose saved scene')
        redo = Path(candidates[0]['path'])
        if digest(redo) != candidates[0]['sha256']:
            raise ValueError(f'{key}: preserved scene hash changed')
        undo = redo.with_name(redo.name.replace('_redo.tscn', '_undo.tscn'))
        if undo == redo or not undo.is_file():
            raise ValueError(f'{key}: missing independent undo scene')
        scenes = {}
        dependencies = {}
        for state, path in [('undo', undo), ('redo', redo)]:
            scenes[state] = {'path': path.as_posix(), 'sha256': digest(path)}
            for resource in re.findall(r'path="(res://[^"]+)"', path.read_text(encoding='utf-8')):
                dependency = project / resource.removeprefix('res://')
                if not dependency.is_file():
                    raise ValueError(f'{key}: unresolved dependency {resource}')
                dependencies[resource] = digest(dependency)
        cases.append({'id': key + ':new', 'operation': key, 'scenes': scenes,
                      'fixture': 'FxHistory', 'player': 'AnimationPlayer', 'clip': 'generated',
                      'clock': 'native_fixed_fps', 'fps': 60, 'seconds': 12, 'take_seconds': 6, 'targets': TARGETS[op],
                      'dependencies': dependencies, 'historical_source': row['source_reference'],
                      'audio_output_required': op == 'audio_cue',
                      'status': 'planned_not_played'})
    return {'schema_version': 1, 'kind': 'saved_effect_render_plan',
            'qualification': 'pending', 'human_review': 'waived_not_approved',
            'tool_sha256': {p: digest(ROOT / p) for p in TOOLS}, 'cases': cases}

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--inventory', type=Path, default=ROOT/'docs/operation-media-coverage.json')
    p.add_argument('--project', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    result = plan(json.loads(a.inventory.read_text(encoding='utf-8')), a.project)
    # Never overwrite a prior plan/receipt.
    with a.output.open('x', encoding='utf-8') as f:
        json.dump(result, f, indent=2)
        f.write('\n')
    print(f'Planned {len(result["cases"])} saved pairs; no playback performed')
if __name__ == '__main__':
    main()
