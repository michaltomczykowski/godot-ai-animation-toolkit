"""Extract the planned frames from the encoded comparison, without seeking."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess

from audit_candidate_case_coverage import load, sha


def select_expression(frames):
    # Balanced nesting prevents FFmpeg's expression parser from exhausting
    # its stack when a review needs many nonuniform frame indices.
    if len(frames) == 1:
        return f'eq(n\\,{frames[0]})'
    mid = len(frames) // 2
    return '(' + select_expression(frames[:mid]) + '+' + select_expression(frames[mid:]) + ')'


def extract(plan_path, output, ffmpeg):
    from PIL import Image, ImageDraw

    plan = load(plan_path)
    if plan.get('kind') != 'saved_effect_review_plan' or not plan.get('cases'):
        raise ValueError('Expected a completed capture review plan')
    output.mkdir(parents=True, exist_ok=False)
    records = []
    for index, case in enumerate(plan['cases']):
        frames = [r['frame'] for r in case['samples']]
        if not frames or any(type(n) is not int or n < 0 for n in frames) or frames != sorted(set(frames)):
            raise ValueError('Expected ordered unique nonnegative video indices')
        video = Path(case['video'])
        if sha(video) != case['video_sha256']:
            raise ValueError('Encoded video changed after the review plan was prepared')
        folder = output / f'case{index:02d}'
        folder.mkdir()
        command = [str(ffmpeg), '-hide_banner', '-loglevel', 'error', '-threads', '1',
                   '-filter_threads', '1', '-i', str(video), '-vf', 'select='+select_expression(frames),
                   '-fps_mode', 'passthrough', '-threads', '1', str(folder / '%04d.png')]
        with (folder / 'extract.log').open('xb') as log:
            subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=90)
        paths = sorted(folder.glob('*.png'))
        if [p.name for p in paths] != [f'{n:04d}.png' for n in range(1, len(frames) + 1)]:
            raise ValueError('Decoded frame set differs from requested ordering')
        observations = []
        for sample, path in zip(case['samples'], paths):
            with Image.open(path) as image:
                if image.format != 'PNG' or image.size != (1400, 800):
                    raise ValueError('Decoded observation size or type changed')
                image.load()
            observations.append(dict(sample, image=path.name, sha256=sha(path)))
        if sha(video) != case['video_sha256']:
            raise ValueError('Encoded video changed during extraction')

        def sheet(rows, name):
            grid = Image.new('RGB', (1400, ((len(rows)+1)//2)*420), '#151a20')
            label = ImageDraw.Draw(grid)
            for i, row in enumerate(rows):
                x, y = i % 2 * 700, i // 2 * 420
                with Image.open(folder / row['image']) as image:
                    grid.paste(image.convert('RGB').resize((700, 400)), (x, y+20))
                label.text((x+6,y+2), f"{case['operation']} | take {row['take']} | frame {row['frame']}",
                           fill='white')
            path = folder / name
            grid.save(path)
            return {'image':name, 'sha256':sha(path), 'frames':[r['frame'] for r in rows]}

        sheets = [sheet(observations[start:start+8], f'sheet-{start//8:03d}.png')
                  for start in range(0, len(observations), 8)]
        picks = []
        for take in (1, 2):
            rows = [r for r in observations if r['take'] == take]
            if not rows:
                raise ValueError('Decoded observations lack one of the two takes')
            first = rows[0]['frame']
            for offset in (0, round(case['fps']*.1), round(case['fps']*.35),
                           round(case['fps']*.7), rows[-1]['frame'] - first):
                row = min(rows, key=lambda r: abs(r['frame']-(first+offset)))
                if row not in picks:
                    picks.append(row)
        overview = sheet(picks, 'overview.png')
        records.append({'case_id':case['case_id'], 'video_sha256':case['video_sha256'],
                        'receipt_sha256':case['receipt_sha256'], 'directory':folder.name, 'command':command,
                        'observations':observations, 'sheets':sheets, 'overview':overview,
                        'take_reset_order':case.get('take_reset_order'), 'visual_status':'pending_review'})
    result = {'kind':'saved_effect_decoded_review', 'review_plan_sha256':sha(plan_path), 'cases':records,
              'scope':'Ordered frame extraction from actual videos. No visual assessment is implied.'}
    with (output / 'manifest.json').open('x', encoding='utf-8') as stream:
        json.dump(result, stream, indent=2)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('plan', 'output', 'ffmpeg'):
        parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    result = extract(args.plan, args.output, args.ffmpeg)
    print(f"DECODED_REVIEW cases={len(result['cases'])} samples={sum(len(c['observations']) for c in result['cases'])}")


if __name__ == '__main__':
    main()
