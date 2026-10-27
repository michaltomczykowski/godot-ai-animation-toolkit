"""Focused Responsive r002 checks; this is not the complete style acceptance matrix."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from uuid import uuid4
from review_receipts import write_json

def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding='utf-8-sig'))

def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('folder', type=Path)
    for name in ('baseline', 'walk-reference', 'idle-reference', 'project-root', 'godot'):
        p.add_argument('--' + name, type=Path, required=True)
    args = p.parse_args()
    attempt = args.folder / ('native-' + uuid4().hex)
    attempt.mkdir()
    receipt = {'state': 'running', 'passed': False, 'rows': [], 'native_runs': 0,
               'body_runs': 0, 'scope': 'Responsive only; final five-style/sequence gates pending',
               'visual_approval': None}
    write_json(attempt / 'matrix.json', receipt)
    sources = set()
    for op in ('walk_start', 'walk_stop'):
        for label in ('responsive', 'responsive-in-place'):
            paths = [args.folder / op / label / 'route.json', args.folder / op / 'responsive/route.json',
                     args.walk_reference / label / 'route.json', args.idle_reference / label / 'route.json']
            baseline = args.baseline / op / label / 'route.json'
            route, *refs = [read(path) for path in paths]
            old = read(baseline)
            sources.add(route['source_head'])
            assert route['passed'] and route['invocation_kind'] == 'ordinary call'
            assert route['phase'] == 'candidate' and route['operation'] == op
            assert [row['id'] for row in route['cases']] == ['dummy', 'xbot', 'short', 'zup_tall']
            for manifest in (route, old, *refs):
                assert manifest['passed']
                for row in manifest['cases']:
                    scene = args.project_root / row['scene'].removeprefix('res://')
                    assert hashlib.sha256(scene.read_bytes()).hexdigest() == row['scene_sha256'], scene
            for row, prev in zip(route['cases'], old['cases']):
                assert row['history']['passed'] == 1 and row['history']['failed'] == 0
                for field in ('actor_translation_keys', 'declared_contacts', 'reference_window_s', 'speed'):
                    assert row['write'][field] == prev['write'][field], (row['id'], field)
                assert 'transition_torso_head' in row['write']['body_reaction_features']
            name = op + '-' + label
            def execute(script: str, inputs: list[Path], suffix: str) -> dict:
                out = attempt / (name + suffix + '.json')
                cmd = [str(args.godot), '--headless', '--path', str(args.project_root), '--script',
                       'res://tools/' + script, '--', *map(str, inputs), str(out)]
                with (attempt / (name + suffix + '.log')).open('w', encoding='utf-8') as log:
                    result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, timeout=120)
                assert result.returncode == 0, out.with_suffix('.log')
                report = read(out)
                assert report['passed'] and not report['engine_errors'], out
                return {'path': str(out), 'sha256': hashlib.sha256(out.read_bytes()).hexdigest(), 'report': report}
            quality = execute('check_start_stop_quality.gd', paths, '-quality')
            coverage = {(row['id'], row['fps'], row['mixer']) for row in quality['report']['runs']}
            expected = {(rig, fps, mixer) for rig in ('dummy', 'xbot', 'short', 'zup_tall')
                        for fps in (30, 60, 120) for mixer in ('player', 'tree')}
            assert coverage == expected and len(quality['report']['runs']) == 24
            body = execute('check_transition_body_response.gd', [baseline, paths[0]], '-body')
            receipt['rows'].append({'operation': op, 'label': label, 'quality': quality, 'body': body,
                'inputs_sha256': {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in [*paths, baseline]}})
            receipt['native_runs'] += 24
            receipt['body_runs'] += 4
            write_json(attempt / 'matrix.json', receipt)
            print(f'{name}: 24 quality + 4 played body comparisons PASS', flush=True)
    assert len(sources) == 1
    receipt.update(state='complete', passed=True, source_head=sources.pop())
    write_json(attempt / 'matrix.json', receipt)
    print('BODY_PREVIEW_MATRIX=' + str(attempt / 'matrix.json'))

if __name__ == '__main__':
    main()
