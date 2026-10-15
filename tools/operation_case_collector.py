"""Exact public-call traces and a conservative operation_case_results collector.

No suite-total inference. This first collector emits mcp_invocation only.
Semantic/history/native checks must be attached by their actual validators.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time
import uuid
from check_release_audit import EXPECTED_OPERATIONS, CORES

_context_cache = None
_trace_file = None
_sequence = 0

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root, text=True).strip()

def operation_key(name, params):
    if name == 'custom_manage' and params.get('op') == 'invoke':
        inner = params.get('params', {})
        family = inner.get('tool_name', '')
        args = inner.get('params', {})
    else:
        family = name.removeprefix('custom_') if name.startswith('custom_') else ''
        args = params
    key = family + '.' + str(args.get('op', ''))
    return (key, args) if key in EXPECTED_OPERATIONS else (None, args)

def prepare(root, core_root, godot, output):
    root = root.resolve()
    source = git(root, 'rev-parse', 'HEAD')
    core_commit = git(core_root, 'rev-parse', 'HEAD')
    core_version = next((v for v, commit in CORES.items() if commit == core_commit), None)
    if git(core_root, 'diff', '--name-only', 'HEAD'):
        raise ValueError('core checkout has tracked changes')
    actual_platform = {'Windows':'windows','Linux':'linux'}.get(platform.system(), platform.system().lower())
    engine = subprocess.run([str(godot), '--version'], capture_output=True, text=True, check=True)
    engine_raw = engine.stdout.strip()
    if not engine_raw.startswith('4.7.2.'):
        raise ValueError('qualification requires actual Godot4.7.2 version output')
    paths = git(root, 'ls-tree', '-r', '--name-only', source, '--',
                'addons/godot_ai_animation', 'tools', 'test_project/tests', 'test_project/tools').splitlines()
    deps = {}
    for rel in paths:
        if rel.endswith('.uid') or not rel.endswith(('.gd','.py','.json','.tscn','.tres','.cfg','.godot')):
            continue
        path = root / rel
        blob = git(root, 'rev-parse', source+':'+rel)
        if not path.is_file() or git(root, 'hash-object', '--path', rel, str(path)) != blob:
            raise ValueError('tested source differs from committed dependency: '+rel)
        deps[rel] = {'git_blob':blob, 'sha256':sha(path)}
    if 'tools/operation_case_collector.py' not in deps:
        raise ValueError('collector must be committed in the tested source')
    context = {'schema_version':1, 'kind':'operation_trace_context',
               'run_id':uuid.uuid4().hex, 'tested_source':source,
               'platform':actual_platform, 'core_version':core_version,
               'core_commit':core_commit, 'core_qualification':'released' if core_version else 'advisory',
               'engine':engine_raw, 'engine_version_stdout':engine.stdout,
               'engine_version_stderr':engine.stderr, 'dependencies':deps,
               'trace_producer_sha256':sha(__file__)}
    with output.open('x', encoding='utf-8') as f:
        json.dump(context, f, indent=2)
    return context

def record_public_call(name, params, response):
    """Called only AFTER the shared public MCP call completed; no caller mutations."""
    global _context_cache, _trace_file, _sequence
    context_path = os.environ.get('TOOLKIT_OPERATION_CONTEXT')
    trace_root = os.environ.get('TOOLKIT_OPERATION_TRACE_DIR')
    if not context_path and not trace_root:
        return
    if not context_path or not trace_root:
        raise RuntimeError('both operation trace environment variables are required')
    key, actual_params = operation_key(name, params)
    if key is None:
        return
    if _context_cache is None:
        context = json.loads(Path(context_path).read_text(encoding='utf-8'))
        if context.get('trace_producer_sha256') != sha(__file__):
            raise RuntimeError('trace producer changed after context preparation')
        _context_cache = context, sha(context_path)
        directory = Path(trace_root)
        directory.mkdir(parents=True, exist_ok=True)
        _trace_file = directory / (context['run_id']+'-'+uuid.uuid4().hex+'.jsonl')
    context, context_sha = _context_cache
    _sequence += 1
    event = {'schema_version':1, 'kind':'public_operation_call',
             'context_sha256':context_sha, 'run_id':context['run_id'],
             'id':_trace_file.stem+':'+str(_sequence), 'sequence':_sequence,
             'operation':key, 'public_tool':name, 'request':params, 'params':actual_params,
             'response':response, 'time_ns':time.time_ns(),
             'driver':Path(sys.argv[0]).name, 'route':'public_godot_ai'}
    with _trace_file.open('a', encoding='utf-8') as f:
        f.write(json.dumps(event, sort_keys=True)+'\n')

def collect(context_path, traces, root):
    context = json.loads(context_path.read_text(encoding='utf-8'))
    if context.get('kind') != 'operation_trace_context' or not context.get('dependencies'):
        raise ValueError('invalid trace context')
    if context.get('trace_producer_sha256') != sha(__file__):
        raise ValueError('collector/trace producer identity changed')
    for rel, identity in context['dependencies'].items():
        path = root / rel
        if not path.is_file() or sha(path) != identity['sha256']:
            raise ValueError('dependency changed during execution: '+rel)
        if git(root, 'rev-parse', context['tested_source']+':'+rel) != identity['git_blob']:
            raise ValueError('source blob mismatch: '+rel)
    cases, seen, successful = [], set(), set()
    artifacts = [{'path':context_path.name,'sha256':sha(context_path),'role':'trace_context'}]
    for path in sorted(traces.glob('*.jsonl')):
        portable_path = path.resolve().relative_to(context_path.parent.resolve()).as_posix()
        artifacts.append({'path':portable_path, 'sha256':sha(path), 'role':'raw_public_calls'})
        previous = 0
        for line in path.read_text(encoding='utf-8').splitlines():
            event = json.loads(line)
            if event.get('kind') != 'public_operation_call' or event.get('context_sha256') != sha(context_path) or event.get('run_id') != context['run_id']:
                raise ValueError('foreign or unbound call event')
            if event.get('id') in seen or event.get('sequence') != previous+1:
                raise ValueError('duplicate/out-of-order call event')
            seen.add(event['id']); previous += 1
            operation = event.get('operation')
            if operation not in EXPECTED_OPERATIONS or event.get('route') != 'public_godot_ai':
                raise ValueError('invalid operation or route')
            rebound, _ = operation_key(event.get('public_tool',''), event.get('request',{}))
            if rebound != operation:
                raise ValueError('operation differs from actual request')
            response = event.get('response')
            okay = isinstance(response, dict) and bool(response) and not response.get('error')
            dry = event.get('params',{}).get('dry_run') is True
            checks = {'mcp_invocation':'pass' if okay else 'fail'} if not dry else {}
            if okay and not dry:
                successful.add(operation)
            cases.append({'id':event['id'], 'operation':operation, 'checks':checks,
                          'scope':'candidate', 'route':'public_godot_ai',
                          'driver':event['driver'], 'raw_event_id':event['id'],
                          'outcome':'dry_run' if dry else 'success' if okay else 'refused_or_failed'})
    return {'schema_version':1, 'kind':'operation_case_results',
            'tested_source':context['tested_source'], 'engine':context['engine'],
            'platform':context['platform'], 'core_version':context['core_version'],
            'core_commit':context['core_commit'], 'core_qualification':context['core_qualification'],
            'context_sha256':sha(context_path), 'dependencies':context['dependencies'],
            'raw_artifacts':artifacts, 'cases':cases,
            'successful_public_operations':sorted(successful),
            'missing_successful_public_operations':sorted(EXPECTED_OPERATIONS-successful),
            'qualification':'pending', 'visual_review':'pending',
            'limits':'Only actual successful public non-dry invocation is derived. No semantic/history/playback checks inferred from suite totals.'}

def main():
    p = argparse.ArgumentParser(description=__doc__)
    commands=p.add_subparsers(dest='command',required=True)
    init=commands.add_parser('prepare')
    init.add_argument('--root',type=Path,required=True)
    init.add_argument('--core-root',type=Path,required=True)
    init.add_argument('--godot',type=Path,required=True)
    init.add_argument('--output',type=Path,required=True)
    out=commands.add_parser('collect')
    out.add_argument('--context',type=Path,required=True)
    out.add_argument('--trace-dir',type=Path,required=True)
    out.add_argument('--root',type=Path,required=True)
    out.add_argument('--output',type=Path,required=True)
    out.add_argument('--allow-partial',action='store_true')
    a=p.parse_args()
    if a.command=='prepare':
        prepare(a.root,a.core_root,a.godot,a.output)
        return 0
    report=collect(a.context,a.trace_dir,a.root)
    with a.output.open('x',encoding='utf-8') as f:
        json.dump(report,f,indent=2)
    print(json.dumps({'public_operations':len(report['successful_public_operations']),
                      'missing':report['missing_successful_public_operations']}))
    return 0 if a.allow_partial or (not report['missing_successful_public_operations'] and report['core_qualification']=='released') else 2
if __name__=='__main__':
    raise SystemExit(main())
