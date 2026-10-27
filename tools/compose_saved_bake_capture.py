"""Compose every admitted bake sample as paired technical source/redo video."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

from PIL import Image, ImageDraw, ImageFont
from check_saved_bake_capture import compare, times
from run_saved_bake_capture import read, require, same_traces, validate_images
from prepare_saved_bake_capture import sha
from review_receipts import write_json


def compose(capture, output, ffmpeg):
    require(not output.exists(), 'preserve previous composition')
    execution = read(capture/'execution.json')
    require(execution.get('passed') is True and execution.get('stage') == 'complete' and execution.get('native_trace_exact') is True, 'completed exact native/render capture required')
    binding = read(capture/'capture-binding.json')
    require(sha(capture/'capture-binding.json') == execution['binding_sha256'] and sha(binding['original_native']) == binding['native_sha256'], 'capture/native binding changed')
    manifest = read(capture/'project/bake-manifest.json')
    rendered = read(capture/'render-native.json')
    admission = compare(rendered, manifest, binding['manifest_sha256'])
    require(admission['parity_pass'] and admission['fresh_take_pass'], 'parity/fresh-take mismatch')
    same_traces(read(Path(binding['original_native'])), rendered)
    images = validate_images(read(capture/'samples/render.json'), manifest, capture/'samples', execution['binding_sha256'])
    index = {(r['id'], r['side'], r['take'], r['sample']):r for r in images}
    output.mkdir(parents=True)
    frames = output/'frames'; frames.mkdir()
    pairs = output/'pairs'; pairs.mkdir()
    try:
        font = ImageFont.truetype('C:/Windows/Fonts/consola.ttf', 19)
    except OSError:
        font = ImageFont.load_default(size=19)
    schedule = []; cases = []; sample_frames = 6; endpoint_hold = 30
    for row in manifest['cases']:
        for take in (0, 1):
            start = len(schedule)
            ticks = times(row['params'])
            for number, time in enumerate(ticks):
                pair = Image.new('RGB', (1920, 1080), '#070e19')
                draw = ImageDraw.Draw(pair)
                for side_number, side in enumerate(('source', 'redo')):
                    witness = index[row['id'], side, take, number]
                    with Image.open(capture/'samples'/witness['name']) as image:
                        pair.paste(image.convert('RGB').resize((960, 1020)), (side_number*960, 60))
                    draw.text((side_number*960+14, 4), '%s | %s | take %d/2' % (row['id'], side.upper(), take+1), fill='white', font=font)
                    draw.text((side_number*960+14, 29), 'native %.6fs / %.3fs | fixed views: top A, bottom B' % (time, row['params']['duration']), fill='#bbd5e5', font=font)
                path = pairs/('%s-%d-%03d.png' % (row['id'], take, number))
                pair.save(path)
                count = sample_frames + (endpoint_hold if number == len(ticks)-1 else 0)
                for repeat in range(count):
                    os.link(path, frames/('%06d.png' % len(schedule)))
                    schedule.append(dict(frame=len(schedule), id=row['id'], take=take, sample=number, native_time=time, native_delta=0.0 if repeat else (time-ticks[number-1] if number else 0.0), presentation_hold=repeat > 0, endpoint_hold=repeat >= sample_frames, pair=path.name))
            cases.append(dict(id=row['id'], take=take, first_frame=start, frames=len(schedule)-start, authored_duration=row['params']['duration'], native_samples=len(ticks)))
    video = output/'saved-bake-eight-source-redo.mp4'
    command = [str(ffmpeg), '-hide_banner', '-loglevel', 'error', '-n', '-framerate', '60', '-i', str(frames/'%06d.png'), '-frames:v', str(len(schedule)), '-an', '-c:v', 'libx264', '-threads', '2', '-preset', 'medium', '-crf', '18', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(video)]
    state = dict(kind='saved_bake_pair_media', capture_execution_sha256=sha(capture/'execution.json'), capture_binding_sha256=execution['binding_sha256'], original_public_source=binding['source_public'], capture_source=binding['capture_source'], frames=len(schedule), size=[1920, 1080], fps=60, cases=cases, schedule=schedule, encode_command=command, visual_approval=False, human_approved=False, presentation='Every evaluated native sample repeated for six 60FPS frames; last sample held thirty additional frames. No simulation steps during repetition. Native intervals may be unequal near events.', scope='Technical unskinned source versus baked redo, two fixed cameras and two fresh takes. No natural character-motion or human full-watch claim.')
    write_json(output/'media.json', {**state, 'stage':'encoding', 'passed':False})
    try:
        subprocess.run(command, check=True, timeout=300)
        decoded = subprocess.run([str(ffmpeg), '-hide_banner', '-nostats', '-i', str(video), '-map', '0:v:0', '-an', '-f', 'null', '-', '-progress', 'pipe:1'], capture_output=True, text=True, check=True, timeout=180)
    except BaseException as error:
        write_json(output/'media.json', {**state, 'stage':'failed', 'passed':False, 'error':str(error)})
        raise
    (output/'decode.log').write_text(decoded.stderr+decoded.stdout, encoding='utf-8')
    counts = re.findall(r'^frame=(\d+)$', decoded.stdout, re.M)
    duration = re.findall(r'^out_time_us=(\d+)$', decoded.stdout, re.M)
    require(counts and int(counts[-1]) == len(schedule) and duration and abs(int(duration[-1])-len(schedule)/60*1e6) <= 17000, 'full decode count/duration mismatch')
    require(any('h264' in line and '1920x1080' in line and '60 fps' in line for line in decoded.stderr.splitlines()), 'wrong video metadata')
    state.update(stage='complete', passed=True, video=str(video.resolve()), video_sha256=sha(video), decoded_frames=int(counts[-1]), decoded_duration_s=int(duration[-1])/1e6)
    write_json(output/'media.json', state)
    return state


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('capture', 'output', 'ffmpeg'):
        parser.add_argument('--'+name, required=True, type=Path)
    result = compose(**vars(parser.parse_args()))
    print(json.dumps({k:result[k] for k in ('passed', 'frames', 'decoded_frames', 'decoded_duration_s', 'video_sha256')}))
