"""Archive complete turn closure and new style movies without granting approval."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import zipfile
from archive_turn_review import read, digest, require
from review_receipts import write_json

STYLES = ('grounded', 'relaxed', 'heavy', 'sneaky')
VARIANTS = ('left90', 'right90', 'left180', 'right180')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for n in ('repo', 'project-root', 'recovery', 'closure', 'matrix', 'ci-receipt', 'delivery'):
        p.add_argument('--' + n, type=Path, required=True)
    p.add_argument('--capture-roots', type=Path, nargs='+', required=True)
    a = p.parse_args()
    require(not a.delivery.exists(), 'Preserve previous delivery attempts')
    a.delivery.mkdir(parents=True)
    focused_path = a.recovery / 'candidate-r004/delivery-r002/review-delivery.json'
    focused = read(focused_path)
    approval_path = a.recovery / 'approved-responsive-r004-feedback.json'
    approval = read(approval_path)
    matrix = read(a.matrix)
    require(matrix['passed'] and matrix['native_runs'] == 768 and len(matrix['rows']) == 32,
            'Incomplete additional ordinary turn matrix')
    contracts = read(a.closure / 'contracts-r001/contracts.json')
    require(contracts['passed'] and len(contracts['timing']) == 6 and len(contracts['aliases']) == 2,
            'Timing/alias/setup contracts incomplete')
    require(read(Path(contracts['setup']))['passed'], 'Setup parity incomplete')
    refusals = read(a.closure / 'refusals-r001/refusals.json')
    require(refusals['passed'] and len(refusals['rows']) == 28, 'Typed nonmutation incomplete')
    reload = read(a.closure / 'reload-r001/core-reload.json')
    require(reload['passed'] and sum(len(p['rows']) for p in reload['phases']) == 320, 'Actual core reload incomplete')
    local = read(a.closure / 'local-gates.json')
    require(local['passed'], 'Local regression incomplete')
    ci = read(a.ci_receipt)
    require(ci['all_required_source_jobs_pass'] and ci['all_advisory_jobs_pass'], 'Exact-source CI incomplete')
    tooling_source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=a.repo, text=True).strip()
    require(subprocess.run(['git', 'diff', '--quiet', ci['source_head'], 'HEAD', '--',
        'addons/godot_ai_animation', 'test_project/tests', 'test_project/tools'], cwd=a.repo).returncode == 0,
        'Current executable engine code differs from CI source')
    require(subprocess.run(['git', 'diff', '--quiet', approval['animation_source'], 'HEAD', '--',
        'addons/godot_ai_animation'], cwd=a.repo).returncode == 0, 'Accepted generator changed')
    protected = read(a.recovery / 'protected-fixtures-unchanged.json')['fixtures']
    for row in protected: require(digest(Path(row['path'])) == row['sha256'], 'Protected fixture changed')
    movies = []
    review = a.delivery / 'review-videos'; review.mkdir()
    for root in a.capture_roots:
        require(read(root / 'recording-progress.json')['state'] == 'complete', 'Capture is still running')
    for variant in VARIANTS:
        for style in STYLES:
            folders = [r / variant / style for r in a.capture_roots if (r / variant / style / 'media.json').is_file()]
            require(len(folders) == 1, 'Require exactly one capture per new style/variant')
            folder = folders[0]
            route_path = folder / 'route.json'; route = read(route_path)
            measured = [r for r in matrix['rows'] if r['name'] == variant + '-' + style]
            require(len(measured) == 1 and measured[0]['passed'] and digest(Path(measured[0]['route'])) == digest(route_path),
                    'Capture differs from measured public route')
            media = read(folder / 'media.json')
            for mode in ('clean', 'diagnostic'):
                video = media['videos'][mode]; render = video['render']
                require(digest(Path(video['path'])) == video['sha256'] and video['decoded_frames'] == 1440
                    and abs(video['decoded_duration_s'] - 24) < .017 and not render['errors']
                    and render['source_head'] == route['source_head'] and render['fps'] == 60
                    and render['size'] == [1920, 1080] and render['bone_writers_per_view'] == 1
                    and render['root_consumers_per_view'] == 0, 'Invalid native movie')
                require([(r['id'], r['scene_sha256']) for r in render['cases']] ==
                        [(r['id'], r['scene_sha256']) for r in route['cases']], 'Render scene identity differs')
                destination = review if mode == 'clean' else review / 'diagnostic'
                destination.mkdir(exist_ok=True)
                target = destination / f'turn-{style}-{variant}-{mode}.mp4'
                shutil.copy2(video['path'], target)
                require(digest(target) == video['sha256'], 'Copied movie differs')
                movies.append({'kind': 'new_style', 'style': style, 'variant': variant, 'mode': mode,
                    'path': str(target), 'sha256': digest(target), 'frames': 1440, 'duration_s': 24,
                    'media_receipt': str(folder / 'media.json'), 'route': str(route_path)})
    for movie in focused['videos']:
        require(digest(Path(movie['path'])) == movie['sha256'], 'Accepted/baseline movie changed')
        destination = review / ('preserved-baseline' if movie['kind'] == 'baseline-r001' else 'accepted-responsive')
        destination.mkdir(exist_ok=True)
        target = destination / Path(movie['path']).name
        shutil.copy2(movie['path'], target)
        require(digest(target) == movie['sha256'], 'Preserved copy differs')
        movies.append({**movie, 'path': str(target), 'preserved_from': movie['path']})
    require(len(movies) == 44, 'Require 32 new and 12 preserved movies')
    scenes = {}
    def keep(scene, expected=None):
        path = a.project_root / scene.removeprefix('res://')
        if not path.is_file(): return
        sha = digest(path)
        if expected: require(sha == expected, 'Saved scene changed: ' + scene)
        scenes[scene] = {'path': path, 'sha256': sha}
    for path in a.recovery.rglob('route.json'):
        for row in read(path).get('cases', []):
            if row.get('scene'): keep(row['scene'], row.get('scene_sha256'))
    for phase in reload['phases']:
        for row in phase['rows']: keep(row['scene'], row['after_sha256'])
    for row in refusals['rows']: keep(row['scene'], row['stages'][-1]['scene_sha256'])
    archives = []
    for label, revision in (('animation-source', approval['animation_source']),
                            ('tested-closure-source', ci['source_head']), ('delivery-tooling-source', tooling_source)):
        path = a.delivery / (label + '.zip')
        subprocess.run(['git', '-c', 'core.autocrlf=false', 'archive', '--format=zip', '--output=' + str(path), revision],
                       cwd=a.repo, check=True)
        with zipfile.ZipFile(path) as archive:
            require(archive.testzip() is None, 'Source ZIP CRC failed')
            for row in protected:
                relative = Path(row['path']).relative_to(a.repo).as_posix()
                require(archive.read(relative) == subprocess.check_output(['git', 'show', revision + ':' + relative], cwd=a.repo),
                        'Archived fixture differs from exact Git blob')
        archives.append({'path': str(path), 'sha256': digest(path), 'source': revision})
    native_zip = a.delivery / 'native-scenes-and-local-rigs.zip'
    with zipfile.ZipFile(native_zip, 'w', zipfile.ZIP_DEFLATED) as archive:
        for scene, entry in sorted(scenes.items()): archive.write(entry['path'], 'test_project/' + scene.removeprefix('res://'))
        for filename in ('project.godot', 'repair_rig_fixture.tscn', 'repair_xbot_fixture.tscn', 'repair_synthetic_short.tscn', 'repair_synthetic_zup_tall.tscn'):
            archive.write(a.project_root / filename, 'test_project/' + filename)
        for model in ('human_dummy', 'x_bot'):
            for path in (a.project_root / 'models' / model).rglob('*'):
                if path.is_file() and path.suffix != '.import':
                    archive.write(path, 'test_project/models/' + model + '/' + path.relative_to(a.project_root / 'models' / model).as_posix())
    with zipfile.ZipFile(native_zip) as archive: require(archive.testzip() is None, 'Native ZIP CRC failed')
    archives.append({'path': str(native_zip), 'sha256': digest(native_zip), 'scene_entries': len(scenes), 'private_assets_local_only': True})
    write_json(a.delivery / 'scene-inventory.json', {s: r['sha256'] for s, r in scenes.items()})
    receipts_zip = a.delivery / 'phase-receipts-before-delivery.zip'
    with zipfile.ZipFile(receipts_zip, 'w', zipfile.ZIP_DEFLATED) as archive:
        for prefix, root in [('recovery', a.recovery), *[(f'capture-{i}', r) for i, r in enumerate(a.capture_roots)]]:
            for path in root.rglob('*'):
                if not path.is_file() or path.suffix not in ('.json', '.log', '.exit', '.py', '.ps1', '.gd'): continue
                if 'review-videos' in path.parts: continue
                if path.parent.name.endswith('_frames') and path.name != 'render.json': continue
                archive.write(path, prefix + '/' + path.relative_to(root).as_posix())
    with zipfile.ZipFile(receipts_zip) as archive: require(archive.testzip() is None, 'Receipt ZIP CRC failed')
    archives.append({'path': str(receipts_zip), 'sha256': digest(receipts_zip), 'scope': 'Before final delivery/PC/integrity/new human receipts'})
    delivery = {'state': 'awaiting_remaining_turn_style_feedback', 'created_utc': datetime.now(timezone.utc).isoformat(),
        'animation_source': approval['animation_source'], 'additional_clip_source': matrix['source_head'],
        'ci_source': ci['source_head'], 'delivery_tooling_source': tooling_source,
        'public_clips': 160, 'native_runs': 960, 'new_public_clips': 128, 'new_native_runs': 768,
        'contracts': str(a.closure / 'contracts-r001/contracts.json'), 'refusals': str(a.closure / 'refusals-r001/refusals.json'),
        'reload': str(a.closure / 'reload-r001/core-reload.json'), 'local_gates': str(a.closure / 'local-gates.json'),
        'ci_receipt': str(a.ci_receipt), 'matrix': str(a.matrix), 'preserved_focused_delivery': str(focused_path),
        'focused_approval': str(approval_path), 'videos': movies, 'archives': archives, 'saved_scene_entries': len(scenes),
        'other_styles_visual_approval': None, 'release_ready': False}
    write_json(a.delivery / 'review-delivery.json', delivery)
    (review / 'START-HERE.txt').write_text(
        'Remaining turn styles: 16 clean MP4s here, 24 seconds each.\n'
        'Grounded, Relaxed, Heavy, Sneaky: left/right 90 and two-stage 180.\n'
        'Each: dummy, X Bot, short, tall Z-up; simultaneous fixed front/side; two complete reset takes per rig.\n'
        'Diagnostic pairs are optional in diagnostic/. Accepted Responsive and original baselines are preserved in separate folders.\n'
        'Review the new styles, then give feedback. Numerical passes do not grant visual approval.\n'
        'These clips own skeletal heading. Actor yaw/controller/idle blending remains R3. No release approval is requested here.\n', encoding='utf-8')
    print(json.dumps({'movies': len(movies), 'archives': len(archives), 'scenes': len(scenes), 'delivery': str(a.delivery)}))


if __name__ == '__main__': main()
