"""Compose native source/bake footage and strict fixed-camera contact sheets."""
import argparse
import json
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw

IDS = ('graph_state_60', 'graph_oneshot_60', 'modifier_spring_1_60',
       'modifier_ordered_spring_look_1_60', 'modifier_retarget_1_60',
       'root_preserve_true_true_true_60', 'root_pose_only_true_true_true_60',
       'root_apply_true_true_true_60')

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--frames', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--ffmpeg', required=True)
    args = p.parse_args()
    files = [args.frames / f'{case:02}_{frame:03}.png' for case in range(8) for frame in range(61)]
    missing = [str(f) for f in files if not f.is_file()]
    if missing: raise RuntimeError('Missing frames: ' + ', '.join(missing[:5]))
    args.output.mkdir(parents=True, exist_ok=True)
    concat = args.output / 'frames.ffconcat'
    concat.write_text('ffconcat version 1.0\n' + ''.join(
        "file '" + str(f.resolve()).replace('\\', '/').replace("'", "'\\''")
        + "'\nduration 0.03333333333333333\n" for f in files), encoding='utf-8')
    subprocess.run([args.ffmpeg, '-y', '-hide_banner', '-loglevel', 'error', '-f', 'concat', '-safe', '0',
        '-i', str(concat), '-vf', 'fps=30', '-c:v', 'libx264', '-crf', '18', '-pix_fmt', 'yuv420p',
        '-movflags', '+faststart', str(args.output / 'bake_restoration.mp4')], check=True)
    overview = Image.new('RGB', (1280, 8 * 400), '#101927')
    for case, label in enumerate(IDS):
        sheet = Image.new('RGB', (1280, 3 * 720), '#101927')
        for cell, frame in enumerate((0, 4, 8, 12, 24, 36)):
            with Image.open(args.frames / f'{case:02}_{frame:03}.png') as im:
                sheet.paste(im.resize((640, 360)), ((cell % 2) * 640, (cell // 2) * 720))
                sheet.paste(im.crop((0, 100, 1280, 710)).resize((640, 360)), ((cell % 2) * 640, (cell // 2) * 720 + 360))
                if cell in (0, 5): overview.paste(im.resize((640, 360)), ((0 if cell == 0 else 640), case * 400))
        ImageDraw.Draw(overview).text((8, case * 400 + 370), label + ' | start / end; both paired source/bake', fill='white')
        sheet.save(args.output / (label + '_contact_sheet.png'))
    overview.save(args.output / 'bake_restoration_contact_sheet.png')
    report = {'cases': IDS, 'frames': len(files), 'render_fps': 60, 'review_fps': 30,
              'comparison': 'native source replay versus saved public Godot AI bake',
              'scope': 'technical bake fidelity; broader character/action quality remains separate'}
    (args.output / 'media.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report))
if __name__ == '__main__': main()
