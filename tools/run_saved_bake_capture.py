"""Capture the eight admitted saved bake pairs using the unchanged native schedule."""
import argparse
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess

from check_saved_bake_capture import compare, times
from ci_rendered_preview import validate_editor_log
from movie_capture_startup import run_capture
from prepare_saved_bake_capture import IDS, sha
from review_receipts import write_json


def require(ok, message):
    if not ok:
        raise ValueError(message)


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def unit(v):
    length = math.sqrt(sum(x*x for x in v))
    require(math.isfinite(length) and length > 0, 'invalid camera vector')
    return [x/length for x in v]


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def cameras(report):
    result = {}
    for key in IDS:
        points = []
        for run in report['runs']:
            if run['id'] != key:
                continue
            for sample in run['trace']:
                for witness in sample['required'].values():
                    for pose in witness['pose']['world']:
                        p = pose['origin']
                        require(len(p) == 3 and all(math.isfinite(x) for x in p), 'invalid world point')
                        points.append(p)
                        for axis in (pose['basis'][0], pose['basis'][2]):
                            points.append([x+.15*y for x, y in zip(p, unit(axis))])
        require(points, 'no native world geometry')
        center = [(min(p[i] for p in points)+max(p[i] for p in points))/2 for i in range(3)]
        extent = max(math.dist(p, center) for p in points)
        configs = []
        for direction in ([3, 2, 5], [-5, 2, 3]):
            back = unit(direction)
            right = unit([back[2], 0, -back[0]])
            up = [back[1]*right[2]-back[2]*right[1], back[2]*right[0]-back[0]*right[2], back[0]*right[1]-back[1]*right[0]]
            offsets = [[p[i]-center[i] for i in range(3)] for p in points]
            size = max(max(abs(dot(p, up))*2 for p in offsets), max(abs(dot(p, right))*2/(960/540) for p in offsets)) * 1.25 + .12
            distance = max(10, extent*4)
            configs.append(dict(center=center, position=[center[i]+back[i]*distance for i in range(3)], size=size, near=.01, far=distance*3))
        result[key] = configs
    return result


def same_traces(native, rendered):
    expected = {(r['id'], r['side'], r['take']): r for r in native['runs']}
    observed = {(r['id'], r['side'], r['take']): r for r in rendered['runs']}
    require(len(expected) == len(observed) == 32 and expected.keys() == observed.keys(), 'incomplete native/render matrix')
    for key, before in expected.items():
        after = observed[key]
        require(before['trace'] == after['trace'], 'render changed exact native trace: '+str(key))
        for field in ('loaded_spring_cache', 'saved_modifiers', 'authored_duration', 'spring_reset_contract'):
            # Saved modifier absolute paths differ solely by the unchanged scene's
            # new viewport ancestor; all relative inputs/outputs stay bound below.
            if field != 'saved_modifiers':
                require(before[field] == after[field], 'render changed '+field+': '+str(key))
        # Compare configured classes/active/influence and relative suffixes.
        require(len(before['saved_modifiers']) == len(after['saved_modifiers']), 'modifier count changed')
        for a, b in zip(before['saved_modifiers'], after['saved_modifiers']):
            require({k:v for k,v in a.items() if k != 'path'} == {k:v for k,v in b.items() if k != 'path'} and b['path'].endswith(a['path'].removeprefix('/root/')), 'saved modifier configuration changed')
    return True


def validate_images(images, manifest, folder, binding_sha):
    from PIL import Image
    require(images.get('passed') is True and images.get('failures') == [] and images.get('engine_errors') == [] and images.get('size') == [960, 1080] and images.get('binding_sha256') == binding_sha, 'render failure/header mismatch')
    expected = [(r['id'], side, take, i, t) for r in manifest['cases'] for take in (0, 1) for side in ('source', 'redo') for i, t in enumerate(times(r['params']))]
    rows = images.get('images', [])
    require(len(rows) == len(expected), 'missing rendered samples')
    cameras_by_case = {}
    for row, key in zip(rows, expected):
        require((row.get('id'), row.get('side'), row.get('take'), row.get('sample'), row.get('time')) == key and row.get('no_simulation_advance') is True, 'wrong rendered sample/clock')
        name = '%s-%s-%d-%03d.png' % key[:4]
        require(row.get('name') == name and sha(folder/name) == row.get('sha256'), 'PNG identity mismatch')
        require(len(row.get('bounds', [])) == 2 and all(len(b) == 4 and all(type(x) in (int, float) and math.isfinite(x) for x in b) and 12 <= b[0] <= b[2] <= 948 and 12 <= b[1] <= b[3] <= 528 for b in row['bounds']), 'invalid rendered bounds')
        actual_cameras = row.get('camera_states')
        require(isinstance(actual_cameras, list) and len(actual_cameras) == 2, 'actual cameras missing')
        require(actual_cameras == cameras_by_case.setdefault(row['id'], actual_cameras), 'fixed camera drift across source/redo/takes')
        with Image.open(folder/name) as im:
            require(im.size == (960, 1080), 'actual PNG dimensions')
            im.verify()
    require(sorted(p.name for p in folder.glob('*.png')) == sorted(r['name'] for r in rows), 'unbound PNG files')
    return rows


