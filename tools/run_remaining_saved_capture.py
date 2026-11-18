"""Stage/run/admit exactly one saved secondary and two static chain pairs.

Prepare is offline. Native and render explicitly launch the engine and are root
queue actions. No production addons, reference generators or archived edits.
"""
import argparse
from copy import deepcopy
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import zipfile

from ci_rendered_preview import validate_editor_log
from movie_capture_startup import run_capture
from operation_rig_intent_checks import close

IDS = ('secondary_branches_local_60', '3d_local_create', '3d_local_append')
SCRIPT = 'tools/check_remaining_saved_media.gd'
BASE = 'tools/render_saved_bake_capture.gd'
PYTHON_HELPERS = ('tools/run_remaining_saved_capture.py', 'tools/prepare_remaining_sequence_static_media.py', 'tools/operation_rig_scene_history_checks.py', 'tools/operation_rig_intent_checks.py', 'tools/movie_capture_startup.py', 'tools/ci_rendered_preview.py')
LIMITS = dict(position=.0001, rotation=.001, scale=.0001)


def need(ok, message):
    if not ok:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def write(path, value):
    with Path(path).open('x', encoding='utf-8') as stream:
        json.dump(value, stream, indent=2, allow_nan=False)


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def vector(value, n):
    need(isinstance(value, list) and len(value) == n and all(finite(v) for v in value), 'nonfinite native vector')
    return value


def error(a, b):
    need(isinstance(a, list) and isinstance(b, list) and len(a) == len(b) and len(a) in (3, 4), 'wrong native channel shape')
    vector(a, len(a)); vector(b, len(b))
    if len(a) == 3:
        return math.dist(a, b)
    for q in (a, b):
        need(abs(sum(x*x for x in q)-1) < .001, 'unnormalized native quaternion')
    den = math.sqrt(sum(x*x for x in a)*sum(x*x for x in b))
    return 2*math.acos(min(1., abs(sum(x*y for x, y in zip(a, b)))/den))


def schedule(tracks, fps, length=1.):
    values = {0., length, *(i/fps for i in range(1, math.ceil(length*fps)))}
    for track in tracks:
        keys = track['keys']
        previous = None
        for key in keys:
            t = key['time']
            need(finite(t) and 0 <= t <= length and (previous is None or previous < t), 'unordered/outside key')
            values.add(t)
            if previous is not None:
                values.add((t+previous)/2)
            previous = t
    return sorted(values)


def verify_frozen(binding):
    for entry in binding['files'] + binding.get('source_helpers', []):
        need(sha(entry['path']) == entry['sha256'], 'changed bound input: '+entry['path'])


def persisted_tracks(path):
    """Parse only the fixed serialized float32 native channel reference.

    This is a read-only byte oracle; playback interpolation is independently
    evaluated by the engine from this exact Animation, never generated here.
    """
    text = Path(path).read_text(encoding='utf-8-sig'); tracks = []
    fields = {}
    for track, field, value in re.findall(r'^tracks/(\d+)/(\w+) = (.*)$', text, re.M):
        fields.setdefault(int(track), {})[field] = value
    need(sorted(fields) == list(range(5)), 'persisted five native tracks required')
    kinds = {'position_3d':1, 'rotation_3d':2, 'scale_3d':3}
    for i in range(5):
        f = fields[i]; kind = json.loads(f['type']); n = 4 if kind == 'rotation_3d' else 3
        need(kind in kinds and f['keys'].startswith('PackedFloat32Array(') and f['keys'].endswith(')'), 'unsupported persisted native track')
        numbers = [struct.unpack('<f', struct.pack('<f', float(v)))[0] for v in f['keys'][len('PackedFloat32Array('):-1].split(',')]
        need(len(numbers) % (n+2) == 0, 'malformed persisted keys')
        keys = [dict(time=numbers[k], transition=numbers[k+1], value=numbers[k+2:k+2+n]) for k in range(0, len(numbers), n+2)]
        path = re.fullmatch(r'NodePath\("([^"\n]+)"\)', f['path'])
        need(path is not None, 'malformed persisted path')
        tracks.append(dict(path=path[1], type=kinds[kind], enabled=f['enabled']=='true', interpolation=int(f['interp']), loop_wrap=f['loop_wrap']=='true', keys=keys))
    return tracks


