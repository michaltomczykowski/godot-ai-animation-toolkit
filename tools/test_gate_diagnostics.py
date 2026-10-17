import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from gate_diagnostics import bounded_run,progress

class Diagnostics(unittest.TestCase):
    def test_timeout_preserves_original_bytes_phase_and_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            record=Path(folder)/'attempt.json'
            args=SimpleNamespace(record=record)
            with contextlib.redirect_stdout(io.StringIO()):
                progress(args,'suite_start',suite='history')
                progress(args,'native_start',suites={'history':{'passed':1,'failed':0}})
            error=subprocess.TimeoutExpired(['fake'],420,output=b'partial\xffstdout',stderr=b'partial stderr')
            with patch('gate_diagnostics.subprocess.run',side_effect=error) as run:
                result=bounded_run(['fake'],420,record,'history')
            self.assertEqual(result.returncode,124)
            self.assertEqual(run.call_args.kwargs['timeout'],420)
            self.assertIn('"stage": "native_start"',result.stderr)
            metadata=json.loads(record.with_suffix('.history.timeout.json').read_text())
            self.assertEqual(metadata['phase']['suites']['history']['failed'],0)
            self.assertEqual(Path(metadata['partial_stdout']).read_bytes(),b'partial\xffstdout')
            self.assertEqual(Path(metadata['partial_stderr']).read_bytes(),b'partial stderr')
            with patch('gate_diagnostics.subprocess.run',side_effect=error):
                with self.assertRaises(FileExistsError):bounded_run(['fake'],420,record,'history')
    def test_nonzero_or_successful_subprocess_keeps_actual_status(self):
        for code in (0,1,12):
            result=subprocess.CompletedProcess(['fake'],code,'actual stdout','actual stderr')
            with patch('gate_diagnostics.subprocess.run',return_value=result):
                self.assertIs(bounded_run(['fake'],240,Path('unused.json'),'native'),result)
    def test_progress_records_stage_without_inferring_test_pass(self):
        with tempfile.TemporaryDirectory() as folder:
            record=Path(folder)/'attempt.json';args=SimpleNamespace(record=record)
            with contextlib.redirect_stdout(io.StringIO()):
                progress(args,'suite_returned',suite='history',suites={'history':{'failed':2}})
            report=json.loads(record.with_suffix('.progress.json').read_text())
            self.assertEqual(report['stage'],'suite_returned')
            self.assertEqual(report['suites']['history']['failed'],2)
            self.assertNotIn('passed',report)
if __name__=='__main__':unittest.main()
