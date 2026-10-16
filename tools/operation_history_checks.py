"""Recompute scoped FX inner-history assertions, never suite-total passes."""
from __future__ import annotations
import re
import math


def equivalent(left,right):
    """Match this source suite's _same, including strict absolute tolerance."""
    if isinstance(left,bool) or isinstance(right,bool):return type(left) is bool and type(right) is bool and left==right
    if isinstance(left,(int,float)) and isinstance(right,(int,float)):
        return math.isfinite(left) and math.isfinite(right) and abs(left-right)<.00001
    if isinstance(left,dict) and isinstance(right,dict):
        # Native vectors/colors use Godot value equality, not _same's numeric
        # scalar tolerance. The transport preserves their typed components.
        if left.get('type') in {'Vector2','Vector3','Color'} or right.get('type') in {'Vector2','Vector3','Color'}:return left==right
        return left.keys()==right.keys() and all(equivalent(left[key],right[key]) for key in left)
    if isinstance(left,list) and isinstance(right,list):return len(left)==len(right) and all(equivalent(a,b) for a,b in zip(left,right))
    return type(left) is type(right) and left==right

TESTS={'new':'test_new_clip_scene_history',
       'overwrite':'test_overwritten_clip_scene_history',
       'missing_library':'test_missing_library_scene_history',
       'instanced':'test_instanced_player_scene_history'}


def derive(row):
    required={'request','dry','invalid_request','invalid','write','before','after_dry',
              'after_error','generated','undone','redone','versions','undo_success',
              'redo_success','persist_undo','persist_redo','failed_before','failed_after','assertion_count'}
    if not required.issubset(row):raise ValueError('history case missing raw stages')
    versions=row['versions'];before=row['before'];generated=row['generated']
    # A prior sticky assertion failure is conservative failure, never reset here.
    clean=row['failed_before'] is False and row['failed_after'] is False and type(row['assertion_count']) is int and row['assertion_count']>=19
    dry=clean and isinstance(row['dry'],dict) and row['dry'].get('data',{}).get('dry_run') is True and not row['dry'].get('error') and equivalent(before,row['after_dry']) and versions.get('dry')==versions.get('before')
    error=row['invalid'].get('error',{})
    typed=clean and isinstance(error,dict) and error.get('code')=='NODE_NOT_FOUND' and isinstance(error.get('message'),str) and bool(error['message']) and equivalent(before,row['after_error']) and versions.get('error')==versions.get('before')
    invalid=dict(row['request'],player_path='/Missing',sprite_path='/Missing')
    typed=typed and equivalent(row['invalid_request'],invalid)
    history=clean and isinstance(row['write'],dict) and 'data' in row['write'] and not row['write'].get('error') and not equivalent(before,generated) and row['undo_success'] is True and row['redo_success'] is True and equivalent(before,row['undone']) and equivalent(generated,row['redone']) and versions.get('write')==versions.get('before',-2)+1 and versions.get('global_write')==versions.get('global_before')
    def persisted(value,expected,stage):
        path='user://fx_history_%s_%s_%s.tscn'%(row.get('op'),row.get('mode'),stage)
        return isinstance(value,dict) and value.get('pack_result')==0 and value.get('save_result')==0 and value.get('fixture_found') is True and value.get('path')==path and isinstance(value.get('sha256'),str) and re.fullmatch('[0-9a-f]{64}',value['sha256']) is not None and equivalent(value.get('snapshot'),expected)
    saved=clean and persisted(row['persist_undo'],before,'undo') and persisted(row['persist_redo'],generated,'redo')
    return {key:'pass' if value else 'fail' for key,value in
            [('dry_run',dry),('typed_errors',typed),('undo_redo',history),('save_reopen',saved)]}


def verify_event(event,context,begins,support):
    dependencies=context.get('dependencies',{})
    for path in ('test_project/tests/test_fx_route_history.gd',
                 'test_project/tests/operation_history_trace.gd',
                 'tools/mcp_presets_audit.py','tools/operation_history_checks.py'):
        if path not in dependencies:raise ValueError('inner history source not bound: '+path)
    if event.get('driver')!='test_fx_route_history.gd' or event.get('validator')!='fx_history_v1' or event.get('route')!='public_test_run_inner_dispatch':
        raise ValueError('unknown inner history assertion source')
    row=event.get('row',{})
    if row.get('suite')!='fx_route_history' or TESTS.get(row.get('mode'))!=row.get('test'):
        raise ValueError('history case suite/mode/test binding differs')
    if event.get('operation')!='animation_fx.'+row.get('op','') or row.get('request',{}).get('op')!=row.get('op'):
        raise ValueError('history operation differs from actual inner dispatch request')
    begin_id=event.get('test_run_begin_id')
    starts=[item for item in begins if item.get('id')==begin_id]
    ends=[item for item in support if item.get('public_tool')=='test_run' and item.get('test_run_begin_id')==begin_id]
    if len(starts)!=1 or len(ends)!=1:raise ValueError('inner history lacks unique real public test span')
    start,end=starts[0],ends[0]
    request=start.get('request',{})
    if request!=end.get('request') or request.get('suite')!=row['suite'] or request.get('verbose') is not True or start.get('execution_ns',0)>=end.get('execution_ns',0):
        raise ValueError('public test span request/order differs')
    results=end.get('response',{}).get('results',[])
    # Godot's actual verbose result is a flat per-test array. A total cannot
    # substitute for an exact test outcome, nor can skipped/advisory results.
    matches=[item for item in results if isinstance(item,dict) and item.get('suite')==row['suite'] and item.get('test')==row['test']]
    checks=derive(row)
    if len(matches)!=1 or matches[0].get('passed') is not True or matches[0].get('skipped',False) or not isinstance(matches[0].get('assertion_count'),int) or matches[0]['assertion_count']<row['assertion_count']:
        checks={key:'fail' for key in checks}
    return {'checks':checks,'public_test_run_case_id':end['id'],
            'limits':'Exact FX inner dispatcher dry/error/Undo/Redo and saved snapshots inside one actual public test_run. No individual external invocation, semantic effect, visual/audio or full source invariant inferred.'}
