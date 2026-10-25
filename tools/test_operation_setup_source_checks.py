"""Synthetic native-shape controls; no claim of actual engine qualification."""
import copy, unittest, asyncio, tempfile, json
from pathlib import Path
from unittest.mock import patch
from setup_history_witness import SetupWitness
import operation_setup_history_checks as history
import operation_setup_source_checks as source
from test_operation_setup_history_checks import bound,fixture,SCENE


def source_rows():
 rows=fixture()
 for phase,row in rows.items():
  player=row['stored']['nodes']['AnimationPlayer'];player['libraries']={};player['clips']={}
  if phase not in ('before','after_dry','undone'):
   state=row['stored'];state['nodes'][source.SKELETON]['children'].append('SetupGrounding')
   state['nodes'][source.SKELETON+'/SetupGrounding']={'id':22,'class':'SkeletonModifier3D','properties':{},'children':[]}
   player['properties'].update(root_motion_track={'type':'NodePath','value':'Dummy:position'},root_motion_local=True)
   state['resources']['setup-library']={'class':'AnimationLibrary','path':'','properties':{}}
   player['properties']['libraries/']={'resource_id':'setup-library'}
   player['libraries']={'':{'resource_id':'setup-library'}}
   player['clips']={name:{} for name in row['clips']}
 return rows


def full_bound():
 event,context,events,public,begins,support=bound();rows=source_rows()
 for item in events:rows[item['row']['phase']]['marker']=item['row']['marker'];item['row']=rows[item['row']['phase']]
 for phase,time in [('before_refusal',-10),('after_refusal',0)]:
  row=copy.deepcopy(rows['before']);row['phase']=phase;row['marker']['phase']=phase
  template=copy.deepcopy(events[0]);template.update(id=phase,time_ns=time+1,test_run_begin_id=phase+'-begin',row=row)
  events.append(template)
  start=copy.deepcopy(begins[0]);start.update(id=phase+'-begin',time_ns=time,execution_ns=time);begins.append(start)
  end=copy.deepcopy(support[0]);end.update(id=phase+'-end',test_run_begin_id=phase+'-begin',time_ns=time+5,execution_ns=time+5);support.append(end)
  rows[phase]=row
 for first,last in [('before_refusal','after_refusal'),('before','after_write')]:
  token=rows[first]['marker']['token'];rows[first]['error_boundary']={'complete':True,'token':token,'begin_phase':first}
  rows[last]['error_observation']={'complete':True,'token':token,'begin_phase':first,'end_phase':last,'errors_before':0,'errors_after':0,'errors':[]}
 public.append(dict(public[0],id='refusal',execution_ns=-3,params=dict(rows['before']['marker']['request'],speed=8.,run_speed=10.),response={'error':'VALUE_OUT_OF_RANGE: Speed exceeds reachable limit'}))
 return next(e for e in events if e['row']['phase']=='persisted'),context,events,public,begins,support