def saved_bone_names(path):
    result = {}; current = None
    for line in Path(path).read_text(encoding='utf-8-sig').splitlines():
        if line.startswith('[node '):
            name = re.search(r'name="([^"]+)"', line)
            parent = re.search(r'parent="([^"]+)"', line)
            current = None
            if 'type="Skeleton3D"' in line:
                need(name is not None and parent is not None, 'nested saved skeleton required')
                current = (parent[1]+'/' if parent[1] != '.' else '')+name[1]
                result[current] = []
        match = re.fullmatch(r'bones/(\d+)/name = "([^"]+)"', line)
        if match and current:
            need(int(match[1]) == len(result[current]), 'non-contiguous saved bones')
            result[current].append(match[2])
    need(result and all(result.values()), 'saved skeleton names missing')
    return result


def verify_originals(inventory):
    from prepare_remaining_sequence_static_media import ARCHIVE_SHA, CHAIN_CONTEXT_SHA, CHAIN_SOURCE, SYNTHETIC_SOURCE
    from operation_rig_scene_history_checks import verify_event
    technical = inventory['technical_pairs']; archive = technical['archive']
    need(archive['sha256'] == ARCHIVE_SHA and sha(archive['path']) == ARCHIVE_SHA, 'original archive changed')
    secondary = [r for r in technical['cases'] if r['id'] == IDS[0]]
    need(len(secondary) == 1, 'one exact secondary case required')
    with zipfile.ZipFile(archive['path']) as z:
        original = next(r for r in json.loads(z.read('motion_sequence_saved_matrix.json'))['cases'] if r['id'] == IDS[0])
        row = secondary[0]
        need(row['original_row'] == original and row['producer_source'] == SYNTHETIC_SOURCE, 'secondary original request/source changed')
        for side, virtual in [('source', original['source']), ('reference', original['reference']), *original['states'].items()]:
            need(hashlib.sha256(z.read(virtual.removeprefix('user://'))).hexdigest() == row['files'][side]['sha256'] == sha(row['files'][side]['path']), 'secondary archive/staged bytes changed')
    for row in inventory['static_pairs']:
        need(row['producer_source'] == CHAIN_SOURCE and row['context']['sha256'] == CHAIN_CONTEXT_SHA == sha(row['context']['path']), 'original public context/source changed')
        need(sha(row['raw_event']['path']) == row['raw_event']['sha256'], 'original public trace changed')
        events = [json.loads(line) for p in Path(row['raw_event']['path']).parent.glob('*.jsonl') for line in p.read_text(encoding='utf-8-sig').splitlines()]
        matches = [e for e in events if e.get('id') == row['public_event_id']]
        need(len(matches) == 1, 'original public event missing/duplicate')
        event = matches[0]
        proof = verify_event(event, read(row['context']['path']), [e for e in events if e['kind']=='public_test_run_begin'], [e for e in events if e['kind']=='public_support_call'])
        need(all(v == 'pass' for v in proof['checks'].values()) and proof['checks'].get('valid_effect') == 'pass', 'original public chain gates failed')
        need(row['request'] == event['row']['request'], 'original public request changed')
        for side, field in (('before', 'persist_undo'), ('after', 'persist_redo')):
            original = event['row'][field]; f = row['files'][side]
            need(f['sha256'] == original['sha256'] == sha(f['path']) and f['native_snapshot'] == original['snapshot'], 'original public snapshot/bytes changed')


def track_contract(actual, reference):
    need(len(actual) == len(reference) == 5, 'complete five-track contract required')
    for a, b in zip(actual, reference):
        need(all(a[k] == b[k] for k in ('path', 'type', 'enabled', 'interpolation', 'loop_wrap')) and a['enabled'] is True, 'track identity/interpolation changed')
        need(a['path'].startswith('Skeleton:') and len(a['keys']) == len(b['keys']) >= 2, 'track target/key count changed')
        for u, v in zip(a['keys'], b['keys']):
            need(finite(u['time']) and abs(u['time']-v['time']) < 1e-7 and u['transition'] == v['transition'], 'key time/transition changed')
            need(error(u['value'], v['value']) <= (.001 if len(v['value']) == 4 else .0001), 'persisted key value differs')


