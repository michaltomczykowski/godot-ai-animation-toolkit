"""Independent scoped predicates for existing rig history matrices, not motion oracles."""
from copy import deepcopy
import math
import re

WRITERS = {'pose_to_clip','walk_cycle','idle_breathing','blink','jumping_jack','squat','punch','bake_pose_sequence'}
OPS = WRITERS | {'pose_apply','rig_chain'}
DEPENDENCIES = ('test_project/tests/rig_history_observation.gd',
 'test_project/tests/operation_history_trace.gd','test_project/tests/test_rig_pose_history.gd',
 'test_project/tests/test_rig_chain_history.gd','test_project/tests/test_rig_clip_history.gd',
 'test_project/tests/test_preset_library_history.gd','test_project/tests/test_edit_route_history.gd',
 'test_project/tests/test_rig_bake_state.gd','test_project/tests/test_graph_route_history.gd',
 'tools/operation_rig_scene_history_checks.py','tools/mcp_presets_audit.py',
 'addons/godot_ai_animation/handlers/rig.gd','addons/godot_ai_animation/handlers/animation_tool_base.gd',
 'addons/godot_ai_animation/spec/pose_math.gd','addons/godot_ai_animation/utils/error_codes.gd')
ROLES = dict(zip('hips spine chest head arm_l arm_r forearm_l forearm_r thigh_l thigh_r shin_l shin_r foot_l foot_r'.split(),
                 'hips spine chest head arm_L arm_R forearm_L forearm_R thigh_L thigh_R shin_L shin_R foot_L foot_R'.split()))

def digest(v):return isinstance(v,str) and re.fullmatch('[0-9a-f]{64}',v) is not None
def same(a,b,native=False):
    if isinstance(a,bool) or isinstance(b,bool):return type(a) is type(b) and a==b
    if type(a) in (float,int) and type(b) in (float,int):
        return math.isfinite(a) and math.isfinite(b) and (a==b or abs(a-b)<1e-5*(max(abs(a),1) if native else 1))
    if isinstance(a,dict) and isinstance(b,dict):
        native = native or a.get('type') in {'Vector2','Vector3','Quaternion','Transform2D','Transform3D','Basis','Color'}
        return a.keys()==b.keys() and all(same(a[k],b[k],native) for k in a)
    if isinstance(a,list) and isinstance(b,list):return len(a)==len(b) and all(same(x,y,native) for x,y in zip(a,b))
    return type(a) is type(b) and a==b

def pose(bone='arm_L',angle=.6):
    return {'rest_relative':True,'bones':{bone:{'rotation':{'kind':'quaternion','z':math.sin(angle/2),'w':math.cos(angle/2)}}}}

def expected_request(row):
    op,kind,mode,variant=row['op'],row['kind'],row['mode'],row['variant']
    root=row.get('fixture_path','')
    name='RigPoseHistory' if op=='pose_apply' else 'RigChainHistory' if op=='rig_chain' else 'RigClipHistory'
    if not root.endswith('/'+name):raise ValueError('actual fixture path missing')
    if op=='pose_apply':
        p=pose();p['bones']['arm_L'].update(position={'kind':'vector3','x':.4,'y':-.3},scale={'kind':'vector3','x':1.6,'y':.6,'z':1.3})
        return dict(op=op,skeleton_path=root+'/Skeleton',pose=p,blend=.5 if variant in {'blend','reset_blend'} else 1.,reset_first=variant in {'reset','reset_blend'},mirror=variant=='mirror')
    if op=='rig_chain':
        if variant=='subtree':return dict(op=op,node_path=root+'/Branch',name='Generated')
        return dict(op=op,kind=kind,name='Generated',skeleton_path=root+('/Skeleton' if variant=='append' else '/Generated'),bones=[dict(name='tool',parent='arm_L' if variant=='append' else '',position=[.5,1.,0.],rotation=[0.,0.,30.],scale=[1.4,.8,1.2],length=15.)])
    p=dict(op=op,duration=1.,loop_mode='none',roles=ROLES,spine_chain=['spine','chest','head'],player_path=root+'/Playback/AnimationPlayer',skeleton_path=root+'/Character/Skeleton',animation_name='generated',overwrite=mode=='overwrite')
    if op=='pose_to_clip':p['keys']=[dict(time=0.,pose=pose(angle=0)),dict(time=1.,pose=pose())]
    elif op=='blink':p.update(bones=['eye'],closed_scale=.1)
    elif op=='bake_pose_sequence':p.update(source_animation='source/input',bones=['hips'],fps=4,scales=True)
    elif op=='squat':p['bob']=.2
    return p

