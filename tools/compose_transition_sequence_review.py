"""Verify and encode continuous dual-camera saved-sequence playback."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
import subprocess
from PIL import Image
from compose_character_quality import digest

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('folder', type=Path); p.add_argument('--ffmpeg', type=Path, required=True)
    p.add_argument('--mode', choices=('clean', 'diagnostic'), required=True)
    a = p.parse_args(); frames_dir = a.folder / (a.mode + '_frames')
    render = json.loads((frames_dir / 'render.json').read_text())
    assert render['operation'] == 'animation_sequence' and not render['errors']
    assert render['fps'] == 60 and render['size'] == [1920,1080]
    assert [r['id'] for r in render['cases']] == ['dummy', 'xbot', 'short', 'zup_tall']
    assert all(r['camera_views'] == ['FRONT', 'SIDE'] and r['frames'] >= 1200
        and r['takes'] == 2 and r['reset_between_takes'] is True for r in render['cases'])
    count = sum(r['frames'] for r in render['cases']); assert count == render['frames']
    frames = sorted(frames_dir.glob('[0-9]*.png'))
    assert [f.name for f in frames] == [f'{i:06d}.png' for i in range(count)]
    for frame in frames:
        with Image.open(frame) as img: assert img.size == (1920,1080)
    movie = a.folder / (render['revision'] + '-' + a.mode + '.mp4')
    subprocess.run([str(a.ffmpeg),'-hide_banner','-loglevel','error','-y','-framerate','60','-i',str(frames_dir/'%06d.png'),
        '-frames:v',str(count),'-an','-c:v','libx264','-threads','2','-preset','medium','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(movie)],check=True)
    decode = subprocess.run([str(a.ffmpeg),'-hide_banner','-nostats','-i',str(movie),'-map','0:v:0','-an','-f','null','-','-progress','pipe:1'],capture_output=True,text=True,check=True)
    assert int(re.findall(r'^frame=(\d+)$',decode.stdout,re.M)[-1]) == count
    duration = int(re.findall(r'^out_time_us=(\d+)$',decode.stdout,re.M)[-1])/1000000
    assert abs(duration-count/60) < .017
    assert any('h264' in line and '1920x1080' in line and '60 fps' in line for line in decode.stderr.splitlines())
    path = a.folder/'media.json'; media = json.loads(path.read_text()) if path.exists() else {'videos': {}}
    media['videos'][a.mode] = {'path':str(movie),'sha256':digest(movie),'bytes':movie.stat().st_size,'decoded_frames':count,'decoded_duration_s':duration,'render':render}
    path.write_text(json.dumps(media,indent=2)+'\n',encoding='utf-8')
    print(f'Verified continuous sequence {a.mode}: {count} frames / {duration:.3f}s / 1080p60',flush=True)
if __name__ == '__main__': main()
