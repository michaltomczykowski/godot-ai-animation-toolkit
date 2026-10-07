"""Compose actual Godot playback frames into local review media."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import subprocess
from PIL import Image

CASES = ('ik', 'look_at', 'twist', 'spring', 'retarget', 'ik_look_twist', 'ik_spring_half')

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--frames', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--ffmpeg', required=True)
    args = parser.parse_args()
    required = [args.frames / f'{case:02}_{frame:03}.png' for case in range(7) for frame in range(120)]
    missing = [str(path) for path in required if not path.is_file()]
    if missing: raise RuntimeError('Missing rendered frames: ' + ', '.join(missing[:5]))
    args.output.mkdir(parents=True, exist_ok=True)
    concat = args.output / 'frames.ffconcat'
    concat.write_text('ffconcat version 1.0\n' + ''.join(
        "file '" + str(path.resolve()).replace('\\', '/').replace("'", "'\\''") + "'\nduration 0.03333333333333333\n"
        for path in required), encoding='utf-8')
    subprocess.run([args.ffmpeg, '-y', '-hide_banner', '-loglevel', 'error', '-f', 'concat', '-safe', '0',
        '-i', str(concat), '-vf', 'fps=30', '-c:v', 'libx264', '-crf', '20', '-pix_fmt', 'yuv420p',
        '-movflags', '+faststart', str(args.output / 'modifier_history.mp4')], check=True)
    overview = Image.new('RGB', (1920, 7 * 360), '#101927')
    for index, case in enumerate(CASES):
        sheet = Image.new('RGB', (1280, 1440), '#101927')
        for cell, frame in enumerate((15, 45, 75, 105)):
            with Image.open(args.frames / f'{index:02}_{frame:03}.png') as image:
                resized = image.convert('RGB').resize((640, 360), Image.Resampling.LANCZOS)
                sheet.paste(resized, ((cell % 2) * 640, (cell // 2) * 720))
                # Keep a full-size output view beneath each paired frame for
                # bone/axis and short-chain collision inspection.
                crop = image.crop((640, 100, 1280, 710)).resize((640, 360), Image.Resampling.LANCZOS)
                sheet.paste(crop, ((cell % 2) * 640, (cell // 2) * 720 + 360))
                if cell in (0, 2, 3):
                    overview.paste(resized, ({0: 0, 2: 640, 3: 1280}[cell], index * 360))
        sheet.save(args.output / f'{case}_contact_sheet.png')
    overview.save(args.output / 'modifier_history_overview.png')
    report = {'frames': len(required), 'fps': 30, 'seconds': 28, 'cases': list(CASES),
        'comparison': 'inactive authored input vs configured output; not prior-addon footage',
        'output': str(args.output.resolve())}
    (args.output / 'media.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report))

if __name__ == '__main__': main()