def case_identity(row):
    op=row.get('op');mode=row.get('mode');kind=row.get('kind');variant=row.get('variant')
    if op not in OPS or kind not in {'2d','3d'}:raise ValueError('unknown rig history operation/kind')
    if op in WRITERS:
        if mode not in {'local','overwrite','missing_library','instanced','editable'} or variant!='clip' or (kind=='2d' and op!='pose_to_clip'):raise ValueError('unknown rig clip case')
        suite='rig_clip_history';test='test_'+mode+'_history';label=f'{mode}_{kind}_{op}';family='clip'
    else:
        if mode not in {'local','locked','editable'}:raise ValueError('unknown rig scene mode')
        allowed={'apply','blend','reset','reset_blend','mirror'} if op=='pose_apply' else {'create','append','subtree'}
        if variant not in allowed:raise ValueError('unknown rig scene variant')
        family='pose' if op=='pose_apply' else 'chain';suite='rig_'+family+'_history';test=f'test_{mode}_{family}_history';label=f'{kind}_{mode}_{variant}'
    if (row.get('suite'),row.get('test'),row.get('label'))!=(suite,test,label):raise ValueError('rig case source identity mismatch')
    if not same(row.get('request'),expected_request(row)):raise ValueError('rig fixed case request mismatch')
    return family

def invariant(row):
    before=deepcopy(row['before']['snapshot']);after=deepcopy(row['write']['state']['snapshot']);op=row['op']
    if op in WRITERS:
        try:
            for value in (before,after):value['players']['AnimationPlayer']['clips'].pop('generated',None)
            old=before['players']['AnimationPlayer'];new=after['players']['AnimationPlayer']
            if row['mode']=='missing_library':
                if old.get('libraries')!=['source'] or new.get('libraries')!=['','source']:return False
                new['libraries']=deepcopy(old['libraries'])
        except (KeyError,TypeError):return False
    elif op=='pose_apply':
        def authored(value):
            if not isinstance(value,dict):return
            if value.get('type')=='Bone2D':value.pop('transform',None)
            if value.get('type')=='Skeleton3D':
                for bone in value.get('bones',[]):bone.pop('pose',None)
            for child in value.get('children',{}).values():authored(child)
        authored(before);authored(after)
    else:
        try:
            if row['variant']=='append':
                skeleton=after['children']['Skeleton']
                if row['kind']=='3d':
                    old=before['children']['Skeleton']['bones']
                    if len(skeleton['bones'])!=len(old)+1 or skeleton['bones'][-1]['name']!='tool':return False
                    skeleton['bones'].pop()
                else:del skeleton['children']['arm_L']['children']['tool']
            else:
                parent=after['children']['Branch'] if row['variant']=='subtree' else after
                del parent['children']['Generated']
        except (KeyError,IndexError,TypeError):return False
    result=bool(before) and same(before,after)
    instanced=row['mode'] not in {'local','overwrite','missing_library'}
    if instanced:
        family='pose' if op=='pose_apply' else 'chain' if op=='rig_chain' else 'clip'
        result=result and row.get('source_path')==f"user://rig_{family}_source_{row['label']}.tscn" and digest(row.get('source_before')) and row.get('source_before')==row.get('source_after') and bool(row.get('peer_before')) and same(row['peer_before'],row.get('peer_after')) and same(row['peer_before'],row.get('pristine'))
    else:result=result and row.get('source_path')=='' and row.get('source_before')==''
    return result

