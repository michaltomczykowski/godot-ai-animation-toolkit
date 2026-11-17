"""Plan decoded-video review from completed immutable saved-effect captures."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from audit_candidate_case_coverage import load, sha
from check_saved_effects import take_reset_failures


def frame_selection(samples, fps):
    """Cover both takes, early effects, observed changes, and final holds."""
    if type(fps) is not int or fps <= 0 or len(samples) < 2:
        raise ValueError('Invalid frame clock')
    by_take = {1: [], 2: []}
    prior_take = 1
    for index, row in enumerate(samples):
        t = row.get('take')
        clock = row.get('time')
        if (row.get('frame') != index + 1 or t not in by_take or t < prior_take
                or type(clock) not in (int, float) or not math.isfinite(clock)
                or not isinstance(row.get('states'), list) or len(row['states']) != 2):
            raise ValueError('Invalid observed saved-effect frame')
        by_take[t].append((index, row))
        prior_take = t
    result = {}
    for take, rows in by_take.items():
        if len(rows) < fps:
            raise ValueError('Missing full take')
        last = len(rows) - 1
        indices = {0, last, last - 1, *range(0, min(fps, last + 1), max(1, fps // 10)),
                   *range(fps, last, max(1, fps // 2))}
        # Sample the beginning, middle and end of actual visible property
        # changes, including transitions that happen late in a take.
        changed = [k for k in range(1, last + 1)
                   if rows[k - 1][1]['states'] != rows[k][1]['states']]
        if changed:
            for k in (changed[0], changed[len(changed) // 2], changed[-1]):
                indices.update((k - 1, k, min(k + 1, last)))
        for i in sorted(indices):
            index, row = rows[i]
            result[index] = {'frame': index, 'take': take, 'native_clock': row['time']}
    return [result[i] for i in sorted(result)]


def prepare(queue, plan, limit=None, offset=0):
    checkpoint = load(queue / 'queue.json')
    if sha(plan) != checkpoint['plan_sha256']:
        raise ValueError('Capture plan hash differs from the active receipt')
    cases = load(plan)['cases']
    result = []
    end = offset+limit if limit is not None else None
    completed = checkpoint['cases'][offset:end]
    first = checkpoint.get('first_plan_case', 0)
    for index, closed in enumerate(completed, first+offset):
        folder = queue / f'case{index:02d}'
        receipt_file = folder / 'media-receipt.json'
        if (closed['index'] != index or Path(closed['receipt']).resolve() != receipt_file.resolve()
                or sha(receipt_file) != closed['sha256']):
            raise ValueError('Completed receipt differs from queue checkpoint')
        case = cases[index]
        receipt = load(receipt_file)
        if (receipt['plan_sha256'] != checkpoint['plan_sha256']
                or receipt['case_id'] != case['id'] or closed['case_id'] != case['id']
                or receipt['operation'] != case['operation']):
            raise ValueError('Captured operation or plan does not match')
        video = folder / 'native-comparison.mp4'
        native_path = Path(receipt['capture_folder']) / 'native-observations.json'
        if (sha(video) != receipt['video_sha256']
                or sha(native_path) != receipt['capture_identity']['native_report_sha256']):
            raise ValueError('Captured video or native observations changed')
        native = load(native_path)
        if case.get('require_predraw_observation') and native.get('observation_phase') != 'rendering_server_frame_pre_draw':
            raise ValueError('Expected actual viewport pre-draw observations')
        fps, duration = case['fps'], case['seconds']
        if (native['plan_sha256'] != receipt['plan_sha256'] or native['case_id'] != case['id']
                or native['scenes'] != case['scenes'] or native['dependencies_verified'] != case['dependencies']
                or native['engine_errors'] or native['runtime_failures']
                or not receipt['capture_identity']['native_check']['native_observation_pass']
                or native['frames'] != len(native['samples']) or native['frames'] != fps * duration
                or receipt['full_decode']['frames'] != fps * duration or take_reset_failures(case, native)
                or abs(receipt['full_decode']['duration_s'] - duration) > 1/fps + .001):
            raise ValueError('Native observation or decoded frame count is incomplete')
        result.append({'case_id': case['id'], 'operation': case['operation'],
                       'video': str(video.resolve()), 'video_sha256': receipt['video_sha256'],
                       'receipt_sha256': closed['sha256'], 'fps': fps,
                       'native_sha256': receipt['capture_identity']['native_report_sha256'],
                       'samples': frame_selection(native['samples'], fps),
                       'take_reset_order': native.get('take_reset_order', 'legacy_reset_frame_unbound'),
                       'observation_phase': native.get('observation_phase', 'legacy_scene_tree_process'),
                       'visual_status': 'pending_review'})
    return {'kind': 'saved_effect_review_plan', 'capture_plan_sha256': checkpoint['plan_sha256'],
            'queue_status_at_read': checkpoint['status'], 'first_queue_case': first+offset, 'cases': result,
            'scope': 'Selection schedule only; video extraction and visual assessment are separate.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--queue', type=Path, required=True)
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--limit', type=int)
    parser.add_argument('--offset', type=int, default=0, help='Skip the already prepared prefix')
    a = parser.parse_args()
    if a.limit is not None and a.limit <= 0:
        parser.error('--limit must be positive')
    if a.offset < 0:
        parser.error('--offset must be nonnegative')
    result = prepare(a.queue, a.plan, a.limit, a.offset)
    if not result['cases']:
        parser.error('No complete captures to review')
    with a.output.open('x', encoding='utf-8') as stream:
        json.dump(result, stream, indent=2)
    print(f"REVIEW_PLAN cases={len(result['cases'])} observations={sum(len(c['samples']) for c in result['cases'])}")


if __name__ == '__main__':
    main()
