"""Raw273-case history evidence only; native physical/reference effects stay pending."""
import math
import re

MOTIONS=('walk_cycle','run_cycle','idle_cycle','jump','turn_cycle','strafe_cycle','walk_start','walk_stop','cycle_walk','cycle_run','cycle_idle')
SEQUENCES=('gap','partial','saved_pose','inline_pose','rooted','self_overwrite')
DEPENDENCIES=('test_project/tests/test_motion_sequence_history.gd','test_project/tests/motion_sequence_history_trace.gd','test_project/tests/operation_history_trace.gd','test_project/tests/motion_sequence_saved_matrix.gd','test_project/tests/test_rig_clip_history.gd','test_project/tests/test_rig_pose_history.gd','test_project/tests/test_preset_library_history.gd','test_project/tests/test_edit_route_history.gd','test_project/tests/test_rig_bake_state.gd','test_project/tests/test_graph_route_history.gd','tools/operation_motion_sequence_history_checks.py','tools/mcp_motion_sequence_history.py','tools/mcp_presets_audit.py','addons/godot_ai_animation/handlers/motion.gd','addons/godot_ai_animation/handlers/sequence.gd')
ROLES={n:n for n in ('hips','spine','chest','head')}
ROLES.update({part+'_'+side.lower():part+'_'+side for part in ('arm','forearm','thigh','shin','foot') for side in ('L','R')})
def number(v):return type(v) in (int,float) and math.isfinite(v)
def digest(v):return isinstance(v,str) and re.fullmatch('[0-9a-f]{64}',v) is not None
def finite_tree(v):
    if type(v) in (int,float):return math.isfinite(v)
    if isinstance(v,dict):return all(finite_tree(x) for x in v.values())
    if isinstance(v,list):return all(finite_tree(x) for x in v)
    return True

def exact(a,b):
    if number(a) and number(b):return abs(a-b)<=1e-14*max(1.,abs(a),abs(b))
    if type(a) is not type(b):return False
    if isinstance(a,dict):return a.keys()==b.keys() and all(exact(a[k],b[k]) for k in a)
    if isinstance(a,list):return len(a)==len(b) and all(exact(x,y) for x,y in zip(a,b))
    return a==b

def snapshot_same(a,b,typed=False):
    # Existing engine snapshots use is_equal_approx for typed geometry only.
    # Resource numeric properties/key times retain exact equality.
    if number(a) and number(b):return abs(a-b)<max(1e-5,1e-5*abs(a)) if typed else a==b
    if type(a) is not type(b):return False
    if isinstance(a,dict):
        typed=typed or a.get('type') in ('Vector2','Vector3','Quaternion','Color','Basis','Transform2D','Transform3D')
        return a.keys()==b.keys() and all(snapshot_same(a[k],b[k],typed) for k in a)
    if isinstance(a,list):return len(a)==len(b) and all(snapshot_same(x,y,typed) for x,y in zip(a,b))
    return a==b

def identity(row):
    group,variant,mode,fps=(row.get(k) for k in ('group','variant','mode','fps'))
    variants=MOTIONS if group=='motion' else SEQUENCES if group=='sequence' else ('single','branches') if group=='secondary' else ()
    modes=('local','instanced','editable') if group=='secondary' else ('local','instanced','editable','missing_library','overwrite')
    if variant not in variants or mode not in modes or type(fps) is not int or fps not in (30,60,120):raise ValueError('unknown motion/sequence matrix identity')
    family='animation_sequence' if group=='sequence' else 'animation_motion'
    op='compose' if group=='sequence' else 'secondary_motion' if group=='secondary' else 'cycle' if variant.startswith('cycle_') else variant
    test='test_'+group+'_'+('locked' if mode=='instanced' else mode)
    if row.get('case_id')!=f'{group}_{variant}_{mode}_{fps}' or row.get('family')!=family or row.get('op')!=op or row.get('test')!=test:raise ValueError('motion/sequence case operation mismatch')
    return family,op

