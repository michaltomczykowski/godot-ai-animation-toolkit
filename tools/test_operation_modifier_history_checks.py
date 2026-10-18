import copy,json,unittest
from operation_modifier_history_checks import derive,native_checks,verify_event,expected_class,expected_refusal_code

def row(op='ik_setup'):
 before={'nodes':{'Peer':{'keep':1}}};generated=copy.deepcopy(before);generated['nodes']['Configured']={'class':'TwoBoneIK3D'};ident={'/Main':1};peer={'keep':1};label='local_'+op+'_base'
 r={'id':label,'suite':'rig_modifier_history','test':'test_local_history','mode':'local','variant':'base','op':op,'request':{'op':op,'active':False},'before':before,'after_dry':copy.deepcopy(before),'generated':generated,'undone':copy.deepcopy(before),'redone':copy.deepcopy(generated),'identities_before':ident,'identities_undo':ident.copy(),'peer_before':peer,'peer_after':peer.copy(),'pristine':peer.copy(),'shared_resource_identity':True,'source_hash_before':'a'*64,'source_hash_after':'a'*64,'inner_hash_before':'b'*64,'inner_hash_after':'b'*64,'versions':{'before':1,'dry':1,'write':2,'global_before':3,'global_dry':3,'global_write':3,'global_after':3},'dry':{'data':{'dry_run':True}},'write':{'data':{'modifier_path':'Configured'}},'undo_success':True,'redo_success':True,'modifier_identity_do':9,'modifier_identity_redo':9,'orphans_before':'[]','orphans_dry':'[]','errors_before':0,'errors_after':0,'errors':[],'failed_before':False,'failed_after':False,'assertion_count':20,'persisted':{}}
 for state,snapshot in [('do',generated),('undo',before),('redo',generated)]:r['persisted'][label+'_'+state]={'path':'user://modifier_history_'+label+'_'+state+'.tscn','sha256':'c'*64,'pack_result':0,'save_result':0,'snapshot':copy.deepcopy(snapshot)}
 r['modifier_class']=expected_class(r)
 return r

def native(r):
 rows=[];pairs=[]
 for fps in (30,60,120):
  for state,reference in [('do',False),('undo',False),('redo',False),('do',True)]:
   p=r['persisted'][r['id']+'_'+state];rows.append({'id':r['id'],'op':r['op'],'state':state,'fps':fps,'native':reference,'params':r['request'],'scene':p['path'],'scene_sha256':p['sha256'],'case_failures':[],'case_engine_errors':[],'samples':1,'influences':[0,.5,1],'influence_error':.0001,'influence_contract':'source_rest'if r['op']=='retarget_setup'else'pose_blend','native_requested_properties':{'saved':{'active':False,'influence':1,'0/root_bone_name':'hips'},'independent_native':{'active':False,'influence':1,'0/root_bone_name':'hips'}}if reference else {}})
  pairs.append({'id':r['id'],'op':r['op'],'fps':fps,'params':r['request'],'native_reference_error':.0001,'redo_error':0,'states':{s:r['persisted'][r['id']+'_'+s]['path']for s in ('do','undo','redo')}})
 report={'rows':rows,'comparisons':pairs};e={'kind':'native_saved_output','operation':'animation_rig_modifiers.'+r['op'],'scene':'user://rig_modifier_history.json','route':'native_godot','command':['godot','--headless','--path','project','--script','res://tools/check_rig_modifier_history.gd'],'returncode':0,'stdout':'RIG_MODIFIER_HISTORY_RUNTIME='+json.dumps(report),'stderr':'','execution_ns':3}
 return e,report
