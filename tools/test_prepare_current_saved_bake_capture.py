import copy,unittest
from pathlib import Path
from unittest.mock import patch
import prepare_current_saved_bake_capture as p
BUNDLE=Path(r'E:/GodotAI-toolkit-release-2.0.0/20261014/gait-bake-public-r001')
class ActualAnchorControls(unittest.TestCase):
 def test_actual_anchor_exact_eight(self):
  c,r,m,rows,w=p.admit(BUNDLE);self.assertEqual(tuple(v['id']for v in rows),p.IDS);self.assertEqual(len(w),6);self.assertEqual(c['tested_source'],p.SOURCE)
 def test_wrong_source_missing_errors_and_suite_response_rejected(self):
  original=p.read
  for variant in ('source','errors','suite','request'):
   def altered(path):
    v=original(path)
    if variant=='source'and path.name=='operation-context.json':v['tested_source']='0'*40
    if variant=='errors'and path.name=='bake-restoration.json':v['runtime'].pop('engine_errors')
    if variant=='suite'and path.name=='bake-restoration.json':v['suites']['rig_bake_graph']['duration_ms']+=1
    if variant=='request'and path.name=='rig_bake_saved_matrix.json':next(r for r in v['cases']if r['id']==p.IDS[0])['params']['fps']=30
    return v
   with self.subTest(variant=variant),patch.object(p,'read',side_effect=altered),self.assertRaises(ValueError):p.admit(BUNDLE)
if __name__=='__main__':unittest.main()
