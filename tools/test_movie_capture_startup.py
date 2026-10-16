from pathlib import Path
import subprocess
import json
import tempfile
import unittest
from movie_capture_startup import run_capture,override_bytes


class MovieStartupControls(unittest.TestCase):
    def test_owned_override_cleanup_success_failure_and_exception(self):
        for mode in ['success','failure','exception']:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temp:
                project=Path(temp);(project/'project.godot').write_text('config_version=5')
                command=['godot','--path',str(project)]
                def runner(cmd,check):
                    self.assertEqual((project/'override.cfg').read_bytes(),override_bytes(1400,800))
                    initial=json.loads((project/'receipt.json').read_text())
                    self.assertEqual(initial['state'],'owned_override_ready_before_launch')
                    self.assertTrue(initial['override_owned'])
                    self.assertIsNone(initial['returncode'])
                    if mode=='exception': raise RuntimeError('controlled launch failure')
                    return subprocess.CompletedProcess(cmd,0 if mode=='success' else 3)
                report=run_capture(project,1400,800,project/'receipt.json',command,runner)
                self.assertEqual(report['passed'],mode=='success')
                self.assertFalse((project/'override.cfg').exists())
                self.assertEqual(report['project_sha256_before'],report['project_sha256_after'])

    def test_foreign_existing_override_is_preserved_and_never_launched(self):
        with tempfile.TemporaryDirectory() as temp:
            project=Path(temp);(project/'project.godot').write_text('config_version=5')
            (project/'override.cfg').write_text('foreign')
            report=run_capture(project,1400,800,project/'receipt.json',['godot','--path',temp],lambda *a,**k:self.fail('must not launch'))
            self.assertFalse(report['passed'])
            self.assertEqual((project/'override.cfg').read_text(),'foreign')

    def test_changed_owned_override_is_preserved_and_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            project=Path(temp);(project/'project.godot').write_text('config_version=5')
            def runner(cmd,check):
                (project/'override.cfg').write_text('changed')
                return subprocess.CompletedProcess(cmd,0)
            report=run_capture(project,1400,800,project/'receipt.json',['godot','--path',temp],runner)
            self.assertFalse(report['passed'])
            self.assertEqual((project/'override.cfg').read_text(),'changed')


if __name__=='__main__': unittest.main()
