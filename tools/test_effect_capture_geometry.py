import struct
import tempfile
from pathlib import Path
import unittest
from check_saved_effects import capture_failures


class CaptureGeometryControls(unittest.TestCase):
    def report(self):
        return {'capture_geometry':{'logical_size':[1400,800],'render_size':[1400,800],
            'window_size':[1152,648],'content_scale_mode':2,'content_scale_aspect':1}}

    def test_small_window_can_present_complete_logical_render(self):
        self.assertEqual(capture_failures(self.report()),[])

    def test_cropped_render_and_missing_contract_fail(self):
        report=self.report()
        report['capture_geometry']['render_size']=[1152,648]
        self.assertTrue(capture_failures(report))
        self.assertTrue(capture_failures({}))

    def test_disabled_scaling_fails(self):
        report=self.report()
        report['capture_geometry']['content_scale_mode']=0
        self.assertTrue(capture_failures(report))

    def test_all_actual_png_headers_and_count_are_checked(self):
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp)
            def header(width,height): return b'\x89PNG\r\n\x1a\n'+struct.pack('>I',13)+b'IHDR'+struct.pack('>II',width,height)
            (folder/'frame000.png').write_bytes(header(1400,800))
            (folder/'frame001.png').write_bytes(header(1400,800))
            self.assertEqual(capture_failures(self.report(),folder,2),[])
            (folder/'frame001.png').write_bytes(header(1152,648))
            self.assertIn('cropped/invalid PNG dimensions: frame001.png',capture_failures(self.report(),folder,2))
            self.assertTrue(capture_failures(self.report(),folder,3))


if __name__ == '__main__': unittest.main()
