"""Check the actual Movie Maker PCM for the saved, untrimmed two-take cue fixture."""
from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
from pathlib import Path
import sys
import wave


def pcm(path):
    with wave.open(str(path), 'rb') as stream:
        channels, width, rate, count, compression, _ = stream.getparams()
        if compression != 'NONE' or width not in (1, 2, 4) or channels not in (1, 2):
            raise ValueError('Expected uncompressed mono/stereo 8/16/32-bit PCM')
        values = array.array({1: 'B', 2: 'h', 4: 'i'}[width], stream.readframes(count))
    if sys.byteorder != 'little' and width > 1:
        values.byteswap()
    scale = 2 ** (width * 8 - 1)
    mono = [sum(values[i:i+channels]) / channels / scale - (1 if width == 1 else 0)
            for i in range(0, len(values), channels)]
    return rate, mono, {'channels': channels, 'sample_width': width, 'sample_rate': rate,
                        'frames': count, 'seconds': count / rate}


def rms(values):
    return math.sqrt(sum(v * v for v in values) / len(values)) if values else 0.0


def active_runs(values, rate):
    # Fixed 5ms windows resolve frame-scale timing without classifying zero crossings as silence.
    block = max(1, rate // 200)
    active = [i for i in range(0, len(values), block) if rms(values[i:i+block]) > 0.0001]
    runs = []
    for start in active:
        if runs and start == runs[-1][1]:
            runs[-1][1] = min(start + block, len(values))
        else:
            runs.append([start, min(start + block, len(values))])
    return [(a / rate, b / rate) for a, b in runs]


def waveform_match(source, source_rate, output, output_rate, onset, duration):
    # Compare independent input samples with actual mixed output; fit only gain and
    # a sub-frame start offset, never pitch, duration or a replacement waveform.
    stride = max(1, source_rate // 4000)
    points = [(i / source_rate, source[i]) for i in range(0, len(source), stride)
              if 0.02 < i / source_rate < duration - 0.02]
    if len(points) < 16:
        return 0.0
    reference_power = sum(v*v for _, v in points)
    best = 0.0
    for shift in range(-40, 41):  # +/-10ms, quarter-millisecond steps.
        at = onset + shift / 4000
        pairs = [(v, output[round((at+t)*output_rate)]) for t, v in points
                 if 0 <= round((at+t)*output_rate) < len(output)]
        if len(pairs) != len(points):
            continue
        power = sum(v*v for _, v in pairs)
        if power and reference_power:
            best = max(best, abs(sum(a*b for a, b in pairs)) / math.sqrt(reference_power*power))
    return best


def check(source_path, output_path, *, take_seconds=6.0, takes=2, fps=60):
    source_rate, source, source_meta = pcm(source_path)
    rate, output, output_meta = pcm(output_path)
    failures = []
    duration = len(source) / source_rate
    intervals = active_runs(output, rate)
    tolerance = 2 / fps + 0.025  # Two native frames plus one bounded audio mix block.
    if abs(len(output) / rate - takes*take_seconds) > 1 / fps:
        failures.append('captured PCM duration differs from the complete movie')
    if len(intervals) != takes:
        failures.append(f'expected {takes} audible cues; found {len(intervals)}')
    if rms(source) < 0.0001:
        failures.append('independent input cue is silent')
    observations = []
    for index, (start, end) in enumerate(intervals):
        expected = index*take_seconds
        correlation = waveform_match(source, source_rate, output, rate, start, duration)
        level = rms(output[round(start*rate):round(end*rate)])
        observations.append({'onset_s': start, 'end_s': end, 'rms': level,
                             'input_waveform_correlation': correlation})
        if abs(start - expected) > tolerance:
            failures.append(f'cue {index+1}: onset differs from actual request time')
        if abs((end-start)-duration) > tolerance:
            failures.append(f'cue {index+1}: audible duration differs from untrimmed input')
        if correlation < 0.95:
            failures.append(f'cue {index+1}: output waveform/pitch does not match input')
    if len(observations) == takes and observations[0]['rms']:
        ratio = observations[-1]['rms'] / observations[0]['rms']
        if abs(ratio-1) > 0.05:
            failures.append('fresh reset take changes cue level by more than 5%')
    if max(map(abs, output), default=0) >= 0.9999:
        failures.append('captured output clips')
    return {'schema_version': 1, 'scope': 'untrimmed time-zero cue; two independently reset native takes',
            'source': {'path': str(source_path), 'sha256': hashlib.sha256(Path(source_path).read_bytes()).hexdigest(), **source_meta},
            'capture': {'path': str(output_path), 'sha256': hashlib.sha256(Path(output_path).read_bytes()).hexdigest(), **output_meta},
            'cues': observations, 'failures': failures, 'audio_output_pass': not failures,
            'visual_assessment': 'pending', 'human_review': 'waived_not_approved'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--capture', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = check(args.source, args.capture)
    with args.output.open('x', encoding='utf-8') as stream:
        json.dump(result, stream, indent=2)
    print(json.dumps(result))
    raise SystemExit(0 if result['audio_output_pass'] else 1)
