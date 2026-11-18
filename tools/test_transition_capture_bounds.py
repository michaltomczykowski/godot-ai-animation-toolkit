import copy
from pathlib import Path
import unittest
from check_saved_effects import transition_rect_failures


class TransitionCaptureBounds(unittest.TestCase):
    def fixture(self):
        case={'operation':'animation_fx.transition'}
        rows=[]
        for take in (1,2):
            for rect in ([469.9968,239.9991,.0032,.0018],[150,150,320,180]):
                panes=[{'target_rects':{'FadeOverlay':{'local_size':[640,360],
                    'viewport_rect':list(rect),'visible_in_tree':True}}} for _ in range(2)]
                rows.append({'take':take,'presentation':panes})
        return case,rows

    def test_actual_rects_fit_both_clones_and_takes_with_original_local_size(self):
        case,rows=self.fixture()
        self.assertEqual(transition_rect_failures(case,rows),[])

    def test_cropping_missing_rect_and_changed_target_extent_fail(self):
        for mutation in ['old_crop','missing','local_changed','no_full_hold','invisible']:
            case,rows=self.fixture()
            for row in rows:
                target=row['presentation'][1]['target_rects']['FadeOverlay']
                if mutation=='old_crop': target['viewport_rect']=[250,260,640,360]
                if mutation=='missing': row['presentation'][1]['target_rects']={}
                if mutation=='local_changed': target['local_size']=[220,50]
                if mutation=='no_full_hold': target['viewport_rect']=[150,150,1,1]
                if mutation=='invisible': target['visible_in_tree']=False
            self.assertTrue(transition_rect_failures(case,rows),mutation)

    def test_only_transition_changes_framing_and_reads_actual_rect(self):
        self.assertEqual(transition_rect_failures({'operation':'animation_fx.wave'},[]),[])
        text=(Path(__file__).resolve().parents[1]/'test_project/tools/render_saved_effects.gd').read_text()
        self.assertIn('target.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, target.size)',text)
        start=text.index('func _fixed_transform()');end=text.index('func _apply_fixed_presentation',start)
        self.assertIn('Vector2(0.5, 0.5)',text[start:end])
        self.assertIn('Vector2(150, 150)',text[start:end])


if __name__=='__main__': unittest.main()
