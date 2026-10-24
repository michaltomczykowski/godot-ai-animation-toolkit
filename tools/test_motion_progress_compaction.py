"""Pure full-native retention and repeated-progress size regression controls."""
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from gate_diagnostics import native_progress_payload,progress,bounded_run


def report():
    return {'cases':273,'saved_states':819,'playback_runs':2457,'travel_runs':270,
            'key_samples':2267092,'intermediate_samples':5267861,'approximation_samples':48011,
            'evidence_schema':'motion_sequence_native_v1','manifest_sha256':'a'*64,
            'failures':[],'engine_errors':[],
            'native_cases':[{'id':f'actual-case-{i}','source':{'sha256':str(i)},'plays':[{'sample':list(range(50)),'proof':'retained'} for _ in range(30)]} for i in range(273)]}

class ProgressCompaction(unittest.TestCase):
    def test_large_native_rows_retained_once_not_repeated_in_progress(self):
        with tempfile.TemporaryDirectory() as folder:
            record=Path(folder)/'attempt.json';original=report();frozen=copy.deepcopy(original)
            payload=json.dumps(original,separators=(',',':'));raw=payload.encode()
            compact=native_progress_payload(record,payload,original,'actual-native:8')
            artifact=record.with_suffix('.native-runtime.json');before=artifact.stat().st_mtime_ns
            self.assertEqual(artifact.read_bytes(),raw)
            self.assertEqual(compact['full_native_report']['sha256'],hashlib.sha256(raw).hexdigest())
            self.assertEqual(compact['full_native_report']['native_case_id'],'actual-native:8')
            self.assertEqual(original,frozen)
            self.assertEqual(json.loads(artifact.read_text()),original)
            args=SimpleNamespace(record=record)
            with contextlib.redirect_stdout(io.StringIO()):
                progress(args,'native_completed',runtime=compact)
                for i in range(20):progress(args,'direct_completed',phase='before_reload',case_id=str(i))
            repeated=record.with_suffix('.progress.json').read_bytes()
            self.assertLess(len(repeated),7000)
            self.assertNotIn(b'"native_cases"',repeated);self.assertNotIn(b'"plays"',repeated)
            self.assertEqual(artifact.stat().st_mtime_ns,before)
            self.assertEqual(artifact.read_bytes(),raw)
            self.assertEqual(json.loads(repeated)['runtime']['cases'],273)
            with self.assertRaises(FileExistsError):native_progress_payload(record,payload,original,'new-native:9')
            self.assertEqual(artifact.read_bytes(),raw)
    def test_errors_cannot_be_silently_discarded(self):
        for field in ('failures','engine_errors'):
            actual=report();actual[field]=['actual failure']
            with tempfile.TemporaryDirectory() as folder:
                record=Path(folder)/'failed.json'
                with self.assertRaises(ValueError):native_progress_payload(record,json.dumps(actual),actual)
                self.assertFalse(record.with_suffix('.native-runtime.json').exists())
    def test_boolean_counts_refused_and_non_record_hash_is_honest(self):
        actual=report();payload=json.dumps(actual)
        summary=native_progress_payload(None,payload,actual)
        self.assertIsNone(summary['full_native_report']['path'])
        self.assertEqual(summary['full_native_report']['bytes'],len(payload.encode()))
        actual['cases']=True
        with self.assertRaises(ValueError):native_progress_payload(None,json.dumps(actual),actual)
    def test_timeout_keeps420_and_full_native_pointer(self):
        with tempfile.TemporaryDirectory() as folder:
            record=Path(folder)/'attempt.json';actual=report();payload=json.dumps(actual)
            compact=native_progress_payload(record,payload,actual,'actual-native:8');args=SimpleNamespace(record=record)
            with contextlib.redirect_stdout(io.StringIO()):progress(args,'reconnect_start',runtime=compact)
            error=subprocess.TimeoutExpired(['driver'],420,output=b'actual stdout',stderr=b'actual stderr')
            with patch('gate_diagnostics.subprocess.run',side_effect=error) as run:result=bounded_run(['driver'],420,record,'motion_sequence_history')
            self.assertEqual(run.call_args.kwargs['timeout'],420);self.assertEqual(result.returncode,124)
            metadata=json.loads(record.with_suffix('.motion_sequence_history.timeout.json').read_text())
            self.assertEqual(metadata['phase']['runtime']['full_native_report'],compact['full_native_report'])
            self.assertLess(record.with_suffix('.motion_sequence_history.timeout.json').stat().st_size,7000)
            self.assertEqual(record.with_suffix('.motion_sequence_history.timeout.stdout.log').read_bytes(),b'actual stdout')

    def test_driver_retains_raw_event_full_result_and_native240_limit(self):
        import mcp_motion_sequence_history as driver
        with tempfile.TemporaryDirectory() as folder:
            args=SimpleNamespace(record=Path(folder)/'attempt.json',godot='actual-godot',project_root=Path(folder))
            actual=report();payload=json.dumps(actual,separators=(',',':'))
            completed=subprocess.CompletedProcess(['actual'],0,'native startup\nMOTION_SEQUENCE_HISTORY_RUNTIME='+payload+'\n','')
            with patch.object(driver,'bounded_run',return_value=completed) as native,patch.object(driver,'record_native_result',return_value='native-event:8') as raw:
                result=driver.runtime(args)
            self.assertEqual(result,actual);self.assertIn('native_cases',result)
            self.assertEqual(native.call_args.args[1],240)
            self.assertEqual(native.call_args.args[0],['actual-godot','--headless','--path',folder,'--script','res://tools/check_motion_sequence_history.gd'])
            self.assertIs(raw.call_args.args[-1],completed)
            self.assertEqual(raw.call_args.args[0],'animation_sequence.compose')
            self.assertNotIn('native_cases',args._native_progress)
            self.assertEqual(args._native_progress['full_native_report']['native_case_id'],'native-event:8')
            self.assertEqual(Path(args._native_progress['full_native_report']['path']).read_bytes(),payload.encode())
    def test_driver_native_failure_keeps_raw_event_and_never_compacts(self):
        import mcp_motion_sequence_history as driver
        for error_case in ('nonzero','engine_error','reported_failure'):
            with self.subTest(error_case=error_case),tempfile.TemporaryDirectory() as folder:
                args=SimpleNamespace(record=Path(folder)/'attempt.json',godot='actual-godot',project_root=Path(folder))
                actual=report()
                if error_case=='reported_failure':actual['failures']=['real native failure']
                stdout='MOTION_SEQUENCE_HISTORY_RUNTIME='+json.dumps(actual)+'\n'
                if error_case=='engine_error':stdout+='ERROR: actual engine error\n'
                completed=subprocess.CompletedProcess(['actual'],1 if error_case=='nonzero' else 0,stdout,'')
                with patch.object(driver,'bounded_run',return_value=completed),patch.object(driver,'record_native_result') as raw:
                    with self.assertRaises(RuntimeError):driver.runtime(args)
                self.assertIs(raw.call_args.args[-1],completed)
                self.assertFalse(args.record.with_suffix('.native-runtime.json').exists())
                self.assertFalse(hasattr(args,'_native_progress'))

if __name__=='__main__':unittest.main()
