import copy
import hashlib
import json
import math
import unittest
from operation_pose_file_checks import derive, saved_bones, blend_bones, TEST, verify_event

def native(kind,values):return dict(type=kind,**dict(zip('xyzw',values)))
def observation(path,raw):return {'path':path,'exists':True,'bytes_hex':raw.hex(),'sha256':hashlib.sha256(raw).hexdigest()}
def row(op='pose_save',dry=False):
    source='/root/Fixture/RigPoseHistory/Skeleton'
    path='res://animation_toolkit/rig_history_contracts/'+('saved.json' if op=='pose_save' else 'blend.json')
    bones=[]
    for i,name in enumerate(['arm_L','arm_R','untouched']):
        a=[.2,-.1,.35][i];b=[.5,-.4,.7][i]
        bones.append({'name':name,'rest_rotation':native('Quaternion',[0,0,math.sin(a/2),math.cos(a/2)]),'pose_rotation':native('Quaternion',[0,0,math.sin(b/2),math.cos(b/2)]),'rest_position':native('Vector3',[i+1,2,0]),'pose_position':native('Vector3',[i+1.1,2.2,0]),'pose_scale':native('Vector3',[1.2,.8,1.1])})
    request={'op':op,'path':path,'overwrite':True}
    if op=='pose_save':request['skeleton_path']=source
    else:
        def endpoint(angle,p,s):return {'rest_relative':True,'bones':{'arm_L':{'rotation':dict(kind='quaternion',x=0,y=0,z=math.sin(angle/2),w=math.cos(angle/2)),'position':dict(kind='vector3',**dict(zip('xyz',p))),'scale':dict(kind='vector3',**dict(zip('xyz',s)))}}}
        request.update(from_pose=endpoint(0,[0,0,0],[1,1,1]),to_pose=endpoint(math.pi/2,[2,4,6],[3,5,7]),factor=.25 if dry else .5)
    r={'op':op,'request':request,'source_path':source,'source_bones':bones,'source_bones_after':copy.deepcopy(bones),'before':{'fixture':'authored'},'after':{'fixture':'authored'},'scene_before':{'all_transforms':'authored'},'scene_after':{'all_transforms':'authored'},'failed_before':False,'history_before':3,'history_after':3,'global_before':4,'global_after':4,'errors_before':0,'errors_after':0,'errors':[]}
    expected=saved_bones(r) if op=='pose_save' else blend_bones(request)
    doc={'format':'godot-ai-animation-pose','version':1,'source':source if op=='pose_save' else '', 'rest_relative':True,'bones':expected}
    data={'pose':doc,'bone_count':len(expected),'saved_path':path,'undoable':False}
    if op=='pose_save':data.update(kind='3d',skeleton_path=source)
    else:data.update(factor=request['factor'],only_in_from=[],only_in_to=[])
    before=b'sentinel';after=json.dumps(doc).encode()
    if dry:request['dry_run']=True;data['dry_run']=True;before=after=b'previous-valid-bytes'
    r.update(file_before=observation(path,before),file_after=observation(path,after),response={'data':data})
    return r

class PoseFileTests(unittest.TestCase):
    def test_save_and_nontrivial_blend(self):
        for op in ['pose_save','pose_blend']:
            r=row(op);self.assertEqual(set(derive(r).values()),{'pass'})
        b=blend_bones(row('pose_blend')['request'])['arm_L']
        self.assertEqual(b['position']['x'],1);self.assertAlmostEqual(b['rotation']['z'],math.sin(math.pi/8))
    def test_positive_dry_cases(self):
        for op in ['pose_save','pose_blend']:self.assertEqual(derive(row(op,True))['dry_run'],'pass')
    def test_dry_write_is_failure(self):
        r=row('pose_blend',True);r['file_after']=observation(r['request']['path'],b'changed');self.assertEqual(derive(r)['dry_run'],'fail');self.assertEqual(derive(r)['source_unchanged'],'fail')
    def test_wrong_pose_response_and_file(self):
        r=row('pose_blend');r['response']['data']['pose']['bones']['arm_L']['position']['x']=9
        self.assertEqual(derive(r)['valid_effect'],'fail')
        r=row();r['file_after']=observation(r['request']['path'],b'{}');self.assertEqual(derive(r)['file_effect'],'fail')
    def test_non_target_history_and_logger(self):
        for key,value in [('scene_after',{'all_transforms':'changed'}),('source_bones_after',[]),('history_after',8),('global_after',9)]:
            r=row();r[key]=value;self.assertEqual(derive(r)['non_target_preserved'],'fail')
        r=row();r.update(errors_after=1,errors=['engine error']);self.assertEqual(derive(r)['reported_errors'],'fail')
    def test_strict_path_hash_and_endpoint(self):
        r=row();r['request']['path']='res://other.json'
        with self.assertRaises(ValueError):derive(r)
        r=row();r['file_before']['sha256']='0'*64
        with self.assertRaises(ValueError):derive(r)
        r=row('pose_blend');r['request']['to_pose']=r['request']['from_pose']
        with self.assertRaises(ValueError):derive(r)
    def test_typed_overwrite_refusal(self):
        r=row();r['request']['overwrite']=False;r['file_after']=copy.deepcopy(r['file_before']);r['response']={'error':{'code':'INVALID_PARAMS','message':'File exists'}}
        self.assertEqual(derive(r)['typed_errors'],'pass')
        r['response']['error']['code']='UNKNOWN';self.assertEqual(derive(r)['typed_errors'],'fail')
    def test_public_span_and_exact_test_binding(self):
        r=row();r.update(suite='rig_pose_history',test=TEST,mode='pose_file_contract',ordinal=3,assertion_count_before=2)
        event={'driver':'test_rig_pose_history.gd','validator':'rig_pose_file_v1','route':'public_test_run_inner_dispatch','operation':'animation_rig.pose_save','row':r,'test_run_begin_id':'begin'}
        deps=['test_project/tests/test_rig_pose_history.gd','test_project/tests/operation_history_trace.gd','test_project/tests/test_preset_library_history.gd','test_project/tests/test_graph_route_history.gd','addons/godot_ai_animation/handlers/rig.gd','addons/godot_ai_animation/spec/pose_math.gd','addons/godot_ai_animation/spec/spec_json.gd','tools/mcp_presets_audit.py','tools/operation_library_file_checks.py','tools/operation_pose_file_checks.py']
        context={'dependencies':dict.fromkeys(deps,{})};req={'suite':'rig_pose_history','verbose':True}
        begins=[{'id':'begin','request':req,'execution_ns':1}]
        support=[{'id':'end','public_tool':'test_run','test_run_begin_id':'begin','request':req,'execution_ns':2,'response':{'results':[{'suite':'rig_pose_history','test':TEST,'passed':True,'assertion_count':70}]}}]
        self.assertEqual(set(verify_event(event,context,begins,support)['checks'].values()),{'pass'})
        r['ordinal']=5
        with self.assertRaises(ValueError):verify_event(event,context,begins,support)
        r['ordinal']=3
        support[0]['response']['results'][0]['skipped']=True
        self.assertEqual(set(verify_event(event,context,begins,support)['checks'].values()),{'fail'})
        event['operation']='animation_rig.pose_blend'
        with self.assertRaises(ValueError):verify_event(event,context,begins,support)
        with self.assertRaises(ValueError):verify_event(event,context,[],support)

if __name__=='__main__':unittest.main()
