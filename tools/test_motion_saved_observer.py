"""File-identity controls; no MCP or engine calls."""
import json
import asyncio
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import motion_saved_observer as observer

class FileControls(unittest.TestCase):
    def test_immutable_receipt_and_trace(self):
        with tempfile.TemporaryDirectory() as tmp, patch.object(observer,'_emit',return_value='w') as emit:
            path=Path(tmp)/'run'/'walk_cycle.tscn';path.parent.mkdir();path.write_bytes(b'saved original')
            request=dict(op='walk_cycle')
            saved=observer.saved_witness(path,'res://run/walk_cycle.tscn',request,{'path':'res://run/walk_cycle.tscn'})
            self.assertEqual(observer.read_witness(path),saved)
            self.assertEqual(saved['scene_sha256'],observer.sha(path))
            self.assertEqual(saved['save_witness_id'],'w')
            self.assertEqual(emit.call_args.args[1]['row']['scene_sha256'],observer.sha(path))
            original=Path(str(path)+'.motion-witness.json').read_bytes()
            with self.assertRaises(FileExistsError):observer.saved_witness(path,'res://run/walk_cycle.tscn',request,{})
            self.assertEqual(original,Path(str(path)+'.motion-witness.json').read_bytes())
    def test_wrong_local_scene_rejected(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(observer,'_emit') as emit:
            path=Path(tmp)/'wrong.tscn';path.write_bytes(b'other')
            with self.assertRaisesRegex(ValueError,'declared scene'):observer.saved_witness(path,'res://run/walk_cycle.tscn',{'op':'walk_cycle'},{})
            emit.assert_not_called()
    def test_changed_bytes_observed(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(observer,'_emit',return_value='w'):
            path=Path(tmp)/'walk_cycle.tscn';path.write_bytes(b'original')
            saved=observer.saved_witness(path,'res://walk_cycle.tscn',{'op':'walk_cycle'},{})
            path.write_bytes(b'changed')
            self.assertNotEqual(saved['scene_sha256'],observer.sha(path))

class NavigationControls(unittest.TestCase):
    def run_case(self, responses):
        calls=[]
        async def call(client, tool, request):
            calls.append((tool,request))
            return responses[len(calls)-1]
        try:return asyncio.run(observer.open_saved(call,None,'res://one.tscn')),calls
        except ValueError:return 'refused',calls
    def test_current_reloads_once(self):
        result,calls=self.run_case([dict(path='res://one.tscn',reloaded_from_disk=True)])
        self.assertEqual(len(calls),1);self.assertIsNone(result[1])
    def test_other_tab_navigates_then_reloads_once(self):
        nav=dict(path='res://one.tscn',reloaded_from_disk=False)
        result,calls=self.run_case([nav,dict(path='res://one.tscn',reloaded_from_disk=True)])
        self.assertEqual(len(calls),2);self.assertEqual(result[1],nav)
    def test_error_unknown_wrong_path_not_retried(self):
        for response in (dict(error='fail'),dict(path='res://one.tscn'),dict(path='res://wrong.tscn',reloaded_from_disk=False)):
            result,calls=self.run_case([response]);self.assertEqual(result,'refused');self.assertEqual(len(calls),1)
    def test_second_false_or_error_not_retried(self):
        for response in (dict(error='fail'),dict(path='res://one.tscn',reloaded_from_disk=False)):
            result,calls=self.run_case([dict(path='res://one.tscn',reloaded_from_disk=False),response]);self.assertEqual(result,'refused');self.assertEqual(len(calls),2)

if __name__=='__main__':unittest.main()
