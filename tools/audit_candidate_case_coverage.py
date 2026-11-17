"""Admit four raw CI cells and report operation/check gaps; never qualify a release."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath, PureWindowsPath
import subprocess

from check_release_audit import CORES, required_checks, validate_inventory
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


def audit(repo, source, directories):
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
    for p in directories:
        deps.update(b['git_blob'] for b in load(p / 'operation-context.json')['dependencies'].values())
    blobs = read_blobs(repo, sorted(deps))
    cells = [admit_cell(p, inventory, tested_tree, blobs) for p in directories]
    actual = [(c['platform'], c['core_version']) for c in cells]
    if len(actual) != 4 or set(actual) != {(p, c) for p in ('windows', 'linux') for c in CORES}:
        raise ValueError('Four distinct released-core/platform cells required')
    production = {p for p in set(tested_tree) | set(candidate_tree) if p.startswith('addons/godot_ai_animation/')}
    changes = [p for p in sorted(production) if tested_tree.get(p) != candidate_tree.get(p)]
    return {'schema_version': 1, 'kind': 'admitted_candidate_case_gap_ledger',
            'candidate_source': source, 'tested_source': tested_source, 'production_changes': changes,
            'production_blobs_equal': not changes, 'cells': cells,
            'qualification': 'pending', 'release_approved': False,
            'scope': 'Raw CI check-to-case presence only. Refusals/failures retained; no cross-cell folding, visual/source bridge or release approval.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--cell', type=Path, action='append', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Exclusive output already exists')
    result = audit(args.repo, args.source, args.cell)
    with args.output.open('x', encoding='utf-8') as stream:
        json.dump(result, stream, indent=2)
    print('CASE_LEDGER_ADMITTED cells=4 operations=103 production_blobs_equal=%s qualification=pending' % result['production_blobs_equal'])


if __name__ == '__main__':
    main()