def prepare(repo, preflight, output):
    require(not output.exists(), 'preserve previous capture')
    source_project = preflight/'project'
    original = read(source_project/'bake-manifest.json')
    native = read(preflight/'native-eight.json')
    comparison = compare(native, original, sha(source_project/'bake-manifest.json'))
    require(comparison['parity_pass'] and comparison['fresh_take_pass'], 'eight-pair native admission failed')
    for virtual, identity in original['files'].items():
        path = source_project/virtual[6:] if virtual.startswith('res://') else preflight/'appdata/Godot/app_userdata/Toolkit Saved Bake Review'/virtual[7:]
        if virtual.startswith('user://'):
            matches = list((preflight/'appdata/Godot/app_userdata').glob('*/'+virtual[7:]))
            require(len(matches) == 1, 'ambiguous saved user resource')
            path = matches[0]
        require(sha(path) == identity['sha256'], 'changed admitted native input: '+virtual)
    output.mkdir(parents=True)
    shutil.copytree(source_project, output/'project', ignore=shutil.ignore_patterns('.godot', 'override.cfg'))
    # Runtime log bytes are outputs, never dependencies of saved scenes.
    shutil.copytree(preflight/'appdata', output/'appdata', ignore=shutil.ignore_patterns('logs'))
    renderer = repo/'test_project/tools/render_saved_bake_capture.gd'
    head = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()
    renderer_blob = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', head+':test_project/tools/'+renderer.name], text=True).strip()
    require(renderer_blob == subprocess.check_output(['git', '-C', str(repo), 'hash-object', '--path', 'test_project/tools/'+renderer.name, str(renderer)], text=True).strip(), 'renderer must match committed source')
    shutil.copyfile(renderer, output/'project/tools'/renderer.name)
    if Path(str(renderer)+'.uid').exists():
        shutil.copyfile(Path(str(renderer)+'.uid'), Path(str(output/'project/tools'/renderer.name)+'.uid'))
    files = [dict(path=str(p.resolve()), sha256=sha(p)) for base in (output/'project', output/'appdata') for p in sorted(base.rglob('*')) if p.is_file()]
    binding = dict(kind='saved_bake_capture_binding', source_public=original['source_public'], capture_source=head, renderer_git_blob=renderer_blob, manifest_sha256=sha(source_project/'bake-manifest.json'), native_sha256=sha(preflight/'native-eight.json'), original_native=str((preflight/'native-eight.json').resolve()), files=files, cameras=cameras(native), scope='Exact original scenes and unchanged shared evaluator; synchronous zero-step drawing. Technical unskinned output only; no human review claim.')
    write_json(output/'capture-binding.json', binding)
    return binding


def run(a):
    binding = prepare(a.repo, a.preflight, a.output)
    state = dict(kind='saved_bake_capture_execution', capture_source=binding['capture_source'], binding_sha256=sha(a.output/'capture-binding.json'), passed=False, visual_approval=False)
    write_json(a.output/'execution.json', {**state, 'stage':'prepared'})
    try:
        project = a.output/'project'
        command = [str(a.godot), '--path', str(project), '--rendering-method', 'gl_compatibility', '--script', 'res://tools/render_saved_bake_capture.gd', '--', 'res://bake-manifest.json', str(a.output/'render-native.json'), str(a.output/'capture-binding.json'), str(a.output/'samples')]
        state['command'] = command
        write_json(a.output/'execution.json', {**state, 'stage':'running'})
        env = {**os.environ, 'APPDATA':str(a.output/'appdata')}
        with (a.output/'render.log').open('x') as log:
            def runner(cmd, **kw):
                process = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, env=env, **{k:v for k,v in kw.items() if k != 'check'})
                write_json(a.output/'process.json', dict(pid=process.pid, command=cmd, state='running'))
                try:
                    code = process.wait(timeout=900)
                except BaseException:
                    process.kill(); process.wait(); raise
                finally:
                    write_json(a.output/'process.json', dict(pid=process.pid, command=cmd, state='exited', returncode=process.returncode))
                return subprocess.CompletedProcess(cmd, code)
            startup = run_capture(project, 960, 1080, a.output/'startup.json', command, runner)
        log = (a.output/'render.log').read_text(encoding='utf-8', errors='replace')
        require('Godot Engine v4.7.2.stable.official.ed1daf0bf' in log, 'official4.7.2 startup required')
        validate_editor_log(log)
        require(startup['passed'], 'capture process/startup failed')
        for f in binding['files']:
            require(sha(f['path']) == f['sha256'], 'capture changed bound resource')
        manifest = read(project/'bake-manifest.json')
        rendered = read(a.output/'render-native.json')
        require(sha(binding['original_native']) == binding['native_sha256'], 'original native report changed during capture')
        native = read(Path(binding['original_native']))
        state['comparison'] = compare(rendered, manifest, binding['manifest_sha256'])
        require(state['comparison']['parity_pass'] and state['comparison']['fresh_take_pass'], 'rendered parity/freshness failed')
        state['native_trace_exact'] = same_traces(native, rendered)
        rows = validate_images(read(a.output/'samples/render.json'), manifest, a.output/'samples', state['binding_sha256'])
        state['samples'] = len(rows)
        state['passed'] = True
        state['scope'] = 'Native/render parity and all PNG admission only; composition/full decode/independent visual assessment pending.'
    except BaseException as error:
        state['error'] = str(error)
        raise
    finally:
        write_json(a.output/'execution.json', {**state, 'stage':'complete'})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'preflight', 'output', 'godot'):
        parser.add_argument('--'+name, required=True, type=Path)
    run(parser.parse_args())
