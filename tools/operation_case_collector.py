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
_active_scene = ""

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
               'engine':engine_raw, 'engine_command':str(godot), 'engine_version_stdout':engine.stdout,
               'engine_version_stderr':engine.stderr, 'dependencies':deps,
               'trace_producer_sha256':sha(__file__)}
    with output.open('x', encoding='utf-8') as f:
        json.dump(context, f, indent=2)
    return context

def _emit(kind, values):
    global _context_cache, _trace_file, _sequence
    context_path = os.environ.get('TOOLKIT_OPERATION_CONTEXT')
    trace_root = os.environ.get('TOOLKIT_OPERATION_TRACE_DIR')
    if not context_path and not trace_root:
        return
    if not context_path or not trace_root:
        raise RuntimeError('both operation trace environment variables are required')
    context_sha = sha(context_path)
    if _context_cache is None or _context_cache[1] != context_sha:
        context = json.loads(Path(context_path).read_text(encoding='utf-8'))
        if context.get('trace_producer_sha256') != sha(__file__):
            raise RuntimeError('trace producer changed after context preparation')
        _context_cache = context, context_sha
        directory = Path(trace_root)
        directory.mkdir(parents=True, exist_ok=True)
        _trace_file = directory / (context['run_id']+'-'+uuid.uuid4().hex+'.jsonl')
        _sequence = 0
    context, context_sha = _context_cache
    _sequence += 1
    event = {'schema_version':1, 'kind':kind,
             'context_sha256':context_sha, 'run_id':context['run_id'],
             'id':_trace_file.stem+':'+str(_sequence), 'sequence':_sequence,
             'time_ns':time.time_ns(), 'execution_ns':time.perf_counter_ns(), 'driver':Path(sys.argv[0]).name, **values}
    with _trace_file.open('a', encoding='utf-8') as f:
        f.write(json.dumps(event, sort_keys=True)+'\n')


def record_public_call(name, params, response):
    """Called only AFTER the shared public MCP call completed; no caller mutations."""
    global _active_scene
    if name == 'scene_open' and isinstance(response, dict) and not response.get('error'):
        _active_scene = params.get('path', '')
    key, actual_params = operation_key(name, params)
    if key is not None:
        _emit('public_operation_call', {'operation':key, 'public_tool':name,
              'request':params, 'params':actual_params, 'response':response,
              'scene':_active_scene, 'route':'public_godot_ai'})


def record_native_result(operation, scene, command, completed):
    """Record the actual completed subprocess, never a caller-supplied pass flag."""
    if not os.environ.get('TOOLKIT_OPERATION_CONTEXT') and not os.environ.get('TOOLKIT_OPERATION_TRACE_DIR'):
        return
    _emit('native_saved_output', {'operation':operation, 'scene':scene,
          'command':[str(part) for part in command], 'returncode':completed.returncode,
          'stdout':completed.stdout, 'stderr':completed.stderr, 'route':'native_godot'})


