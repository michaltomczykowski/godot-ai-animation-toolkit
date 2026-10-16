"""Strict exact rig pose file cases, independent numeric pose oracle."""
import json
import math
from operation_library_file_checks import same, file_bytes
TEST='test_pose_file_and_shape_contracts'
DIR='res://animation_toolkit/rig_history_contracts/'

def near(a,b):
    if isinstance(a,bool) or isinstance(b,bool): return a is b
    if isinstance(a,(int,float)) and isinstance(b,(int,float)):
        return math.isfinite(a) and math.isfinite(b) and math.isclose(a,b,rel_tol=2e-5,abs_tol=2e-5)
    if isinstance(a,dict) and isinstance(b,dict): return a.keys()==b.keys() and all(near(a[k],b[k]) for k in a)
    if isinstance(a,list) and isinstance(b,list):return len(a)==len(b) and all(near(x,y) for x,y in zip(a,b))
    return type(a) is type(b) and a==b

def vec(kind,values):return dict(kind=kind,**dict(zip('xyzw',values)))
def native(v,kind,n):
    if not isinstance(v,dict) or v.get('type')!=kind:raise ValueError('missing native source component')
    result=[v.get(k) for k in 'xyzw'[:n]]
    if any(type(x) not in (int,float) or not math.isfinite(x) for x in result):raise ValueError('nonfinite native source')
    return result

def multiply(a,b):
    x,y,z,w=a; X,Y,Z,W=b
    return [w*X+x*W+y*Z-z*Y,w*Y-x*Z+y*W+z*X,w*Z+x*Y-y*X+z*W,w*W-x*X-y*Y-z*Z]

def saved_bones(row):
    inputs=row.get('source_bones')
    if not isinstance(inputs,list) or [x.get('name') for x in inputs]!=['arm_L','arm_R','untouched']:raise ValueError('unexpected native source bones')
    out={}
    for item in inputs:
        rest=native(item.get('rest_rotation'),'Quaternion',4)
        pose=native(item.get('pose_rotation'),'Quaternion',4)
        if not near(sum(x*x for x in rest),1) or not near(sum(x*x for x in pose),1):raise ValueError('source rotation is not normalized')
        q=multiply([-rest[0],-rest[1],-rest[2],rest[3]],pose)
        rp=native(item.get('rest_position'),'Vector3',3);p=native(item.get('pose_position'),'Vector3',3)
        out[item['name']]={'rotation':vec('quaternion',q),'position':vec('vector3',[x-y for x,y in zip(p,rp)]),'scale':vec('vector3',native(item.get('pose_scale'),'Vector3',3))}
    return out

def blend_bones(request):
    # Exact nontrivial endpoints authored by the source test; no production oracle.
    def bone(angle,pos,scale):return {'rotation':vec('quaternion',[0,0,math.sin(angle/2),math.cos(angle/2)]),'position':vec('vector3',pos),'scale':vec('vector3',scale)}
    expected_a={'rest_relative':True,'bones':{'arm_L':bone(0,[0,0,0],[1,1,1])}}
    expected_b={'rest_relative':True,'bones':{'arm_L':bone(math.pi/2,[2,4,6],[3,5,7])}}
    if not near(request.get('from_pose'),expected_a) or not near(request.get('to_pose'),expected_b):raise ValueError('blend inputs differ from exact nontrivial source pair')
    t=request.get('factor')
    if type(t) not in (int,float) or t not in (.25,.5):raise ValueError('unexpected authored blend factor')
    return {'arm_L':bone(math.pi/2*t,[2*t,4*t,6*t],[1+2*t,1+4*t,1+6*t])}

def pose_matches(doc,bones,source):
    return isinstance(doc,dict) and doc.get('format')=='godot-ai-animation-pose' and doc.get('version')==1 and doc.get('rest_relative') is True and doc.get('source')==source and near(doc.get('bones'),bones)

def canonical_source(source):
    # Native get_path includes editor UI ancestors. The public pose contract
    # names /<edited-root>/RigPoseHistory/Skeleton, as ValueCodec.from_node
    # documents. The exact fixture has these last two descendants under root.
    parts=source.split('/')
    if len(parts)<5 or parts[:2]!=['','root'] or any(not p or p in ('.','..') for p in parts[2:]) or parts[-2:]!=['RigPoseHistory','Skeleton']:
        raise ValueError('unexpected absolute native source path')
    return '/'+('/'.join(parts[-3:]))

