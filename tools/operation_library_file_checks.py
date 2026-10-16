"""Exact existing library-contract file/read cases; no scene-producing inference."""
from __future__ import annotations
import hashlib
import json
import math

TEST='test_file_operations_preserve_history_and_dry_bytes'
OPS={'template_save','template_list','template_delete','spec_export','spec_import'}
DIRECTORY='res://animation_toolkit/history_contracts/'


def same(left,right):
    if isinstance(left,bool) or isinstance(right,bool):return type(left) is bool and type(right) is bool and left==right
    if isinstance(left,(int,float)) and isinstance(right,(int,float)):
        return math.isfinite(left) and math.isfinite(right) and left==right
    if isinstance(left,dict) and isinstance(right,dict):return left.keys()==right.keys() and all(same(left[key],right[key]) for key in left)
    if isinstance(left,list) and isinstance(right,list):return len(left)==len(right) and all(same(a,b) for a,b in zip(left,right))
    return type(left) is type(right) and left==right


def file_bytes(value,path):
    if not isinstance(value,dict) or value.get('path')!=path or type(value.get('exists')) is not bool:
        raise ValueError('file observation differs from exact request path')
    if not value['exists']:
        if set(value)!={'path','exists'}:raise ValueError('absent file carries fabricated bytes')
        return None
    try:raw=bytes.fromhex(value['bytes_hex'])
    except (KeyError,TypeError,ValueError):raise ValueError('file bytes missing/invalid')
    if hashlib.sha256(raw).hexdigest()!=value.get('sha256'):raise ValueError('file content hash differs from actual embedded bytes')
    return raw


def document(raw,format_name):
    value=json.loads(raw.decode('utf-8'))
    if not isinstance(value,dict) or value.get('format')!=format_name or value.get('version')!=1:
        raise ValueError('file format/version differs from this exact source contract')
    return value


def exported_clip(clip):
    """Independent native metadata reader's scalar fixture, not exporter output."""
    if clip.get('markers')!={} or not clip.get('tracks'):raise ValueError('unrecognized export fixture metadata')
    tracks=[]
    for track in clip['tracks']:
        if track.get('type')!=0:raise ValueError('this file case requires its actual value-track fixture')
        keys=[]
        for key in track['keys']:
            if len(key)!=3 or not isinstance(key[1],(float,int,bool,str)):raise ValueError('unrecognized scalar export fixture key')
            keys.append({'time':key[0],'value':key[1],'transition':key[2]})
        tracks.append({'type':0,'path':track['path'],'enabled':track['enabled'],
                       'interp':track['interp'],'loop_wrap':track['wrap'],
                       'update_mode':track['update'],'keys':keys})
    return {'format':'godot-ai-animation-clip','version':1,'length':clip['length'],
            'loop_mode':clip['loop'],'markers':[],'tracks':tracks}