def native_fx_checks(event, context):
    """Narrow adapter for the actual FX runtime checker; no generic green output."""
    operation = event['operation']
    if not operation.startswith('animation_fx.'):
        raise ValueError('native FX adapter cannot qualify another family')
    command = event.get('command', [])
    if not command or command[0] != context.get('engine_command'):
        raise ValueError('native engine command differs from actual version probe')
    try:
        script = command[command.index('--script')+1]
        args = command[command.index('--')+1:]
    except (ValueError, IndexError):
        raise ValueError('native command does not identify checker and case')
    source_path = 'test_project/tools/check_fx_runtime.gd'
    if script != 'res://tools/check_fx_runtime.gd' or source_path not in context['dependencies']:
        raise ValueError('native checker is not bound to tested source')
    if len(args) < 2 or args[0] != event['scene']:
        raise ValueError('native command scene differs from case')
    op = args[1]
    canonical_op = 'sprite_frames' if op == 'sprite_frames_stopped' else op
    if operation != 'animation_fx.'+canonical_op:
        raise ValueError('native command operation differs from case')
    prefix = 'FX_RUNTIME='
    payloads = [line[len(prefix):] for line in event.get('stdout','').splitlines() if line.startswith(prefix)]
    if len(payloads) != 1:
        checks = {'playback':'fail'}
        if canonical_op != 'sprite_frames': checks['track_paths_types'] = 'fail'
        return checks, ['missing or ambiguous native JSON result']
    report = json.loads(payloads[0])
    if report.get('op') != op or report.get('scene') != event['scene']:
        raise ValueError('native output operation/scene differs from executed command')
    errors = event.get('stdout','')+'\n'+event.get('stderr','')
    passed = (event.get('returncode') == 0 and report.get('failures') == []
              and isinstance(report.get('checks'),list) and bool(report['checks'])
              and 'SCRIPT ERROR:' not in errors and 'ERROR:' not in errors)
    status = 'pass' if passed else 'fail'
    checks = {'playback':status}
    if canonical_op != 'sprite_frames': checks['track_paths_types'] = status
    return checks, [] if passed else ['actual native checker failed or reported an engine error']


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
    public_events, native_events = [], []
    artifacts = [{'path':context_path.name,'sha256':sha(context_path),'role':'trace_context'}]
    for path in sorted(traces.glob('*.jsonl')):
        portable_path = path.resolve().relative_to(context_path.parent.resolve()).as_posix()
        artifacts.append({'path':portable_path, 'sha256':sha(path), 'role':'raw_public_calls'})
        previous = 0
        for line in path.read_text(encoding='utf-8').splitlines():
            event = json.loads(line)
            if event.get('kind') not in {'public_operation_call','native_saved_output'} or event.get('context_sha256') != sha(context_path) or event.get('run_id') != context['run_id']:
                raise ValueError('foreign or unbound call event')
            if event.get('id') in seen or event.get('sequence') != previous+1:
                raise ValueError('duplicate/out-of-order call event')
            seen.add(event['id']); previous += 1
            if event['kind'] == 'native_saved_output':
                native_events.append(event)
                continue
            public_events.append(event)
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
    for event in native_events:
        if event.get('operation') not in EXPECTED_OPERATIONS or event.get('route') != 'native_godot':
            raise ValueError('invalid native operation or route')
        checks, failures = native_fx_checks(event, context)
        matches = [call for call in public_events
                   if call['operation'] == event['operation'] and call.get('scene') == event.get('scene')
                   and call['execution_ns'] < event['execution_ns']
                   and isinstance(call.get('response'),dict) and bool(call['response'])
                   and not call['response'].get('error') and not call.get('params',{}).get('dry_run')]
        if not matches:
            checks = {key:'fail' for key in checks}
            failures.append('native output lacks a prior successful public call for this exact operation and scene')
        origin = max(matches,key=lambda call:call['time_ns']) if matches else None
        cases.append({'id':event['id'],'operation':event['operation'],'checks':checks,
                      'scope':'candidate','route':'public_output_native_godot',
                      'public_case_ids':[origin['id']] if origin else [],
                      'raw_event_id':event['id'],'scene':event['scene'],'failures':failures,
                      'limits':'FX native playback/path/type checks only. Audio means observed native playing event; audible output and visual assessment remain separate.'})
    return {'schema_version':1, 'kind':'operation_case_results',
            'tested_source':context['tested_source'], 'engine':context['engine'],
            'platform':context['platform'], 'core_version':context['core_version'],
            'core_commit':context['core_commit'], 'core_qualification':context['core_qualification'],
            'context_sha256':sha(context_path), 'dependencies':context['dependencies'],
            'raw_artifacts':artifacts, 'cases':cases,
            'successful_public_operations':sorted(successful),
            'missing_successful_public_operations':sorted(EXPECTED_OPERATIONS-successful),
            'qualification':'pending', 'visual_review':'pending',
            'limits':'Exact public non-dry invocation and whitelisted linked FX native playback/path/type checks only. No suite-total inference; semantic, audio-output, history and visual gates stay separate.'}

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
