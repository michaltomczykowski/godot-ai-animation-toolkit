import copy,unittest
from check_saved_bake_capture import compare,times
from prepare_saved_bake_capture import IDS
POSE={'p':[0.,0.,0.],'q':[0.,0.,0.,1.],'s':[1.,1.,1.]}
def fixture():
 m={'files':{'res://tools/check_saved_bake_capture.gd':{'sha256':'b'*64},'res://tools/check_rig_bake_restoration.gd':{'sha256':'c'*64}},'cases':[{'id':key,'skeleton':'selected','modifiers':[{'path':'source/modifier'}],'params':{'duration':.205,'fps':60,'tree_events':[{'time':.07}]}}for key in IDS]};r={'evaluator_sha256':'b'*64,'reference_helper_sha256':'c'*64,'kind':'saved_bake_eight_native','manifest_sha256':'a'*64,'passed':True,'failures':[],'engine_errors':[],'runs':[]}
 for row in m['cases']:
  for take in (0,1):
   for side in ('source','redo'):
    trace=[{'time':t,'body':copy.deepcopy(POSE),'selected_pose':[copy.deepcopy(POSE)],'required':{'selected':{'final_before':i,'skin_before':i,'final':i+1,'skin':i+1,'pose':{'local':[copy.deepcopy(POSE)]},'skin_pose':[copy.deepcopy(POSE)],'skin_fresh':True,'skin_cached_unchanged':False}}}for i,t in enumerate(times(row['params']))]
    if row['id']=='modifier_retarget_1_60':
     for sample in trace:sample['required']['source']=copy.deepcopy(sample['required']['selected'])
    r['runs'].append({'id':row['id'],'side':side,'take':take,'paced':False,'flush':False,'failures':[],'trace':trace})
 return r,m
class Controls(unittest.TestCase):
 def test_exact_schedule_shape(self):
  r,m=fixture();v=compare(r,m,'a'*64);self.assertTrue(v['parity_pass']);self.assertTrue(v['fresh_take_pass']);self.assertIn(.07,times(m['cases'][0]['params']));self.assertTrue(any(abs(v-.06996)<1e-14 for v in times(m['cases'][0]['params'])))
 def test_missing_retarget_source_not_admitted(self):
  r,m=fixture();run=next(v for v in r['runs']if v['id']=='modifier_retarget_1_60');run['trace'][0]['required'].pop('source')
  with self.assertRaisesRegex(ValueError,'retarget source'):compare(r,m,'a'*64)
 def test_missing_receiver_skin_not_admitted(self):
  r,m=fixture();r['runs'][0]['trace'][0]['required']['selected']['skin']=0
  with self.assertRaisesRegex(ValueError,'freshness|skin'):compare(r,m,'a'*64)
 def test_skipped_key_not_admitted(self):
  r,m=fixture();r['runs'][0]['trace'].pop(2)
  with self.assertRaisesRegex(ValueError,'samples'):compare(r,m,'a'*64)
 def test_wrong_pose_keeps_original_limits(self):
  r,m=fixture();r['runs'][1]['trace'][2]['selected_pose'][0]['p'][0]=.0002
  self.assertFalse(compare(r,m,'a'*64)['parity_pass'])
 def test_wrong_owner_not_hidden_by_bone_parity(self):
  r,m=fixture();r['runs'][1]['trace'][2]['body']['p'][0]=.0002
  self.assertFalse(compare(r,m,'a'*64)['parity_pass'])
 def test_wrong_source_or_absent_errors_not_admitted(self):
  for field in ('manifest_sha256','engine_errors','failures'):
   r,m=fixture();r.pop(field)
   with self.subTest(field=field),self.assertRaises(ValueError):compare(r,m,'a'*64)
 def test_fresh_reset_difference_is_reported(self):
  r,m=fixture();r['runs'][2]['trace'][0]['body']['p'][0]=.000001
  self.assertFalse(compare(r,m,'a'*64)['fresh_take_pass'])
 def test_exact_cached_skin_allowed_only_if_observed_equal(self):
  r,m=fixture();w=r['runs'][0]['trace'][1]['required']['selected'];w.update(skin=w['skin_before'],skin_fresh=False,skin_cached_unchanged=True)
  self.assertTrue(compare(r,m,'a'*64)['parity_pass'])
  w['skin_pose'][0]['p'][0]=.000001
  with self.assertRaisesRegex(ValueError,'stale changed skin'):compare(r,m,'a'*64)
if __name__=='__main__':unittest.main()
