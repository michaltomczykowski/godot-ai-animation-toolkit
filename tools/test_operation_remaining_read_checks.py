"""Offline corruptions only; synthetic positives do not establish native proof."""
import asyncio,copy,json,re,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
import operation_remaining_read_checks as s
from remaining_read_witness import witnessed_read

KEYS=tuple(s.DRIVERS)
def graph():
 edge=lambda a,b,x:dict(**{'from':a,'to':b},**{'class':'AnimationNodeStateMachineTransition','xfade':x,'advance_mode':2,'switch_mode':0,'condition':'','expression':'','priority':1,'reset':True})
 n={'tree_class':'AnimationTree','root_class':'AnimationNodeStateMachine','tree_path':'AnimationTree','player_path':'AnimationPlayer','player_resolved':True,'anim_player':'../AnimationPlayer','active':False,'states':[{'name':n,'class':'AnimationNodeAnimation','animation':n}for n in ('idle','walk')],'implicit_states':['Start','End'],'transitions':[edge('Start','idle',0.),edge('idle','walk',.1)]}
 links=[{'from':e['from'],'to':e['to'],'xfade_time':e['xfade'],'advance_mode':'auto','switch_mode':'immediate','condition':'','advance_expression':'','priority':1,'reset':True}for e in n['transitions']]
 r={'tree_path':'/RepairGraphFixture/AnimationTree','anim_player':'../AnimationPlayer','anim_player_resolved':True,'active':False,'animations':['idle','walk'],'root':{'type':'state_machine','state_count':2,'transition_count':2,'states':[{'name':n,'position':{'x':0,'y':0},'node':{'type':'animation','animation':n}}for n in ('idle','walk')],'transitions':links}}
 return n,r

def fixture(key):
 graph_case=key=='animation_graph.graph_get';scene='res://repair_graph_audit/20261024_123456/graph_get.tscn'if graph_case else'res://repair_rig_audit/20261024_123456/'+('poses'if key.endswith('pose_list')else'pose_apply')+'.tscn';driver=s.DRIVERS[key];native,result=graph()
 source='test_project/repair_graph_fixture.tscn'if graph_case else'test_project/repair_rig_fixture.tscn'
 deps=s.BASE+('tools/'+driver,source,'addons/godot_ai_animation/utils/error_codes.gd')+(('addons/godot_ai_animation/handlers/graph.gd','addons/godot_ai_animation/spec/graph_builders.gd')if graph_case else(s.MODEL,'addons/godot_ai_animation/handlers/rig.gd'))
 context={'run_id':'run','dependencies':{p:{'sha256':'d'*64,'git_blob':'e'*40}for p in deps}}
 classes={'.':'Node2D','Character':'Node2D','AnimationPlayer':'AnimationPlayer','AnimationTree':'AnimationTree'}if graph_case else{'.':'Node3D','Dummy':'Node3D','Dummy/Skeleton3D':'Skeleton3D','AnimationPlayer':'AnimationPlayer'}
 nodes={p:{'id':i,'class':kind,'name':('RepairGraphFixture'if graph_case else'RepairRigFixture')if p=='.'else p.rsplit('/',1)[-1],'properties':{},'children':[]}for i,(p,kind)in enumerate(classes.items(),1)};nodes['.']['children']=[p for p in nodes if p!='.'and'/'not in p]
 if not graph_case:
  nodes['Dummy']['children']=['Skeleton3D'];nodes['Dummy/Skeleton3D']['bones']=[{'name':name,'parent':-1,'rest':{'type':'Transform3D','bytes_sha256':'a'*64},'position':{'type':'Vector3','bytes_sha256':'a'*64},'rotation':{'type':'Quaternion','bytes_sha256':'a'*64},'scale':{'type':'Vector3','bytes_sha256':'a'*64},'enabled':True}for name in s.EXPECTED_BONES]
 player=nodes['AnimationPlayer'];player.update(libraries={},clips={},playback={'assigned':'','current':'','playing':False,'queue':{'type':'PackedStringArray','bytes_sha256':'a'*64},'speed':1.,'playing_speed':0.,'position':None})
 resources={}
 if graph_case:nodes['AnimationTree']['properties']['tree_root']={'resource_id':'10'};resources['10']={'class':'AnimationNodeStateMachine','properties':{},'path':scene+'::Tree'}
 files={scene:'c'*64}
 if key=='animation_rig.pose_list':files.update({'res://animation_toolkit/repair_audit/rig_poses_20261024_123456/'+n+'.json':'a'*64 for n in ('rest','arm')})
 if not graph_case:files['res://models/human_dummy/HumanCharacterDummy_F.fbx']='d'*64
 state={'scene':scene,'nodes':nodes,'resources':resources,'files':files,'unsupported':[],'history':5,'global_history':1}
 events=[];begins=[];support=[];public=[]
 for i,stage in enumerate(('valid','refusal')):
  t=10+i*50;m={'token':str(i+1)*32,'context_sha256':'b'*64,'run_id':'run','operation':key,'request':s.fixed(key,stage,scene),'scene':scene,'stage':stage}
  for j,phase in enumerate(('begin','end')):
   test='test_'+phase;begin_id=stage+'-'+phase;request={'suite':'remaining_read_witness','test_name':test,'verbose':True};at=t+j*20
   begins.append({'id':begin_id,'driver':driver,'scene':scene,'request':request,'execution_ns':at,'time_ns':at})
   support.append({'id':begin_id+'-done','driver':driver,'scene':scene,'request':request,'public_tool':'test_run','test_run_begin_id':begin_id,'execution_ns':at+5,'time_ns':at+5,'response':{'results':[{'suite':'remaining_read_witness','test':test,'passed':True,'assertion_count':1}]}})
   row={'op':key.split('.')[-1],'mode':'remaining_read','phase':phase,'marker':copy.deepcopy(m)}
   if phase=='end':
    row.update(begin_marker=copy.deepcopy(m),before=copy.deepcopy(state),after=copy.deepcopy(state),snapshot_schema='stored_graph_v1',fixture_path='res://'+source.removeprefix('test_project/'),fixture_sha256='d'*64,errors_before=0,errors_after=0,errors=[])
    if graph_case:row.update(graph_before=copy.deepcopy(native),graph_after=copy.deepcopy(native))
   events.append({'id':begin_id+'-raw','validator':'remaining_read_witness_v1','operation':key,'driver':'test_remaining_read_witness.gd','route':'public_test_run_inner_dispatch','run_id':'run','context_sha256':'b'*64,'test_run_begin_id':begin_id,'time_ns':at+2,'row':row})
  public.append({'id':stage+'-call','operation':key,'driver':driver,'public_tool':'custom_animation_graph'if graph_case else'custom_animation_rig','route':'public_godot_ai','scene':scene,'params':copy.deepcopy(m['request']),'response':copy.deepcopy(result)if graph_case and stage=='valid'else {'bone_count':56}if stage=='valid'else{'error':{'code':'INVALID_PARAMS'if key.endswith('pose_list')else'NODE_NOT_FOUND','message':'expected refusal'}},'execution_ns':t+10})
 if graph_case:public.append({'id':'producer','operation':'animation_graph.state_machine','driver':driver,'public_tool':'custom_animation_graph','route':'public_godot_ai','scene':scene,'params':copy.deepcopy(s.GRAPH_BASE),'response':{'created':True},'execution_ns':1})
 return events[1],context,events,public,begins,support

