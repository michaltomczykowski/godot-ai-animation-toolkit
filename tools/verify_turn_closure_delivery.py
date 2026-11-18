"""Independently compare delivered movies/ZIP entries with disk and Git sources."""
import argparse
from datetime import datetime, timezone
import hashlib
from pathlib import Path
import subprocess
import zipfile
from archive_turn_review import read, digest, require
from review_receipts import write_json


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for n in ('repo', 'project-root', 'recovery', 'delivery'): p.add_argument('--' + n, type=Path, required=True)
    a = p.parse_args()
    output = a.delivery / 'independent-delivery-integrity.json'
    require(not output.exists(), 'Preserve previous verification')
    delivery = read(a.delivery / 'review-delivery.json')
    require(len(delivery['videos']) == 44 and delivery['public_clips'] == 160 and delivery['native_runs'] == 960,
            'Full ordinary coverage required')
    for movie in delivery['videos']:
        require(digest(Path(movie['path'])) == movie['sha256'], 'Delivered movie differs')
    playlist_path = a.delivery / 'review-playlist.json'
    playlist = read(playlist_path)
    require(playlist['passed'] and playlist['decoded_frames'] == 23040 and playlist['duration_s'] == 384
        and digest(Path(playlist['path'])) == playlist['sha256'], 'Review compilation changed')
    expected_movies = {v['sha256'] for v in delivery['videos'] if v['kind'] == 'new_style' and v['mode'] == 'clean'}
    require(len(playlist['source_movies']) == 16 and {v['sha256'] for v in playlist['source_movies']} == expected_movies,
            'Compilation does not cover exactly the sixteen new cases')
    protected = read(a.recovery / 'protected-fixtures-unchanged.json')['fixtures']
    for row in protected: require(digest(Path(row['path'])) == row['sha256'], 'Protected fixture changed')
    inventory = read(a.delivery / 'scene-inventory.json')
    require(len(inventory) == delivery['saved_scene_entries'], 'Scene inventory count differs')
    required_scenes = set()
    for route_path in a.recovery.rglob('route.json'):
        for row in read(route_path).get('cases', []):
            if row.get('scene'): required_scenes.add(row['scene'])
    reload = read(Path(delivery['reload']))
    for phase in reload['phases']:
        for row in phase['rows']: required_scenes.add(row['scene'])
    for row in read(Path(delivery['refusals']))['rows']: required_scenes.add(row['scene'])
    require(set(inventory) == required_scenes, 'Missing attempted/public/reload/refusal scene')
    source_checks = 0
    scene_checks = 0
    model_checks = 0
    require(len(delivery['archives']) == 5, 'Require source, native and receipt archives')
    for entry in delivery['archives']:
        path = Path(entry['path'])
        require(digest(path) == entry['sha256'], 'Archive file differs')
        with zipfile.ZipFile(path) as archive:
            require(archive.testzip() is None, 'Archive CRC failure')
            if entry.get('source'):
                for row in protected:
                    relative = Path(row['path']).relative_to(a.repo).as_posix()
                    require(archive.read(relative) == subprocess.check_output(
                        ['git', 'show', entry['source'] + ':' + relative], cwd=a.repo), 'Source ZIP differs from Git blob')
                    source_checks += 1
            elif entry.get('scene_entries') is not None:
                names = set(archive.namelist())
                for scene, expected in inventory.items():
                    name = 'test_project/' + scene.removeprefix('res://')
                    require(name in names, 'Native ZIP lacks scene: ' + scene)
                    raw = archive.read(name)
                    require(hashlib.sha256(raw).hexdigest() == expected and
                            digest(a.project_root / scene.removeprefix('res://')) == expected, 'Native scene bytes differ')
                    scene_checks += 1
                for name in names:
                    if name.startswith('test_project/models/'):
                        require(archive.read(name) == (a.project_root / name.removeprefix('test_project/')).read_bytes(),
                                'Archived local model dependency differs')
                        model_checks += 1
    require(source_checks == 33 and scene_checks == len(inventory) and model_checks > 0, 'Incomplete archive verification')
    ci_path = Path(delivery['ci_receipt']); ci = read(ci_path)
    require(ci['all_required_source_jobs_pass'] and ci['all_advisory_jobs_pass'] and
            read(Path(delivery['local_gates']))['passed'], 'Source gates no longer match delivery')
    require(subprocess.run(['git', 'diff', '--quiet', ci['source_head'], 'HEAD', '--',
        'addons/godot_ai_animation', 'test_project/tests', 'test_project/tools'], cwd=a.repo).returncode == 0,
        'Current executable engine source differs from tested source')
    result = {'passed': True, 'checked_utc': datetime.now(timezone.utc).isoformat(),
        'source_videos_checked': 44, 'derived_playlist_checked': True, 'archives_checked': 5,
        'exact_git_fixture_blobs_checked': source_checks, 'saved_scenes_checked': scene_checks,
        'local_model_dependencies_checked': model_checks, 'protected_working_fixtures_checked': 11,
        'delivery_sha256': digest(a.delivery / 'review-delivery.json'), 'playlist_receipt_sha256': digest(playlist_path),
        'ci_receipt_sha256': digest(ci_path), 'other_styles_visual_approval': None, 'release_ready': False}
    write_json(output, result)
    print(f'Delivery integrity: 44 source movies + playlist, 5 ZIPs, {scene_checks} scenes, 33 exact Git fixture blobs; all pass.')


if __name__ == '__main__': main()
