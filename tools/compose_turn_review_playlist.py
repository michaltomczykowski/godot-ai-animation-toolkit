"""Join the 16 verified new clean turn movies into one convenient review MP4.

Original native movies remain intact. This is a labeled sequence of cases,
not a claim that separate actions form one continuous character animation.
"""
import argparse
from datetime import datetime, timezone
import re
import subprocess
from archive_turn_review import read, digest, require
from pathlib import Path
from review_receipts import write_json


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--delivery', type=Path, required=True)
    p.add_argument('--ffmpeg', type=Path, required=True)
    a = p.parse_args()
    delivery = read(a.delivery / 'review-delivery.json')
    movies = [v for v in delivery['videos'] if v['kind'] == 'new_style' and v['mode'] == 'clean']
    expected = [(s, v) for s in ('grounded', 'relaxed', 'heavy', 'sneaky')
                for v in ('left90', 'right90', 'left180', 'right180')]
    require(len(movies) == 16 and {(v['style'], v['variant']) for v in movies} == set(expected),
            'Require all sixteen new clean cases')
    movies = [next(v for v in movies if (v['style'], v['variant']) == case) for case in expected]
    target = a.delivery / 'review-videos/PLAY-ALL-new-turn-styles.mp4'
    require(not target.exists(), 'Preserve the previous compilation')
    listing = a.delivery / 'playlist-concat-input.txt'
    require(not listing.exists(), 'Preserve the previous compilation inputs')
    lines = []
    for movie in movies:
        path = Path(movie['path'])
        require(digest(path) == movie['sha256'] and movie['frames'] == 1440 and movie['duration_s'] == 24,
                'Source movie changed')
        require("'" not in path.as_posix(), 'Use an explicitly escaped concat file path')
        lines.append("file '" + path.as_posix() + "'\n")
    listing.write_text(''.join(lines), encoding='utf-8')
    command = [str(a.ffmpeg), '-hide_banner', '-loglevel', 'error', '-f', 'concat', '-safe', '0',
               '-i', str(listing), '-c', 'copy', '-movflags', '+faststart', str(target)]
    subprocess.run(command, check=True)
    decoded = subprocess.run([str(a.ffmpeg), '-hide_banner', '-nostats', '-i', str(target),
        '-map', '0:v:0', '-an', '-f', 'null', '-', '-progress', 'pipe:1'],
        check=True, capture_output=True, text=True)
    (a.delivery / 'playlist-decode.log').write_text(decoded.stderr + decoded.stdout, encoding='utf-8')
    frames = re.findall(r'^frame=(\d+)$', decoded.stdout, re.M)
    times = re.findall(r'^out_time_us=(\d+)$', decoded.stdout, re.M)
    require(frames and int(frames[-1]) == 23040 and times and abs(int(times[-1]) - 384_000_000) <= 17_000,
            'Review compilation decode count/duration differs')
    require(any('h264' in line and '1920x1080' in line and '60 fps' in line
                for line in decoded.stderr.splitlines()), 'Compilation must remain native 1080p60 H.264')
    result = {'passed': True, 'created_utc': datetime.now(timezone.utc).isoformat(), 'path': str(target),
        'sha256': digest(target), 'decoded_frames': 23040, 'duration_s': 384,
        'source_movies': [{**v, 'start_s': i * 24} for i, v in enumerate(movies)],
        'concat_command': command, 'input_list_sha256': digest(listing),
        'note': 'Lossless stream-copy compilation of sixteen labeled native cases; original individual files are preserved.',
        'visual_approval': None, 'release_ready': False}
    write_json(a.delivery / 'review-playlist.json', result)
    instructions = a.delivery / 'review-videos/START-HERE.txt'
    original = instructions.read_text(encoding='utf-8')
    instructions.write_text('Start with PLAY-ALL-new-turn-styles.mp4 (6 minutes 24 seconds).\n'
        'Four styles, each left90/right90/left180/right180, 24 seconds per labeled case.\n'
        'This compilation preserves the original movie streams; individual files remain available below.\n\n'
        + original, encoding='utf-8')
    print('Review playlist verified: 16 native cases /23040 decoded frames /6 minutes 24 seconds.')


if __name__ == '__main__': main()