def derive(row):
    family=case_identity(row)
    required={'before','dry','refusal','write','undo','redo','persist_undo','persist_redo','failed_before','failed_after','assertion_count','errors_before','errors_after','errors'}
    if not required.issubset(row):raise ValueError('missing raw rig history stages')
    clean=row['failed_before'] is False and row['failed_after'] is False and type(row['assertion_count']) is int and row['assertion_count']>0
    before=row['before'];write=row['write'];generated=write.get('state',{});request=row['request']
    states=[before]+[row[k].get('state',{}) for k in ('dry','refusal','write','undo','redo')]
    clean=clean and all(isinstance(v.get('snapshot'),dict) and bool(v['snapshot']) and type(v.get('version')) is int and type(v.get('global_version')) is int and type(v.get('editable')) is bool for v in states)
    clean=clean and before.get('editable') is (row['mode']=='editable') and generated.get('editable') is (row['mode'] in {'locked','instanced','editable'})
    def success(value):return isinstance(value,dict) and 'data'in value and not value.get('error')
    dry=success(row['dry'].get('response')) and same(before,row['dry'].get('state'))
    refused=deepcopy(request)
    if family=='pose':
        refused['pose']={'rest_relative':True,'bones':{'ghost':next(iter(request['pose']['bones'].values()))}}
    else:refused['node_path' if family=='chain' else 'player_path']='/Missing'
    error=row['refusal'].get('response',{}).get('error',{})
    typed=same(row['refusal'].get('request'),refused) and error.get('code')==('INVALID_PARAMS' if family=='pose' else 'NODE_NOT_FOUND') and isinstance(error.get('message'),str) and bool(error['message']) and same(before,row['refusal'].get('state'))
    history=success(write.get('response')) and type(before.get('version')) is int and type(before.get('global_version')) is int and generated.get('version')==before['version']+1 and generated.get('global_version')==before['global_version'] and not same(before.get('snapshot'),generated.get('snapshot')) and row['undo'].get('success') is True and row['redo'].get('success') is True and same(before,row['undo'].get('state')) and same(generated,row['redo'].get('state'))
    if family=='clip':history=history and bool(before.get('playback')) and same(before.get('playback'),generated.get('playback'))
    def persisted(stage,state):
        p=row['persist_'+stage]
        return p.get('path')==f"user://rig_{family}_history_{row['label']}_{stage}.tscn" and type(p.get('pack_result')) is int and p['pack_result']==0 and type(p.get('save_result')) is int and p['save_result']==0 and digest(p.get('sha256')) and same(p.get('snapshot'),state.get('snapshot'))
    saved=persisted('undo',before) and persisted('redo',generated)
    errors=type(row['errors_before']) is int and row['errors_before']>=0 and type(row['errors_after']) is int and row['errors_after']==row['errors_before'] and row['errors']==[]
    return {k:'pass' if clean and v else 'fail' for k,v in [('dry_run',dry),('typed_errors',typed),('undo_redo',history),('save_reopen',saved),('reported_errors',errors),('source_unchanged',invariant(row))]}

def verify_event(event,context,begins,support):
    for path in DEPENDENCIES:
        identity=context.get('dependencies',{}).get(path,{})
        if not digest(identity.get('sha256')) or re.fullmatch('[0-9a-f]{40}',str(identity.get('git_blob',''))) is None:raise ValueError('unbound rig source '+path)
    row=event.get('row',{});case_identity(row)
    if event.get('validator')!='rig_scene_history_v1' or event.get('driver')!='test_'+row['suite']+'.gd' or event.get('route')!='public_test_run_inner_dispatch' or event.get('operation')!='animation_rig.'+row['op'] or not context.get('run_id') or event.get('run_id')!=context['run_id']:raise ValueError('rig event source differs')
    span=event.get('test_run_begin_id');starts=[v for v in begins if v.get('id')==span];ends=[v for v in support if v.get('public_tool')=='test_run' and v.get('test_run_begin_id')==span]
    if len(starts)!=1 or len(ends)!=1:raise ValueError('rig history lacks unique actual public span')
    start,end=starts[0],ends[0];request=start.get('request',{})
    if request!=end.get('request') or request.get('suite')!=row['suite'] or request.get('verbose') is not True or start.get('execution_ns',0)>=end.get('execution_ns',0) or start.get('scene')!=row.get('scene') or end.get('scene')!=row['scene'] or type(event.get('time_ns')) is not int or not start.get('time_ns',0)<=event['time_ns']<=end.get('time_ns',0):raise ValueError('rig public request/scene/order mismatch')
    checks=derive(row)
    matches=[v for v in end.get('response',{}).get('results',[]) if v.get('suite')==row['suite'] and v.get('test')==row['test']]
    if len(matches)!=1 or matches[0].get('passed') is not True or matches[0].get('skipped',False) or type(matches[0].get('assertion_count')) is not int or matches[0]['assertion_count']<row['assertion_count']:checks={k:'fail' for k in checks}
    return {'checks':checks,'public_test_run_case_id':end['id'],'limits':'Existing fixed rig case inner dispatch: exact dry/refusal/history/saved reload, synchronous post-seed logger errors, observed authored rest/hierarchy/non-target clips and peer/source invariants. Native playback, full requested effect, allocation identities and visual quality remain separate gates.'}
