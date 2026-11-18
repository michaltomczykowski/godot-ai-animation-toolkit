import copy
import unittest
from operation_fx_intention_checks import CASES, DEPENDENCIES, derive, intention, expected_samples, vector, verify_event
import test_operation_history_checks as history_tests

class FxIntentionTests(unittest.TestCase):
 def fixture(self,op='shake',mode='new'):
  row,context,event,begins,support=history_tests.HistoryChecks().fixture()
  row.update(op=op,mode=mode,scene='res://main.tscn')
  tests={'new':'test_new_clip_scene_history','overwrite':'test_overwritten_clip_scene_history','missing_library':'test_missing_library_scene_history','instanced':'test_instanced_player_scene_history'}
  row['test']=tests[mode]
  row['request']=dict(CASES[op],op=op,player_path='/Main/FxHistory/AnimationPlayer',animation_name='generated',overwrite=mode=='overwrite')
  if op=='path_follow':row['request']['path_node']='/Main/FxHistory/PatrolPath'
  if op=='sprite_frames':row['request']['sprite_path']='/Main/FxHistory/SheetSprite'
  row['invalid_request']=dict(row['request'],player_path='/Missing',sprite_path='/Missing')
  for label in ('before','generated','after_dry','after_error','undone','redone'):
   row[label]['props']={'Other':{'position':vector(0,0)},'Camera2D':{'zoom':vector(1,1)}}
   row[label]['path_points']=[vector(0,0),vector(100,0),vector(100,80)]
   row[label]['player_state']={'playing':False,'root_node':'..'}
   row[label].update(animation='',playing=False)
  row['after_probe']=copy.deepcopy(row['generated'])
  row.update(errors_before=2,errors_after=2,errors=[])
  row['input_files_before']={p:'a'*64 for p in ('res://repair_fx_fixture.tscn','res://tests/fixtures/sheet.png','res://tests/fixtures/cue.wav')}
  row['input_files_after']=copy.deepcopy(row['input_files_before'])
  for label,state,stage in [('persist_undo','before','undo'),('persist_redo','generated','redo')]:
   row[label].update(snapshot=copy.deepcopy(row[state]),path=f'user://fx_history_{op}_{mode}_{stage}.tscn')
  if mode=='instanced':row.update(source_path='user://fx_history_source.tscn',source_sha256_before='b'*64,source_sha256_after='b'*64,peer_before=copy.deepcopy(row['before']),peer_after=copy.deepcopy(row['before']),pristine=copy.deepcopy(row['before']))
  if op=='sprite_frames':
   row['intention']={'resource_class':'SpriteFrames','animation':'generated','playing':False,'fps':12,'loop':True,'cells':[{'class':'AtlasTexture','atlas':'res://tests/fixtures/sheet.png','size':vector(16,16),'region':[i*16,0,16,16],'duration':1} for i in range(4)]}
  else:
   row['intention']={'probe_mode':'duplicate_generated_fixture_manual_player','samples':[{'at':at,'path':path,'actual':copy.deepcopy(value) if value is not None else vector(.1,.2)} for at,path,value in expected_samples(op)]}
  if op=='counter':row['intention']['samples'][0]['actual']='0'
  if op=='audio_cue':
   row['generated']['clips']['generated']={'tracks':[{'path':'CuePlayer','type':7,'keys':[{'time':0,'start_offset':0,'end_offset':0,'stream':{'resource':'res://tests/fixtures/cue.wav','class':'AudioStreamWAV'}}]}]}
   row['after_probe']=copy.deepcopy(row['generated']);row['redone']=copy.deepcopy(row['generated']);row['persist_redo']['snapshot']=copy.deepcopy(row['generated'])
  context['dependencies'].update({p:{'sha256':'a'*64} for p in DEPENDENCIES})
  event.update(validator='fx_intention_history_v1',operation='animation_fx.'+op,time_ns=5)
  begins[0].update(scene=row['scene'],time_ns=1)
  support[0].update(scene=row['scene'],time_ns=10)
  support[0]['response']['results'][0]['test']=row['test']
  return row,context,event,begins,support
 def test_all_sixteen_four_modes(self):
  for op in CASES:
   for mode in ('new','overwrite','missing_library','instanced'):
    with self.subTest(op=op,mode=mode):
     row,c,e,b,s=self.fixture(op,mode);checks=verify_event(e,c,b,s)['checks']
     if op=='counter':
      self.assertEqual(checks['valid_effect'],'pending');self.assertEqual(checks['playback'],'pending')
      self.assertTrue(all(v=='pass' for k,v in checks.items() if k not in ('valid_effect','playback')))
     else:self.assertTrue(all(v=='pass' for v in checks.values()))
 def test_each_operation_corrupt_intention_rejected(self):
  for op in CASES:
   row,*_=self.fixture(op)
   if op=='sprite_frames':row['intention']['cells'][2]['region'][0]=0
   else:row['intention']['samples'][0]['actual']='corrupted'
   with self.subTest(op=op):self.assertEqual(derive(row)['valid_effect'],'fail')
 def test_wrong_request_rejected(self):
  row,*_=self.fixture();row['request']['seed']=8
  with self.assertRaises(ValueError):derive(row)
 def test_case_error_retained(self):
  row,*_=self.fixture();row.update(errors_after=3,errors=['real engine error'])
  self.assertEqual(derive(row)['reported_errors'],'fail')
 def test_non_target_clip_and_property_and_curve_and_player_corruptions(self):
  for key in ('clips','props','path_points','player_state'):
   row,*_=self.fixture();row['generated'][key]={}
   with self.subTest(key=key):self.assertEqual(derive(row)['source_unchanged'],'fail')
 def test_probe_pollution_rejected(self):
  row,*_=self.fixture();row['after_probe']['props']['Other']['position']=vector(1,0)
  self.assertEqual(derive(row)['source_unchanged'],'fail')
 def test_instanced_source_peer_corruptions(self):
  for key,value in [('source_sha256_after','c'*64),('peer_after',{}),('pristine',{})]:
   row,*_=self.fixture(mode='instanced');row[key]=value
   with self.subTest(key=key):self.assertEqual(derive(row)['source_unchanged'],'fail')
 def test_wrong_input_file_hash(self):
  row,c,e,b,s=self.fixture();row['input_files_before']['res://tests/fixtures/cue.wav']='d'*64
  with self.assertRaises(ValueError):verify_event(e,c,b,s)
 def test_wrong_scene_and_span(self):
  row,c,e,b,s=self.fixture();row['scene']='res://wrong.tscn'
  with self.assertRaises(ValueError):verify_event(e,c,b,s)
  row,c,e,b,s=self.fixture();e['time_ns']=11
  with self.assertRaises(ValueError):verify_event(e,c,b,s)
 def test_missing_dependency(self):
  row,c,e,b,s=self.fixture();c['dependencies'].pop(DEPENDENCIES[0])
  with self.assertRaises(ValueError):verify_event(e,c,b,s)
 def test_nonfinite_and_inert_shake(self):
  for value in (vector(0,0),vector(float('nan'),0),vector(float('inf'),0),vector(9999,0)):
   row,*_=self.fixture();row['intention']['samples'][0]['actual']=value
   self.assertFalse(intention(row))
 def test_audio_wrong_stream_or_event(self):
  row,*_=self.fixture('audio_cue');row['generated']['clips']['generated']['tracks'][0]['keys'][0]['stream']['resource']='wrong.wav'
  self.assertFalse(intention(row))
 def test_sprite_wrong_type_fps_and_play_state(self):
  for key,value in [('resource_class','Texture2D'),('fps',4),('playing',True)]:
   row,*_=self.fixture('sprite_frames');row['intention'][key]=value
   self.assertFalse(intention(row))
if __name__=='__main__':unittest.main()