class Controls(unittest.TestCase):
 def test_graph_hierarchy_matches_committed_fixture_and_authored_tree(self):
  text=(Path(__file__).resolve().parents[1]/'test_project/repair_graph_fixture.tscn').read_text()
  actual={name:kind for name,kind in re.findall(r'\[node name="([^"]+)" type="([^"]+)"',text)}
  self.assertEqual(actual,{'RepairGraphFixture':'Node2D','Character':'Node2D','AnimationPlayer':'AnimationPlayer'})
  e,c,*_=fixture('animation_graph.graph_get');row=e['row'];nodes=row['before']['nodes']
  self.assertEqual(set(nodes),{'.','Character','AnimationPlayer','AnimationTree'})
  self.assertTrue(s.snapshot_complete(row['before'],row['marker'],c))
  for path in ('Character','AnimationPlayer','AnimationTree'):
   changed=copy.deepcopy(row['before']);del changed['nodes'][path]
   self.assertFalse(s.snapshot_complete(changed,row['marker'],c),path)
 def test_literal_pose_directory_from_actual_driver_path(self):
  scene='res://repair_rig_audit/20261024_123456/poses.tscn'
  self.assertEqual(s.fixed('animation_rig.pose_list','valid',scene),{'op':'pose_list','directory':'res://animation_toolkit/repair_audit/rig_poses_20261024_123456'})
  self.assertEqual(s.fixed('animation_rig.pose_list','refusal',scene),{'op':'pose_list','directory':[]})

 def test_all_three_exact_same_call_shapes(self):
  for key in KEYS:
   proof=s.verify_pair(*fixture(key));self.assertEqual(set(proof['checks'].values()),{'pass'},key)
 def test_same_call_source_file_resource_bone_and_logger_corruptions(self):
  for key in KEYS:
   for fault in ('node','file','resource','history','error','missing_error','fixture','unsupported','missing_player','bone'):
    if fault=='bone'and key.startswith('animation_graph'):continue
    args=list(fixture(key));row=args[2][1]['row']
    if fault=='node':row['after']['nodes']['.']['properties']['changed']=True
    elif fault=='file':row['after']['files'][row['marker']['scene']]='9'*64
    elif fault=='resource':row['after']['resources']['foreign']={'class':'Resource','properties':{},'path':''}
    elif fault=='history':row['after']['history']+=1
    elif fault=='error':row['errors']=[{'code':'REAL_ERROR'}];row['errors_after']=1
    elif fault=='missing_error':row.pop('errors')
    elif fault=='fixture':row['fixture_sha256']='0'*64
    elif fault=='unsupported':row['before']['unsupported']=row['after']['unsupported']=['unreadable']
    elif fault=='missing_player':row['before']['nodes']['AnimationPlayer'].pop('playback');row['after']['nodes']['AnimationPlayer'].pop('playback')
    elif fault=='bone':row['before']['nodes']['Dummy/Skeleton3D']['bones'].pop();row['after']['nodes']['Dummy/Skeleton3D']['bones'].pop()
    proof=s.verify_pair(*args)
    check='reported_errors'if fault in ('error','missing_error')else'source_unchanged'
    self.assertNotEqual(proof['checks'][check],'pass',(key,fault))
 def test_public_identity_scope_and_single_execution_controls(self):
  for key in KEYS:
   for fault in ('source','context','request','scene','token','duplicate','missing','call_order','extra_call','skipped','code'):
    e,c,events,public,begins,support=copy.deepcopy(fixture(key))
    # Bind e to the mutated actual event, as collector does.
    e=events[1]
    if fault=='source':c['dependencies'].pop(s.BASE[0])
    elif fault=='context':events[0]['context_sha256']='0'*64
    elif fault=='request':public[0]['params']['unexpected']=True
    elif fault=='scene':public[0]['scene']='res://other.tscn'
    elif fault=='token':events[0]['row']['marker']['token']='f'*32
    elif fault=='duplicate':events.append(copy.deepcopy(events[1]))
    elif fault=='missing':events.pop(0)
    elif fault=='call_order':public[0]['execution_ns']=0
    elif fault=='extra_call':public.append(dict(public[0],id='extra'))
    elif fault=='skipped':support[0]['response']['results'][0]['skipped']=True
    elif fault=='code':public[1]['response']={'error':{'code':'WRONG','message':'not expected'}}
    try:proof=s.verify_pair(e,c,events,public,begins,support)
    except (ValueError,KeyError):continue
    self.assertTrue('fail'in proof['checks'].values(),(key,fault))
 def test_native_graph_and_response_cannot_echo_a_wrong_topology(self):
  for fault in ('state','edge','xfade','binding','class','animation','response_state','response_edge','response_binding','producer'):
   args=list(fixture('animation_graph.graph_get'));row=args[2][1]['row'];ref=row['graph_before']
   if fault=='state':ref['states'][0]['name']='other'
   elif fault=='edge':ref['transitions'][0]['to']='walk'
   elif fault=='xfade':ref['transitions'][1]['xfade']=.2
   elif fault=='binding':ref['player_resolved']=False
   elif fault=='class':ref['states'][0]['class']='AnimationNodeBlend2'
   elif fault=='animation':ref['states'][0]['animation']='run'
   elif fault=='response_state':args[3][0]['response']['root']['states'][0]['node']['animation']='run'
   elif fault=='response_edge':args[3][0]['response']['root']['transitions'][1]['to']='idle'
   elif fault=='response_binding':args[3][0]['response']['anim_player_resolved']=False
   elif fault=='producer':args[3][-1]['params']['states'][0]['animation']='run'
   row['graph_after']=copy.deepcopy(ref)
   try:proof=s.verify_pair(*args)
   except ValueError:continue
   self.assertEqual(proof['checks']['valid_effect'],'fail',fault)
 def test_original_read_is_called_once_and_error_still_finishes_witness(self):
  async def run():
   with tempfile.TemporaryDirectory()as d:
    directory=Path(d);ctx=directory/'context.json';ctx.write_text(json.dumps({'run_id':'run'}));calls=[]
    async def fake(client,tool,request):
     calls.append((tool,request))
     if tool=='test_run':return {'results':[{'suite':'remaining_read_witness','test':request['test_name'],'passed':True,'assertion_count':1}]}
     raise RuntimeError('actual operator failure')
    with patch.dict('os.environ',TOOLKIT_OPERATION_CONTEXT=str(ctx),TOOLKIT_OPERATION_TRACE_DIR=str(directory)),patch('remaining_read_witness.call',fake):
     with self.assertRaisesRegex(RuntimeError,'actual operator failure'):await witnessed_read(None,'custom_animation_rig',{'op':'rig_get','skeleton_path':'/Missing'},'res://scene.tscn','refusal')
    self.assertEqual([x[0]for x in calls],['test_run','custom_animation_rig','test_run']);self.assertFalse((directory/'active-remaining-read.json').exists())
  asyncio.run(run())
if __name__=='__main__':unittest.main()
