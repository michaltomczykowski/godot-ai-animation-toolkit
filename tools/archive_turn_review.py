"""Archive the focused turn review without granting human approval."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile
from review_receipts import write_json

def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def digest(path):
    with path.open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()
def require(value, message):
    if not value: raise ValueError(message)

def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'project-root', 'recovery', 'matrix', 'ci-receipt'):
        p.add_argument('--' + name, type=Path, required=True)
    p.add_argument('--delivery-root', type=Path, help='New delivery attempt; preserve any earlier partial archive')
    args = p.parse_args()
    candidate = args.recovery / 'candidate-r004'
    delivery_root = args.delivery_root or candidate
    delivery_root.mkdir(parents=True, exist_ok=True)
    destination = delivery_root / 'review-delivery.json'
    require(not destination.exists(), 'Preserve the completed delivery and its feedback')
    matrix = read(args.matrix)
    require(matrix['passed'] and matrix['native_runs'] == 192, 'Incomplete focused native matrix')
    require(read(args.recovery / 'controls-r004/summary.json')['passed'], 'Failed checker controls')
    local = read(args.recovery / 'local-gates.json')
    require(local['passed'], 'Local source gates incomplete')
    ci = read(args.ci_receipt)
    require(ci['all_required_source_jobs_pass'] and ci['all_advisory_jobs_pass'], 'Source CI incomplete')
    require(read(candidate / 'recording-progress.json')['state'] == 'complete', 'Candidate capture still running')
    protected = read(args.recovery / 'protected-fixtures-unchanged.json')['fixtures']
    for entry in protected: require(digest(Path(entry['path'])) == entry['sha256'], 'Protected fixture drift')
    scenes = {}
    videos = []
    review = delivery_root / 'review-videos'
    review.mkdir(exist_ok=True)
    source = matrix['source_head']
    for variant in ('left90', 'right90', 'left180', 'right180'):
        for root_mode in ('responsive', 'responsive-in-place'):
            route_path = candidate / variant / root_mode / 'route.json'
            route = read(route_path)
            require(route['passed'] and route['source_head'] == source, 'Changed candidate public route')
            for row in route['cases']:
                path = args.project_root / row['scene'].removeprefix('res://')
                require(digest(path) == row['scene_sha256'], 'Changed candidate saved scene')
                require(row['history']['passed'] == 1 and row['history']['failed'] == 0, 'History witness failed')
                scenes[row['scene']] = path
        for kind, modes in (('candidate-r004', ('clean', 'diagnostic')), ('baseline-r001', ('clean',))):
            folder = args.recovery / kind / variant / 'responsive'
            media = read(folder / 'media.json')
            route = read(folder / 'route.json')
            for mode in modes:
                video = media['videos'][mode]
                path = Path(video['path'])
                require(video['decoded_frames'] == 1440 and video['decoded_duration_s'] == 24.0, 'Incomplete video')
                require(video['render']['source_head'] == route['source_head'] and not video['render']['errors'], 'Invalid render provenance')
                require(digest(path) == video['sha256'], 'Changed movie')
                name = ('baseline-' if kind == 'baseline-r001' else 'turn-') + variant + '-responsive-' + mode + '.mp4'
                copied = review / name
                require(not copied.exists(), 'Preserve existing review copy')
                copied.write_bytes(path.read_bytes())
                require(digest(copied) == video['sha256'], 'Review copy drift')
                videos.append({'kind': kind, 'variant': variant, 'mode': mode,
                    'path': str(copied), 'sha256': video['sha256'], 'frames': 1440, 'duration_s': 24.0})
    # Preserve every attempted public scene, including typed refusals and failed
    # revisions; never replace the original scene with a regenerated animation.
    for route_path in args.recovery.glob('*/**/route.json'):
        if 'review-videos' in route_path.parts: continue
        route = read(route_path)
        for row in route.get('cases', []):
            if not row.get('scene'): continue
            path = args.project_root / row['scene'].removeprefix('res://')
            if path.exists(): scenes[row['scene']] = path
    archives = []
    tooling_source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=args.repo, text=True).strip()
    for label, revision in (('animation-source', source), ('tested-source', ci['source_head']), ('delivery-tooling-source', tooling_source), ('baseline-tooling-source', '8dc306ab80834f940f63418603386fe5c7cdadb1')):
        path = delivery_root / (label + '.zip')
        require(not path.exists(), 'Preserve existing source archive')
        subprocess.run(['git', '-c', 'core.autocrlf=false', 'archive', '--format=zip', '--output=' + str(path), revision], cwd=args.repo, check=True)
        with zipfile.ZipFile(path) as archive:
            require(archive.testzip() is None, 'Source ZIP CRC failed')
            for entry in protected:
                relative = Path(entry['path']).relative_to(args.repo).as_posix()
                blob = subprocess.check_output(['git', 'show', revision + ':' + relative], cwd=args.repo)
                require(archive.read(relative) == blob, 'Source archive fixture differs from Git blob')
        archives.append({'path': str(path), 'sha256': digest(path), 'source': revision})
    native_zip = delivery_root / 'native-scenes-and-local-rigs.zip'
    require(not native_zip.exists(), 'Preserve existing native scene archive')
    with zipfile.ZipFile(native_zip, 'w', zipfile.ZIP_DEFLATED) as archive:
        for scene, path in sorted(scenes.items()): archive.write(path, 'test_project/' + scene.removeprefix('res://'))
        for filename in ('project.godot', 'repair_rig_fixture.tscn', 'repair_xbot_fixture.tscn', 'repair_synthetic_short.tscn', 'repair_synthetic_zup_tall.tscn'):
            archive.write(args.project_root / filename, 'test_project/' + filename)
        for model in ('human_dummy', 'x_bot'):
            for path in (args.project_root / 'models' / model).rglob('*'):
                if path.is_file() and path.suffix != '.import':
                    archive.write(path, 'test_project/models/' + model + '/' + path.relative_to(args.project_root / 'models' / model).as_posix())
    with zipfile.ZipFile(native_zip) as archive: require(archive.testzip() is None, 'Native ZIP CRC failed')
    archives.append({'path': str(native_zip), 'sha256': digest(native_zip), 'saved_scene_entries': len(scenes), 'private_rigs_local_only': True})
    receipts_zip = delivery_root / 'phase-receipts-before-delivery.zip'
    require(not receipts_zip.exists(), 'Preserve original receipt snapshot')
    with zipfile.ZipFile(receipts_zip, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in args.recovery.rglob('*'):
            if not path.is_file() or path.suffix not in ('.json', '.log', '.exit', '.py', '.ps1', '.gd'): continue
            if 'review-videos' in path.parts: continue
            if path.parent.name.endswith('_frames') and path.name != 'render.json': continue
            archive.write(path, path.relative_to(args.recovery).as_posix())
    with zipfile.ZipFile(receipts_zip) as archive: require(archive.testzip() is None, 'Receipt ZIP CRC failed')
    archives.append({'path': str(receipts_zip), 'sha256': digest(receipts_zip), 'scope': 'Snapshot before final delivery/PC/human-feedback receipts'})
    delivery = {'state': 'awaiting_focused_turn_feedback', 'created_utc': datetime.now(timezone.utc).isoformat(),
        'animation_source': source, 'ci_source': ci['source_head'], 'delivery_tooling_source': tooling_source, 'native_matrix': str(args.matrix),
        'public_clips': 32, 'native_runs': 192, 'positive_controls': 24, 'negative_controls': 120,
        'local_editor_tests': 400, 'public_motion_tests': 74, 'headless_suites': 14,
        'videos': videos, 'archives': archives, 'saved_scene_entries': len(scenes),
        'visual_approval': None, 'release_ready': False,
        'pending': 'Focused Responsive feedback, other styles/full turn closure and remaining R2/R3-R5 gates'}
    write_json(destination, delivery)
    (review / 'START-HERE.txt').write_text('Responsive turn review: play the four turn-*-clean.mp4 files first (24 seconds each).\n'
        'Each shows dummy, X Bot, short and tall Z-up rigs, front/side together, two complete reset-separated takes.\n'
        'baseline-*.mp4 preserves the original broken output; diagnostic movies are optional.\n'
        '180: two dominant pivot stages plus one final stance-recovery footfall, 1.4-second action.\n'
        'This clip owns skeletal heading. Actor yaw extraction/controller blending remains a separate integration gate.\n'
        'No other style or GitHub release approval is inferred from this review.\n', encoding='utf-8')
    print(json.dumps({'movies': len(videos), 'archives': len(archives), 'scenes': len(scenes), 'delivery': str(destination)}))

if __name__ == '__main__': main()
