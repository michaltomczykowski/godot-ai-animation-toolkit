"""Recompute scoped FX/edit inner-history assertions, never suite-total passes."""
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
EDIT_TESTS={'local':'test_local_scene_history','instanced':'test_instanced_scene_history',
            'editable':'test_editable_instance_scene_history'}


def derive(row):
    edit=row.get('suite')=='edit_route_history'
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
    invalid=dict(row['request'],player_path='/Missing') if edit else dict(row['request'],player_path='/Missing',sprite_path='/Missing')
    typed=typed and equivalent(row['invalid_request'],invalid)
    history=clean and isinstance(row['write'],dict) and 'data' in row['write'] and not row['write'].get('error') and not equivalent(before,generated) and row['undo_success'] is True and row['redo_success'] is True and equivalent(before,row['undone']) and equivalent(generated,row['redone']) and versions.get('write')==versions.get('before',-2)+1 and versions.get('global_write')==versions.get('global_before')
    def persisted(value,expected,stage):
        path=('user://edit_history_%s_%s_%s_%s.tscn'%(row.get('mode'),row.get('op'),row.get('variant'),stage)) if edit else ('user://fx_history_%s_%s_%s.tscn'%(row.get('op'),row.get('mode'),stage))
        return isinstance(value,dict) and value.get('pack_result')==0 and value.get('save_result')==0 and value.get('fixture_found') is True and value.get('path')==path and isinstance(value.get('sha256'),str) and re.fullmatch('[0-9a-f]{64}',value['sha256']) is not None and equivalent(value.get('snapshot'),expected)
    saved=clean and persisted(row['persist_undo'],before,'undo') and persisted(row['persist_redo'],generated,'redo')
    if edit:
        identity=row.get('original_library_id')
        # RefCounted ObjectIDs may carry the high bit and serialize as negative
        # signed Godot ints. Zero is invalid; positivity is not an ID contract.
        dry=dry and type(identity) is int and identity!=0 and row.get('dry_library_id')==identity and versions.get('global_dry_error')==versions.get('global_before')
        typed=typed and versions.get('global_dry_error')==versions.get('global_before')
        history=history and type(identity) is int and identity!=0 and row.get('undo_library_id')==identity and bool(row.get('original_clip_ids')) and row.get('undo_clip_ids')==row.get('original_clip_ids')
    checks={key:'pass' if value else 'fail' for key,value in
            [('dry_run',dry),('typed_errors',typed),('undo_redo',history),('save_reopen',saved)]}
    if edit:
        errors=clean and type(row.get('errors_before')) is int and row.get('errors_after')==row['errors_before'] and row.get('errors')==[]
        # Source means the non-target inputs: other clips, another player,
        # and (when instanced) its peer and immutable packed source file.
        changed=[str(row['request'].get('animation_name'))]
        if row['op']=='merge':changed=['walk_run']
        if row['op']=='split_at':changed.append('walk_head')
        clips=before.get('clips',{});actual=generated.get('clips',{})
        source=clean and bool(clips) and 'other' in before and 'other' in generated and equivalent(before['other'],generated['other']) and all(name in actual and equivalent(value,actual[name]) for name,value in clips.items() if name not in changed)
        if row.get('mode') in {'instanced','editable'}:
            digest=row.get('source_sha256_before')
            expected='user://edit_source_%s_%s_%s.tscn'%(row.get('mode'),row.get('op'),row.get('variant'))
            source=source and row.get('source_path')==expected and isinstance(digest,str) and re.fullmatch('[0-9a-f]{64}',digest) is not None and row.get('source_sha256_after')==digest and bool(row.get('peer_before')) and equivalent(row['peer_before'],row.get('peer_after')) and equivalent(before,row.get('pristine'))
        checks.update(reported_errors='pass' if errors else 'fail',source_unchanged='pass' if source else 'fail')
    return checks


def verify_event(event,context,begins,support):
    edit=event.get('validator')=='edit_history_v1'
    driver='test_edit_route_history.gd' if edit else 'test_fx_route_history.gd'
    suite='edit_route_history' if edit else 'fx_route_history'
    family='animation_edit' if edit else 'animation_fx'
    dependencies=context.get('dependencies',{})
    for path in ('test_project/tests/test_fx_route_history.gd',
                 'test_project/tests/operation_history_trace.gd',
                 'tools/mcp_presets_audit.py','tools/operation_history_checks.py'):
        if path not in dependencies:raise ValueError('inner history source not bound: '+path)
    if edit and any(path not in dependencies for path in ('test_project/tests/test_edit_route_history.gd','test_project/tests/test_graph_route_history.gd')):
        raise ValueError('edit inner history lacks actual case/logger dependencies')
    if event.get('driver')!=driver or event.get('validator') not in {'fx_history_v1','edit_history_v1'} or event.get('route')!='public_test_run_inner_dispatch':
        raise ValueError('unknown inner history assertion source')
    row=event.get('row',{})
    if row.get('suite')!=suite or (EDIT_TESTS if edit else TESTS).get(row.get('mode'))!=row.get('test'):
        raise ValueError('history case suite/mode/test binding differs')
    if edit and (row.get('variant') not in {'base','overwrite','cross'} or (row['variant']=='overwrite' and row.get('op') not in {'split_at','merge'}) or (row['variant']=='cross' and row.get('op') not in {'merge','layer'})):
        raise ValueError('edit history variant is not an actual inner case')
    if event.get('operation')!=family+'.'+row.get('op','') or row.get('request',{}).get('op')!=row.get('op'):
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
            'limits':('Exact edit dry/error/Undo/Redo/saved snapshots, case-local engine errors and non-target clips/OtherPlayer/peer/packed-source invariants. ' if edit else 'Exact FX inner dispatcher dry/error/Undo/Redo and saved snapshots. ')+
                     'Bound to one actual public test_run; no individual external invocation, semantic effect, visual/audio or broader source invariant inferred.'}
