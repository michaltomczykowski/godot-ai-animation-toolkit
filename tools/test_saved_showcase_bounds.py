import copy
import unittest
from check_saved_effects import showcase_rect_failures

class ShowcaseBounds(unittest.TestCase):
    def fixture(self):
        controls={name:{'viewport_rect':[20,100,100,30],'visible_in_tree':True,'fits':True} for name in ('Title','BounceButton','OrbitDot','SweepPivot/SweepBar','DriftLine','PulseLabel')}
        controls['DriftLine']['viewport_rect']=[515,352,135,1.8]
        rows=[{'take':take,'presentation':[{'showcase_present':False,'showcase_controls':{}},{'showcase_present':True,'showcase_controls':copy.deepcopy(controls)}]} for take in (1,2)]
        return {'display_mode':'showcase'},rows
    def test_exact_redo_controls_and_empty_undo(self):
        case,rows=self.fixture();self.assertEqual(showcase_rect_failures(case,rows),[])
    def test_cropped_target_cannot_borrow_a_fit_flag(self):
        case,rows=self.fixture()
        rows[1]['presentation'][1]['showcase_controls']['DriftLine']['viewport_rect']=[605,352,165,2.2]
        self.assertEqual(len(showcase_rect_failures(case,rows)),1)
    def test_missing_hidden_nan_undo_and_second_take_refused(self):
        for fault in ('missing','hidden','nan','undo','take'):
            case,rows=self.fixture();pane=rows[1]['presentation'][1]
            if fault=='missing':pane['showcase_controls'].pop('SweepPivot/SweepBar')
            if fault=='hidden':pane['showcase_controls']['DriftLine']['visible_in_tree']=False
            if fault=='nan':pane['showcase_controls']['DriftLine']['viewport_rect'][0]=float('nan')
            if fault=='undo':rows[1]['presentation'][0]['showcase_present']=True
            if fault=='take':rows.pop()
            with self.subTest(fault=fault):self.assertTrue(showcase_rect_failures(case,rows))

if __name__=='__main__':unittest.main()
