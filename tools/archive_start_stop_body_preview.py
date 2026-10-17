"""Preserve a focused body-response review; never mark full acceptance or approval."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile
from archive_run_review import digest, read, require, write, RIGS

def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'project-root', 'recovery', 'baseline', 'matrix'):
        p.add_argument('--' + name, type=Path, required=True)
    a = p.parse_args()
    candidate = a.recovery / 'preview-r002'
    require(not (candidate / 'review-delivery.json').exists(), 'Preserve the previous delivery')
    matrix = read(a.matrix)
    require(matrix['passed'] and matrix['native_runs'] == 96 and matrix['body_runs'] == 16
            and len(matrix['rows']) == 4, 'Incomplete focused played checks')
    regression = read(a.recovery / 'motion-regression.json')['tests']
    require(regression['total'] == regression['passed'] == 71 and regression['failed'] == regression['skipped'] == 0,
            'Motion regression failed')
    inert = read(a.recovery / 'inert-control.json')
    require(not inert['passed'] and len(inert['runs']) == len(inert['failures']) == 4
            and not inert['engine_errors'] and (a.recovery / 'inert-control.exit').read_text().strip() == '1',
            'Inert control was not rejected cleanly')
    source = matrix['source_head']
    tooling = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=a.repo, text=True).strip()
    require(subprocess.run(['git', 'diff', '--quiet', source, tooling, '--', 'addons/godot_ai_animation',
        ':(exclude)**/*.uid'], cwd=a.repo).returncode == 0, 'Animation changed after source capture')
    scenes: dict[str, str] = {}
    for item in matrix['rows']:
        for path, sha in item['inputs_sha256'].items():
            require(digest(Path(path)) == sha, 'Native input changed')
            for row in read(Path(path))['cases']:
                relative = row['scene'].removeprefix('res://')
                scene = a.project_root / relative
                require(digest(scene) == row['scene_sha256'], 'Saved scene changed')
                scenes[relative] = row['scene_sha256']
        for key in ('quality', 'body'):
            report = item[key]
            require(digest(Path(report['path'])) == report['sha256'] and report['report']['passed']
                    and not report['report']['engine_errors'], 'Played report changed')
    require(len(scenes) == 48, 'Expected sixteen revised, sixteen previous and sixteen reference scenes')
    protected = read(a.recovery / 'protected-fixtures-before.json')
    for row in protected:
        require(digest(Path(row['path'])) == row['sha256'], 'Accepted or historical fixture changed')
    destination = candidate / 'review-videos'
    destination.mkdir(exist_ok=True)
    videos = []
    for op in ('walk_start', 'walk_stop'):
        route = read(candidate / op / 'responsive/route.json')
        previous = read(a.baseline / op / 'responsive/route.json')
        media = read(candidate / op / 'responsive/media.json')['videos']['clean']
        render = media['render']
        require(route['passed'] and route['source_head'] == source and media['decoded_frames'] == 2880
                and abs(media['decoded_duration_s'] - 48) < .017 and digest(Path(media['path'])) == media['sha256'],
                'Incomplete continuous comparison')
        require(render['source_head'] == source and render['baseline_source_head'] == previous['source_head']
                and render['mode'] == 'clean' and render['size'] == [1920, 1080] and render['fps'] == 60
                and render['root_consumers_per_view'] == 1 and not render['errors']
                and [(r['id'], r['angle']) for r in render['cases']] == [(rig, angle) for rig in RIGS for angle in ('FRONT', 'SIDE')],
                'Incorrect captured source or camera coverage')
        for chapter in render['cases']:
            before_row = next(r for r in previous['cases'] if r['id'] == chapter['id'])
            after_row = next(r for r in route['cases'] if r['id'] == chapter['id'])
            require(chapter['takes'] == 2 and chapter['reset_between_takes'] and chapter['frames'] == 360
                    and chapter['baseline_scene'] == before_row['scene'] and chapter['candidate_scene'] == after_row['scene'],
                    'Recorded scene/take mismatch')
        target = destination / (op + '-body-r002-clean.mp4')
        require(not target.exists(), 'Preserve previous movie copy')
        shutil.copy2(media['path'], target)
        require(digest(target) == media['sha256'], 'Movie copy changed')
        videos.append({'operation': op, 'review_copy': str(target), **media})
    (destination / 'START-HERE.txt').write_text(
        'BODY RESPONSE REVIEW r002 - awaiting your feedback\n\n'
        'Open walk_start-body-r002-clean.mp4, then walk_stop-body-r002-clean.mp4.\n'
        'LEFT: preserved r001. RIGHT: revised body response.\n'
        'Each movie: dummy 00-12s; X Bot 12-24s; short 24-36s; tall Z-up 36-48s.\n'
        'Each rig: front then side; two fresh-reset complete takes per angle.\n'
        'Review weight transfer, chest/head reaction and arm follow-through.\n'
        'Responsive preview only. Full style/sequence acceptance and release are pending.\n', encoding='utf-8')
    archives = {}
    for name, sha in (('animation-source.zip', source), ('review-tooling-source.zip', tooling)):
        target = candidate / name
        require(not target.exists(), 'Preserve source archive')
        subprocess.run(['git', '-c', 'core.autocrlf=false', 'archive', '--format=zip', '--output', str(target), sha], cwd=a.repo, check=True)
        with zipfile.ZipFile(target) as z:
            require(z.testzip() is None, 'Source ZIP CRC failed')
            for row in protected:
                relative = Path(row['path']).relative_to(a.repo).as_posix()
                blob = subprocess.check_output(['git', 'show', sha + ':' + relative], cwd=a.repo)
                require(z.read(relative) == blob, 'Archived fixture differs from exact Git blob')
        archives[str(target)] = digest(target)
    prior_archive = a.baseline / 'native-scenes-and-local-rigs.zip'
    previous_delivery = read(a.baseline / 'review-delivery.json')
    require(digest(prior_archive) == previous_delivery['archives'][str(prior_archive)], 'Previous rig archive changed')
    target = candidate / 'saved-scenes-and-local-rigs.zip'
    require(not target.exists(), 'Preserve scene archive')
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED) as z, zipfile.ZipFile(prior_archive) as old:
        for relative in scenes:
            z.write(a.project_root / relative, 'project/' + relative)
        assets = [n for n in old.namelist() if n.startswith('project/models/') or n in
                  {'project/repair_rig_fixture.tscn', 'project/repair_xbot_fixture.tscn',
                   'project/repair_synthetic_short.tscn', 'project/repair_synthetic_zup_tall.tscn'}]
        require(len(assets) == 13, 'Incomplete local rig dependencies')
        for name in assets:
            data = old.read(name)
            require(hashlib.sha256(data).hexdigest() == digest(a.project_root / name.removeprefix('project/')),
                    'Local rig dependency changed')
            z.writestr(name, data)
    with zipfile.ZipFile(target) as z:
        require(z.testzip() is None, 'Scene ZIP CRC failed')
        for relative, sha in scenes.items():
            require(hashlib.sha256(z.read('project/' + relative)).hexdigest() == sha, 'Archived scene changed')
    archives[str(target)] = digest(target)
    receipt = {'state': 'awaiting_body_feedback', 'scope': 'Responsive focused checkpoint; no full style/sequence approval',
        'created_utc': datetime.now(timezone.utc).isoformat(), 'animation_source': source, 'tooling_source': tooling,
        'public_clips': 16, 'native_runs': 96, 'body_runs': 16, 'motion_regression': 71, 'inert_control_rigs': 4,
        'scene_files': scenes, 'protected_fixtures': len(protected), 'videos': videos, 'archives': archives,
        'visual_approval': None, 'release_ready': False}
    write(candidate / 'review-delivery.json', receipt)
    state = read(a.repo / 'docs/character-quality-review.json')
    require(state['revision'] == 'start-stop-body-r002' and state['start_stop_review']['visual_approval'] is None,
            'Review state changed; preserve feedback')
    state['state'] = state['start_stop_review']['state'] = 'awaiting_start_stop_body_feedback'
    state['start_stop_review']['focused_delivery'] = receipt
    state['start_stop_review']['remaining_gates'] = ['explicit human body-response feedback',
        'full five-style/timing/sequence/reload/regression and exact-source CI closure after feedback']
    state['next_action'] = 'Open the two continuous body-response comparisons in PC Explorer and pause for explicit human feedback.'
    write(a.repo / 'docs/character-quality-review.json', state)
    print('BODY_PREVIEW_DELIVERY=' + str(candidate / 'review-delivery.json'))

if __name__ == '__main__':
    main()