class Controls(unittest.TestCase):
 def test_native_default_library_slot_is_target_but_other_libraries_are_not(self):
  rows=source_rows();self.assertTrue(source.source_preserved(rows,full_bound()[1]))
  for fault in ('alias','class','other_library','clips'):
   rows=source_rows();state=rows['after_write']['stored'];player=state['nodes']['AnimationPlayer']
   if fault=='alias':player['properties']['libraries/']={'resource_id':'wrong'}
   elif fault=='class':state['resources']['setup-library']['class']='Resource'
   elif fault=='other_library':player['properties']['libraries/extra']={'resource_id':'setup-library'}
   else:player['clips'].pop('walk')
   with self.assertRaises(ValueError,msg=fault):source.source_preserved(rows,full_bound()[1])
 def test_complete_new_source_and_error_contract(self):
  proof=history.verify_event(*full_bound());self.assertEqual(set(proof['checks'].values()),{'pass'});self.assertIn('refusal',proof['public_case_ids'])
  self.assertIn('not the entire editor session',proof['limits'])
 def test_non_target_mutations_and_authoring_mask_corruption(self):
  for fault in ('bone','node','property','file','clip','rootmotion','identity','script','peerresource'):
   rows=source_rows();state=rows['after_write']['stored']
   if fault=='bone':state['nodes'][source.SKELETON]['bones'][0]['enabled']=False
   elif fault=='node':state['nodes']['Other']={'id':100,'class':'Node','properties':{},'children':[]}
   elif fault=='property':state['nodes']['Dummy']['properties']['position']={'bytes_sha256':'9'*64}
   elif fault=='file':state['files']['res://other.txt']='0'*64
   elif fault=='clip':rows['after_write']['clips']['extra']=rows['after_write']['clips']['walk']
   elif fault=='rootmotion':state['nodes']['AnimationPlayer']['properties']['root_motion_track']['value']='Other:position'
   elif fault=='identity':state['nodes']['Dummy']['id']+=1
   elif fault=='script':state['files'][source.GROUNDING]='0'*64
   else:
    rows['before']['stored']['resources']['peer']={'class':'Resource','path':'','properties':{'value':1}}
    rows['before']['stored']['nodes']['Dummy']['properties']['peer']={'resource_id':'peer'}
   with self.assertRaises(ValueError,msg=fault):source.source_preserved(rows,full_bound()[1])
 def test_source_is_independent_of_product_output(self):
  args=full_bound();args[3][1]['response']={'anything':'not an output oracle'}
  self.assertEqual(history.verify_event(*args)['checks']['source_unchanged'],'pass')
 def test_original_receipts_do_not_fabricate_new_logger_or_refusal_passes(self):
  proof=history.verify_event(*bound())['checks'];self.assertEqual(proof['typed_errors'],'pending');self.assertEqual(proof['reported_errors'],'pending')
 def test_refusal_code_atomicity_and_exact_request(self):
  for fault in ('code','message','bone','history','files','request','order','duplicate','context','span'):
   args=copy.deepcopy(full_bound());event,context,events,public,begins,support=args
   refusal=public[-1];after=next(e['row']for e in events if e['row']['phase']=='after_refusal')
   if fault=='code':refusal['response']['error']='INVALID_PARAMS: reachable'
   elif fault=='message':refusal['response']['error']='VALUE_OUT_OF_RANGE: other'
   elif fault=='bone':after['stored']['nodes'][source.SKELETON]['bones'][0]['enabled']=False
   elif fault=='history':after['stored']['history']+=1
   elif fault=='files':after['stored']['files']['res://new.json']='a'*64
   elif fault=='request':refusal['params']['speed']=7.
   elif fault=='order':refusal['execution_ns']=8
   elif fault=='duplicate':public.append(copy.deepcopy(refusal))
   elif fault=='context':events[-1]['context_sha256']='f'*64
   else:begins[-1]['request']['test_name']='wrong'
   if fault in ('code','message','bone','history','files'):self.assertEqual(history.verify_event(*args)['checks']['typed_errors'],'fail',fault)
   else:
    with self.assertRaises(ValueError,msg=fault):history.verify_event(*args)
 def test_logger_entries_and_boundaries_cannot_be_hidden(self):
  for fault in ('token','phase','complete','count','entry','missing','actualerror'):
   args=copy.deepcopy(full_bound());rows={e['row']['phase']:e['row']for e in args[2]};end=rows['after_write']['error_observation']
   if fault=='token':end['token']='f'*32
   elif fault=='phase':end['begin_phase']='before_refusal'
   elif fault=='complete':end['complete']=False
   elif fault=='count':end['errors_after']=True
   elif fault=='entry':end.update(errors_after=1,errors=[{}])
   elif fault=='missing':del rows['before']['error_boundary']
   else:end.update(errors_after=1,errors=[{'function':'f','file':'x.gd','line':1,'code':'assert','message':'actual error','type':0}])
   if fault=='actualerror':self.assertEqual(history.verify_event(*args)['checks']['reported_errors'],'fail')
   else:
    with self.assertRaises(ValueError,msg=fault):history.verify_event(*args)
 def test_cleanup_is_readonly_once_and_preserves_marker_ownership(self):
  async def run():
   with tempfile.TemporaryDirectory()as d:
    directory=Path(d);context=directory/'context.json';context.write_text(json.dumps({'run_id':'run'}));calls=[]
    async def fake(client,name,request):
     calls.append((name,request));return {'results':[{'suite':request['suite'],'test':request['test_name'],'passed':True,'assertion_count':1}]}
    with patch.dict('os.environ',TOOLKIT_OPERATION_CONTEXT=str(context),TOOLKIT_OPERATION_TRACE_DIR=d),patch('setup_history_witness.call',fake):
     witness=SetupWitness(None,SCENE,fixture()['before']['marker']['request'],directory)
     await witness.snapshot('before_refusal');await witness.cleanup();await witness.cleanup()
     self.assertEqual(len(calls),2);self.assertTrue(all(name=='test_run'for name,_ in calls));self.assertFalse((directory/'active-setup-history.json').exists())
     # A completed end boundary needs no cleanup RPC.
     await witness.snapshot('before_refusal');await witness.snapshot('after_refusal');await witness.cleanup()
     self.assertEqual(len(calls),4)
  asyncio.run(run())
 def test_missing_dependency_and_partial_refusal_cannot_qualify(self):
  args=full_bound();args[1]['dependencies'].pop('tools/operation_setup_source_checks.py')
  with self.assertRaises(ValueError):history.verify_event(*args)
  args=full_bound();args[2].pop(-1)
  with self.assertRaises(ValueError):history.verify_event(*args)
if __name__=='__main__':unittest.main()
