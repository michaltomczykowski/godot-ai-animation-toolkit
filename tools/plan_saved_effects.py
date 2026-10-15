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
TOOLS = ['tools/plan_saved_effects.py', 'test_project/tools/render_saved_effects.gd', 'tools/check_saved_effects.py',
         'test_project/tools/check_fx_runtime.gd',
         'test_project/tools/check_preset_library_history.gd',
         'test_project/tools/check_edit_history_runtime.gd']

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

PRESETS = 'pulse bounce orbit sweep drift spin float stagger showcase'.split()
EDITS = 'retime reverse mirror trim amplitude resample layer offset loop key_edit overlap retarget ease_range set_interp split_at merge cleanup smooth reduce add_noise'.split()

def plan_remaining(inventory, project):
    rows = {row['key']: row for row in inventory['operations']}
    result = {
        'schema_version': 1, 'kind': 'saved_effect_render_plan',
        'qualification': 'pending', 'human_review': 'waived_not_approved',
        'tool_sha256': {p: digest(ROOT / p) for p in TOOLS}, 'cases': []}
    selectors = [('animation_presets.' + op, op) for op in PRESETS]
    selectors += [('animation_edit.' + op, op) for op in EDITS]
    selectors += [('animation_library.template_apply', 'template_fx'),
                  ('animation_library.template_apply', 'template_preset'),
                  ('animation_library.spec_apply', 'spec_apply')]
    for key, variant in selectors:
        row = rows[key]
        known = [scene for scene in row['representative_saved_scenes'] if not scene['archive']]
        if not known:
            raise ValueError(f'{key}: missing preserved representative')
        redo = Path(known[0]['path'])
        if variant == 'template_preset':
            redo = redo.with_name(redo.name.replace('template_fx', 'template_preset'))
        undo = redo.with_name(redo.name.replace('_redo.tscn', '_undo.tscn'))
        scenes, dependencies = {}, {}
        for state, path in [('undo', undo), ('redo', redo)]:
            observed = digest(path)
            prior = next((scene for scene in known if Path(scene['path']) == path), None)
            if prior and observed != prior['sha256']:
                raise ValueError(f'{key}: preserved scene hash changed')
            scenes[state] = {'path': path.as_posix(), 'sha256': observed}
            for resource in re.findall(r'path="(res://[^\"]+)"', path.read_text(encoding='utf-8')):
                dependency = project / resource.removeprefix('res://')
                if not dependency.is_file():
                    raise ValueError(f'{key}: unresolved dependency {resource}')
                dependencies[resource] = digest(dependency)
        is_edit = key.startswith('animation_edit.')
        targets = ['Character', 'OtherCharacter'] if is_edit else (
            ['Target3D'] if variant in ['pulse','orbit','drift','spin','float'] else ['Widget','OtherWidget'])
        clip = ('idle' if variant == 'cleanup' else 'jump' if variant == 'smooth' else
                'walk_run' if variant == 'merge' else 'walk') if is_edit else 'generated'
        undo_clip = 'walk' if variant == 'merge' else clip
        playbacks = [{'player':'AnimationPlayer', 'undo_clip':undo_clip, 'redo_clip':clip}]
        if variant == 'showcase':
            pairs = [('Bounce','bounce','BounceButton'),('Orbit','orbit','OrbitDot'),
                     ('Sweep','sweep','SweepPivot'),('Drift','drift','DriftLine'),
                     ('Pulse','pulse','PulseLabel'),('Float','float','World3D/FloatCube'),
                     ('Spin','spin','World3D/SpinCube')]
            targets = ['ReviewShowcase/' + target for _, _, target in pairs]
            playbacks = [{'player':'ReviewShowcase/Anim'+player, 'undo_clip':'', 'redo_clip':name}
                         for player, name, _ in pairs]
        case = {'id':key+':'+variant, 'operation':key, 'variant':variant,
                'scenes':scenes, 'fixture':'EditHistory' if is_edit else 'PresetHistory',
                'player':'AnimationPlayer', 'clip':clip, 'playbacks':playbacks,
                'targets':targets, 'clock':'native_fixed_fps', 'fps':60,
                'seconds':12, 'take_seconds':6, 'dependencies':dependencies,
                'historical_source':row['source_reference'], 'audio_output_required':False,
                'require_progression': variant != 'cleanup',
                'require_visible_difference': variant not in ['cleanup','resample','reduce'],
                'display_mode':'showcase' if variant == 'showcase' else 'isolated_targets',
                'status':'planned_not_played'}
        result['cases'].append(case)
        if variant == 'split_at':
            head = dict(case, id=key+':split_head', variant='split_head',
                        playbacks=[{'player':'AnimationPlayer','undo_clip':'walk','redo_clip':'walk_head'}])
            result['cases'].append(head)
    return result

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--inventory', type=Path, default=ROOT/'docs/operation-media-coverage.json')
    p.add_argument('--project', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--family', choices=['fx','remaining','all'], default='fx')
    a = p.parse_args()
    inventory = json.loads(a.inventory.read_text(encoding='utf-8'))
    result = plan(inventory, a.project) if a.family == 'fx' else plan_remaining(inventory, a.project)
    if a.family == 'all':
        result['cases'] = plan(inventory, a.project)['cases'] + result['cases']
    # Never overwrite a prior plan/receipt.
    with a.output.open('x', encoding='utf-8') as f:
        json.dump(result, f, indent=2)
        f.write('\n')
    print(f'Planned {len(result["cases"])} saved pairs; no playback performed')
if __name__ == '__main__':
    main()
