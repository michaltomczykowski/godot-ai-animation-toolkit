import json,tempfile,unittest
from pathlib import Path
from types import SimpleNamespace
from subprocess import CompletedProcess,TimeoutExpired
from test_check_saved_modifier_capture import fixture
from saved_media_capture_checks import sha
from record_saved_modifier_capture import capture
class Receipt(unittest.TestCase):
    def test_engine_timeout_preserves_failure_receipt(self):
        with tempfile.TemporaryDirectory() as folder:
            base=Path(folder);report,manifest=fixture();m=base/'manifest.json';m.write_text(json.dumps(manifest));report['manifest_sha256']=sha(m);n=base/'native.json';n.write_text(json.dumps(report))
            args=SimpleNamespace(output=base/'output',manifest=m,native=n,project=base,appdata=base/'appdata',godot=Path('never-launched'),ffmpeg=Path('never-encoded'),ffprobe=Path('never-probed'))
            calls=[]
            def expire(command,**kwargs):
                calls.append(kwargs);raise TimeoutExpired(command,kwargs['timeout'])
            with self.assertRaises(TimeoutExpired):capture(args,runner=expire)
            receipt=json.loads((args.output/'recording.json').read_text());self.assertEqual(receipt['state'],'failed_preserved');self.assertIn('TimeoutExpired',receipt['error']);self.assertEqual(calls[0]['timeout'],900);self.assertEqual(len(calls),1)
    def test_engine_failure_preserves_receipt_without_launch(self):
        with tempfile.TemporaryDirectory() as folder:
            base=Path(folder);report,manifest=fixture();m=base/'manifest.json';m.write_text(json.dumps(manifest));report['manifest_sha256']=sha(m);n=base/'native.json';n.write_text(json.dumps(report))
            args=SimpleNamespace(output=base/'output',manifest=m,native=n,project=base,appdata=base/'appdata',godot=Path('never-launched'),ffmpeg=Path('never-encoded'),ffprobe=Path('never-probed'))
            calls=[]
            def fail(command,**kwargs):calls.append(command);return CompletedProcess(command,1,'synthetic controlled failure','')
            with self.assertRaises(ValueError):capture(args,runner=fail)
            receipt=json.loads((args.output/'recording.json').read_text());self.assertEqual(receipt['state'],'failed_preserved');self.assertEqual(receipt['engine_exit'],1);self.assertEqual(len(calls),1);self.assertTrue((args.output/'engine.log').is_file())
if __name__=='__main__':unittest.main()