def state_parity(actual, wanted):
    need(actual['rigs'].keys() == wanted['rigs'].keys(), 'required skeleton set changed')
    def topology(value):
        value = deepcopy(value)
        def strip(node):
            for bone in node.get('bones', []): bone.pop('pose', None)
            for child in node.get('children', {}).values(): strip(child)
        strip(value)
        return value
    need(close(topology(actual['tree']), topology(wanted['tree'])), 'complete original topology/rest/body state differs')
    for key, rig in actual['rigs'].items():
        other = wanted['rigs'][key]
        need(len(rig['components']) == len(other['components']), 'all-bone parity missing')
        for a, b in zip(rig['components'], other['components']):
            need(error(a['position'], b['position']) <= .0001 and error(a['rotation'], b['rotation']) <= .001 and error(a['scale'], b['scale']) <= .0001, 'all-bone native position/rotation/scale differs')


def validate(report, manifest, manifest_sha, binding_sha, rendered=False):
    need(report.get('kind') == 'remaining_saved_native' and report.get('manifest_sha256') == manifest_sha and report.get('binding_sha256') == binding_sha and report.get('rendered') is rendered, 'wrong report/manifest/binding/mode')
    need(report.get('passed') is True and report.get('failures') == [] and report.get('engine_errors') == [], 'native engine/observation failure')
    need([r['id'] for r in manifest['cases']] == list(IDS), 'wrong bounded cases')
    expected = {(IDS[0], side, take, fps) for side in ('reference', 'redo') for take in (0, 1) for fps in ((60,) if rendered else (30, 60, 120))}
    expected |= {(key, side, take, 0) for key in IDS[1:] for side in ('before', 'after') for take in (0, 1)}
    runs = report.get('runs', []); index = {}
    rows = {r['id']: r for r in manifest['cases']}
    for run in runs:
        key = (run.get('id'), run.get('side'), run.get('take'), run.get('fps'))
        need(type(run.get('fps')) is int and type(run.get('take')) is int and key in expected and key not in index and run.get('failures') == [], 'missing/foreign/duplicate/failed run')
        index[key] = run; row = rows[key[0]]; secondary = key[0] == IDS[0]
        side = ('source' if key[1] == 'reference' else 'redo') if secondary else key[1]
        need(run['scene_sha256'] == row['files'][side]['sha256'], 'wrong original scene')
        trace = run.get('trace', [])
        if not secondary:
            need(run.get('fps') == 0 and type(run.get('simulation_advances')) is int and run['simulation_advances'] == 0 and len(trace) == 1 and finite(trace[0]['time']) and finite(trace[0]['delta']) and trace[0]['time'] == trace[0]['delta'] == 0, 'static simulation clock advanced')
            need(close(run['snapshot'], row['files'][side]['native_snapshot']), 'static names/parents/rest/pose/scale/enabled/meta/owner changed')
            need(trace[0]['state'] == run['after_draw'] and all(c['active'] is False and c['playing'] is False and c['position'] == 0 and c['manual'] is True for c in run['after_draw']['clocks'].values()), 'static writer or draw mutation')
        else:
            need(run.get('reference_sha256') == row['files']['reference']['sha256'] and run.get('length') == 1 and run.get('loop_mode') == 0 and run.get('evaluation_speed_scale') == 1 and finite(run.get('saved_speed_scale')), 'persisted reference/finite clip/speed changed')
            track_contract(run['tracks'], run['reference_tracks'])
            need(close(run['reference_tracks'], row['persisted_reference_tracks']), 'raw persisted reference differs from native report')
            expected_times = schedule(run['reference_tracks'], key[3])
            need(len(trace) == len(expected_times), 'incomplete key/midpoint/FPS schedule')
            previous = 0.
            for sample, t in zip(trace, expected_times):
                need(finite(sample['time']) and abs(sample['time']-t) < 1e-12 and finite(sample['delta']) and abs(sample['delta']-(t-previous)) < 1e-12, 'wrong native time/delta')
                need(sample.get('owners') == 1 and vector(sample['root_delta'], 3) == [0, 0, 0], 'wrong writer/root ownership')
                clocks = sample['state']['clocks']; active = [c for c in clocks.values() if c['active']]
                need(len(active) == 1 and active[0]['manual'] is True and all(c['manual'] is True for c in clocks.values()), 'actual writer/manual clock differs')
                need(active[0]['assigned'] == row['params']['animation_name'] and active[0]['speed'] == 1 and finite(active[0]['position']) and abs(active[0]['position']-t) < 1e-6, 'actual native player clock/speed differs')
                need(len(sample['actual']) == len(sample['reference']) == 5, 'missing played native channel')
                for a, b in zip(sample['actual'], sample['reference']):
                    need(error(a, b) <= (.001 if len(b) == 4 else .0001), 'played native channel differs')
                rig = sample['state']['rigs']['MotionSequenceHistory/Character/Skeleton']
                names = [b['name'] for b in rig['snapshot']['bones']]
                for track, value, wanted in zip(run['reference_tracks'], sample['actual'], sample['reference']):
                    bone = names.index(track['path'].split(':')[1])
                    channel = {1:'position', 2:'rotation', 3:'scale'}[track['type']]
                    need(value == rig['components'][bone][channel], 'played channel not joined to actual bone state')
                    for key_value in track['keys']:
                        if abs(t-key_value['time']) < 1e-8:
                            need(error(wanted, key_value['value']) <= (.001 if track['type'] == 2 else .0001), 'native key sample differs from raw persisted value')
                previous = t
            need(trace[-1]['state'] == run.get('held_endpoint') and run.get('hold_simulation_advances') == 0, 'endpoint hold advanced/changed')
        need(trace and all(s.get('required') and s['state']['rigs'] for s in trace), 'all-rig geometry missing')
        for sample in trace:
            need(sample['state']['rigs'].keys() == row['expected_bone_names'][side].keys() == sample['required'].keys(), 'complete saved skeleton set missing')
            for path, names in row['expected_bone_names'][side].items():
                need([b['name'] for b in sample['state']['rigs'][path]['snapshot']['bones']] == names, 'complete original/new bone names missing')
            for rig in sample['state']['rigs'].values():
                need(len(rig['components']) == len(rig['snapshot']['bones']) == len(rig['pose']['world']) > 0, 'incomplete bone observations')
                for transform in rig['pose']['world']:
                    vector(transform['origin'], 3)
                    need(len(transform['basis']) == 3, 'missing world basis')
                    for axis in transform['basis']: vector(axis, 3)
                for components in rig['components']:
                    vector(components['position'], 3); vector(components['rotation'], 4); vector(components['scale'], 3)
    need(set(index) == expected, 'incomplete fresh load/FPS matrix')
    for key, side, take, fps in expected:
        run = index[key, side, take, fps]
        other = index[key, side, 1-take, fps]
        need(run['trace'] == other['trace'], 'fresh loads differ')
        if key == IDS[0] and side == 'redo':
            reference = index[key, 'reference', take, fps]
            need(run['reference_tracks'] == reference['reference_tracks'] and run['markers'] == reference['markers'], 'diagnostic persisted reference differs')
            need(len(run['trace']) == len(reference['trace']), 'reference playback schedule differs')
            for actual, wanted in zip(run['trace'], reference['trace']):
                need(all(error(a, b) <= (.001 if len(b) == 4 else .0001) for a, b in zip(actual['reference'], wanted['actual'])), 'reference engine playback differs from persisted interpolation')
                # All original non-target bones and body transforms remain visible.
                need(actual['required'].keys() == wanted['required'].keys(), 'required skeleton set changed')
                state_parity(actual['state'], wanted['state'])
    return dict(passed=True, runs=len(runs), secondary_plays=4 if rendered else 12, static_zero_clock_loads=8, limits=LIMITS, fresh_loads_exact=True, full_key_midpoint_fps=True, visual_approval=False)


