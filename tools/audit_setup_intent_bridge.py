"""Read-only, fixed historical dummy setup intent bridge; never launches Godot.

The original public producer, route reusers, native executor and candidate are
different identities. A candidate-equivalence result never means fresh playback.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess

GROUP = 'responsive-extracted-stationary-no-turn'
NATIVE_SOURCE = '54744b138f0767da317f0f4eeac90e58cf478768'
PUBLIC_SOURCES = ('c19a25e3ea7e574361c239d254e3f45528121795',
                  '233ad02853e74cbd21327954fe4f2086c34faf1d',
                  '233562a776bf8deac6177cf9b67cbe2ae1efdedf')
RUNS = ('production-r003', 'production-r004', 'production-r007')
CORE_SOURCE = 'bfc264200584ea5823f18356acb164781f57796d'
SCENE = 'res://repair_setup_quality/3273f2c51f144757878911b8bea028b6/'+GROUP+'-dummy.tscn'
SCENE_SHA = '209136530e6cc93db46d4ebb31c7012f41806350d5cccae10b4bd917320c7412'
REQUEST = dict(op='character_setup', player_path='/RepairRigFixture/AnimationPlayer',
               skeleton_path='/RepairRigFixture/Dummy/Skeleton3D', include_jump=True,
               include_turn=False, active=False, root_motion=True)
# Fixed historical replay input, not read from response speed_values. It only
# qualifies this desired-ground-speed command against independently integrated
# world travel; it does not certify the omitted generated default walk speed.
SPEC = dict(kind='blend', speed_mps=0.410319762167571, duration_s=6., controller_speed_mps=0.)
TRACE_NAME = '3997ef950c1b425cbc94d5b223e4904d-00c2242597134bcdb39200a2ae05d8f9.jsonl'
PREFIX = 'public-bundles/'+GROUP+'/route.json'
PINS = {
 'native-matrix-r009/execution.json': 'bcd34558dc86014a52cda0e9032975faf18025880b8c95b15ea974813fa6e2e0',
 'native-matrix-r009/independent-validation.json': 'd8d28ca3df6dab1d4e82d0c50412eb2190df36118670f7949b5985c45f285658',
 'native-matrix-r009/'+GROUP+'/native.json': 'e3254561a7ca64a23c37b2d0b89316bb6abcec7b27b5b0e2ca638e9b0aada77d',
 'native-matrix-r009/'+GROUP+'/native.log': 'e88f8952bb7619d9992b3e9d00c8083e73d889ca9e757d19d15ab5adfe294944',
 'production-r003/public-bundles/setup-matrix.json': 'ef2d164a517d3cae44a1491817c43b1efa343cc69789770e667c0f601d3c48d6',
 'production-r003/'+PREFIX: '3ab0a932525b4c5b25dc74aa43106f003418961c144902c40258fb84b3afe3e1',
 'production-r003/operation-context.json': 'afc62f2ac3e863b495a48456a503d3cf1a4892b83523d998ad1c0ffe31ce06e0',
 'production-r003/public-calls/'+TRACE_NAME: '4700731c4ed6855edf387c8caf7043b3e3199521817ce35296aedd5d46ce084a',
 'production-r004/public-bundles/setup-matrix.json': '630ecca88cccf475be6228948d4e1a648faf890caf19a4f54c349331caef62b2',
 'production-r004/'+PREFIX: 'a40598f7ae4d062716545689ffa7cba66b62fa235a1209f33be79bf0aad118c3',
 'production-r004/operation-context.json': 'cfc2a624ccbdacff9fd571d43748fa0ff1061597dbd643a5af3eab53912eeb9a',
 'production-r007/public-bundles/setup-matrix.json': '3569655cdb9d6ee8144e5a9867ab0bead808dee644acac9d40e1b30b0bd529e0',
 'production-r007/'+PREFIX: '9f97862414c8d9d0443eceb7ba622c5be0a09c7494a896183be7985bee94309a',
 'production-r007/operation-context.json': '495f45b796ea20dbd0b8df69174642302b3870776beeef7c4a0a59f1fa9a7ee0',
}
CHANGES = {
 'toolkit/handlers/rig.gd': ('eb9c4f11bbd1ec949e2b4b2d45047ef61d25e6ebfc344433150a0e3f14c16b65', '3f44dc79133f25c88ddcc776e09a56b394ae0e2a55c8a4022f4e0eac4a003950', 'Only rig_pose_list typed directory refusal; setup/rig_profile do not invoke it.'),
 'toolkit/utils/pose_bake_sampler.gd': ('547b490f67f8e22f01a63519e5ddf67e914310b7132dd3159f66ed696cba4671', '0fff38593b6d6ddc96353b9a4a31ec470338e55c5ea2fe2ceffe795836b17e62', 'Only private Spring bake cache priming. This setup generation/native graph playback does not call the bake sampler or include an active Spring.'),
}
ADDITIONS = {'toolkit/utils/spring_bake_cache.gd': 'e9bb4ee26150d7f802446e2c4e6baecca9064e2bb0d1e5014f8f3fa832490715'}
UID = 'addons/godot_ai_animation/utils/spring_bake_cache.gd.uid'
UID_SHA = '445f5369e1f96d491e60ce8b611d9960d0c7dd51f66b6beebff652f4e4df4003'


def need(ok, message):
    if not ok:
        raise ValueError(message)


def sha(raw): return hashlib.sha256(raw).hexdigest()
def number(v): return type(v) in (int, float) and math.isfinite(v)
def vec(v): return isinstance(v, list) and len(v) == 3 and all(number(x) for x in v)
def dot(a, b): return sum(x*y for x, y in zip(a, b))
def norm(v): return math.sqrt(dot(v, v))
def sub(a, b): return [x-y for x, y in zip(a, b)]
def bounded(v, limit): return number(v) and 0 <= v <= limit


def same(a, b):
    if isinstance(a, bool) or isinstance(b, bool): return type(a) is type(b) and a == b
    if number(a) and number(b): return abs(a-b) <= max(abs(a), abs(b))*1e-14
    if type(a) is not type(b): return False
    if isinstance(a, dict): return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    if isinstance(a, list): return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return a == b


def one(values, message):
    need(len(values) == 1, message)
    return values[0]


def read_evidence(setup, project):
    artifacts = {}
    for path, digest in PINS.items():
        raw = (setup/path).read_bytes()
        need(sha(raw) == digest, 'historical bytes changed: '+path)
        artifacts[path] = raw
    raw = (project/SCENE.removeprefix('res://')).read_bytes()
    need(sha(raw) == SCENE_SHA, 'historical saved scene bytes changed')
    result = {'artifacts': {p: sha(v) for p, v in artifacts.items()}, 'scene_text': raw.decode('utf-8-sig')}
    result['execution'] = json.loads(artifacts['native-matrix-r009/execution.json'])
    result['independent'] = json.loads(artifacts['native-matrix-r009/independent-validation.json'])
    result['native'] = json.loads(artifacts['native-matrix-r009/'+GROUP+'/native.json'])
    result['native_log'] = artifacts['native-matrix-r009/'+GROUP+'/native.log'].decode('utf-8-sig')
    result['routes'] = [json.loads(artifacts[r+'/'+PREFIX]) for r in RUNS]
    result['matrices'] = [json.loads(artifacts[r+'/public-bundles/setup-matrix.json']) for r in RUNS]
    result['contexts'] = [json.loads(artifacts[r+'/operation-context.json']) for r in RUNS]
    result['events'] = [json.loads(line) for line in artifacts['production-r003/public-calls/'+TRACE_NAME].decode('utf-8-sig').splitlines()]
    return result


def verify_numeric(runs, forward):
    selected = [r for r in runs if r.get('id') == 'dummy' and same(r.get('spec'), SPEC)]
    need(len(selected) == 3 and {(r.get('fps'), type(r.get('fps'))) for r in selected} == {(f, int) for f in (30, 60, 120)}, 'missing/duplicate/foreign selected blend clocks')
    need(vec(forward) and abs(norm(forward)-1) < 1e-5 and abs(forward[1]) < 1e-5, 'missing independently probed rig forward')
    wanted = [v*SPEC['speed_mps']*SPEC['duration_s'] for v in forward]
    observations = []
    for r in selected:
        fps = r['fps']; frames = 6*fps; leg = r.get('leg_length_m')
        need(number(leg) and leg > 0, 'missing native rig scale')
        need(r.get('passed') is True and r.get('failures') == [] and type(r.get('nonfinite')) is int and r['nonfinite'] == 0, 'native physical failure')
        need(r.get('rooted') is True and r.get('controller_speed_mps') == 0. and r.get('consumer_space') == 'owner_parent', 'wrong translation ownership')
        need(r.get('reset_performed') is False and r.get('reset_witness') == {} and r.get('takes') == [] and type(r.get('extra_prime_signals')) is int and r['extra_prime_signals'] == 0, 'foreign reset/take schedule')
        need(type(r.get('frames')) is int and r['frames'] == frames and number(r.get('elapsed_s')) and abs(r['elapsed_s']-6) < 1e-5, 'wrong native duration/frames')
        need(r.get('modification_processed_signals') == frames, 'missing final grounded output signals')
        trace = r.get('trace'); need(isinstance(trace, list) and len(trace) == frames, 'missing complete actual setup trace')
        consumed = [0., 0., 0.]; contacts = {'l': 0, 'r': 0}; windows = {'l': 0, 'r': 0}; active = {'l': False, 'r': False}
        for index, sample in enumerate(trace):
            need(number(sample.get('time')) and abs(sample['time']-(index+1)/fps) < 1e-5, 'native setup clock differs')
            delta = sample.get('root_delta_parent'); need(vec(delta), 'missing observed extraction delta')
            # Selected saved root/owner have identity transforms, verified below.
            need(norm(sub(delta, [v*SPEC['speed_mps']/fps for v in forward])) <= .0001, 'played setup signed velocity differs from explicit spec')
            consumed = [a+b for a, b in zip(consumed, delta)]
            need(norm(sub(consumed, [v*SPEC['speed_mps']*sample['time'] for v in forward])) <= .0001, 'played setup cumulative trajectory differs from explicit spec')
            need(sample.get('shot_active') is False and number(sample.get('shot_phase')) and sample['shot_phase'] == 0., 'foreign OneShot playback')
            feet = sample.get('feet'); need(isinstance(feet, dict) and set(feet) == {'l', 'r'}, 'missing bilateral setup trace feet')
            for side, foot in feet.items():
                height, contact = foot.get('height_m'), foot.get('declared_contact')
                need(number(height) and type(contact) is bool and height >= -.01*leg and (not contact or abs(height) <= .01*leg), 'played setup ground/contact failure')
                contacts[side] += int(contact); windows[side] += int(contact and not active[side]); active[side] = contact
        need(norm(sub(consumed, wanted)) <= .0001 and vec(r.get('consumer_position')) and norm(sub(consumed, r['consumer_position'])) <= .000001, 'actual extraction consumer/endpoint differs')
        need(number(r.get('actual_world_distance_m')) and abs(r['actual_world_distance_m']-norm(wanted)) <= .0001, 'actual world travel differs from explicit blend request')
        need(r.get('endpoint_reference_available') is True and bounded(r.get('endpoint_error_m'), .0001), 'missing physical endpoint')
        need(all(bounded(r.get(k), .000001) for k in ('extraction_error_m', 'unconsumed_actor_change_m', 'grounded_root_delta_world_m')), 'competing translation owner')
        need(number(r.get('max_bone_speed_legs_per_s')) and .000001 < r['max_bone_speed_legs_per_s'] <= 10 and number(r.get('max_bone_angular_speed_rad_s')) and r['max_bone_angular_speed_rad_s'] >= 0, 'inert/nonfinite/discontinuous setup poses')
        need(bounded(r.get('recovery_position_error_m'), min(.01*leg, .01)) and bounded(r.get('recovery_rotation_error_rad'), .01), 'native recovery failed')
        feet = r.get('feet'); need(isinstance(feet, dict) and set(feet) == {'l', 'r'}, 'missing native foot predicates')
        for side, foot in feet.items():
            need(type(foot.get('knee_flips')) is int and foot['knee_flips'] == 0 and foot.get('frames') == contacts[side] > 0 and foot.get('windows') == windows[side] > 0, 'native contact/knee coverage differs')
            need(bounded(foot.get('slide'), min(.02*leg, .03)) and bounded(foot.get('penetration'), .01*leg) and bounded(foot.get('height'), .01*leg), 'native foot physical budget failed')
        g = r.get('grounding', {})
        need(g.get('contract_version') == 1 and g.get('error') == '' and g.get('status') == 'grounded' and g.get('unreachable') == 0 and g.get('evaluations') == frames and g.get('resets') == 2 and g.get('reset_reason') == 'inactive_tree', 'grounding diagnostics/schedule differ')
        need(number(g.get('target_tolerance_m')) and abs(g['target_tolerance_m']-1e-5) < 1e-12 and bounded(g.get('evaluation_residual_m'), 1e-5) and bounded(g.get('max_residual_m'), 1e-5) and bounded(g.get('max_correction_m'), .25*leg), 'grounding residual/correction failure')
        observations.append(dict(fps=fps, frames=frames, observed_world_vector_m=consumed, requested_distance_m=norm(wanted), actual_world_distance_m=r['actual_world_distance_m']))
    return observations


def verify_evidence(b):
    e, native, routes, matrices, contexts = (b[k] for k in ('execution', 'native', 'routes', 'matrices', 'contexts'))
    need(len(routes) == len(matrices) == len(contexts) == 3, 'incomplete original public reuse chain')
    need(e.get('kind') == 'saved_setup_native_replay' and e.get('state') == 'complete' and e.get('native_source') == NATIVE_SOURCE and e.get('public_source') == PUBLIC_SOURCES[-1], 'historical native executor/route source differs')
    need(len(e.get('groups', [])) == 30 and e.get('plays') == 1800 and len({g.get('id') for g in e['groups']}) == 30, 'historical fullmatrix identity differs')
    groups = [g for g in e['groups'] if g.get('id') == GROUP]; group = one(groups, 'selected native group missing/duplicate')
    need(group.get('returncode') == 0 and group.get('passed') is True and group.get('failures') == [] and group.get('engine_errors') == [], 'native selected group failure')
    need(group.get('route_sha256') == PINS[RUNS[-1]+'/'+PREFIX] and group.get('native_sha256') == PINS['native-matrix-r009/'+GROUP+'/native.json'] and group.get('log_sha256') == PINS['native-matrix-r009/'+GROUP+'/native.log'], 'native group/report/route bytes differ')
    deps = e.get('production_dependencies', {})
    need(len(deps) == 613 and sum(k.startswith('core/') for k in deps) == 567 and sum(k.startswith('toolkit/') for k in deps) == 46, 'incomplete production dependency map')
    need(e.get('public_matrix_sha256') == PINS[RUNS[-1]+'/public-bundles/setup-matrix.json'], 'native public matrix identity differs')
    selected = []
    for i, (route, matrix, context) in enumerate(zip(routes, matrices, contexts)):
        need(route.get('source_head') == matrix.get('source_head') == context.get('tested_source') == PUBLIC_SOURCES[i], 'public producer/reuse source relabeled')
        need(matrix.get('production_dependencies') == deps and route.get('operation') == 'character_setup' and route.get('revision') == 'setup-'+GROUP and route.get('passed') is True, 'reuse production/source/group mismatch')
        row = one([r for r in route.get('cases', []) if r.get('id') == 'dummy'], 'selected public dummy missing/duplicate')
        need(same(row.get('request'), REQUEST) and same(row.get('params'), REQUEST) and row.get('scene') == SCENE and row.get('scene_sha256') == SCENE_SHA and row.get('passed') is True and row.get('player') == 'AnimationPlayer' and row.get('skeleton') == 'Dummy/Skeleton3D' and row.get('synthetic') is False, 'original public request/rig/scene differs')
        if i:
            need(str(row.get('reused_from', '')).replace('\\', '/').endswith('/'+RUNS[i-1]+'/'+PREFIX), 'reuse chain differs')
            need(same({k:v for k,v in row.items() if k != 'reused_from'}, {k:v for k,v in selected[0].items() if k != 'reused_from'}), 'reuse changed original public row')
        else: need(not row.get('reused_from'), 'original public row is itself reused')
        need(context.get('core_commit') == CORE_SOURCE and context.get('core_version') == '4.2.1' and context.get('core_qualification') == 'released' and context.get('engine') == '4.7.2.stable.official.ed1daf0bf', 'historical runtime identity differs')
        selected.append(row)
    original = selected[0]; ctx = contexts[0]
    need(native.get('source_head') == PUBLIC_SOURCES[-1] and native.get('manifest_sha256') == group['route_sha256'] and native.get('checker_sha256') == e['checker_dependencies']['test_project/tools/check_setup_tree_quality.gd'], 'native report inherited route/checker identity differs')
    need(native.get('passed') is True and native.get('failures') == [] and native.get('engine_errors') == [] and len(native.get('runs', [])) == 60, 'native group physical failure/incomplete')
    log = b['native_log']; need('Godot Engine v4.7.2.stable.official.ed1daf0bf' in log and 'ERROR:' not in log, 'native engine log differs')
    summaries = [json.loads(line.split('=', 1)[1]) for line in log.splitlines() if line.startswith('SETUP_TREE_QUALITY=')]
    need(summaries == [dict(engine_errors=[], failures=[], passed=True, runs=60)], 'native log lacks exact completion')
    events = b['events']; matches = [v for v in events if v.get('kind') == 'public_operation_call' and v.get('operation') == 'animation_motion.character_setup' and v.get('scene') == SCENE and same(v.get('params'), REQUEST) and v.get('response') == original['write']]
    made = one(matches, 'original actual public call missing/duplicate')
    need(made.get('request') == {'op':'invoke', 'params': {'tool_name':'animation_motion', 'params': REQUEST}} and made.get('public_tool') == 'custom_manage', 'original public invocation envelope differs')
    save = one([v for v in events if v.get('public_tool') == 'scene_save' and v.get('scene') == SCENE and v.get('response') == original['save']], 'original public save missing/duplicate')
    reopen = one([v for v in events if v.get('public_tool') == 'scene_open' and v.get('request') == {'path':SCENE, 'force_reload':True} and v.get('response') == original['reopen']], 'original forced reload missing/duplicate')
    profile = one([v for v in events if v.get('operation') == 'animation_inspect.rig_profile' and v.get('scene') == SCENE and v.get('response') == original['profile']], 'independent original rig profile absent')
    for v in (made, save, reopen, profile):
        need(v.get('context_sha256') == PINS[RUNS[0]+'/operation-context.json'] and v.get('run_id') == ctx.get('run_id') and v.get('driver') == 'mcp_setup_quality_review.py' and v.get('route') == 'public_godot_ai', 'original public event context/source differs')
    need(profile['execution_ns'] < made['execution_ns'] < save['execution_ns'] < reopen['execution_ns'] and reopen['response'].get('reloaded_from_disk') is True, 'public source/save/reload order differs')
    need(original['profile'].get('roles') == original.get('roles') and original.get('roles_source') == 'public animation_inspect rig_profile(save=false)', 'original measured role binding differs')
    # Identity root and Dummy make recorded owner-parent deltas world vectors.
    text = b['scene_text']
    for name in ('RepairRigFixture', 'Dummy'):
        blocks = re.findall(r'(?ms)^\[node name="'+name+r'"[^\n]*\]\s*\n(.*?)(?=^\[|\Z)', text)
        need(len(blocks) == 1 and not re.search(r'(?m)^(transform|position|rotation|scale|top_level)\s*=', blocks[0]), 'selected scene owner-parent world transform changed')
    external = set(re.findall(r'\[ext_resource[^\n]*path="([^"]+)"', text))
    need(external == {'res://models/human_dummy/HumanCharacterDummy_F.fbx', 'res://addons/godot_ai_animation/runtime/setup_grounding.gd'}, 'foreign saved scene dependency')
    frame = original['profile']['axes']['forward']; forward = [frame[k] for k in ('x','y','z')]
    numeric = verify_numeric(native['runs'], forward)
    return dict(checks={'valid_effect':'pass'}, original_public_event_ids=[v['id'] for v in (profile, made, save, reopen)], selected_spec=SPEC, native_observations=numeric, production_dependencies=deps, original_scene_sha256=SCENE_SHA)


def git_bytes(repo, source, paths):
    paths = list(paths)
    result = subprocess.run(['git', 'cat-file', '--batch'], cwd=repo,
        input=''.join(source+':'+p+'\n' for p in paths).encode(), capture_output=True, check=True)
    raw = result.stdout; at = 0; values = {}
    for path in paths:
        end = raw.index(b'\n', at); header = raw[at:end].split()
        need(len(header) == 3 and header[1] == b'blob', 'historical git source dependency missing: '+path)
        size = int(header[2]); start = end+1; values[path] = raw[start:start+size]; at = start+size+1
    need(at == len(raw), 'ambiguous git source stream')
    return values


def source_matches(raw, digest):
    # Windows receipts hash checked-out CRLF bytes; Git stores LF. This only
    # verifies source bytes, never rounds or transforms physical observations.
    lf = raw.replace(b'\r\n', b'\n')
    return digest in {sha(raw), sha(lf), sha(lf.replace(b'\n', b'\r\n'))}


def production_inventory(repo, core):
    result = {}
    for label, root in (('toolkit', repo/'addons/godot_ai_animation'), ('core', core)):
        for p in root.rglob('*'):
            if p.is_file() and p.suffix in {'.gd','.py','.cfg','.json'} and not any(x in {'.git','.godot','.venv','__pycache__','node_modules'} for x in p.relative_to(root).parts):
                result[label+'/'+p.relative_to(root).as_posix()] = sha(p.read_bytes())
    return result


def verify_candidate_dependencies(recorded, current):
    need(set(current) == set(recorded)|set(ADDITIONS), 'candidate production dependency inventory differs')
    changed = []
    for path, digest in recorded.items():
        if path in CHANGES:
            old, new, rationale = CHANGES[path]
            need(digest == old and current[path] == new, 'unreviewed candidate source change: '+path)
            changed.append(dict(path=path, historical_sha256=old, candidate_sha256=new, scope_reason=rationale))
        else: need(current[path] == digest, 'candidate production dependency differs: '+path)
    need(all(current[p] == h for p,h in ADDITIONS.items()), 'candidate Spring helper bytes differ')
    return changed


def audit(args):
    b = read_evidence(args.setup_root, args.project_root); proof = verify_evidence(b)
    candidate = subprocess.check_output(['git','rev-parse','HEAD'], cwd=args.repo, text=True).strip()
    core_source = subprocess.check_output(['git','rev-parse','HEAD'], cwd=args.core_root, text=True).strip()
    need(core_source == CORE_SOURCE, 'candidate released core commit differs')
    inventory = production_inventory(args.repo, args.core_root)
    changes = verify_candidate_dependencies(proof['production_dependencies'], inventory)
    toolkit = {k.removeprefix('toolkit/'):v for k,v in proof['production_dependencies'].items() if k.startswith('toolkit/')}
    for source in PUBLIC_SOURCES+(NATIVE_SOURCE,):
        files = git_bytes(args.repo, source, ['addons/godot_ai_animation/'+p for p in toolkit])
        need(all(source_matches(files['addons/godot_ai_animation/'+p], h) for p,h in toolkit.items()), 'historical operative toolkit source differs: '+source)
    checker = b['execution']['checker_dependencies']; files = git_bytes(args.repo, NATIVE_SOURCE, checker)
    need(all(source_matches(files[p], h) for p,h in checker.items()), 'historical native checker dependencies differ')
    need(all(sha((args.repo/p).read_bytes()) == h for p,h in checker.items()), 'candidate native checker dependency changed')
    core = {p.removeprefix('core/'):h for p,h in inventory.items() if p.startswith('core/')}
    files = git_bytes(args.core_root, CORE_SOURCE, core)
    need(all(source_matches(files[p],h) for p,h in core.items()), 'released core source bytes differ')
    candidate_files = {'addons/godot_ai_animation/'+p.removeprefix('toolkit/'):h for p,h in inventory.items() if p.startswith('toolkit/')}
    files = git_bytes(args.repo, candidate, candidate_files)
    need(all(source_matches(files[p],h) for p,h in candidate_files.items()), 'candidate working production bytes differ from committed source')
    need(sha((args.repo/UID).read_bytes()) == UID_SHA and source_matches(git_bytes(args.repo,candidate,[UID])[UID],UID_SHA), 'new Spring helper UID source differs')
    original_context = b['contexts'][0]
    model = 'test_project/models/human_dummy/HumanCharacterDummy_F.fbx'
    original_model_sha = sha(git_bytes(args.repo,PUBLIC_SOURCES[0],[model])[model])
    need(sha((args.project_root/'models/human_dummy/HumanCharacterDummy_F.fbx').read_bytes()) == original_model_sha and sha((args.repo/model).read_bytes()) == original_model_sha, 'original/current dummy rig source bytes differ')
    need(all(sha(git_bytes(args.repo,source,[model])[model]) == original_model_sha for source in PUBLIC_SOURCES[1:]+(NATIVE_SOURCE,candidate)), 'historical/candidate committed dummy source differs')
    need(sha((args.project_root/'addons/godot_ai_animation/runtime/setup_grounding.gd').read_bytes()) == proof['production_dependencies']['toolkit/runtime/setup_grounding.gd'], 'saved project grounding helper changed')
    diff = subprocess.check_output(['git','diff',NATIVE_SOURCE,candidate,'--','addons/godot_ai_animation/handlers/rig.gd','addons/godot_ai_animation/utils/pose_bake_sampler.gd','addons/godot_ai_animation/utils/spring_bake_cache.gd'],cwd=args.repo,text=True)
    return dict(schema_version=1, kind='scoped_historical_setup_intent_bridge', operation='animation_motion.character_setup',
        candidate_source=candidate, original_public_source=PUBLIC_SOURCES[0], route_reuse_sources=list(PUBLIC_SOURCES[1:]), native_executor_source=NATIVE_SOURCE,
        native_report_route_source=b['native']['source_head'], candidate_execution='not_run; source equivalence bridge only',
        group=GROUP, checks={'valid_effect':'pending'}, historical_effect_checks=proof['checks'], selected_spec=SPEC, original_public_event_ids=proof['original_public_event_ids'], native_observations=proof['native_observations'],
        original_scene=SCENE, original_scene_sha256=SCENE_SHA, original_fullmatrix=dict(groups=30,plays=1800,execution_sha256=PINS['native-matrix-r009/execution.json'],scope='historical matrix identity retained; this auditor rechecks only selected three blend plays'),
        dependency_comparison=dict(recorded=613,core_exact=567,toolkit_exact=44,toolkit_changed=changes,toolkit_added=ADDITIONS,new_helper_uid_sha256=UID_SHA,exact_source_diff=diff),
        historical_source_content='All46 toolkit dependencies verified at original producer, both reusers and native executor; native checker4 verified at native source; core567 verified against released source. Checked-out CRLF source hashes retain their original values.',
        original_matrix_statuses=[dict(source=m['source_head'],state=m['state'],passed=m['passed']) for m in b['matrices']],
        model_source_sha256=original_model_sha, missing_joins=['Original public context and r009 native report omit contemporaneous FBX/imported-cache/rest hashes. Committed source and present bytes match, but actual historical loaded rig bytes are unbound. Run one freshly imported current three-FPS blend replay to close this join.'],
        artifacts=b['artifacts'], auditor_sha256=sha(Path(__file__).read_bytes()),
        limits='One original dummy setup saved scene and explicit desired-ground-speed blend spec at30/60/120FPS. No fresh candidate runtime, omitted default speed selection, jump/turn/reset/takes, other rigs/styles, visuals or Linux qualification. No source/history channel promotion. Original r004 overall matrix failure retained; selected immutable route reuse is separately bound.')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('repo','core-root','setup-root','project-root','output'):p.add_argument('--'+name,type=Path,required=True)
    args = p.parse_args()
    need(not args.output.exists(), 'preserve prior bridge output')
    report = audit(args)
    with args.output.open('x',encoding='utf-8') as stream:json.dump(report,stream,indent=2)
    print(json.dumps({k:report[k] for k in ('kind','candidate_source','original_public_source','native_executor_source','checks')}))
    return 0


if __name__ == '__main__':raise SystemExit(main())
