"""Check narrow native FX observations; does not certify visual or audio quality."""
from __future__ import annotations
import argparse
import json
from pathlib import Path

# Independent history-case inputs, not values extracted from output animation keys.
ENDPOINTS = {'damage_bar': ('DamageBar', 'value', 30),
             'progress_fill': ('FillBar', 'value', 100),
             'counter': ('ScoreLabel', 'text', 100)}
TARGETS = {'shake':'Camera2D','zoom_punch':'Camera2D','hit_flash':'Flash',
           'damage_bar':'DamageBar','typewriter':'TypeLabel','progress_fill':'FillBar',
           'counter':'ScoreLabel','dialog_pop':'DialogPanel','transition':'FadeOverlay',
           'wave':'Card1','spring':'SpringTarget','pendulum':'PendulumTarget',
           'path_follow':'Drone','flipbook':'Sprite2D','sprite_frames':'SheetSprite',
           'audio_cue':'CuePlayer'}

def check(case, report):
    failures = []
    if report.get('operation') != case['operation'] or report.get('case_id') != case['id']:
        failures.append('operation/case mismatch')
    if report.get('scenes') != case['scenes'] or report.get('dependencies_verified') != case['dependencies']:
        failures.append('scene/dependency identity mismatch')
    op = case['operation'].split('.')[-1]
    target = TARGETS[op]
    samples = report.get('samples', [])
    expected_frames = case['fps'] * case['seconds']
    if len(samples) < expected_frames - 2 or report.get('frames', 0) < expected_frames - 2:
        failures.append('incomplete fixed-FPS temporal samples')
    if report.get('max_delta_error', 1) > 0.00001:
        failures.append('native clock was not fixed at requested FPS')
    if any(s.get('frame') != i + 1 for i, s in enumerate(samples)):
        failures.append('missing/duplicate/out-of-order frame sample')
    if any(abs(s.get('time', 0) - (i + 1) / case['fps']) > 0.002 for i, s in enumerate(samples)):
        failures.append('sample clock does not match native fixed FPS')
    checks = {}
    for take in (1, 2):
        rows = [s for s in samples if s.get('take') == take]
        if len(rows) < case['fps'] * case['take_seconds'] - 2:
            failures.append(f'take {take}: incomplete')
            continue
        if any(len(r.get('states', [])) != 2 for r in rows):
            failures.append(f'take {take}: missing independently played clone')
            continue
        redo = [r['states'][1].get(target, {}) for r in rows]
        undo = [r['states'][0].get(target, {}) for r in rows]
        if not all(redo) or not all(undo):
            failures.append(f'take {take}: missing target state')
            continue
        changed = len({json.dumps(s, sort_keys=True) for s in redo}) > 1
        different = any(a != b for a, b in zip(redo, undo))
        if not changed:
            failures.append(f'take {take}: intended target never progressed')
        if not different:
            failures.append(f'take {take}: no changed effect relative to undo')
        checks[f'take_{take}_target_progression'] = 'pass' if changed else 'fail'
        checks[f'take_{take}_changed_effect'] = 'pass' if different else 'fail'
        if op in ENDPOINTS:
            node, prop, expected = ENDPOINTS[op]
            try:
                actual = float(rows[-1]['states'][1][node][prop])
                okay = abs(actual - expected) < 0.05
            except (ValueError, KeyError, TypeError):
                okay = False
            checks[f'take_{take}_independent_endpoint'] = 'pass' if okay else 'fail'
            if not okay:
                failures.append(f'take {take}: independent endpoint expected {expected}')
        if op in ('flipbook', 'sprite_frames'):
            frames = {s.get('frame') for s in redo}
            okay = {'0', '1', '2', '3'} <= frames
            checks[f'take_{take}_four_native_cells'] = 'pass' if okay else 'fail'
            if not okay:
                failures.append(f'take {take}: did not observe all four native cells')
    return {'schema_version': 1, 'operation': case['operation'], 'case_id': case['id'],
            'checks': checks, 'failures': failures, 'native_observation_pass': not failures,
            'semantic_endpoints': 'checked' if op in ENDPOINTS else 'not_comprehensive',
            'visual_assessment': 'pending', 'audio_output': 'pending' if op == 'audio_cue' else 'not_applicable',
            'qualification': 'pending', 'human_review': 'waived_not_approved'}

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--plan', type=Path, required=True)
    p.add_argument('--case', type=int, required=True)
    p.add_argument('--observations', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    case = json.loads(a.plan.read_text(encoding='utf-8'))['cases'][a.case]
    report = check(case, json.loads(a.observations.read_text(encoding='utf-8')))
    with a.output.open('x', encoding='utf-8') as f:
        json.dump(report, f, indent=2)
    print(json.dumps(report))
    return 0 if report['native_observation_pass'] else 1
if __name__ == '__main__':
    raise SystemExit(main())
