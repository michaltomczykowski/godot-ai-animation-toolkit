import unittest
from prepare_effect_temporal_review import frame_selection


class SelectionTests(unittest.TestCase):
    def test_uses_observed_reset_boundary_and_preserves_late_changes(self):
        fps = 60
        samples = [
            {'frame': i+1, 'take': 1 if i < 361 else 2, 'time': (i+1)/fps,
             'states': [{}, {'value': 0 if i < 235 or 236 <= i < 542 or i >= 543 else 1}]}
            for i in range(720)
        ]
        observed = {r['frame']: r for r in frame_selection(samples, fps)}
        for i in (0, 234, 235, 236, 359, 360, 361, 541, 542, 543, 719):
            self.assertIn(i, observed)
        self.assertEqual(observed[360]['take'], 1)
        self.assertEqual(observed[361]['take'], 2)
        self.assertEqual(list(observed), sorted(observed))

    def test_refuses_a_missing_take_or_broken_frame_index(self):
        samples = [{'frame': i+1, 'take': 1, 'time': i/10, 'states': [{}, {}]}
                   for i in range(20)]
        with self.assertRaisesRegex(ValueError, 'Missing full take'):
            frame_selection(samples, 10)
        samples[0]['frame'] = 0
        with self.assertRaisesRegex(ValueError, 'Invalid observed'):
            frame_selection(samples, 10)


if __name__ == '__main__':
    unittest.main()
