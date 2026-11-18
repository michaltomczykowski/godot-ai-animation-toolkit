"""Actual per-row snapshot assertions for public FX/edit audit drivers.

Only dry-run invariance, durable save/reopen and explicit typed wrap refusals
are derived here. No generic semantic/history/visual qualification is inferred.
"""
from __future__ import annotations
import math


def equivalent(left,right):
    if isinstance(left,bool) or isinstance(right,bool):return type(left) is bool and type(right) is bool and left==right
    if isinstance(left,(int,float)) and isinstance(right,(int,float)):
        return math.isfinite(left) and math.isfinite(right) and math.isclose(left,right,rel_tol=1e-6,abs_tol=1e-5)
    if isinstance(left,dict) and isinstance(right,dict):return left.keys()==right.keys() and all(equivalent(left[key],right[key]) for key in left)
    if isinstance(left,list) and isinstance(right,list):return len(left)==len(right) and all(equivalent(a,b) for a,b in zip(left,right))
    return type(left) is type(right) and left==right


def successful(value):return isinstance(value,dict) and bool(value) and not value.get('error')


def error_code(value):
    error=value.get('error','') if isinstance(value,dict) else ''
    return error.get('code','') if isinstance(error,dict) else str(error).split(':',1)[0]


def derive(validator,row):
    if validator not in {'fx_snapshot_v1','edit_snapshot_v1'}:raise ValueError('unknown snapshot assertion source')
    required={'op','scene','request','before','after_dry','after','persisted','open','dry','write','save','reopen'}
    if not required.issubset(row):return {'dry_run':'fail','save_reopen':'fail'}
    rejected=validator=='edit_snapshot_v1' and row['op'].endswith('_wrap_reject')
    if rejected:
        return {'typed_errors':'pass' if error_code(row['dry'])=='VALUE_OUT_OF_RANGE' and error_code(row['write'])=='VALUE_OUT_OF_RANGE' and equivalent(row['before'],row['after_dry']) and equivalent(row['before'],row['after']) and equivalent(row['before'],row['persisted']) else 'fail'}
    dry=successful(row['open']) and successful(row['dry']) and row['dry'].get('dry_run') is True and equivalent(row['before'],row['after_dry'])
    after,persisted=row['after'],row['persisted']
    if validator=='fx_snapshot_v1' and row['op'].startswith('sprite_frames'):
        # A running native frame is not durable scene data. Verify persisted
        # SpriteFrames assignment and animation identity; native playback is separate.
        after={key:after.get(key) for key in ('assigned','animation')}
        persisted={key:persisted.get(key) for key in ('assigned','animation')}
    if validator=='fx_snapshot_v1':
        available=(after.get('assigned') is True and bool(after.get('animation'))) if row['op'].startswith('sprite_frames') else all(successful(row[label].get('describe')) and len(row[label]['describe'].get('clips',[]))==1 for label in ('after','persisted'))
    else:available=successful(after) and successful(persisted)
    saved=available and all(successful(row[key]) for key in ('open','write','save','reopen')) and equivalent(after,persisted)
    if validator=='edit_snapshot_v1' and row['op']=='split_at':
        saved=saved and successful(row.get('head')) and equivalent(row['head'],row.get('persisted_head'))
    return {'dry_run':'pass' if dry else 'fail','save_reopen':'pass' if saved else 'fail'}


def probe_matches(snapshot,validator,events,player,animation,scene,lower,upper):
    rows=[event for event in events if event.get('scene')==scene and lower<event['execution_ns']<upper and event.get('params',{}).get('player_path')==player and event.get('params',{}).get('animation_name')==animation]
    if validator=='fx_snapshot_v1':
        described=snapshot.get('describe');timeline=snapshot.get('timeline')
    else:
        described={key:value for key,value in snapshot.items() if key!='timeline'}
        timeline=snapshot.get('timeline')
    descriptions=[event for event in rows if event.get('operation')=='animation_inspect.describe']
    timelines=[event for event in rows if event.get('operation')=='animation_inspect.timeline']
    if validator=='fx_snapshot_v1':
        return any(equivalent(event['response'],described) for event in descriptions) and any(equivalent(event['response'],timeline) for event in timelines)
    if 'error' in described:
        return any(equivalent(event.get('response',{}).get('error','clip absent'),described['error']) and not event.get('response',{}).get('clips') for event in descriptions)
    return any(len(event.get('response',{}).get('clips',[]))==1 and equivalent(event['response']['clips'][0],described) for event in descriptions) and any(equivalent(event['response'],timeline) for event in timelines)