def expected_request(row):
    family,op=identity(row);g,v,m,f=(row[k] for k in ('group','variant','mode','fps'))
    player=row.get('request',{}).get('player_path','')
    if not isinstance(player,str) or not player.startswith('/') or not player.endswith('/MotionSequenceHistory/Playback/AnimationPlayer'):raise ValueError('unexpected player path')
    base=player.removesuffix('Playback/AnimationPlayer')
    p=dict(op=op,player_path=player,skeleton_path=base+'Character/Skeleton',animation_name='generated',duration=1.2 if v=='jump' else 1.,samples=f,roles=ROLES,spine_chain=['spine','chest','head'],overwrite=m=='overwrite')
    if g=='motion':
        if op=='cycle':p['preset']=v.removeprefix('cycle_')
        p['root_motion']=v in ('walk_cycle','run_cycle','strafe_cycle','walk_start','walk_stop','cycle_walk','cycle_run')
        p['loop_mode']='linear' if v in ('walk_cycle','run_cycle','idle_cycle','strafe_cycle','cycle_walk','cycle_run','cycle_idle') else 'none'
    elif g=='secondary':p.update(animation_name='unrelated',bones=['hand_L'] if v=='single' else ['hand_L','hand_R'],stiffness=120.,damping=12.)
    else:
        p.update(duration=1.6,segments=[dict(start=0.,duration=.6,source_animation='source/first'),dict(start=.8,duration=.8,source_animation='source/second')])
        if v in ('partial','rooted','self_overwrite'):p.update(duration=1.4,segments=[dict(start=0.,duration=1.,source_animation='source/first'),dict(start=.6,duration=.8,source_animation='source/second',fade_in=.2)])
        if v=='rooted':
            p['segments'][0].update(source_start=.1,source_end=.9)
            p['segments'][1].update(source_start=.2,source_end=.8,contacts=[dict(name='impact',time=.3)])
        elif v in ('saved_pose','inline_pose'):
            p['segments']=[dict(start=0.,duration=.6,source_animation='source/first'),dict(start=.5,duration=.6,fade_in=.1),dict(start=1.,duration=.6,source_animation='source/second',fade_in=.1)]
            if v=='saved_pose':p['segments'][1]['pose_name']='matrix_history_pose'
            else:p['segments'][1]['pose']={'rest_relative':True,'bones':{'arm_L':{'rotation':{'kind':'quaternion','x':math.sin(.3),'w':math.cos(.3)}}}}
        if v=='self_overwrite' and m=='overwrite':p['segments'][0]['source_animation']='generated'
    return p

def derive(r):
    identity(r)
    required=('request','dry','invalid_request','invalid','write','before','after_dry','after_error','generated','undone','redone','versions','persist_do','persist_undo','persist_redo','playback_before','playback_dry','playback_error','playback_write','playback_undo','playback_redo','undo_success','redo_success','failed_before','failed_after','assertion_count','errors_before','errors_after','errors','orphans_before','orphans_dry','orphans_error','orphans_write','source_library_identity','undo_library_identity','redo_clip_identity','peer_before','peer_after','source_bytes_unchanged')
    if any(k not in r for k in required):raise ValueError('incomplete raw motion/sequence stages')
    clean=finite_tree(r) and exact(r['request'],expected_request(r)) and r['failed_before'] is False and r['failed_after'] is False and type(r['assertion_count']) is int and r['assertion_count']>=20
    v=r['versions'];b=r['before'];a=r['generated'];pb=r['playback_before']
    versions=all(type(v.get(k)) is int for k in ('before','global_before','dry','global_dry','error','global_error','write','global_write','undo','global_undo','redo','global_redo'))
    fixed=versions and all(v.get('global_'+stage)==v['global_before'] for stage in ('dry','error','write','undo','redo'))
    dry=clean and fixed and r['dry'].get('data',{}).get('dry_run') is True and not r['dry'].get('error') and exact(b,r['after_dry']) and exact(pb,r['playback_dry']) and v['dry']==v['before'] and r['orphans_before']==r['orphans_dry']
    err=r['invalid'].get('error',{})
    typed=clean and fixed and exact(r['invalid_request'],dict(r['request'],player_path='/Missing')) and err.get('code')=='NODE_NOT_FOUND' and isinstance(err.get('message'),str) and bool(err['message']) and exact(b,r['after_error']) and exact(pb,r['playback_error']) and v['error']==v['before'] and r['orphans_before']==r['orphans_error']
    history=clean and fixed and isinstance(r['write'].get('data'),dict) and not r['write'].get('error') and b!=a and r['undo_success'] is True and r['redo_success'] is True and exact(b,r['undone']) and exact(a,r['redone']) and v['write']==v['before']+1 and v['undo']==v['before'] and v['redo']==v['write'] and all(exact(pb,r['playback_'+s]) for s in ('write','undo','redo')) and all(r[k] is True for k in ('source_library_identity','undo_library_identity','redo_clip_identity')) and set(r['orphans_write']).issubset(set(r['orphans_before']))
    def saved(stage,expected):
        p=r['persist_'+stage]
        return p.get('path')=='user://motion_sequence_'+r['case_id']+'_'+stage+'.tscn' and digest(p.get('sha256')) and type(p.get('bytes')) is int and p['bytes']>0 and p.get('matches_expected') is True and snapshot_same(p.get('snapshot'),expected)
    persisted=clean and r.get("source_scene_path")=="user://motion_sequence_"+r["case_id"]+"_source.tscn" and digest(r.get("source_scene_sha256")) and type(r.get("source_scene_bytes")) is int and r["source_scene_bytes"]>0 and all(saved(stage,state) for stage,state in (('do',a),('undo',b),('redo',a)))
    # All hierarchy/rest/pose and non-target player/source clips must remain intact.
    source=clean and b.get('children')==a.get('children') and bool(b.get('players')) and b['players'].get('OtherPlayer')==a.get('players',{}).get('OtherPlayer') and r['source_library_identity'] is True
    target=r['request']['animation_name']
    bc=b.get('players',{}).get('AnimationPlayer',{}).get('clips',{})
    ac=a.get('players',{}).get('AnimationPlayer',{}).get('clips',{})
    source=source and bool(bc) and {k:x for k,x in bc.items() if k!=target}=={k:x for k,x in ac.items() if k!=target}
    if r['mode'] in ('instanced','editable'):
        source=source and r.get('source_path')=='user://motion_sequence_instance_'+r['case_id']+'.tscn' and digest(r.get('source_sha256_before')) and r.get('source_sha256_before')==r.get('source_sha256_after') and type(r.get('source_bytes_before')) is int and r['source_bytes_before']>0 and r.get('source_bytes_after')==r['source_bytes_before'] and r['source_bytes_unchanged'] is True and bool(r['peer_before']) and exact(r['peer_before'],r['peer_after'])
    else:source=source and r.get('source_path')=='' and r['peer_before']==r['peer_after']=={} and r['source_bytes_unchanged'] is True
    errors=clean and type(r['errors_before']) is int and type(r['errors_after']) is int and r['errors_before']==r['errors_after'] and type(r['errors']) is list and r['errors']==[]
    return {k:'pass' if value else 'fail' for k,value in (('dry_run',dry),('typed_errors',typed),('undo_redo',history),('save_reopen',persisted),('source_unchanged',source),('reported_errors',errors))}


