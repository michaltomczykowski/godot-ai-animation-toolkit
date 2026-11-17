"""Admit four raw CI cells and report operation/check gaps; never qualify a release."""
from __future__ import annotations
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path, PurePosixPath, PureWindowsPath
import subprocess

from check_release_audit import CORES, artifact_is_valid, operation_binding_errors, required_checks, validate_inventory
from check_rendered_preview_matrix import verify_identity
from operation_dependencies import source_blobs
from validate_release_package import read_blobs


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def confined(root, name):
    if not isinstance(name, str) or not name or '\\' in name or PureWindowsPath(name).drive:
        raise ValueError('Unsafe artifact path')
    rel = PurePosixPath(name)
    if rel.is_absolute() or '..' in rel.parts:
        raise ValueError('Unsafe artifact path')
    path = (root / name).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file():
        raise ValueError('Artifact absent or outside cell: ' + name)
    return path


def tree(repo, source):
    rows = subprocess.check_output(['git', '-C', str(repo), 'ls-tree', '-r', source], text=True)
    return {row.split('\t', 1)[1]: row.split('\t', 1)[0].split()[2]
            for row in rows.splitlines() if row.split('\t', 1)[0].split()[1] == 'blob'}


def admit_cell(directory, inventory, tested_tree, blobs):
    context_path = directory / 'operation-context.json'
    report_path = directory / 'operation-case-results.json'
    context, report = load(context_path), load(report_path)
    for field in ('tested_source', 'engine', 'platform', 'core_version', 'core_commit', 'dependencies'):
        if context.get(field) != report.get(field):
            raise ValueError('Context/report identity differs: ' + field)
    if report.get('context_sha256') != sha(context_path):
        raise ValueError('Changed trace context')
    if not report.get('engine', '').startswith('4.7.2.stable.official.'):
        raise ValueError('Official Godot 4.7.2 required')
    if report.get('core_commit') != CORES.get(report.get('core_version')) or report.get('platform') not in ('windows', 'linux'):
        raise ValueError('Unknown compatibility cell')
    if context.get('ci_source_identity', {}).get('checkout_sha') != report['tested_source']:
        raise ValueError('Actual checkout identity missing')
    dependencies = report['dependencies']
    # The runtime collector pins executable/resource files. The separate
    # whole-addon comparison below also includes UID and documentation blobs.
    production = {p for p in tested_tree if p.startswith('addons/godot_ai_animation/')
                  and p.endswith(('.gd', '.py', '.json', '.tscn', '.tres', '.cfg', '.godot'))}
    if not production.issubset(dependencies):
        raise ValueError('Incomplete production dependency manifest')
    for rel, binding in dependencies.items():
        blob = tested_tree.get(rel)
        content = blobs.get(blob, b'')
        hashes = {hashlib.sha256(content).hexdigest()}
        if report['platform'] == 'windows' and b'\0' not in content:
            # Checkout filters may expand LF to CRLF while retaining the Git blob.
            hashes.add(hashlib.sha256(content.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')).hexdigest())
        if not blob or blob != binding.get('git_blob') or binding.get('sha256') not in hashes:
            raise ValueError('Dependency identity differs from tested Git source: ' + rel)
    raw, names = [], set()
    for artifact in report.get('raw_artifacts', []):
        name = artifact['path']
        if name in names:
            raise ValueError('Duplicate artifact identity')
        names.add(name)
        path = confined(directory, name)
        digest = sha(path)
        if digest != artifact['sha256']:
            raise ValueError('Changed raw artifact: ' + name)
        raw.append({'path': name, 'sha256': digest, 'role': artifact.get('role')})
    if 'operation-context.json' not in names or not any(a.get('role') == 'raw_public_calls' for a in raw):
        raise ValueError('Missing context/public call artifacts')
    operations = {row['key']: row for row in inventory['operations']}
    cases = report.get('cases', [])
    ids = [case.get('id') for case in cases]
    if not cases or any(not isinstance(i, str) or not i for i in ids) or len(ids) != len(set(ids)):
        raise ValueError('Missing/duplicate case identity')
    for case in cases:
        if case.get('operation') not in operations or not isinstance(case.get('checks'), dict):
            raise ValueError('Unknown operation or absent checks')
        if any(value not in ('pass', 'fail', 'pending') for value in case['checks'].values()):
            raise ValueError('Unknown check status')
    coverage = {}
    for key, row in operations.items():
        selected = [c for c in cases if c['operation'] == key]
        checks = {}
        for name in sorted(required_checks(row['effect_kind'])):
            checks[name] = {state: [c['id'] for c in selected if c['checks'].get(name) == state]
                            for state in ('pass', 'fail', 'pending')}
        coverage[key] = {'checks': checks, 'missing_passing_checks': [n for n, v in checks.items() if not v['pass']]}
    return {'tested_source': report['tested_source'], 'platform': report['platform'],
            'core_version': report['core_version'], 'core_commit': report['core_commit'],
            'engine': report['engine'], 'report': str(report_path), 'report_sha256': sha(report_path),
            'context_sha256': sha(context_path), 'raw_artifacts': raw, 'cases': len(cases),
            'refused_or_failed': [c['id'] for c in cases if c.get('outcome') == 'refused_or_failed'],
            'non_invocation_failures': [{'id': c['id'], 'operation': c['operation'], 'check': n}
                                        for c in cases for n, v in c['checks'].items() if n != 'mcp_invocation' and v == 'fail'],
            'operations': coverage}


def attach_rendered_previews(repo, tested_source, cells, directories):
    """Bind actual positive public preview cases without changing other checks."""
    from operation_preview_adapter import verify_preview_bundle

    expected = {(row['platform'], row['core_version']): row for row in cells}
    bindings = {}
    dependencies = source_blobs(repo, tested_source)
    for directory in directories:
        result = verify_preview_bundle(directory)
        context, proof = result['context'], result['proof']
        key = (context.get('platform'), context.get('core_version'))
        if key not in expected or key in bindings:
            raise ValueError('Unexpected or duplicate rendered preview cell')
        verify_identity(context, tested_source, key[1], dependencies, platform=key[0])
        if context['engine'] != expected[key]['engine']:
            raise ValueError('Rendered preview engine differs from live-route engine')
        # The adapter enforces the non-dry, successful public request/response,
        # in addition to its declared machine checks. It does not assess visuals.
        checks = {'mcp_invocation': 'pass', **proof['checks']}
        if checks != {name: 'pass' for name in required_checks('render') - {'visual_review'}}:
            raise ValueError('Unexpected rendered preview check coverage')
        bindings[key] = {
            'case_id': proof['public_case_id'],
            'checks': checks,
            'directory': str(directory.resolve()),
            'context_sha256': sha(directory / 'context.json'),
            'artifacts': proof['artifacts'],
            'traces': {p.relative_to(directory).as_posix(): sha(p)
                       for p in sorted((directory / 'traces').glob('*.jsonl'))},
        }
    if set(bindings) != set(expected):
        raise ValueError('Require one rendered preview bundle per live-route cell')
    for key, row in expected.items():
        bound = bindings[key]
        item = row['operations']['animation_inspect.preview']
        for check in bound['checks']:
            passing = item['checks'][check]['pass']
            if bound['case_id'] not in passing:
                passing.append(bound['case_id'])
        item['missing_passing_checks'] = [check for check in item['missing_passing_checks']
                                          if check not in bound['checks']]
        item['rendered_preview'] = bound


def attach_preview_visual(cells, tested_source, tested_tree, candidate_tree, receipt):
    """Join the independently reviewed PNGs to their actual preview cases."""
    operation = 'animation_inspect.preview'
    bindings = [cell['operations'][operation].get('rendered_preview') for cell in cells]
    if len(bindings) != 4 or not all(bindings):
        raise ValueError('Preview visual evidence requires all four public preview bundles')
    expected_ids = {binding['case_id'] for binding in bindings}
    evidence = load(receipt)
    dependencies = evidence.get('dependencies', {})
    ids = evidence.get('case_ids', [])
    if (len(expected_ids) != 4 or len(ids) != 4 or set(ids) != expected_ids
            or evidence.get('tested_source') != tested_source or evidence.get('engine') != '4.7.2'
            or evidence.get('scope') != 'candidate' or not dependencies
            or any(tested_tree.get(path) != blob or candidate_tree.get(path) != blob
                   for path, blob in dependencies.items())):
        raise ValueError('Preview visual cases, source or dependencies differ')
    for artifact in evidence.get('artifacts', []):
        if not artifact_is_valid(artifact, receipt.parent):
            raise ValueError('Preview visual artifact is missing or changed')
    errors = operation_binding_errors(evidence, operation, 'visual_review', receipt.parent)
    if errors:
        raise ValueError('; '.join(errors))
    assessments = [artifact for artifact in evidence['artifacts'] if artifact['role'] == 'independent_assessment']
    if len(assessments) != 1:
        raise ValueError('Expected one independent preview assessment artifact')
    rows = load(receipt.parent / assessments[0]['path'])['assessments']
    expected_images = Counter(artifact['sha256'] for binding in bindings for artifact in binding['artifacts']
                              if artifact['role'] == 'rendered_preview_image')
    if (len(rows) != 1 or sum(expected_images.values()) != 16
            or Counter(image['sha256'] for image in rows[0]['media'] if image.get('kind') == 'image')
            != expected_images):
        raise ValueError('Independently reviewed image hashes differ from the four public preview bundles')
    for cell, binding in zip(cells, bindings):
        item = cell['operations'][operation]
        item['checks']['visual_review']['pass'].append(binding['case_id'])
        item['missing_passing_checks'].remove('visual_review')
        item['preview_visual'] = {'receipt': str(receipt.resolve()), 'sha256': sha(receipt)}


RIG_RECORDING_OPERATIONS = frozenset('animation_rig.' + name for name in (
    'pose_apply', 'pose_to_clip', 'walk_cycle', 'idle_breathing', 'blink',
    'jumping_jack', 'squat', 'punch', 'bake_pose_sequence'))


def attach_saved_visual(inventory, tested_source, tested_tree, candidate_tree, blobs, cells,
                        directory, receipt, kind):
    """Admit a saved-scene assessment only in its observed platform/core cell."""
    source = admit_cell(directory, inventory, tested_tree, blobs)
    if source['tested_source'] != tested_source or source['non_invocation_failures']:
        raise ValueError(f'{kind} visual source differs or has derived failures')
    fields = ('platform', 'core_version', 'core_commit', 'engine')
    matched = [cell for cell in cells if all(cell[field] == source[field] for field in fields)]
    if len(matched) != 1:
        raise ValueError(f'{kind} visuals are outside the released matrix')
    expected = {row['key'] for row in inventory['operations']
                if row['key'].startswith(f'animation_{kind}.') and 'visual_review' in required_checks(row['effect_kind'])}
    records = load(receipt)['records']
    keys = {record['operation_key'] for record in records}
    valid_keys = keys == expected if kind == 'graph' else keys <= expected & RIG_RECORDING_OPERATIONS
    if not keys or len(records) != len(keys) or not valid_keys:
        raise ValueError(f'{kind} review has unexpected operation coverage')
    for record in records:
        op = record['operation_key']
        ids = record.get('case_ids', [])
        dependencies = record.get('dependencies', {})
        checks = source['operations'][op]['checks']
        if (record.get('tested_source') != tested_source or record.get('scope') != 'candidate'
                or record.get('engine') != '4.7.2' or len(ids) != 1 or not dependencies
                or any(tested_tree.get(path) != blob or candidate_tree.get(path) != blob
                       for path, blob in dependencies.items())
                or any(ids[0] not in checks[name]['pass'] for name in ('undo_redo', 'save_reopen', 'source_unchanged'))):
            raise ValueError(f'{kind} visual case, source or dependencies differ: ' + op)
        if not all(artifact_is_valid(artifact, receipt.parent) for artifact in record['artifacts']):
            raise ValueError(f'{kind} visual artifact is missing or changed')
        errors = operation_binding_errors(record, op, 'visual_review', receipt.parent)
        if errors:
            raise ValueError('; '.join(errors))
    for record in records:
        item = matched[0]['operations'][record['operation_key']]
        item['checks']['visual_review']['pass'].extend(record['case_ids'])
        item['missing_passing_checks'].remove('visual_review')
        item[kind + '_visual'] = {'receipt': str(receipt.resolve()), 'sha256': sha(receipt),
                                  kind + '_case_report_sha256': source['report_sha256']}


MOTION_EFFECT_KEYS = frozenset('animation_motion.' + name for name in (
    'idle_cycle', 'turn_cycle', 'jump', 'strafe_cycle', 'walk_start', 'walk_stop'))


def attach_motion_effects(inventory, tested_source, tested_tree, blobs, cells, directory):
    """Add only the six independently checked effects in their actual cell."""
    supplement = admit_cell(directory, inventory, tested_tree, blobs)
    if supplement['tested_source'] != tested_source or supplement['non_invocation_failures']:
        raise ValueError('Motion supplement has a foreign source or derived failures')
    matches = [row for row in cells if all(row[k] == supplement[k] for k in
               ('platform', 'core_version', 'core_commit', 'engine'))]
    if len(matches) != 1:
        raise ValueError('Motion supplement is outside the released matrix')
    target = matches[0]
    if 'motion_effect_supplement' in target:
        raise ValueError('Duplicate motion supplement for the same released cell')
    observed = {k: item['checks'].get('valid_effect', {}).get('pass', [])
                for k, item in supplement['operations'].items()}
    if {k for k, values in observed.items() if values} != MOTION_EFFECT_KEYS:
        raise ValueError('Motion supplement does not bind the six intended effects')
    for key in sorted(MOTION_EFFECT_KEYS):
        item = target['operations'][key]
        values = item['checks']['valid_effect']['pass']
        values.extend(case_id for case_id in observed[key] if case_id not in values)
        item['missing_passing_checks'] = [check for check in item['missing_passing_checks']
                                          if check != 'valid_effect']
    target['motion_effect_supplement'] = {
        'report': supplement['report'], 'report_sha256': supplement['report_sha256'],
        'context_sha256': supplement['context_sha256'], 'raw_artifacts': supplement['raw_artifacts'],
        'operations': {k: observed[k] for k in sorted(MOTION_EFFECT_KEYS)},
        'scope': 'Six independent ordinary Responsive dummy cases; this cell only.',
    }


def setup_input_digests(replay, inputs, scene, dependencies):
    pinned = inputs['paths']
    base = inputs.get('path_base')
    if base == 'replay':
        relative_scene = 'inputs/' + scene.removeprefix('res://')
        expected = {relative_scene, 'inputs/models/human_dummy/HumanCharacterDummy_F.fbx',
                    'inputs/tools/check_setup_tree_quality.gd',
                    'inputs/addons/godot_ai_animation/runtime/setup_grounding.gd',
                    'inputs/addons/godot_ai_animation/spec/motion_space.gd'}
        if set(pinned) != expected:
            raise ValueError('Unexpected portable setup inputs')
        for name in expected - {relative_scene}:
            path = name.removeprefix('inputs/')
            dependency = path if path.startswith('addons/') else 'test_project/' + path
            if dependencies.get(dependency, {}).get('sha256') != pinned[name]:
                raise ValueError('Portable setup input differs from the tested context: ' + path)
        paths = {name: confined(replay, name) for name in pinned}
    elif base is None:
        paths = {name: Path(name) for name in pinned}
    else:
        raise ValueError('Unknown setup input path base')
    if len(paths) != 5 or any(sha(path) != pinned[name] for name, path in paths.items()):
        raise ValueError('Setup replay physical inputs changed')
    tail = '/' + scene.removeprefix('res://')
    return [pinned[name] for name, path in paths.items() if path.as_posix().endswith(tail)]


def attach_setup_effect(inventory, tested_source, tested_tree, blobs, cells, replay):
    """Bind a fixed desired-speed replay to the actual saved public setup case."""
    from audit_setup_intent_bridge import REQUEST, SPEC, verify_numeric

    directory = replay.parent
    supplement = admit_cell(directory, inventory, tested_tree, blobs)
    context = load(directory / 'operation-context.json')
    receipt, inputs = load(replay / 'setup-valid-effect.json'), load(replay / 'input.json')
    native, manifest = load(replay / 'native.json'), load(replay / 'fixed-spec.json')
    key = 'animation_motion.character_setup'
    case_id = receipt['public_case_id']
    if (receipt.get('status') != 'pass' or receipt.get('operation') != key
            or supplement['non_invocation_failures']
            or any(value != tested_source for value in (
                supplement['tested_source'], receipt.get('tested_source'), inputs.get('source'),
                native.get('source_head'), manifest.get('source_head')))):
        raise ValueError('Setup supplement has a foreign source, operation or failure')
    for field in ('engine', 'platform', 'core_version'):
        if receipt.get(field) != supplement[field]:
            raise ValueError('Setup replay platform/core/engine differs from public execution')
    if (receipt.get('input_sha256') != sha(replay / 'input.json')
            or receipt.get('native_sha256') != sha(replay / 'native.json')
            or inputs.get('manifest_sha256') != sha(replay / 'fixed-spec.json')
            or native.get('manifest_sha256') != inputs['manifest_sha256']
            or inputs.get('case_report_sha256') != supplement['report_sha256']
            or inputs.get('context_sha256') != supplement['context_sha256']
            or native.get('checker_sha256') != context['dependencies'][
                'test_project/tools/check_setup_tree_quality.gd']['sha256']):
        raise ValueError('Setup replay bound artifacts changed')
    rows = manifest.get('cases', [])
    if (len(rows) != 1 or rows[0].get('id') != 'dummy' or rows[0].get('request') != REQUEST
            or rows[0].get('quality_specs') != [SPEC] or native.get('passed') is not True
            or native.get('failures') != [] or native.get('engine_errors') != []
            or len(native.get('runs', [])) != 3
            or case_id not in supplement['operations'][key]['checks']['mcp_invocation']['pass']):
        raise ValueError('Setup replay must join exactly one real dummy setup and three native clocks')
    if setup_input_digests(replay, inputs, rows[0]['scene'], context['dependencies']) != [rows[0]['scene_sha256']]:
        raise ValueError('Setup replay scene does not match the pinned saved output')
    ordered = inputs.get('raw_case_ids', [])
    if len(ordered) != 4 or len(set(ordered)) != 4 or ordered[1] != case_id:
        raise ValueError('Setup trace must bind dry run, write, save and forced reopen')
    linked = {}
    for raw in supplement['raw_artifacts']:
        if raw['role'] != 'raw_public_calls':
            continue
        with confined(directory, raw['path']).open(encoding='utf-8') as stream:
            for line in stream:
                event = json.loads(line)
                if event.get('id') in ordered:
                    if event['id'] in linked:
                        raise ValueError('Duplicate setup trace case')
                    linked[event['id']] = event
    if set(linked) != set(ordered):
        raise ValueError('Missing setup public trace cases')
    dry, write, save, reopen = [linked[case] for case in ordered]
    if (not all(e.get('scene') == rows[0]['scene'] and e.get('route') == 'public_godot_ai'
                and e.get('context_sha256') == supplement['context_sha256']
                and not e.get('response', {}).get('error') for e in (dry, write, save, reopen))
            or not dry['execution_ns'] < write['execution_ns'] < save['execution_ns'] < reopen['execution_ns']
            or dry.get('params') != dict(REQUEST, dry_run=True) or write.get('params') != REQUEST
            or write.get('response') != rows[0].get('write')
            or save.get('public_tool') != 'scene_save' or reopen.get('public_tool') != 'scene_open'
            or reopen.get('request') != {'path': rows[0]['scene'], 'force_reload': True}
            or reopen.get('response', {}).get('reloaded_from_disk') is not True):
        raise ValueError('Setup public request, saved result or forced reopen changed')
    if verify_numeric(native['runs'], [-1.35006184791564e-5, 0., 1.]) != receipt['observations']:
        raise ValueError('Recomputed setup observation differs')
    matched = [row for row in cells if all(row[k] == supplement[k] for k in
               ('platform', 'core_version', 'core_commit', 'engine'))]
    if len(matched) != 1:
        raise ValueError('Setup supplement is outside the released matrix')
    target = matched[0]['operations'][key]
    if 'setup_effect_supplement' in target:
        raise ValueError('Duplicate setup supplement for the same released cell')
    target['checks']['valid_effect']['pass'].append(case_id)
    target['missing_passing_checks'] = [n for n in target['missing_passing_checks'] if n != 'valid_effect']
    target['setup_effect_supplement'] = {
        'case_id': case_id, 'proof': str(replay / 'setup-valid-effect.json'),
        'proof_sha256': sha(replay / 'setup-valid-effect.json'),
        'report_sha256': supplement['report_sha256'], 'raw_artifacts': supplement['raw_artifacts'],
    }


def audit(repo, source, directories, preview_directories=(), motion_directory=None, setup_replay=None,
          preview_visual=None, graph_cases=None, graph_visual=None, rig_cases=None, rig_visual=None):
    source = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', source + '^{commit}'], text=True).strip()
    inventory = json.loads(subprocess.check_output(['git', '-C', str(repo), 'show', source + ':docs/operation-audit.json']))
    errors = validate_inventory(inventory)
    if errors:
        raise ValueError('; '.join(errors))
    tested = {load(p / 'operation-context.json')['tested_source'] for p in directories}
    if len(tested) != 1:
        raise ValueError('Four cells require one actual tested source')
    tested_source = tested.pop()
    tested_tree, candidate_tree = tree(repo, tested_source), tree(repo, source)
    deps = set()
    motion_directories = (motion_directory,) if isinstance(motion_directory, Path) else motion_directory or ()
    setup_replays = (setup_replay,) if isinstance(setup_replay, Path) else setup_replay or ()
    visual_inputs = {'graph': (graph_cases, graph_visual), 'rig': (rig_cases, rig_visual)}
    extras = [*motion_directories, *(replay.parent for replay in setup_replays)]
    for kind, (directory, receipt) in visual_inputs.items():
        if bool(directory) != bool(receipt):
            raise ValueError(f'{kind} visual evidence requires a public case directory and visual receipt')
        if directory:
            extras.append(directory)
    for p in [*directories, *extras]:
        deps.update(b['git_blob'] for b in load(p / 'operation-context.json')['dependencies'].values())
    blobs = read_blobs(repo, sorted(deps))
    cells = [admit_cell(p, inventory, tested_tree, blobs) for p in directories]
    actual = [(c['platform'], c['core_version']) for c in cells]
    if len(actual) != 4 or set(actual) != {(p, c) for p in ('windows', 'linux') for c in CORES}:
        raise ValueError('Four distinct released-core/platform cells required')
    if preview_directories:
        attach_rendered_previews(repo, tested_source, cells, preview_directories)
    if preview_visual:
        attach_preview_visual(cells, tested_source, tested_tree, candidate_tree, preview_visual)
    for kind, (directory, receipt) in visual_inputs.items():
        if receipt:
            attach_saved_visual(inventory, tested_source, tested_tree, candidate_tree, blobs, cells,
                                directory, receipt, kind)
    for directory in motion_directories:
        attach_motion_effects(inventory, tested_source, tested_tree, blobs, cells, directory)
    for replay in setup_replays:
        attach_setup_effect(inventory, tested_source, tested_tree, blobs, cells, replay)
    for cell in cells:
        cell['required_gaps'] = dict(Counter(
            check for item in cell['operations'].values() for check in item['missing_passing_checks']))
    production = {p for p in set(tested_tree) | set(candidate_tree) if p.startswith('addons/godot_ai_animation/')}
    changes = [p for p in sorted(production) if tested_tree.get(p) != candidate_tree.get(p)]
    return {'schema_version': 1, 'kind': 'admitted_candidate_case_gap_ledger',
            'candidate_source': source, 'tested_source': tested_source, 'production_changes': changes,
            'production_blobs_equal': not changes, 'cells': cells,
            'qualification': 'pending', 'release_approved': False,
            'scope': 'Raw CI and optional exact-source preview, motion and visual assessment bindings. Refusals/failures retained. Qualification remains pending.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--cell', type=Path, action='append', required=True)
    parser.add_argument('--preview', type=Path, action='append', default=[],
                        help='Optional exact-source bundle; if supplied, require all four cells')
    parser.add_argument('--preview-visual', type=Path, help='Independent PNG assessment bound to the four preview cases')
    parser.add_argument('--graph-cases', type=Path, help='Fresh public graph history evidence')
    parser.add_argument('--graph-visual', type=Path, help='Independent recordings bound to the fresh graph cases')
    parser.add_argument('--rig-cases', type=Path, help='Fresh public rig history evidence')
    parser.add_argument('--rig-visual', type=Path, help='Independent recordings bound to the fresh rig cases')
    parser.add_argument('--motion-effects', type=Path, action='append',
                        help='Exact-source six-effect supplement, once per platform/core cell')
    parser.add_argument('--setup-effect', type=Path, action='append',
                        help='Exact-source fixed-speed setup replay, once per platform/core cell')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Exclusive output already exists')
    result = audit(args.repo, args.source, args.cell, args.preview, args.motion_effects, args.setup_effect,
                   args.preview_visual, args.graph_cases, args.graph_visual, args.rig_cases, args.rig_visual)
    with args.output.open('x', encoding='utf-8') as stream:
        json.dump(result, stream, indent=2)
    print('CASE_LEDGER_ADMITTED cells=4 operations=103 production_blobs_equal=%s qualification=pending' % result['production_blobs_equal'])


if __name__ == '__main__':
    main()