def derive(row):
    op=row.get('op');request=row.get('request',{});reply=row.get('response',{})
    if op not in {'pose_save','pose_blend'} or request.get('op')!=op:raise ValueError('pose file operation differs from dispatch')
    path=DIR+('saved.json' if op=='pose_save' else 'blend.json')
    if request.get('path')!=path:raise ValueError('unexpected pose output path')
    before=file_bytes(row.get('file_before'),path);after=file_bytes(row.get('file_after'),path)
    if before is None or after is None:raise ValueError('source case must observe existing file bytes')
    source=row.get('source_path')
    if not isinstance(source,str) or not source.endswith('/RigPoseHistory/Skeleton'):raise ValueError('unexpected actual source path')
    if op=='pose_save' and request.get('skeleton_path')!=source:raise ValueError('pose source differs from dispatch')
    # Always require actual source reads, including blend non-target observations.
    captured=saved_bones(row)
    invariant=row.get('failed_before') is False and bool(row.get('before')) and bool(row.get('scene_before')) and same(row['before'],row.get('after')) and same(row['scene_before'],row.get('scene_after')) and same(row.get('source_bones'),row.get('source_bones_after')) and type(row.get('history_before')) is int and row.get('history_after')==row['history_before'] and type(row.get('global_before')) is int and row.get('global_after')==row['global_before']
    clean=type(row.get('errors_before')) is int and row.get('errors_after')==row['errors_before'] and row.get('errors')==[]
    dry=request.get('dry_run') is True
    checks={'source_unchanged':'pass' if invariant else 'fail','non_target_preserved':'pass' if invariant else 'fail','reported_errors':'pass' if clean else 'fail'}
    if 'error' in reply:
        error=reply['error']
        valid=op=='pose_save' and request.get('overwrite') is False and before==b'sentinel' and after==before and isinstance(error,dict) and error.get('code')=='INVALID_PARAMS' and bool(error.get('message'))
        checks['typed_errors']='pass' if invariant and valid else 'fail'
        if before!=after:checks['source_unchanged']='fail'
        return checks
    data=reply.get('data',{})
    bones=captured if op=='pose_save' else blend_bones(request)
    expected_source=canonical_source(source) if op=='pose_save' else ''
    valid=isinstance(data,dict) and data.get('undoable') is False and data.get('saved_path')==path and data.get('bone_count')==len(bones) and pose_matches(data.get('pose'),bones,expected_source)
    if op=='pose_save':valid=valid and data.get('kind')=='3d' and data.get('skeleton_path')==expected_source
    else:valid=valid and data.get('factor')==request['factor'] and data.get('only_in_from')==[] and data.get('only_in_to')==[]
    if dry:
        checks['dry_run']='pass' if invariant and valid and data.get('dry_run') is True and before==after else 'fail'
        if before!=after:checks['source_unchanged']='fail'
    else:
        try:doc=json.loads(after.decode('utf-8'))
        except (UnicodeDecodeError,json.JSONDecodeError):doc=None
        valid=valid and pose_matches(doc,bones,expected_source) and near(doc,data.get('pose'))
        checks['valid_effect']='pass' if invariant and valid else 'fail'
        checks['file_effect']='pass' if invariant and valid and before!=after else 'fail'
    return checks

def verify_event(event,context,begins,support):
    dependencies=context.get('dependencies',{})
    for path in ('test_project/tests/test_rig_pose_history.gd','test_project/tests/operation_history_trace.gd',
                 'test_project/tests/test_preset_library_history.gd','test_project/tests/test_graph_route_history.gd',
                 'addons/godot_ai_animation/handlers/rig.gd','addons/godot_ai_animation/spec/pose_math.gd',
                 'addons/godot_ai_animation/handlers/animation_tool_base.gd','addons/godot_ai_animation/utils/value_codec.gd',
                 'addons/godot_ai_animation/spec/spec_json.gd','tools/mcp_presets_audit.py',
                 'tools/operation_library_file_checks.py','tools/operation_pose_file_checks.py'):
        if path not in dependencies:raise ValueError('pose file source not bound: '+path)
    row=event.get('row',{})
    if event.get('driver')!='test_rig_pose_history.gd' or event.get('validator')!='rig_pose_file_v1' or event.get('route')!='public_test_run_inner_dispatch' or row.get('suite')!='rig_pose_history' or row.get('test')!=TEST or row.get('mode')!='pose_file_contract':
        raise ValueError('unknown pose file contract source/case')
    if event.get('operation')!='animation_rig.'+row.get('op','') or type(row.get('ordinal')) is not int or row['ordinal']<1 or type(row.get('assertion_count_before')) is not int or row['assertion_count_before']<0:
        raise ValueError('pose file operation/case identity differs')
    signature={1:('pose_save',True,False),2:('pose_save',False,False),3:('pose_save',False,True),4:('pose_save',True,True),5:('pose_blend',False,True),6:('pose_blend',True,True)}
    actual_signature=(row['op'],row.get('request',{}).get('dry_run',False),row.get('request',{}).get('overwrite'))
    if signature.get(row['ordinal'])!=actual_signature:raise ValueError('pose ordinal/request differs from exact authored dispatch')
    token=event.get('test_run_begin_id')
    starts=[item for item in begins if item.get('id')==token]
    ends=[item for item in support if item.get('public_tool')=='test_run' and item.get('test_run_begin_id')==token]
    if len(starts)!=1 or len(ends)!=1:raise ValueError('pose case lacks unique actual public span')
    start,end=starts[0],ends[0]
    if start.get('request')!=end.get('request') or start.get('request',{}).get('suite')!='rig_pose_history' or start['request'].get('verbose') is not True or start.get('execution_ns',0)>=end.get('execution_ns',0):raise ValueError('pose public request/order differs')
    checks=derive(row)
    actual=[item for item in end.get('response',{}).get('results',[]) if isinstance(item,dict) and item.get('suite')=='rig_pose_history' and item.get('test')==TEST]
    if len(actual)!=1 or actual[0].get('passed') is not True or actual[0].get('skipped',False) or type(actual[0].get('assertion_count')) is not int or actual[0]['assertion_count']<30 or actual[0]['assertion_count']<=row.get('assertion_count_before',-1):
        checks={key:'fail' for key in checks}
    return {'checks':checks,'public_test_run_case_id':end['id'],
            'limits':'Exact saved pose/blend file bytes, independently calculated pose output, fixture plus scene transform/bone invariance, and scene/global history. No external operation invocation, scene Undo/Redo, playback or visual/audio qualification.'}