def verify_event(event,context,public_events,scene_events):
    validator=event.get('validator');row=event.get('row',{})
    source={'fx_snapshot_v1':'mcp_fx_audit.py','edit_snapshot_v1':'mcp_edit_audit.py'}.get(validator)
    if not source or event.get('driver')!=source or any(path not in context['dependencies'] for path in ('tools/'+source,'tools/operation_snapshot_checks.py')):
        raise ValueError('snapshot assertions lack their actual source-bound driver')
    checks=derive(validator,row)
    if checks!=event.get('checks'):raise ValueError('declared snapshot checks differ from actual comparisons')
    family='animation_fx' if validator=='fx_snapshot_v1' else 'animation_edit'
    op='sprite_frames' if row.get('op')=='sprite_frames_stopped' else row.get('op','').removesuffix('_wrap_reject')
    if event.get('operation')!=family+'.'+op or row.get('request',{}).get('op')!=op:
        raise ValueError('snapshot operation differs from actual row request')
    def matching(params,response):
        return [call for call in public_events if call.get('operation')==event['operation'] and call.get('scene')==row.get('scene') and equivalent(call.get('params'),params) and equivalent(call.get('response'),response) and call['execution_ns']<event['execution_ns']]
    writes=matching(row.get('request'),row.get('write'))
    drys=matching(dict(row.get('request',{}),dry_run=True),row.get('dry'))
    if not writes or not drys:raise ValueError('snapshot comparisons lack their exact actual write/dry public calls')
    write=max(writes,key=lambda call:call['execution_ns']);dry=max(drys,key=lambda call:call['execution_ns'])
    if dry['execution_ns']>=write['execution_ns']:raise ValueError('dry/write source order differs')
    failures=[]
    if not row.get('op','').startswith('sprite_frames'):
        player=row['request'].get('player_path');animation=row.get('inspection_animation',row['request'].get('animation_name'))
        for label,lower,upper in [('before',0,dry['execution_ns']),('after_dry',dry['execution_ns'],write['execution_ns'])]:
            if not probe_matches(row[label],validator,public_events,player,animation,row['scene'],lower,upper):
                failures.append('actual '+label+' inspection not bound')
                if 'dry_run' in checks:checks['dry_run']='fail'
        saves=[call for call in scene_events if call.get('public_tool')=='scene_save' and call.get('scene')==row['scene'] and successful(call.get('response')) and write['execution_ns']<call['execution_ns']<event['execution_ns']]
        opens=[call for call in scene_events if call.get('public_tool')=='scene_open' and call.get('request',{}).get('path')==row['scene'] and call.get('request',{}).get('force_reload') is True and successful(call.get('response')) and write['execution_ns']<call['execution_ns']<event['execution_ns']]
        pairs=[(save,opened) for save in saves for opened in opens if save['execution_ns']<opened['execution_ns']]
        bound=any(probe_matches(row['after'],validator,public_events,player,animation,row['scene'],write['execution_ns'],save['execution_ns']) and probe_matches(row['persisted'],validator,public_events,player,animation,row['scene'],opened['execution_ns'],event['execution_ns']) for save,opened in pairs)
        if not bound:
            failures.append('actual save/forced reopen/paired inspections not bound')
            if 'save_reopen' in checks:checks['save_reopen']='fail'
    else:
        def node_matches(snapshot,lower,upper):
            for call in scene_events:
                if call.get('public_tool')!='node_get_properties' or call.get('request',{}).get('path')!=row['request'].get('sprite_path') or call.get('scene')!=row['scene'] or not lower<call['execution_ns']<upper:continue
                response=call.get('response',{})
                if response.get('error'):
                    actual=response
                else:
                    props={item['name']:item.get('value') for item in response.get('properties',[])}
                    actual={'assigned':bool(props.get('sprite_frames')),'animation':props.get('animation'),'frame':props.get('frame')}
                if equivalent(actual,snapshot):return True
            return False
        if not node_matches(row['before'],0,dry['execution_ns']) or not node_matches(row['after_dry'],dry['execution_ns'],write['execution_ns']):
            checks['dry_run']='fail';failures.append('actual SpriteFrames dry property probes not bound')
        saves=[call for call in scene_events if call.get('public_tool')=='scene_save' and call.get('scene')==row['scene'] and successful(call.get('response')) and write['execution_ns']<call['execution_ns']<event['execution_ns']]
        opens=[call for call in scene_events if call.get('public_tool')=='scene_open' and call.get('request',{}).get('path')==row['scene'] and call.get('request',{}).get('force_reload') is True and successful(call.get('response')) and write['execution_ns']<call['execution_ns']<event['execution_ns']]
        if not any(save['execution_ns']<opened['execution_ns'] and node_matches(row['after'],write['execution_ns'],save['execution_ns']) and node_matches(row['persisted'],opened['execution_ns'],event['execution_ns']) for save in saves for opened in opens):
            checks['save_reopen']='fail';failures.append('actual SpriteFrames save/reopen property probes not bound')
    return {'checks':checks,'public_case_ids':[write['id']],'dry_case_ids':[dry['id']],
            'failures':failures,'limits':'Actual scoped dry/saved-target comparisons only; no Undo, full semantic, source-input or visual pass inferred.'}
