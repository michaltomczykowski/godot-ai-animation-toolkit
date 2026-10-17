"""Diagnostic observation must not retry, alter params or hide failures."""
import asyncio
import contextlib
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from motion_sequence_transport_diagnostics import observed_call

class Observation(unittest.IsolatedAsyncioTestCase):
    async def test_response_is_identical_and_watch_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            args=SimpleNamespace(record=Path(folder)/'gate.json')
            calls=[];response={'failed':2,'results':[{'duration_ms':80}]}
            async def invoke(client,name,params):
                calls.append((client,name,params));await asyncio.sleep(.02);return response
            params={'suite':'history','verbose':True}
            with contextlib.redirect_stdout(io.StringIO()):result=await observed_call(args,'client',invoke,'test_run',params,interval=.005)
            self.assertIs(result,response)
            self.assertEqual(calls,[('client','test_run',params)])
            events=[json.loads(s) for s in args.record.with_suffix('.transport.jsonl').read_text().splitlines()]
            self.assertEqual(events[0]['stage'],'request_start')
            self.assertEqual(events[-1]['stage'],'response_returned')
            self.assertTrue(any(e['stage']=='awaiting' and e['tasks'] for e in events))
            self.assertEqual(len(events[-1]['response_sha256']),64)
            self.assertFalse(any(t.get_name()=='motion-sequence-diagnostic-watch' for t in asyncio.all_tasks()))
    async def test_original_exception_propagates_once(self):
        args=SimpleNamespace(record=None);calls=[]
        failure=RuntimeError('original')
        async def invoke(*values):calls.append(values);raise failure
        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(RuntimeError) as actual:await observed_call(args,None,invoke,'test_run',{'suite':'x'})
        self.assertIs(actual.exception,failure);self.assertEqual(len(calls),1)
    async def test_cancellation_is_not_swallowed(self):
        async def invoke(*values):raise asyncio.CancelledError()
        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(asyncio.CancelledError):await observed_call(SimpleNamespace(record=None),None,invoke,'test_run',{})