def verify_event(event,context,begins,support):
    for path in DEPENDENCIES:
        dep=context.get('dependencies',{}).get(path,{})
        if not digest(dep.get('sha256')) or not isinstance(dep.get('git_blob'),str) or re.fullmatch('[0-9a-f]{40}',dep['git_blob']) is None:raise ValueError('motion/sequence dependency lacks exact source identity')
    if event.get('run_id')!=context.get('run_id') or not isinstance(context.get('run_id'),str) or not context['run_id']:raise ValueError('foreign motion/sequence run')
    if event.get('validator')!='motion_sequence_history_v1' or event.get('driver')!='test_motion_sequence_history.gd' or event.get('route')!='public_test_run_inner_dispatch':raise ValueError('unknown motion/sequence source')
    r=event.get('row',{});family,op=identity(r)
    if r.get('suite')!='motion_sequence_history' or event.get('operation')!=family+'.'+op:raise ValueError('wrong operation/suite')
    begin=event.get('test_run_begin_id');starts=[x for x in begins if x.get('id')==begin];ends=[x for x in support if x.get('public_tool')=='test_run' and x.get('test_run_begin_id')==begin]
    if len(starts)!=1 or len(ends)!=1:raise ValueError('missing unique actual public span')
    start,end=starts[0],ends[0];req=start.get('request',{})
    if any(x.get('driver')!='mcp_motion_sequence_history.py' or x.get('route')!='public_godot_ai' or x.get('public_tool')!='test_run' for x in (start,end)):raise ValueError('unexpected public driver/route')
    if start.get('kind')!='public_test_run_begin' or end.get('kind')!='public_support_call':raise ValueError('unexpected public span event kind')
    if not digest(event.get('context_sha256')) or any(x.get('context_sha256')!=event['context_sha256'] or x.get('run_id')!=context['run_id'] for x in (start,end)):raise ValueError('foreign public span context')
    if req!=end.get('request') or req!={'suite':r['suite'],'verbose':True} or start.get('execution_ns',0)>=end.get('execution_ns',0):raise ValueError('public request/order mismatch')
    stamp=event.get('time_ns')
    if type(stamp) is not int or not start.get('time_ns',0)<=stamp<=end.get('time_ns',0):raise ValueError('case outside actual public span')
    checks=derive(r)
    matches=[x for x in end.get('response',{}).get('results',[]) if x.get('suite')==r['suite'] and x.get('test')==r['test']]
    if len(matches)!=1 or matches[0].get('passed') is not True or matches[0].get('skipped',False) or type(matches[0].get('assertion_count')) is not int or matches[0]['assertion_count']<r['assertion_count']:checks={k:'fail' for k in checks}
    return {'checks':checks,'public_test_run_case_id':end['id'],'limits':'Raw case-local dry/refusal/history/save/source/logger observations only. Ten unique motion writers plus compose; character_setup separate. No independent per-case native reference hook: valid_effect, playback and track_paths_types remain pending, not inferred from273-case batch totals. Inner dispatch is bound to actual external verbose test_run, not an individual external operation invocation.'}
