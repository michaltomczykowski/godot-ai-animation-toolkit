"""Exact public-call traces and a conservative operation_case_results collector.

No suite-total inference. This first collector emits mcp_invocation only.
Semantic/history/native checks must be attached by their actual validators.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import re
import os
from pathlib import Path
import platform
import subprocess
import sys
import time
import uuid
from contextlib import contextmanager
from check_release_audit import EXPECTED_OPERATIONS, CORES

_context_cache = None
_trace_file = None
_sequence = 0
_active_scene = ""
_active_test_run = None

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

def ci_source_identity(source):
    """Label the real checkout honestly; never substitute PR head for tested HEAD."""
    identity={'event_name':os.environ.get('GITHUB_EVENT_NAME'),
              'github_sha':os.environ.get('GITHUB_SHA'),
              'run_id':os.environ.get('GITHUB_RUN_ID'),
              'checkout_sha':source, 'pr_head_sha':None, 'pr_merge_sha':None}
    event_path=os.environ.get('GITHUB_EVENT_PATH')
    if event_path:
        try:
            payload=json.loads(Path(event_path).read_text(encoding='utf-8'))
            identity['event_payload_sha256']=sha(event_path)
            pr=payload.get('pull_request',{})
            identity['pr_head_sha']=pr.get('head',{}).get('sha')
            identity['pr_merge_sha']=pr.get('merge_commit_sha')
        except (OSError,ValueError,TypeError):
            identity['event_metadata_error']='CI event payload unavailable or invalid'
    if identity['event_name']=='pull_request' and source==identity['pr_head_sha']:
        label='pull_request_head'
    elif identity['event_name']=='pull_request' and identity['pr_head_sha'] and source==identity['github_sha']:
        label='pull_request_merge_checkout'
    elif source==identity['github_sha']:
        label='event_checkout'
    elif not identity['event_name']:
        label='local_checkout'
    else:
        label='explicit_or_other_checkout'
    identity['tested_reference']=label
    return identity


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
                'addons/godot_ai_animation', 'tools', 'test_project/tests', 'test_project/tools',
                'test_project/repair_graph_fixture.tscn', 'test_project/repair_edit_fixture.tscn',
                'test_project/repair_fx_fixture.tscn', 'test_project/repair_motion_fixture.tscn',
                'test_project/repair_rig_fixture.tscn',
                'test_project/models/human_dummy/HumanCharacterDummy_F.fbx').splitlines()
    deps = {}
    for rel in paths:
        if rel.endswith('.uid') or (not rel.endswith(('.gd','.py','.json','.tscn','.tres','.cfg','.godot')) and rel not in {'test_project/tests/fixtures/sheet.png','test_project/tests/fixtures/cue.wav','test_project/models/human_dummy/HumanCharacterDummy_F.fbx'}):
            continue
        path = root / rel
        blob = git(root, 'rev-parse', source+':'+rel)
        if not path.is_file() or git(root, 'hash-object', '--path', rel, str(path)) != blob:
            raise ValueError('tested source differs from committed dependency: '+rel)
        deps[rel] = {'git_blob':blob, 'sha256':sha(path)}
    if 'tools/operation_case_collector.py' not in deps:
        raise ValueError('collector must be committed in the tested source')
    context = {'schema_version':1, 'kind':'operation_trace_context',
               'run_id':uuid.uuid4().hex, 'tested_source':source, 'ci_source_identity':ci_source_identity(source),
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
    return event['id']


@contextmanager
def public_test_run_span(name, params):
    """Bind editor inner cases to one real in-flight public test_run request."""
    global _active_test_run
    if name!='test_run' or not os.environ.get('TOOLKIT_OPERATION_CONTEXT'):
        yield
        return
    directory=Path(os.environ['TOOLKIT_OPERATION_TRACE_DIR'])
    directory.mkdir(parents=True,exist_ok=True)
    active=directory/'active-public-test-run.json'
    # Concurrent test requests would make attribution ambiguous. Refuse them.
    file=active.open('x',encoding='utf-8')
    try:
        with file:
            begin=_emit('public_test_run_begin',{'public_tool':name,'request':params,
                        'scene':_active_scene,'route':'public_godot_ai'})
            context_path=Path(os.environ['TOOLKIT_OPERATION_CONTEXT'])
            context=json.loads(context_path.read_text(encoding='utf-8'))
            _active_test_run={'begin_id':begin,'request':params,'run_id':context['run_id'],
                              'context_sha256':sha(context_path)}
            json.dump(_active_test_run,file)
        yield
    finally:
        _active_test_run=None
        active.unlink()


def record_public_call(name, params, response):
    """Called only AFTER the shared public MCP call completed; no caller mutations."""
    global _active_scene
    if name == 'scene_open' and isinstance(response, dict) and not response.get('error'):
        _active_scene = params.get('path', '')
    if name in {'scene_open','scene_save','node_get_properties','test_run'}:
        extra={'test_run_begin_id':_active_test_run['begin_id']} if name=='test_run' and _active_test_run else {}
        return _emit('public_support_call',{'public_tool':name,'request':params,'response':response,'scene':_active_scene,'route':'public_godot_ai',**extra})
    key, actual_params = operation_key(name, params)
    if key is not None:
        return _emit('public_operation_call', {'operation':key, 'public_tool':name,
              'request':params, 'params':actual_params, 'response':response,
              'scene':_active_scene, 'route':'public_godot_ai'})


def record_native_result(operation, scene, command, completed):
    """Record the actual completed subprocess, never a caller-supplied pass flag."""
    if not os.environ.get('TOOLKIT_OPERATION_CONTEXT') and not os.environ.get('TOOLKIT_OPERATION_TRACE_DIR'):
        return
    return _emit('native_saved_output', {'operation':operation, 'scene':scene,
          'command':[str(part) for part in command], 'returncode':completed.returncode,
          'stdout':completed.stdout, 'stderr':completed.stderr, 'route':'native_godot'})


def record_snapshot_result(validator,row):
    if not os.environ.get('TOOLKIT_OPERATION_CONTEXT') and not os.environ.get('TOOLKIT_OPERATION_TRACE_DIR'):return
    if validator=="bounded_read_v1":
        from operation_bounded_read_checks import derive
        return _emit("operation_snapshot_assertions", {"operation":row["operation"],
            "validator":validator,"row":row,"checks":derive(row),"route":"public_godot_ai"})
    if validator=="inspect_read_v1":
        from operation_inspect_checks import derive
        return _emit("operation_snapshot_assertions", {"operation":"animation_inspect."+row["op"],
            "validator":validator,"row":row,"checks":derive(row),"route":"public_godot_ai"})
    from operation_snapshot_checks import derive
    family='animation_fx' if validator=='fx_snapshot_v1' else 'animation_edit'
    op='sprite_frames' if row['op']=='sprite_frames_stopped' else row['op'].removesuffix('_wrap_reject')
    return _emit('operation_snapshot_assertions',{'operation':family+'.'+op,
        'validator':validator,'row':row,'checks':derive(validator,row),'route':'public_godot_ai'})


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
    if not isinstance(report,dict): raise ValueError('native result must be an object')
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


def _number(value):
    return isinstance(value, (int,float)) and not isinstance(value,bool) and math.isfinite(value)

def native_checks(event, context):
    from operation_edit_native_checks import OPS as EDIT_OPS, verify_native as verify_edit_native
    if event.get('operation','').removeprefix('animation_edit.') in EDIT_OPS and event.get('operation','').startswith('animation_edit.'):
        return verify_edit_native(event,context)
    from operation_rig_native_checks import OPS, verify_native
    if event.get('operation') in OPS:
        return verify_native(event, context)
    command = event.get('command', [])
    if not command or command[0] != context.get('engine_command'):
        raise ValueError('native engine command differs from actual version probe')
    try:
        script = command[command.index('--script')+1]
        args = command[command.index('--')+1:]
    except (ValueError, IndexError):
        raise ValueError('native command does not identify checker and case')
    if script == 'res://tools/check_fx_runtime.gd':
        return native_fx_checks(event,context)
    rules = {
      'check_edit_runtime.gd':('animation_edit','EDIT_RUNTIME='),
      'check_edit_remaining_runtime.gd':('animation_edit','EDIT_REMAINING='),
      'check_presets_saved_playback.gd':('animation_presets','PRESET_SAVED_PLAYBACK='),
      'verify_saved_graph_playback.gd':('animation_graph','GRAPH_SAVED_PLAYBACK_PASS: '),
      'check_motion_remaining_runtime.gd':('animation_motion','MOTION_REMAINING_RUNTIME='),
      'check_motion_setup_runtime.gd':('animation_motion','MOTION_SETUP_RUNTIME='),
      'check_rig_recipe_runtime.gd':('animation_rig','RIG_RECIPE_RUNTIME='),
      'check_rig_pose_clip_runtime.gd':('animation_rig','RIG_POSE_CLIP='),
      'check_rig_bake_runtime.gd':('animation_rig','RIG_BAKE_RUNTIME='),
      'check_sequence_runtime.gd':('animation_sequence','SEQUENCE_RUNTIME='),
      'check_library_runtime.gd':('animation_library','LIBRARY_RUNTIME='),
    }
    name = script.removeprefix('res://tools/')
    if script != 'res://tools/'+name or name not in rules or 'test_project/tools/'+name not in context['dependencies']:
        raise ValueError('native checker lacks a whitelisted source-bound contract')
    family,prefix = rules[name]
    if not event['operation'].startswith(family+'.') or not args or args[0] != event['scene']:
        raise ValueError('native operation family/scene differs from executed command')
    op=event['operation'].split('.',1)[1]
    parameterized = name in {'check_edit_runtime.gd','check_edit_remaining_runtime.gd',
        'check_presets_saved_playback.gd','check_motion_remaining_runtime.gd','check_rig_recipe_runtime.gd'}
    if len(args) != (2 if parameterized else 1) or (parameterized and args[1] != op):
        raise ValueError('native command arguments differ from operation contract')
    if name == 'check_presets_saved_playback.gd' and op == 'showcase':
        prefix='PRESET_SHOWCASE_PLAYBACK='
    raw = event.get('stdout','')+'\n'+event.get('stderr','')
    payloads=[line[len(prefix):] for line in event.get('stdout','').splitlines() if line.startswith(prefix)]
    okay=event.get('returncode') == 0 and 'SCRIPT ERROR:' not in raw and 'ERROR:' not in raw and len(payloads)==1
    report={}
    if len(payloads)==1 and name != 'verify_saved_graph_playback.gd':
        report=json.loads(payloads[0])
        if not isinstance(report,dict): raise ValueError('native result must be an object')
        scene_optional = name == 'check_motion_remaining_runtime.gd' or (name == 'check_presets_saved_playback.gd' and op == 'showcase')
        if not scene_optional and report.get('scene') != event['scene']:
            raise ValueError('native output scene differs from executed command')
        if 'scene' in report and report['scene'] != event['scene']:
            raise ValueError('native output scene differs from executed command')
        if name in {'check_edit_runtime.gd','check_edit_remaining_runtime.gd','check_rig_recipe_runtime.gd'} and report.get('op') != op:
            raise ValueError('native output operation differs from executed command')
        if 'op' in report and report['op'] != op:
            raise ValueError('native output operation differs from executed command')
    if name in {'check_edit_runtime.gd','check_edit_remaining_runtime.gd'}:
        expected_count = 3 if name == 'check_edit_runtime.gd' else None
        samples=report.get('samples',[])
        limit=1.0 if name == 'check_edit_runtime.gd' else .25
        okay = okay and isinstance(samples,list) and bool(samples) and (expected_count is None or len(samples)==expected_count)
        okay = okay and _number(report.get('worst_error')) and report['worst_error']<limit
    elif name == 'check_presets_saved_playback.gd':
        if op == 'showcase':
            players={'AnimBounce','AnimOrbit','AnimSweep','AnimDrift','AnimPulse','AnimFloat','AnimSpin'}
            rows=report.get('rows',[])
            okay = okay and report.get('failures')==[] and len(rows)==7 and {r.get('player') for r in rows}==players
            okay = okay and all(r.get('track') and _number(r.get('maximum_change')) and r['maximum_change']>.001 for r in rows)
        else:
            okay = okay and report.get('op')==op and report.get('scene')==event['scene'] and _number(report.get('maximum_change')) and report['maximum_change']>.001
    elif name == 'verify_saved_graph_playback.gd':
        if op == 'graph_get':
            return {}, ['read-only graph_get has no applicable producer playback check']
        text=payloads[0] if len(payloads)==1 else ''
        number=r'([-+0-9.]+)'
        # Match each actual checker branch and its original native thresholds.
        # A generic walk marker cannot qualify a jump, additive or wired branch.
        if op=='wire':
            pattern=r' condition_walk_x='+number
            valid=lambda m:float(m[1])>=20.0
        elif op=='locomotion' and Path(event['scene']).name=='locomotion_state_machine.tscn':
            pattern=r' walk_x='+number+r' run_x='+number
            valid=lambda m:float(m[1])>=20.0 and float(m[2])>=70.0
        elif op=='one_shot_layer':
            pattern=r' jump_y='+number
            valid=lambda m:float(m[1])<=-20.0
        elif op=='additive_lean':
            pattern=r' lean='+number
            valid=lambda m:float(m[1])>=.05
        elif op in {'state_machine','blend_space','blend_tree','locomotion'}:
            pattern=r' walk_x='+number
            valid=lambda m:float(m[1])>=20.0
        else:
            raise ValueError('graph operation has no source-specific playback branch')
        match=re.fullmatch(re.escape(event['scene'])+pattern+r' player_idle=true',text)
        try:okay = okay and bool(match) and valid(match)
        except ValueError:okay=False
    elif name in {'check_motion_remaining_runtime.gd','check_rig_recipe_runtime.gd'}:
        if name == 'check_motion_remaining_runtime.gd' and report.get('clip') != op:
            raise ValueError('native output clip differs from operation')
        okay = okay and report.get('failures')==[] and _number(report.get('checked')) and report['checked']>0 and _number(report.get('moving')) and report['moving']>0
        okay = okay and _number(report.get('worst_error')) and report['worst_error']<.02
    elif name == 'check_motion_setup_runtime.gd':
        if op not in {'character_setup','secondary_motion'}: raise ValueError('setup result cannot qualify unrelated motion')
        okay=okay and report.get('failures')==[]
        if op == 'character_setup':
            okay=okay and _number(report.get('thigh_change')) and report['thigh_change']>.001 and _number(report.get('root_extraction')) and report['root_extraction']>.01
        else:
            okay=okay and _number(report.get('jaw_range')) and report['jaw_range']>.001 and _number(report.get('jaw_play_error')) and report['jaw_play_error']<=.02
    elif name == 'check_rig_pose_clip_runtime.gd':
        if op!='pose_to_clip': raise ValueError('pose clip checker cannot qualify unrelated rig operation')
        okay=okay and len(report.get('samples',[]))==3 and _number(report.get('worst_error')) and report['worst_error']<.02
    elif name == 'check_rig_bake_runtime.gd':
        if op!='bake_pose_sequence':raise ValueError('bake checker cannot qualify unrelated rig operation')
        okay=okay and report.get('samples')==24 and _number(report.get('worst_error')) and report['worst_error']<.02
    elif name == 'check_sequence_runtime.gd':
        if op!='compose':raise ValueError('sequence checker cannot qualify unrelated operation')
        okay=okay and report.get('contact_impact') is True and _number(report.get('early_angle')) and _number(report.get('late_angle')) and report['late_angle']>report['early_angle']+.25
        okay=okay and _number(report.get('impact_time')) and abs(report['impact_time']-1.1)<.001
        angle=report.get('saved_pose_angle')
        okay=okay and _number(angle) and (angle<0 or abs(angle-.6)<.02)
    elif name == 'check_library_runtime.gd':
        if op not in {'template_apply','spec_apply'}:raise ValueError('library playback cannot qualify read/file operations')
        clip='templated_drift' if op=='template_apply' else 'imported_walk'
        expected=30.0 if op=='template_apply' else 50.0
        rows=report.get('samples',[])
        selected=[row for row in rows if row.get('clip')==clip]
        okay=okay and len(rows)==2 and len(selected)==1 and _number(report.get('worst_error')) and report['worst_error']<.1
        okay=okay and len(selected)==1 and _number(selected[0].get('target_x')) and abs(selected[0]['target_x']-expected)<.1 and _number(selected[0].get('source_x')) and abs(selected[0]['source_x'])<.1
    return {'playback':'pass' if okay else 'fail'}, [] if okay else ['actual source-specific native runtime contract failed']


def native_origin_matches(event, call):
    """Bind named checker outputs, not merely another successful clip in the scene."""
    from operation_edit_native_checks import OPS as EDIT_OPS, origin_matches as edit_origin_matches
    if event.get('operation','').removeprefix('animation_edit.') in EDIT_OPS and event.get('operation','').startswith('animation_edit.'):
        return edit_origin_matches(event,call)
    from operation_rig_native_checks import OPS, origin_matches
    if event.get('operation') in OPS:
        return origin_matches(event, call)
    command=event['command']
    script=command[command.index('--script')+1]
    args=command[command.index('--')+1:]
    name=script.removeprefix('res://tools/')
    op=event['operation'].split('.',1)[1]
    expected=None
    if name=='check_fx_runtime.gd': expected=args[2] if len(args)>2 else args[1]
    elif name in {'check_motion_remaining_runtime.gd','check_rig_recipe_runtime.gd'}: expected=args[1]
    elif name=='check_presets_saved_playback.gd' and op!='showcase': expected='audit_'+op
    elif name in {'check_edit_runtime.gd','check_edit_remaining_runtime.gd'}: expected='idle' if op=='cleanup' else 'jump' if op=='smooth' else 'walk'
    elif name=='check_rig_pose_clip_runtime.gd': expected='arm_wave'
    elif name=='check_rig_bake_runtime.gd': expected='walk_baked'
    elif name=='check_sequence_runtime.gd': expected='audit_action'
    elif name=='check_library_runtime.gd': expected='templated_drift' if op=='template_apply' else 'imported_walk'
    return expected is None or call.get('params',{}).get('animation_name')==expected


def collect(context_path, traces, root, preview_report=None):
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
    public_events, native_events, support_events, snapshot_events = [], [], [], []
    test_begins, history_events = [], []
    artifacts = [{'path':context_path.name,'sha256':sha(context_path),'role':'trace_context'}]
    for path in sorted(traces.glob('*.jsonl')):
        portable_path = path.resolve().relative_to(context_path.parent.resolve()).as_posix()
        artifacts.append({'path':portable_path, 'sha256':sha(path), 'role':'raw_public_calls'})
        previous = 0
        for line in path.read_text(encoding='utf-8').splitlines():
            event = json.loads(line)
            if event.get('kind') not in {'public_operation_call','native_saved_output','public_support_call','operation_snapshot_assertions','public_test_run_begin','editor_history_assertions'} or event.get('context_sha256') != sha(context_path) or event.get('run_id') != context['run_id']:
                raise ValueError('foreign or unbound call event')
            if event.get('id') in seen or event.get('sequence') != previous+1:
                raise ValueError('duplicate/out-of-order call event')
            seen.add(event['id']); previous += 1
            if event['kind']=='public_test_run_begin':
                if event.get('public_tool')!='test_run' or event.get('route')!='public_godot_ai':raise ValueError('invalid public test begin')
                test_begins.append(event)
                continue
            if event['kind']=='editor_history_assertions':
                history_events.append(event)
                continue
            if event['kind'] == 'public_support_call':
                if event.get('public_tool') not in {'scene_open','scene_save','node_get_properties','test_run'} or event.get('route')!='public_godot_ai':raise ValueError('invalid public support call')
                support_events.append(event)
                continue
            if event['kind'] == 'operation_snapshot_assertions':
                snapshot_events.append(event)
                continue
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
        if any(script in event.get('command', []) for script in ('res://tools/check_rig_modifier_history.gd','res://tools/check_motion_sequence_history.gd')):
            # Joined below to exact inner history case/state hashes, not public-call totals.
            continue
        from operation_fx_counter_native_checks import is_event as fx_counter_history_event
        if fx_counter_history_event(event):
            # Existing saved counter native runs join their exact inner history row below.
            continue
        from operation_rig_clip_native_checks import is_event as rig_clip_event, verify_native as rig_clip_native
        if rig_clip_event(event):
            proof=rig_clip_native(event,context,history_events,test_begins,support_events)
            cases.append({'id':event['id'],'operation':event['operation'],'checks':proof['checks'],
                          'scope':'candidate','route':'public_output_native_godot','raw_event_id':event['id'],
                          'public_test_run_case_id':proof['public_test_run_case_id'],
                          'public_origin_id':proof['public_origin_id'],'scene':event['scene'],
                          'failures':proof['failures'],'limits':proof['limits']})
            continue
        checks, failures = native_checks(event, context)
        matches = [call for call in public_events
                   if call['operation'] == event['operation'] and call.get('scene') == event.get('scene')
                   and call['execution_ns'] < event['execution_ns'] and native_origin_matches(event,call)
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
                      'limits':'Source-specific native playback checks only; additional FX paths/types when applicable. Native audio playing is an event, not audible-output or visual approval.'})
    for event in snapshot_events:
        if event.get("validator")=="bounded_read_v1":
            from operation_bounded_read_checks import verify_event
        elif event.get("validator")=="inspect_read_v1":
            from operation_inspect_checks import verify_event
        else:
            from operation_snapshot_checks import verify_event
        proof=verify_event(event,context,public_events,support_events)
        cases.append({'id':event['id'],'operation':event['operation'],'checks':proof['checks'],
                      'scope':'candidate','route':'public_godot_ai','raw_event_id':event['id'],
                      'public_case_ids':proof['public_case_ids'],'dry_case_ids':proof['dry_case_ids'],
                      'failures':proof['failures'],'limits':proof['limits']})
    for event in history_events:
        if event.get('validator')=='inspect_read_witness_v1':
            if event.get('row',{}).get('phase')!='end' or event['row'].get('marker',{}).get('stage')!='valid':continue
            from operation_read_witness_checks import verify_pair
            proof=verify_pair(event,context,history_events,public_events,test_begins,support_events)
            cases.append({'id':event['id'],'operation':event['operation'],'checks':proof['checks'],
                          'scope':'candidate','route':'public_godot_ai','raw_event_id':event['id'],
                          'public_case_ids':proof['public_case_ids'],
                          'public_test_run_case_id':proof['public_test_run_case_id'],'limits':proof['limits']})
            continue
        if event.get('validator')=='motion_sequence_history_v1':
            from operation_motion_sequence_native_checks import verify_event
        elif event.get('validator')=='rig_scene_history_v1':
            from operation_rig_scene_history_checks import verify_event
        elif event.get('validator')=='rig_modifier_history_v1':
            from operation_modifier_history_checks import verify_event
        elif event.get('validator')=='graph_history_v1':
            from operation_graph_history_checks import verify_event
        elif event.get('validator')=='rig_pose_file_v1':
            from operation_pose_file_checks import verify_event
        elif event.get('validator')=='preset_library_history_v1':
            from operation_preset_history_checks import verify_event
        elif event.get('validator')=='library_read_refusal_v1':
            from operation_library_read_checks import verify_event
        elif event.get('validator')=='fx_intention_history_v1':
            from operation_fx_intention_checks import verify_event
        elif event.get('validator')=='library_file_v1':
            from operation_library_file_checks import verify_event
        else:
            from operation_history_checks import verify_event
        if event.get('operation') not in EXPECTED_OPERATIONS:raise ValueError('invalid inner history operation')
        evidence_support = support_events + native_events if event.get('validator') in ('rig_modifier_history_v1','motion_sequence_history_v1','fx_intention_history_v1') else support_events
        proof=verify_event(event,context,test_begins,evidence_support)
        cases.append({'id':event['id'],'operation':event['operation'],'checks':proof['checks'],
                      'scope':'candidate','route':'public_test_run_inner_dispatch',
                      'raw_event_id':event['id'],'public_test_run_case_id':proof['public_test_run_case_id'],
                      'mode':event['row']['mode'],'limits':proof['limits'],
                      **({'counter_native':proof['counter_native']} if 'counter_native' in proof else {})})
    if preview_report is not None:
        from operation_preview_adapter import validate_preview
        preview=validate_preview(preview_report,context_path,context,public_events+support_events)
        actual=[case for case in cases if case['id']==preview['public_case_id'] and case['operation']=='animation_inspect.preview']
        if len(actual)!=1:raise ValueError('preview public case identity ambiguous')
        actual[0]['checks'].update(preview['checks'])
        actual[0]['limits']=preview['limits']
        artifacts.extend(preview['artifacts'])
    return {'schema_version':1, 'kind':'operation_case_results',
            'tested_source':context['tested_source'], 'engine':context['engine'],
            'platform':context['platform'], 'core_version':context['core_version'],
            'core_commit':context['core_commit'], 'core_qualification':context['core_qualification'],
            'context_sha256':sha(context_path), 'dependencies':context['dependencies'],
            'raw_artifacts':artifacts, 'cases':cases,
            'successful_public_operations':sorted(successful),
            'missing_successful_public_operations':sorted(EXPECTED_OPERATIONS-successful),
            'qualification':'pending', 'visual_review':'pending',
            'limits':'Exact public non-dry invocation and whitelisted source-specific native playback checks only. No suite-total inference; semantic, audio-output, history and visual gates stay separate.'}

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
    out.add_argument('--preview-report',type=Path)
    a=p.parse_args()
    if a.command=='prepare':
        prepare(a.root,a.core_root,a.godot,a.output)
        return 0
    report=collect(a.context,a.trace_dir,a.root,a.preview_report)
    with a.output.open('x',encoding='utf-8') as f:
        json.dump(report,f,indent=2)
    from operation_derived_gate import derived_failures
    failed_derived=derived_failures(report)
    print(json.dumps({'public_operations':len(report['successful_public_operations']),
                      'missing':report['missing_successful_public_operations'],
                      'failed_derived_checks':len(failed_derived)}))
    return 0 if not failed_derived and (a.allow_partial or (not report['missing_successful_public_operations'] and report['core_qualification']=='released')) else 2
if __name__=='__main__':
    raise SystemExit(main())
