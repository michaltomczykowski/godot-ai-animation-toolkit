"""Preserve a turn variant matrix through the ordinary public review client."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
from review_receipts import write_json

def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'core-root', 'project-root', 'output'):
        p.add_argument('--' + name, type=Path, required=True)
    p.add_argument('--phase', choices=('baseline', 'candidate'), required=True)
    p.add_argument('--styles', nargs='+', default=['responsive'])
    p.add_argument('--revision', required=True)
    args = p.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    progress_path = args.output / 'public-progress.json'
    if progress_path.exists(): raise FileExistsError('Preserve the prior public attempt')
    progress = {'state': 'creating', 'completed': [], 'current': None,
                'created_utc': datetime.now(timezone.utc).isoformat()}
    write_json(progress_path, progress)
    for variant in ('left90', 'right90', 'left180', 'right180'):
        progress['current'] = variant
        write_json(progress_path, progress)
        command = [sys.executable, str(args.repo / 'tools/mcp_run_quality_review.py'),
            '--repo', str(args.repo), '--core-root', str(args.core_root),
            '--project-root', str(args.project_root), '--output', str(args.output / variant),
            '--phase', args.phase, '--revision', args.revision + '-' + variant,
            '--operation', 'turn_cycle', '--direction', 'left' if variant.startswith('left') else 'right',
            '--root-modes', 'extracted', 'in_place', '--styles', *args.styles]
        if variant.endswith('180'): command.extend(['--angle', '180', '--steps', '2'])
        with (args.output / (variant + '-public.log')).open('w', encoding='utf-8') as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
        (args.output / (variant + '-public.exit')).write_text(str(result.returncode), encoding='utf-8')
        if result.returncode:
            progress.update(state='failed', error='Public call failed; original receipts preserved: ' + variant)
            write_json(progress_path, progress)
            return 1
        progress['completed'].append(variant)
        write_json(progress_path, progress)
        print('Saved public turn variant: ' + variant, flush=True)
    progress.update(state='complete', current=None)
    write_json(progress_path, progress)
    print('TURN_PUBLIC=' + json.dumps(progress))
    return 0

if __name__ == '__main__': raise SystemExit(main())
