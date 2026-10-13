"""Measure preserved public turn scenes; retain failed baselines and raw logs."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
from uuid import uuid4
from review_receipts import write_json

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--review-root', type=Path, required=True)
    parser.add_argument('--project-root', type=Path, required=True)
    parser.add_argument('--godot', type=Path, required=True)
    args = parser.parse_args()
    routes = sorted(args.review_root.glob('*/**/route.json'))
    if not routes:
        raise ValueError('No preserved public route receipts')
    attempt = args.review_root / ('native-' + uuid4().hex)
    attempt.mkdir()
    summary = {'state': 'measuring', 'created_utc': datetime.now(timezone.utc).isoformat(),
               'rows': [], 'native_runs': 0, 'failures': [], 'passed': False}
    sources = set()
    write_json(attempt / 'matrix.json', summary)
    for route_path in routes:
        route = json.loads(route_path.read_text(encoding='utf-8-sig'))
        if not route['passed'] or len(route['cases']) != 4:
            raise ValueError('Invalid public route: ' + str(route_path))
        sources.add(route['source_head'])
        for case in route['cases']:
            path = args.project_root / case['scene'].removeprefix('res://')
            if hashlib.sha256(path.read_bytes()).hexdigest() != case['scene_sha256']:
                raise ValueError('Changed native scene: ' + str(path))
        name = '-'.join(route_path.relative_to(args.review_root).parts[:-1])
        report_path = attempt / (name + '.json')
        result = subprocess.run([str(args.godot), '--headless', '--path', str(args.project_root),
            '--script', 'res://tools/check_turn_quality.gd', '--', str(route_path), str(report_path)],
            capture_output=True, text=True)
        (attempt / (name + '.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
        (attempt / (name + '.exit')).write_text(str(result.returncode), encoding='utf-8')
        report = json.loads(report_path.read_text(encoding='utf-8')) if report_path.exists() else {}
        complete = len(report.get('runs', [])) == 24
        passed = result.returncode == 0 and complete and report.get('passed') is True
        row = {'name': name, 'route': str(route_path), 'report': str(report_path),
               'exit_code': result.returncode, 'complete': complete, 'passed': passed,
               'runs': len(report.get('runs', [])), 'engine_errors': report.get('engine_errors', []),
               'failures': sorted({reason for run in report.get('runs', []) for reason in run.get('failures', [])})}
        if not complete: row['failures'].append('missing or incomplete native report')
        summary['rows'].append(row)
        summary['native_runs'] += row['runs']
        if not passed: summary['failures'].append(name)
        write_json(attempt / 'matrix.json', summary)
        print(json.dumps({'name': name, 'passed': passed, 'runs': row['runs'], 'failures': row['failures']}), flush=True)
    summary.update(state='complete', source_head=next(iter(sources)) if len(sources) == 1 else None,
                   passed=not summary['failures'] and len(sources) == 1)
    write_json(attempt / 'matrix.json', summary)
    print('TURN_MATRIX=' + json.dumps({'report': str(attempt / 'matrix.json'),
                                     'runs': summary['native_runs'], 'passed': summary['passed']}))
    return int(not summary['passed'])

if __name__ == '__main__':
    raise SystemExit(main())