class Controls(unittest.TestCase):
 def test_known_guard_code_map_and_unknown_locked_refusal(self):
  requests=[('ik_setup',{'kind':'jacobian'},'OPERATION_UNAVAILABLE'),('look_at_setup',{'forward_axis':'+y','primary_axis':'y'},'INVALID_PARAMS'),('look_at_setup',{'origin_from':'invalid'},'VALUE_OUT_OF_RANGE'),('retarget_setup',{'move_target':False},'INVALID_PARAMS'),('retarget_setup',{'skeleton_path':'/Source','target_path':'/Source'},'INVALID_PARAMS'),('retarget_setup',{'position':False,'rotation':False,'scale':False},'INVALID_PARAMS'),('twist_setup',{'disperse':{'mode':'custom'}},'INVALID_PARAMS'),('spring_setup',{'springs':[{'root_bone':'head'}]},'INVALID_PARAMS')]
  for i,(op,params,code)in enumerate(requests):
   for dry in (False,True):
    r={'single_refusal':True,'id':f'refusal_{i}_{str(dry).lower()}','op':op,'request':dict(params,dry_run=dry)};self.assertEqual(expected_refusal_code(r),code)
  r=row('retarget_setup');r['mode']='locked';r['refusal']=True
  self.assertNotIn('typed_errors',derive(r))
 def test_five_operation_actual_schema_positive_controls(self):
  for op in ('ik_setup','look_at_setup','spring_setup','twist_setup','retarget_setup'):
   r=row(op);self.assertTrue(all(v=='pass'for v in derive(r).values()));e,_=native(r);self.assertEqual(native_checks(r,e,{'engine_command':'godot'}),{'playback':'pass','valid_effect':'pass'})
 def test_history_dry_persisted_peer_source_error_and_identity_corruption(self):
  for key,value in [('after_dry',{}),('undone',{}),('peer_after',{}),('source_hash_after','d'*64),('errors',['enginefailure']),('modifier_identity_redo',10),('failed_before',True)]:
   r=row();r[key]=value;self.assertIn('fail',derive(r).values(),key)
  r=row();r['persisted'][r['id']+'_redo']['snapshot']={};self.assertEqual(derive(r)['save_reopen'],'fail')
 def test_native_hash_request_signal_error_reference_and_fps_controls(self):
  for change in ('hash','params','casefail','engineerror','influence','property','missingfps','duplicate','parity'):
   r=row();e,p=native(r)
   if change=='hash':p['rows'][0]['scene_sha256']='d'*64
   if change=='params':p['rows'][0]['params']={'op':'spring_setup'}
   if change=='casefail':p['rows'][0]['case_failures']=['reachabletargetmiss']
   if change=='engineerror':p['rows'][0]['case_engine_errors']=['nativeerror']
   if change=='influence':p['rows'][0]['influence_error']=.001
   if change=='property':p['rows'][3]['native_requested_properties']['independent_native']['0/root_bone_name']='foreign'
   if change=='missingfps':p['rows']=p['rows'][:-1]
   if change=='duplicate':p['rows'][1]=copy.deepcopy(p['rows'][0])
   if change=='parity':p['comparisons'][0]['native_reference_error']=.001
   e['stdout']='RIG_MODIFIER_HISTORY_RUNTIME='+json.dumps(p);self.assertIn('fail',native_checks(r,e,{'engine_command':'godot'}).values(),change)
 def test_refusals_require_typed_nonmutation_and_no_orphans(self):
  r={'id':'refusal_8_false','request':{'dry_run':False,'springs':[{'center_from':'node','collisions':['/Caller/A/Collider']}]},'single_refusal':True,'op':'spring_setup','failed_before':False,'failed_after':False,'before':{'keep':1},'after':{'keep':1},'versions':{'before':1,'after':1,'global_before':1,'global_after':1},'response':{'error':{'code':'OPERATION_UNAVAILABLE'}},'expected_code':'OPERATION_UNAVAILABLE','orphans_before':'[]','orphans_after':'[]','errors':[],'error_count_before':0,'error_count_after':0};self.assertTrue(all(x=='pass'for x in derive(r).values()));wrong=copy.deepcopy(r);wrong['response']['error']['code']='NODE_NOT_FOUND';self.assertEqual(derive(wrong)['typed_errors'],'fail');unknown=copy.deepcopy(r);unknown['id']='refusal_99_false';self.assertNotIn('typed_errors',derive(unknown));r['orphans_after']='[99]';self.assertEqual(derive(r)['typed_errors'],'fail')
 def test_span_and_individual_test_binding_not_totals(self):
  r=row();ev={'validator':'rig_modifier_history_v1','driver':'test_rig_modifier_history.gd','route':'public_test_run_inner_dispatch','operation':'animation_rig_modifiers.ik_setup','test_run_begin_id':'begin','row':r};deps=['test_project/tests/test_rig_modifier_history.gd','test_project/tests/operation_history_trace.gd','tools/operation_modifier_history_checks.py','tools/operation_preset_history_checks.py','test_project/tools/check_rig_modifier_history.gd','test_project/tools/modifier_native_reference.gd','tools/mcp_rig_modifier_history.py','tools/mcp_presets_audit.py'];ctx={'dependencies':dict.fromkeys(deps,{})};req={'suite':'rig_modifier_history','verbose':True};starts=[{'id':'begin','request':req,'execution_ns':1}];ends=[{'id':'end','public_tool':'test_run','test_run_begin_id':'begin','request':req,'execution_ns':2,'response':{'results':[{'suite':r['suite'],'test':r['test'],'passed':True,'assertion_count':100}]}}];proof=verify_event(ev,ctx,starts,ends);self.assertNotIn('valid_effect',proof['checks']);self.assertTrue(all(x=='pass'for x in proof['checks'].values()));ends[0]['response']={'passed':9999};self.assertTrue(all(x=='fail'for x in verify_event(ev,ctx,starts,ends)['checks'].values()))
if __name__=='__main__':unittest.main()