def derive(row):
    op=row.get('op');request=row.get('request',{});reply=row.get('response',{})
    if op not in OPS or request.get('op')!=op:raise ValueError('file case operation differs from actual dispatch')
    path=request.get('library_path') if op.startswith('template_') else request.get('path')
    expected=DIRECTORY+('recipes.json' if op.startswith('template_') else 'export.json')
    if path!=expected:raise ValueError('file case is outside its exact existing fixture paths')
    before=file_bytes(row.get('file_before'),path);after=file_bytes(row.get('file_after'),path)
    required={'before','after','history_before','history_after','global_before','global_after',
              'errors_before','errors_after','errors','failed_before'}
    if not required.issubset(row):raise ValueError('file case lacks actual scene/history/error observations')
    clean=row['failed_before'] is False
    invariant=clean and bool(row['before']) and same(row['before'],row['after']) and type(row['history_before']) is int and row['history_after']==row['history_before'] and type(row['global_before']) is int and row['global_after']==row['global_before']
    errors=clean and type(row['errors_before']) is int and row['errors_after']==row['errors_before'] and row['errors']==[]
    write=op in {'template_save','template_delete','spec_export'}
    dry=request.get('dry_run') is True
    checks={'source_unchanged':'pass' if invariant and (write and not dry or before==after) else 'fail',
            'reported_errors':'pass' if errors else 'fail'}
    error=reply.get('error')
    if error:
        typed=isinstance(error,dict) and error.get('code')=='INVALID_PARAMS' and isinstance(error.get('message'),str) and bool(error['message'])
        checks['typed_errors']='pass' if typed and invariant and before==after else 'fail'
        return checks
    data=reply.get('data')
    if not isinstance(data,dict) or not data:
        checks['dry_run' if dry else 'valid_effect']='fail'
        return checks
    if dry:
        checks['dry_run']='pass' if invariant and before==after and data.get('dry_run') is True and data.get('undoable') is False else 'fail'
        return checks
    valid=False
    if op.startswith('template_'):
        old={} if before is None else document(before,'godot-ai-animation-library')['templates']
        new=document(after,'godot-ai-animation-library')['templates'] if after is not None else None
        if not isinstance(old,dict) or not isinstance(new,dict):raise ValueError('library templates must be actual objects')
        if op=='template_list':
            entries=[dict(value,name=name,param_count=len(value['params'])) for name,value in sorted(old.items())]
            valid=before==after and data.get('exists') is (before is not None) and data.get('library_path')==path and data.get('template_count')==len(entries) and same(data.get('templates'),entries)
        elif op=='template_save':
            if request.get('tool')!='animation_presets' or request.get('forward_op')!='bounce' or request.get('name')!='bounce' or request.get('intensity') not in {.25,.4}:
                raise ValueError('template save differs from actual narrow fixture recipe')
            entry={'tool':'animation_presets','op':'bounce','description':'','params':{'intensity':request['intensity']}}
            expected=dict(old,bounce=entry)
            valid=('bounce' not in old or request.get('overwrite') is True) and same(new,expected) and data.get('undoable') is False and data.get('template_count')==len(new) and data.get('overwritten') is ('bounce' in old) and same(data.get('params'),entry['params'])
        else:
            expected={name:value for name,value in old.items() if name!=request.get('name')}
            valid=request.get('name') in old and same(new,expected) and data.get('undoable') is False and data.get('template_count')==len(new)
    else:
        spec=document(after,'godot-ai-animation-clip') if after is not None else None
        if op=='spec_export':
            if not str(request.get('player_path','')).endswith('/LibraryContracts/AnimationPlayer') or request.get('animation_name')!='unrelated':raise ValueError('export source differs from actual independent clip fixture')
            clip=row['before']['children']['AnimationPlayer']['clips']['unrelated']
            valid=spec is not None and same(spec,exported_clip(clip)) and data.get('undoable') is False and data.get('path')==path and (before is None or request.get('overwrite',True) is True)
        elif spec is not None:
            tracks=spec.get('tracks',[])
            valid=before==after and bool(tracks) and all(track.get('type')==0 for track in tracks) and data.get('path')==path and same(data.get('length'),spec['length']) and data.get('loop_mode')=={0:'none',1:'linear',2:'pingpong'}.get(spec['loop_mode']) and data.get('track_count')==len(tracks) and data.get('key_count')==sum(len(track['keys']) for track in tracks) and data.get('track_types')=={'value':len(tracks)} and data.get('paths')==[track['path'] for track in tracks] and data.get('issues')==[]
    valid=clean and invariant and valid
    checks['valid_effect']='pass' if valid else 'fail'
    if write:checks['file_effect']='pass' if valid and before!=after else 'fail'
    return checks


def verify_event(event,context,begins,support):
    dependencies=context.get('dependencies',{})
    for path in ('test_project/tests/test_library_contracts.gd','test_project/tests/operation_history_trace.gd',
                 'test_project/tests/test_preset_library_history.gd','test_project/tests/test_edit_route_history.gd',
                 'test_project/tests/test_fx_route_history.gd','test_project/tests/test_graph_route_history.gd',
                 'tools/mcp_presets_audit.py','tools/operation_library_file_checks.py'):
        if path not in dependencies:raise ValueError('file contract source not bound: '+path)
    row=event.get('row',{})
    if event.get('driver')!='test_library_contracts.gd' or event.get('validator')!='library_file_v1' or event.get('route')!='public_test_run_inner_dispatch' or row.get('suite')!='library_contracts' or row.get('test')!=TEST or row.get('mode')!='file_contract':
        raise ValueError('unknown library file contract source/case')
    if event.get('operation')!='animation_library.'+row.get('op','') or type(row.get('ordinal')) is not int or row['ordinal']<1 or type(row.get('assertion_count_before')) is not int or row['assertion_count_before']<0:
        raise ValueError('library file operation/case identity differs')
    token=event.get('test_run_begin_id')
    starts=[item for item in begins if item.get('id')==token]
    ends=[item for item in support if item.get('public_tool')=='test_run' and item.get('test_run_begin_id')==token]
    if len(starts)!=1 or len(ends)!=1:raise ValueError('library case lacks unique actual public span')
    start,end=starts[0],ends[0]
    if start.get('request')!=end.get('request') or start.get('request',{}).get('suite')!='library_contracts' or start['request'].get('verbose') is not True or start.get('execution_ns',0)>=end.get('execution_ns',0):raise ValueError('library public request/order differs')
    checks=derive(row)
    actual=[item for item in end.get('response',{}).get('results',[]) if isinstance(item,dict) and item.get('suite')=='library_contracts' and item.get('test')==TEST]
    if len(actual)!=1 or actual[0].get('passed') is not True or actual[0].get('skipped',False) or type(actual[0].get('assertion_count')) is not int or actual[0]['assertion_count']<30 or actual[0]['assertion_count']<=row.get('assertion_count_before',-1):
        checks={key:'fail' for key in checks}
    return {'checks':checks,'public_test_run_case_id':end['id'],
            'limits':'Exact existing library file/read contract, embedded hashed file bytes and scene/global history invariance. No external operation invocation, scene Undo/Redo, playback or visual/audio qualification.'}
