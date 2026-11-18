"""Prove independent turn checks reject specific corrupt played outputs."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
from review_receipts import write_json

def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('route', 'project-root', 'godot', 'output'):
        p.add_argument('--' + name, type=Path, required=True)
    args = p.parse_args()
    if args.output.exists(): raise FileExistsError('Preserve previous control evidence')
    args.output.mkdir(parents=True)
    route = json.loads(args.route.read_text(encoding='utf-8-sig'))
    original = {case['scene']: hashlib.sha256((args.project_root / case['scene'].removeprefix('res://')).read_bytes()).hexdigest() for case in route['cases']}
    summary = {'state': 'checking', 'source_head': route['source_head'],
        'created_utc': datetime.now(timezone.utc).isoformat(), 'rows': [], 'passed': False,
        'checker_sha256': hashlib.sha256((args.project_root / 'tools/check_turn_quality.gd').read_bytes()).hexdigest()}
    controls = {'positive': None, 'missing_contacts': 'missing declared contact windows',
        'inert': 'inert playback', 'wrong_heading': 'wrong settled hip heading',
        'stance_slide': 'r: stance slide', 'double_actor_yaw': 'unexpected actor transform'}
    for control, reason in controls.items():
        report_path = args.output / (control + '.json')
        command = [str(args.godot), '--headless', '--path', str(args.project_root),
                   '--script', 'res://tools/check_turn_quality.gd', '--', str(args.route), str(report_path)]
        if reason: command.append(control)
        result = subprocess.run(command, capture_output=True, text=True)
        (args.output / (control + '.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
        report = json.loads(report_path.read_text(encoding='utf-8')) if report_path.exists() else {}
        runs = report.get('runs', [])
        detected = len(runs) == 24 and not report.get('engine_errors') and all(reason in run['failures'] for run in runs) if reason else False
        passed = detected and result.returncode == 1 and report.get('passed') is False if reason else len(runs) == 24 and result.returncode == 0 and report.get('passed') is True and not report.get('engine_errors')
        summary['rows'].append({'control': control, 'expected_failure': reason,
            'exit_code': result.returncode, 'runs': len(runs), 'passed': passed,
            'report': str(report_path), 'engine_errors': report.get('engine_errors', [])})
        write_json(args.output / 'summary.json', summary)
        print(json.dumps(summary['rows'][-1]), flush=True)
    unchanged = all(hashlib.sha256((args.project_root / scene.removeprefix('res://')).read_bytes()).hexdigest() == digest for scene, digest in original.items())
    summary.update(state='complete', scenes_unchanged=unchanged,
        positive_runs=24, negative_runs=120,
        passed=unchanged and all(row['passed'] for row in summary['rows']))
    write_json(args.output / 'summary.json', summary)
    return int(not summary['passed'])

if __name__ == '__main__': raise SystemExit(main())
