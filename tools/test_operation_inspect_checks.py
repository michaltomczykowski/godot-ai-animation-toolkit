import copy
import unittest
from operation_inspect_checks import derive, effect, verify_event, DEPENDENCIES, SCENE, PLAYER, ERROR_CODES, EDIT_OPS
from mcp_inspect_audit import CASES, ERROR_CASES

WALK={'key_count':2,'tracks':[{'path':'Character:position','keys':[{'value':{'x':0}},{'value':{'x':100}}]}]}
RESULTS={'describe':{'clip_count':1,'clips':[{'key_count':2}]},'timeline':WALK,
 'audit':{'players_scanned':1,'clips_scanned':5},'compare':{'identical':False,'changed_tracks':[{'path':'Character:position','key_count_a':2,'key_count_b':2,'changed_keys':1,'max_delta':100}]},
 'stats':{'totals':{'key_count':12}},'motion_report':{'worst_seam_gap':100},
 'dry_run':{'dry_run':True,'length_before':1,'length_after':0.5},'help':{'tool_count':1,'tools':[{'ops':[{'name':x} for x in EDIT_OPS]}]}}

class InspectTests(unittest.TestCase):
 def fixture(self,op):
  row={'op':op,'scene':SCENE,'request':{'op':op,**CASES[op]},'error_request':{'op':op,**ERROR_CASES[op]},'result':copy.deepcopy(RESULTS[op]),'typed_error':{'error':ERROR_CODES[op]+': test'},'before':copy.deepcopy(WALK),'after':copy.deepcopy(WALK),'open':{'opened':True}}
  event={'validator':'inspect_read_v1','driver':'mcp_inspect_audit.py','operation':'animation_inspect.'+op,'row':row,'checks':derive(row),'execution_ns':10}
  probe={'op':'timeline','player_path':PLAYER,'animation_name':'walk'}
  calls=[]
  for n,(operation,params,response) in enumerate([('animation_inspect.timeline',probe,WALK),(event['operation'],row['request'],row['result']),('animation_inspect.timeline',probe,WALK),(event['operation'],row['error_request'],row['typed_error'])],2):
   calls.append({'id':str(n),'execution_ns':n,'scene':SCENE,'operation':operation,'public_tool':'custom_animation_inspect','route':'public_godot_ai','params':params,'response':response})
  opened={'id':'1','execution_ns':1,'public_tool':'scene_open','request':{'path':SCENE,'force_reload':True},'response':row['open']}
  return event,{'dependencies':dict.fromkeys(DEPENDENCIES,{})},calls,[opened]
 def test_eight_exact_rows(self):
  for op in RESULTS:
   with self.subTest(op=op):self.assertEqual(set(verify_event(*self.fixture(op))['checks'].values()),{'pass'})
 def test_inert_rejected(self):
  for op in RESULTS:self.assertFalse(effect(op,{}))
 def test_generic_changed_flag_rejected(self):
  self.assertFalse(effect('compare',{'identical':False,'changed_tracks':[{'changed':True}]}))
 def test_wrong_oracles(self):
  for op in RESULTS:
   event,*_=self.fixture(op);event['row']['result']={}
   self.assertEqual(derive(event['row'])['valid_effect'],'fail')
 def test_wrong_error_each(self):
  for op in RESULTS:
   event,*_=self.fixture(op);event['row']['typed_error']={'error':'SOME_UPPERCASE: no'}
   self.assertEqual(derive(event['row'])['typed_errors'],'fail')
 def test_changed_walk(self):
  event,*_=self.fixture('stats');event['row']['after']['tracks'][0]['keys'][1]['value']['x']=99
  self.assertEqual(derive(event['row'])['source_unchanged'],'fail')
 def test_missing_public_call(self):
  args=list(self.fixture('stats'));args[2]=args[2][:-1]
  with self.assertRaises(ValueError):verify_event(*args)
 def test_wrong_request(self):
  args=list(self.fixture('stats'));args[0]['row']['request']['player_path']='/wrong'
  with self.assertRaises(ValueError):verify_event(*args)
 def test_forged_checks(self):
  args=list(self.fixture('stats'));args[0]['checks']['valid_effect']='pending'
  with self.assertRaises(ValueError):verify_event(*args)
 def test_missing_dependency(self):
  args=list(self.fixture('stats'));args[1]['dependencies'].pop(DEPENDENCIES[0])
  with self.assertRaises(ValueError):verify_event(*args)
if __name__=='__main__':unittest.main()