def git(repo, *args):
    return subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()


def current_boundaries(repo, inventory):
    from prepare_remaining_sequence_static_media import source_comparison, function_comparison, SYNTHETIC_SOURCE, CHAIN_SOURCE
    old = inventory['source_boundaries']
    secondary = source_comparison(repo, SYNTHETIC_SOURCE, [r['path'] for r in old['secondary_technical']])
    chain = source_comparison(repo, CHAIN_SOURCE, [r['path'] for r in old['chain']])
    operative = function_comparison(repo, SYNTHETIC_SOURCE, 'addons/godot_ai_animation/handlers/motion.gd', 'motion_secondary')
    need(operative['exact'] and all(r['exact'] for r in chain), 'selected operative secondary/chain source changed; review required')
    need(all(r['exact'] for r in secondary if not r['path'].endswith(('/motion.gd','/bone_animation.gd'))), 'secondary dependency changed; review required')
    return dict(secondary=secondary, secondary_operative_function=operative, chain=chain, limitation='Historical replay only. Whole motion/bone writer differences remain disclosed; no current generation or all-variant approval.')


def prepare(repo, inputs, output):
    need(not output.exists(), 'preserve previous run/staging')
    inventory = read(inputs); candidate = git(repo, 'rev-parse', 'HEAD')
    verify_originals(inventory)
    selected = [r for r in inventory['technical_pairs']['cases'] if r['id'] == IDS[0]] + inventory['static_pairs']
    need([r['id'] for r in selected] == list(IDS), 'wrong selected original cases')
    output.mkdir(parents=True, exist_ok=False); project = output/'project'; (project/'tools').mkdir(parents=True)
    files = []; helpers = []; pending = [SCRIPT, BASE]; seen = set()
    while pending:
        virtual = pending.pop()
        if virtual in seen:
            continue
        seen.add(virtual); source = repo/'test_project'/virtual
        raw = source.read_bytes(); target = project/virtual
        target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(raw)
        blob = git(repo, 'rev-parse', candidate+':test_project/'+virtual)
        need(git(repo, 'hash-object', '--path', 'test_project/'+virtual, str(source)) == blob, 'helper must match committed source: '+virtual)
        helpers.append(dict(path=virtual, git_blob=blob, runtime_sha256=sha(target), source= candidate))
        for found in re.findall(r'(?:extends\s+|(?:preload|load)\(\s*)"res://([^"\n]+\.gd)"', raw.decode('utf-8-sig')):
            need(found.startswith('tools/') and '..' not in Path(found).parts, 'helper outside fixed independent tools')
            pending.append(found)
    cases = []
    for original in selected:
        row = {k:deepcopy(original[k]) for k in ('id', 'operation', 'producer_source')}
        row['files'] = {}; row['expected_bone_names'] = {}; row['original_evidence'] = deepcopy(original)
        if row['id'] == IDS[0]:
            row['params'] = deepcopy(original['original_row']['params'])
            row['persisted_reference_tracks'] = persisted_tracks(original['files']['reference']['path'])
            labels = ('source', 'reference', 'do', 'undo', 'redo')
        else:
            row['request'] = deepcopy(original['request']); labels = ('before', 'after')
        for label in labels:
            f = original['files'][label]; source = Path(f['path'])
            need(sha(source) == f['sha256'], 'changed original stage bytes')
            text = source.read_text(encoding='utf-8-sig')
            need('[ext_resource' not in text and 'script =' not in text and 'type="Skin"' not in text and 'type="MeshInstance3D"' not in text, 'self-contained synthetic input required')
            target = project/'saved'/row['id']/source.name; target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
            row['files'][label] = {**deepcopy(f), 'path':'res://'+target.relative_to(project).as_posix(), 'original_staged_path':str(source)}
            if source.suffix == '.tscn': row['expected_bone_names'][label] = saved_bone_names(source)
        cases.append(row)
    project_file = project/'project.godot'
    project_file.write_text('config_version=5\n[application]\nconfig/name="Remaining Saved Technical Review"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding='utf-8')
    manifest = dict(kind='remaining_saved_three_cases', candidate_source=candidate, inventory=dict(path=str(inputs.resolve()), sha256=sha(inputs)), cases=cases, current_source_boundaries=current_boundaries(repo, inventory), original_inventory_source_boundaries=inventory['source_boundaries'], scope='Historical saved replay only. No generation or human approval.', presentation=dict(fps=60, secondary_take_frames=360, static_take_frames=240, total_frames=1680, seconds=28, views=2, takes=2))
    write(project/'remaining-manifest.json', manifest)
    for p in sorted(project.rglob('*')):
        if p.is_file(): files.append(dict(path=str(p.resolve()), sha256=sha(p)))
    source_helpers = []
    for relative in PYTHON_HELPERS:
        source = repo/relative; blob = git(repo, 'rev-parse', candidate+':'+relative)
        need(git(repo, 'hash-object', '--path', relative, str(source)) == blob, 'Python helper must match committed source')
        source_helpers.append(dict(path=str(source.resolve()), sha256=sha(source), source=candidate, git_blob=blob))
    binding = dict(kind='remaining_saved_capture_binding', candidate_source=candidate, manifest_sha256=sha(project/'remaining-manifest.json'), inventory=manifest['inventory'], helpers=helpers, source_helpers=source_helpers, files=files, cameras={}, scope='Native admission pending; exact original bytes and historical identities retained.')
    write(output/'capture-binding.json', binding)
    return binding


def cameras(report):
    # Same conservative geometry inputs/directions as the admitted bake helper.
    def unit(v):
        length = math.sqrt(sum(x*x for x in vector(v, 3)))
        need(length > 0, 'zero geometry/camera axis')
        return [x/length for x in v]
    def dot(a, b): return sum(x*y for x, y in zip(a, b))
    result = {}
    for key in IDS:
        points = []
        for run in report['runs']:
            if run['id'] != key:
                continue
            for sample in run['trace']:
                for witness in sample['required'].values():
                    for pose in witness['pose']['world']:
                        p = vector(pose['origin'], 3); points.append(p)
                        for axis in (pose['basis'][0], pose['basis'][2]):
                            points.append([x+.15*y for x, y in zip(p, unit(axis))])
        need(points, 'missing native camera geometry')
        center = [(min(p[i] for p in points)+max(p[i] for p in points))/2 for i in range(3)]
        configs = []
        for direction in ([3, 2, 5], [-5, 2, 3]):
            back = unit(direction); right = unit([back[2], 0, -back[0]])
            up = [back[1]*right[2]-back[2]*right[1], back[2]*right[0]-back[0]*right[2], back[0]*right[1]-back[1]*right[0]]
            offsets = [[p[i]-center[i] for i in range(3)] for p in points]
            size = max(max(abs(dot(p, up))*2 for p in offsets), max(abs(dot(p, right))*2/(960/540) for p in offsets))*1.3+.16
            distance = max(10, max(math.dist(p, center) for p in points)*4)
            configs.append(dict(center=center, position=[center[i]+back[i]*distance for i in range(3)], size=size, near=.01, far=distance*3))
        result[key] = configs
    return result


def prepare_render(native_folder, output):
    native = admit(native_folder, rendered=False)
    need(not output.exists(), 'preserve previous render attempt')
    output.mkdir(parents=True); shutil.copytree(native_folder/'project', output/'project', ignore=shutil.ignore_patterns('.godot', 'override.cfg'))
    binding = read(native_folder/'capture-binding.json')
    binding['files'] = [dict(path=str((output/'project'/Path(f['path']).relative_to(native_folder/'project')).resolve()), sha256=f['sha256']) for f in binding['files']]
    binding.update(cameras=cameras(read(native_folder/'native.json')), original_native=dict(path=str((native_folder/'native.json').resolve()), sha256=sha(native_folder/'native.json')), native_admission=native)
    write(output/'capture-binding.json', binding)
    return binding


def validate_images(folder, binding, report):
    from PIL import Image
    image_report = read(folder/'samples/render.json'); rows = image_report.get('images', [])
    need(image_report.get('kind') == 'remaining_saved_images' and image_report.get('passed') is True and image_report.get('failures') == [] and image_report.get('engine_errors') == [] and image_report.get('size') == [960, 1080] and image_report.get('binding_sha256') == sha(folder/'capture-binding.json'), 'image header/failure')
    expected = [(run, i, sample) for run in report['runs'] for i, sample in enumerate(run['trace'])]
    need(len(rows) == len(expected), 'missing captured sample')
    cameras_by_case = {}
    for row, (run, i, sample) in zip(rows, expected):
        need((row['id'], row['side'], row['take'], row['sample'], row['time'], row['delta']) == (run['id'], run['side'], run['take'], i, sample['time'], sample['delta']) and row.get('no_simulation_advance') is True, 'render changed native clock/sample')
        name = '%s-%s-%d-%03d.png' % (run['id'], run['side'], run['take'], i)
        need(row['name'] == name and sha(folder/'samples'/name) == row['sha256'], 'PNG bytes changed')
        need(len(row['bounds']) == 2 and all(len(b) == 4 and all(finite(v) for v in b) and 12 <= b[0] <= b[2] <= 948 and 12 <= b[1] <= b[3] <= 528 for b in row['bounds']), 'actual geometry outside framing')
        need(len(row['camera_states']) == 2 and row['camera_states'] == cameras_by_case.setdefault(row['id'], row['camera_states']), 'fixed view changed')
        with Image.open(folder/'samples'/name) as im:
            need(im.size == (960, 1080), 'PNG dimensions changed'); im.verify()
    need(sorted(p.name for p in (folder/'samples').glob('*.png')) == sorted(r['name'] for r in rows), 'unbound sample PNGs')
    return len(rows)


def admit(folder, rendered=False):
    binding = read(folder/'capture-binding.json'); verify_frozen(binding)
    need(sha(binding['inventory']['path']) == binding['inventory']['sha256'], 'inventory provenance changed')
    verify_originals(read(binding['inventory']['path']))
    execution = read(folder/'execution.json'); process = read(folder/'process.json')
    need(execution.get('stage') == 'complete' and execution.get('rendered') is rendered and execution.get('binding_sha256') == sha(folder/'capture-binding.json'), 'incomplete/wrong engine attempt')
    need(process.get('state') == 'exited' and process.get('returncode') == 0 and process.get('command') == execution.get('command'), 'actual engine process failed')
    need(sha(process['command'][0]) == execution['godot_sha256'], 'engine executable changed')
    log = (folder/'engine.log').read_text(encoding='utf-8', errors='replace')
    need('Godot Engine v4.7.2.stable.official.ed1daf0bf' in log, 'official 4.7.2 banner required'); validate_editor_log(log)
    report_path = folder/('render-native.json' if rendered else 'native.json'); report = read(report_path)
    summary = validate(report, read(folder/'project/remaining-manifest.json'), binding['manifest_sha256'], sha(folder/'capture-binding.json'), rendered)
    if rendered:
        startup = read(folder/'startup.json')
        need(startup.get('passed') is True and startup.get('cleanup') == 'owned_override_removed' and startup.get('command') == process['command'], 'startup/override cleanup failed')
        original = binding['original_native']; need(sha(original['path']) == original['sha256'], 'original native changed')
        before = read(original['path']); selected = [r for r in before['runs'] if r['fps'] in (0, 60)]
        need(selected == report['runs'], 'render differs from exact admitted native traces')
        summary['images'] = validate_images(folder, binding, report)
    return {**summary, 'native_sha256':sha(report_path), 'binding_sha256':sha(folder/'capture-binding.json'), 'original_execution_sha256':sha(folder/'execution.json'), 'original_execution_passed':execution.get('passed'), 'original_execution_error':execution.get('error')}


def presentation(folder):
    admission = admit(folder, rendered=True)
    report = read(folder/'render-native.json'); manifest = read(folder/'project/remaining-manifest.json')
    images = read(folder/'samples/render.json')['images']
    lookup = {(r['id'], r['side'], r['take'], r['sample']):r for r in images}
    runs = {(r['id'], r['side'], r['take']):r for r in report['runs']}
    frames = []
    for key in IDS:
        for take in (0, 1):
            for local in range(360 if key == IDS[0] else 240):
                if key == IDS[0]:
                    t = min(local/60, 1.)
                    sides = ('reference', 'redo'); phase = 'native_clip' if local < 60 else 'held_endpoint'
                    indices = [min(range(len(runs[key, side, take]['trace'])), key=lambda i:abs(runs[key, side, take]['trace'][i]['time']-t)) for side in sides]
                    need(all(abs(runs[key, side, take]['trace'][i]['time']-t) < 1e-12 for side, i in zip(sides, indices)), 'uniform native frame not captured')
                else:
                    t = 0.; sides = ('before', 'before' if local < 120 else 'after'); indices = (0, 0)
                    phase = 'before_static' if local < 120 else 'after_static'
                sources = [lookup[key, side, take, i] for side, i in zip(sides, indices)]
                frames.append(dict(frame=len(frames), id=key, take=take, phase=phase, native_time=t, simulation_advances_for_presentation=0, panes=[dict(side=side, path=str((folder/'samples'/r['name']).resolve()), sha256=r['sha256'], sample=r['sample'], native_time=r['time']) for side, r in zip(sides, sources)]))
    need(len(frames) == 1680, 'fixed 28-second queue changed')
    result = dict(kind='remaining_saved_presentation_schedule', fps=60, frames=frames, frame_count=1680, duration_s=28, size=[1920,1080], fit_native_panes_below_header_preserving_aspect=True, native_admission=admission, source_manifest_sha256=sha(folder/'project/remaining-manifest.json'), case_metadata=manifest['cases'], note='Each 960x1080 pane includes two fixed views. Static left stays before; right shows before for 2s then after for 2s. Secondary plays the complete 1s native clip then holds for 5s. All repetition is encoding only; fit complete PNGs below a composition header preserving aspect for case/take/phase, bone names/parent/rest/scale/enabled metadata. PNG geometry must not be cropped or covered. Composition/full decode/independent assessment remain pending.', human_approved=False)
    write(folder/'presentation-schedule.json', result)
    return dict(schedule_sha256=sha(folder/'presentation-schedule.json'), frame_count=1680, duration_s=28, visual_approval=False)


def run(folder, godot, rendered=False, timeout=900):
    need(not (folder/'execution.json').exists(), 'preserve prior engine attempt')
    binding = read(folder/'capture-binding.json'); verify_frozen(binding)
    command = [str(godot), '--path', str(folder/'project')]
    command += ['--rendering-method', 'gl_compatibility'] if rendered else ['--headless']
    command += ['--script', 'res://'+SCRIPT, '--', 'res://remaining-manifest.json', str(folder/('render-native.json' if rendered else 'native.json')), str(folder/'capture-binding.json'), str(folder/'samples') if rendered else '-']
    state = dict(kind='remaining_saved_execution', stage='running', passed=False, rendered=rendered, binding_sha256=sha(folder/'capture-binding.json'), godot_sha256=sha(godot), command=command, timeout_s=timeout, visual_approval=False)
    write(folder/'execution.json', state)
    try:
        with (folder/'engine.log').open('x') as log:
            def launch(cmd, **kwargs):
                process = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, env={**os.environ, 'APPDATA':str(folder/'appdata')})
                write(folder/'process.json', dict(pid=process.pid, state='running', command=cmd))
                try:
                    code = process.wait(timeout=timeout)
                except BaseException:
                    process.kill(); process.wait(); raise
                finally:
                    (folder/'process.json').write_text(json.dumps(dict(pid=process.pid, state='exited', command=cmd, returncode=process.returncode), indent=2), encoding='utf-8')
                return subprocess.CompletedProcess(cmd, code)
            if rendered:
                receipt = run_capture(folder/'project', 960, 1080, folder/'startup.json', command, launch)
                need(receipt['passed'], 'actual capture startup failed')
            else:
                need(launch(command).returncode == 0, 'actual native engine failed')
        state['stage'] = 'complete'
        (folder/'execution.json').write_text(json.dumps(state, indent=2), encoding='utf-8')
        state['admission'] = admit(folder, rendered); state['passed'] = True
    except BaseException as exc:
        state['error'] = str(exc); raise
    finally:
        state['stage'] = 'complete'
        (folder/'execution.json').write_text(json.dumps(state, indent=2), encoding='utf-8')
    return state


def main():
    p = argparse.ArgumentParser(description=__doc__); p.add_argument('action', choices=('prepare', 'native', 'prepare-render', 'render', 'admit', 'presentation'))
    for key in ('repo', 'inputs', 'output', 'native', 'godot'):
        p.add_argument('--'+key, type=Path)
    p.add_argument('--rendered', action='store_true'); a = p.parse_args()
    if a.action == 'prepare': result = prepare(a.repo.resolve(), a.inputs.resolve(), a.output.resolve())
    elif a.action == 'prepare-render': result = prepare_render(a.native.resolve(), a.output.resolve())
    elif a.action == 'admit': result = admit(a.output.resolve(), a.rendered)
    elif a.action == 'presentation': result = presentation(a.output.resolve())
    else: result = run(a.output.resolve(), a.godot.resolve(), a.action == 'render')
    print(json.dumps({k:v for k, v in result.items() if k not in ('files', 'cameras', 'helpers')}, indent=2))


if __name__ == '__main__': main()
