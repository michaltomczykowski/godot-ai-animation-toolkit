"""Require all native capture frames and make local review video/contact sheets."""
import argparse
import json
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--frames', type=Path, required=True)
    p.add_argument('--manifest', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--ffmpeg', required=True)
    args = p.parse_args()
    report = json.loads((args.frames / 'render.json').read_text(encoding='utf-8'))
    manifest = json.loads(args.manifest.read_text(encoding='utf-8'))
    if report.get('cases') != 4 or report.get('errors') != [] or sum(report['counts']) != report['frames']:
        raise RuntimeError('Incomplete/error capture: ' + repr(report))
    files = [args.frames / f'{case:02}_{frame:03}.png'
             for case, count in enumerate(report['counts']) for frame in range(count)]
    if len(files) != report['frames'] or any(not file.is_file() for file in files):
        raise RuntimeError('Required frames missing')
    args.output.mkdir(parents=True, exist_ok=True)
    concat = args.output / 'frames.ffconcat'
    concat.write_text('ffconcat version 1.0\n' + ''.join(
        "file '" + str(file.resolve()).replace('\\', '/').replace("'", "'\\''")
        + "'\nduration 0.016666666666666667\n" for file in files), encoding='utf-8')
    subprocess.run([args.ffmpeg, '-y', '-hide_banner', '-loglevel', 'error',
        '-f', 'concat', '-safe', '0', '-i', str(concat), '-vf', 'fps=60',
        '-c:v', 'libx264', '-crf', '18', '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
        str(args.output / 'motion_sequence_history.mp4')], check=True)
    overview = Image.new('RGB', (1280, 4 * 440), '#101927')
    for case, count in enumerate(report['counts']):
        row = manifest['cases'][case]
        sheet = Image.new('RGB', (1280, 3 * 400), '#101927')
        for cell in range(6):
            frame = round(cell * (count - 1) / 5)
            with Image.open(args.frames / f'{case:02}_{frame:03}.png') as im:
                thumbnail = im.resize((640, 360))
                sheet.paste(thumbnail, ((cell % 2) * 640, (cell // 2) * 400))
                ImageDraw.Draw(sheet).text(((cell % 2) * 640 + 8, (cell // 2) * 400 + 370),
                                          f'frame {frame} / {frame / 60:.3f}s', fill='white')
                if cell in (0, 3): overview.paste(thumbnail, ((cell // 3) * 640, case * 440))
        ImageDraw.Draw(overview).text((8, case * 440 + 375), row['id'] + ' | start / recovery; paired native playback', fill='white')
        sheet.save(args.output / (row['id'] + '_contact_sheet.png'))
    overview.save(args.output / 'motion_sequence_history_contact_sheet.png')
    report.update(comparison='native clip/reference playback versus saved Godot AI output',
                  scope='technical sequence/spring/history fidelity; full humanoid/action quality remains open')
    (args.output / 'media.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report))
if __name__ == '__main__': main()
