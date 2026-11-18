"""Copy immutable preserved graph scenes and emit exact native control manifest."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

OPS = ('state_machine', 'blend_space', 'blend_tree', 'wire', 'locomotion', 'one_shot_layer', 'additive_lean')

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def build(coverage, output):
    output.mkdir(parents=True, exist_ok=False)
    (output/'scenes').mkdir()
    evidence = json.loads(coverage.read_text(encoding='utf-8-sig'))
    rows = []
    for op in OPS:
        record = next(r for r in evidence['operations'] if r['key'] == 'animation_graph.' + op)
        candidate = next(r for r in record['representative_saved_scenes'] if r['name'] == f'graph_history_{op}_new_redo.tscn')
        source = Path(candidate['path'])
        if sha(source) != candidate['sha256']: raise ValueError('Preserved scene hash mismatch: ' + op)
        if op == 'wire': source = source.with_name('graph_history_wire_replace_redo.tscn')
        text = source.read_text(encoding='utf-8-sig')
        if '[ext_resource' in text: raise ValueError('Self-contained scenes required')
        if 'tree_root = SubResource(' not in text: raise ValueError('Saved graph root required')
        target = output/'scenes'/f'{op}.tscn'
        shutil.copyfile(source, target)
        controls = {
            'state_machine': 'parameters/playback: start(idle), travel(walk); original automatic idle->walk transition retained; stop flag does not promise neutral output; fresh saved-instance reset',
            'blend_space': 'parameters/blend_position: 0 -> 1 -> 2 -> 0; saved sync mode retained',
            'locomotion': 'parameters/blend_position: 0 -> 1 -> 2 -> 0; saved sync mode retained',
            'blend_tree': 'parameters/Blend2/blend_amount: 0 -> 1 -> 0',
            'one_shot_layer': 'parameters/OneShot/request: ABORT -> FIRE -> ABORT',
            'additive_lean': 'parameters/Add2/add_amount: 0 -> 1 -> 0',
            'wire': 'original saved idle node; activate exactly this bound tree; no movement authored by wire',
        }
        rows.append(dict(control_contract=controls[op], operation=op, scene=str(target.resolve()), scene_sha256=sha(target),
            preserved_source=str(source), covered_source=candidate, tree='GraphHistory/AnimationTree',
            player='GraphHistory/AnimationPlayer', target='GraphHistory/Character',
            effect='saved_idle_binding_hold' if op == 'wire' else op,
            schedule=[dict(time_s=0, command='neutral'), dict(time_s=.5, command='effect'),
                      dict(time_s=1, command='check_effect'), dict(time_s=1.1, command='faster'),
                      dict(time_s=1.2, command='check_faster'), dict(time_s=1.5, command='neutral'),
                      dict(time_s=2, command='check_reset')]))
    manifest = dict(schema_version=1, cases=rows, fps=60, takes=2, take_duration_s=2,
        fixed_camera=dict(position=[100,-40],zoom=[3,3]), coverage_sha256=sha(coverage), graph_get='not_applicable_read_only',
        display_geometry='Unanimated display-only polygon attached to invisible saved Character target; fixed floor/grid and origin ghost. No target keys, poses or graph nodes synthesized.',
        visual_approval=False)
    with (output/'manifest.json').open('x', encoding='utf-8') as stream: json.dump(manifest, stream, indent=2)
    return manifest

if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--coverage', type=Path, default=Path(__file__).resolve().parents[1]/'docs/operation-media-coverage.json')
    p.add_argument('--output', type=Path, required=True)
    a=p.parse_args()
    build(a.coverage, a.output)
