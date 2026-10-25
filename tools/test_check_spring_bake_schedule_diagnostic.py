import unittest,copy,math
from check_spring_bake_schedule_diagnostic import summarize,STRATEGIES
P={'position':[0.,0.,0.],'rotation':[0.,0.,0.,1.],'scale':[1.,1.,1.]}
def fixture():
 runs=[]
 for axis,individual,animated in ((3,False,False),(4,True,False),(3,False,True)):
  for fps in (30,60,120):
   for strategy in STRATEGIES:
    trace=[{'tick':i,'time':min(i/fps,.2),'final_pose':[copy.deepcopy(P)],'after_player':{'raw':i,'final':i,'skin':i},'after_wait':{'raw':i,'final':i,'skin':i}}for i in range(math.ceil(.2*fps)+1)]
    runs.append(dict(axis=axis,individual=individual,animated=animated,fps=fps,strategy=strategy,trace=trace))
 return {'kind':'spring_bake_raw_schedule_diagnostic','passed_observations':True,'engine_errors':[],'failures':[],'runs':runs}
class Controls(unittest.TestCase):
 def test_complete_shape(self):self.assertEqual(len(summarize(fixture())['comparisons']),54)
 def test_missing_or_duplicate_cells_refused(self):
  for change in ('missing','duplicate'):
   r=fixture()
   if change=='missing':r['runs'].pop()
   else:r['runs'].append(copy.deepcopy(r['runs'][0]))
   with self.subTest(change=change),self.assertRaises(ValueError):summarize(r)
 def test_wrong_manual_clock_refused(self):
  r=fixture();r['runs'][0]['trace'][1]['time']=0
  with self.assertRaisesRegex(ValueError,'manual clock'):summarize(r)
 def test_real_divergence_and_unsolicited_solve_preserved(self):
  r=fixture();r['runs'][2]['trace'][1]['final_pose'][0]['position'][0]=.0002;r['runs'][2]['trace'][1]['after_wait']['raw']+=1
  s=summarize(r);self.assertTrue(any(v['outside_original_limits_ticks']for v in s['comparisons']));self.assertTrue(any(v['pre_sample_wait_changes']for v in s['notifications']));self.assertTrue(s['diagnostic_only'])
if __name__=='__main__':unittest.main()
