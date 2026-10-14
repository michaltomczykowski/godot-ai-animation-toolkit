"""Capture targeted public turn timing, cycle-alias and setup parity cases."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from review_receipts import write_json


TIMING = (
    ('small', 'left', 30, 1, .6, 30),
    ('signed', 'right', -45, 1, .9, 120),
    ('two-stage', 'left', 135, 2, 1.6, 60),
    ('three-stage', 'right', 270, 3, 2.4, 120),
    ('eight-stage', 'left', 360, 8, 6.4, 120),
    ('sparse-request', 'right', 90, 1, 2.0, 4),
)


def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for n in ('repo', 'core-root', 'project-root', 'output', 'accepted', 'godot', 'leg-matrix'):
        p.add_argument('--' + n, type=Path, required=True)
    p.add_argument('--resume', action='store_true', help='Resume the preserved pre-write source-guard interruption only')
    a = p.parse_args()
    if not a.resume:
        a.output.mkdir(parents=True, exist_ok=False)
    empty = a.output / 'empty-recipes.json'
    report = {'passed': False, 'state': 'running', 'timing': [], 'aliases': [], 'setup': None}
    if a.resume:
        path = a.output / 'contracts.json'
        report = read(path)
        assert report['state'] == 'failed' and report['error'] == 'RuntimeError: capture-right failed; preserve its receipts'
        assert len(report['timing']) == 6 and len(report['aliases']) == 2 and report['setup'] is None
        assert not (a.output / 'setup-references/right').exists(), 'Partial mutation requires a fresh capture attempt'
        failure = a.output / 'contracts-failed-before-resume.json'
        with failure.open('xb') as stream: stream.write(path.read_bytes())
        report.update(state='resuming', previous_failure=str(failure),
                      previous_failure_sha256=hashlib.sha256(failure.read_bytes()).hexdigest(), previous_error=report.pop('error'))
    else:
        write_json(empty, {s: {} for s in ('responsive', 'grounded', 'relaxed', 'heavy', 'sneaky')})
    def save(): write_json(a.output / 'contracts.json', report)
    def run(command, label):
        if a.resume: label += '-resume-r002'
        if (a.output / (label + '.log')).exists(): raise FileExistsError('Preserve existing command log: ' + label)
        with (a.output / (label + '.log')).open('w', encoding='utf-8') as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
        (a.output / (label + '.exit')).write_text(str(result.returncode), encoding='utf-8')
        if result.returncode: raise RuntimeError(label + ' failed; preserve its receipts')
    def capture(output, extra, styles=('responsive',), phase='prototype', modes=('in_place',)):
        command = [sys.executable, str(a.repo / 'tools/mcp_run_quality_review.py'),
            '--repo', str(a.repo), '--core-root', str(a.core_root), '--project-root', str(a.project_root),
            '--output', str(output), '--operation', 'turn_cycle', '--revision', 'turn-contract-' + output.name,
            '--phase', phase, '--styles', *styles, '--root-modes', *modes, *extra]
        if phase == 'prototype': command.extend(['--recipes', str(empty)])
        run(command, 'capture-' + output.name)
    def native(output):
        run([sys.executable, str(a.repo / 'tools/check_turn_review.py'), '--review-root', str(output),
             '--project-root', str(a.project_root), '--godot', str(a.godot)], 'native-' + output.name)
        matrices = list(output.glob('native-*/matrix.json'))
        assert len(matrices) == 1 and read(matrices[0])['passed']
        return str(matrices[0])
    def preserved(entry):
        route = read(Path(entry['route']))
        assert route['passed'] and len(route['cases']) == 4
        for row in route['cases']:
            path = a.project_root / row['scene'].removeprefix('res://')
            assert hashlib.sha256(path.read_bytes()).hexdigest() == row['scene_sha256']
        matrix = read(Path(entry['native']))
        assert matrix['passed'] and matrix['native_runs'] == 24
        if entry.get('parity'): assert read(Path(entry['parity']))['passed']
        assert subprocess.run(['git', 'diff', '--quiet', route['source_head'], 'HEAD', '--',
            'addons/godot_ai_animation', ':(exclude)addons/godot_ai_animation/registry/op_registry.gd'], cwd=a.repo).returncode == 0
    try:
        for label, direction, angle, steps, period, samples in TIMING:
            prior = [r for r in report['timing'] if r['label'] == label]
            if prior:
                assert a.resume and len(prior) == 1
                preserved(prior[0]); continue
            output = a.output / ('timing-' + label)
            capture(output, ['--direction', direction, '--angle', str(angle), '--steps', str(steps),
                             '--duration', str(period), '--samples', str(samples)])
            route_path = output / 'responsive-in-place/route.json'
            route = read(route_path)
            assert all(abs(r['write']['length'] - period) < .000001 and r['write']['samples'] == 120
                       for r in route['cases']), 'Explicit duration must be honored; dense turn sampling must be reported'
            report['timing'].append({'label': label, 'route': str(route_path), 'native': native(output), 'passed': True})
            save(); print('Turn timing: ' + label, flush=True)
        for variant, direction, angle, steps, mode, folder in (
            ('left90', 'left', 90, 1, 'in_place', 'responsive-in-place'),
            ('right180', 'right', 180, 2, 'extracted', 'responsive')):
            prior = [r for r in report['aliases'] if r['variant'] == variant]
            if prior:
                assert a.resume and len(prior) == 1
                preserved(prior[0]); continue
            output = a.output / ('alias-' + variant)
            extra = ['--entry-point', 'cycle', '--direction', direction]
            if angle == 180: extra.extend(['--angle', str(angle), '--steps', str(steps)])
            capture(output, extra, phase='candidate', modes=(mode,))
            route_path = output / folder / 'route.json'
            ref = a.accepted / variant / folder / 'route.json'
            parity = output / 'parity.json'
            run([str(a.godot), '--headless', '--path', str(a.project_root), '--script',
                 'res://tools/check_turn_contract_parity.gd', '--', str(ref), str(route_path), str(parity)],
                'parity-' + output.name)
            assert read(parity)['passed']
            report['aliases'].append({'variant': variant, 'route': str(route_path), 'reference': str(ref),
                                     'parity': str(parity), 'native': native(output), 'passed': True})
            save(); print('Turn cycle alias: ' + variant, flush=True)
        references = a.output / 'setup-references'
        if a.resume:
            for style in ('responsive', 'grounded', 'relaxed', 'heavy', 'sneaky'):
                route = read(references / 'left' / (style + '-in-place') / 'route.json')
                assert route['passed'] and len(route['cases']) == 4
                for row in route['cases']:
                    assert hashlib.sha256((a.project_root / row['scene'].removeprefix('res://')).read_bytes()).hexdigest() == row['scene_sha256']
        else:
            capture(references / 'left', ['--direction', 'left', '--duration', '.7'],
                    styles=('responsive', 'grounded', 'relaxed', 'heavy', 'sneaky'))
        capture(references / 'right', ['--direction', 'right', '--duration', '.9'])
        run([sys.executable, str(a.repo / 'tools/mcp_turn_setup_review.py'),
            '--repo', str(a.repo), '--core-root', str(a.core_root), '--project-root', str(a.project_root),
            '--output', str(a.output / 'setup'), '--references', str(references), '--godot', str(a.godot),
            '--leg-matrix', str(a.leg_matrix)], 'setup')
        report['setup'] = str(a.output / 'setup/setup-matrix.json')
        report.update(state='complete', passed=read(Path(report['setup']))['passed'])
    except Exception as error:
        report.update(state='failed', error=f'{type(error).__name__}: {error}')
        raise
    finally: save()
    return int(not report['passed'])


if __name__ == '__main__': raise SystemExit(main())
