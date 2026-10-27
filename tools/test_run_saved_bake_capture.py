import copy
import unittest

from check_saved_bake_capture import times
from run_saved_bake_capture import cameras, same_traces
from test_check_saved_bake_capture import fixture


def native_fixture():
    report, manifest = fixture()
    for run in report['runs']:
        run.update(loaded_spring_cache=[], saved_modifiers=[], authored_duration=.205, spring_reset_contract='same_mutable_axes_value_then_native_reset')
        for sample in run['trace']:
            for witness in sample['required'].values():
                witness['pose']['world'] = [{'origin':[0., 0., 0.], 'basis':[[1., 0., 0.], [0., 1., 0.], [0., 0., 1.]]}]
    return report, manifest


class CaptureControls(unittest.TestCase):
    def test_exact_native_trace(self):
        r, _ = native_fixture()
        self.assertTrue(same_traces(r, copy.deepcopy(r)))

    def test_draw_cannot_add_solve_change_pose_root_or_event(self):
        for field, value in [('event_cursor', 1), ('consumer_count', 2), ('delta', .1)]:
            r, _ = native_fixture(); changed = copy.deepcopy(r)
            changed['runs'][0]['trace'][1][field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, 'exact native trace'):
                same_traces(r, changed)
        r, _ = native_fixture(); changed = copy.deepcopy(r)
        changed['runs'][0]['trace'][1]['required']['selected']['final'] += 1
        with self.assertRaises(ValueError): same_traces(r, changed)

    def test_missing_or_duplicate_run_refused(self):
        r, _ = native_fixture(); changed = copy.deepcopy(r)
        changed['runs'][-1] = changed['runs'][0]
        with self.assertRaisesRegex(ValueError, 'matrix'): same_traces(r, changed)

    def test_camera_union_includes_redo_and_second_take(self):
        r, _ = native_fixture(); original = cameras(r)
        r['runs'][3]['trace'][-1]['required']['selected']['pose']['world'][0]['origin'] = [20., 30., -10.]
        changed = cameras(r)
        key = r['runs'][3]['id']
        self.assertNotEqual(original[key], changed[key])
        self.assertGreater(changed[key][0]['size'], original[key][0]['size'])

    def test_nonfinite_geometry_refused(self):
        r, _ = native_fixture()
        r['runs'][0]['trace'][0]['required']['selected']['pose']['world'][0]['origin'][0] = float('nan')
        with self.assertRaisesRegex(ValueError, 'world point'): cameras(r)

    def test_actual_subframe_schedule_and_endpoint_retained(self):
        _, m = native_fixture(); schedule = times(m['cases'][0]['params'])
        self.assertEqual(schedule[-1], .205)
        self.assertIn(.07, schedule)
        self.assertTrue(any(abs(t-.06996) < 1e-12 for t in schedule))


if __name__ == '__main__': unittest.main()
