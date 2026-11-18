import argparse
import asyncio
import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch
import mcp_rig_clip_history as rig
from ci_mcp_route import rig_clip_history_gate


class RigHistoryDiagnostics(unittest.TestCase):
    def test_full_result_is_durable_before_transport_exit_and_each_runtime(self):
        with tempfile.TemporaryDirectory() as temp,contextlib.redirect_stdout(io.StringIO()):
            args=argparse.Namespace(core_root=Path(temp),project_root=Path(temp),port=8000,ws_port=9500,
                session_hint='fixture',godot='fake',record=Path(temp)/'rig.json')
            suite={'passed':len(rig.EXPECTED),'failed':0,'skipped':0,'total':len(rig.EXPECTED),
                'results':[{'test':name,'passed':True,'assertion_count':count} for name,count in rig.EXPECTED.items()]}
            class Client:
                async def __aenter__(self): return self
                async def __aexit__(self,*unused):
                    saved=json.loads(args.record.with_suffix('.progress.json').read_text())
                    self_test.assertEqual(saved['stage'],'transport_exit_start')
                    self_test.assertEqual(saved['suite_result'],suite)
                async def call_tool(self,*unused): return {}
            self_test=self
            async def call(client,name,params): return suite if name=='test_run' else {}
            def native(command,**kwargs):
                saved=json.loads(args.record.with_suffix('.progress.json').read_text())
                self.assertEqual(saved['stage'],'native_start')
                return subprocess.CompletedProcess(command,0,'RIG_CLIP_HISTORY_RUNTIME='+json.dumps({'saved_states':18,'failures':[],'engine_errors':[]}), '')
            with patch.object(rig,'StdioTransport',return_value=object()),patch.object(rig,'Client',return_value=Client()),patch.object(rig,'call',call),patch.object(rig.subprocess,'run',native):
                self.assertEqual(asyncio.run(rig.run(args)),0)
            saved=json.loads(args.record.with_suffix('.progress.json').read_text())
            self.assertEqual(saved['stage'],'completed')
            self.assertEqual(sum(row['report']['saved_states'] for row in saved['runtime']),90)

    def test_outer_gate_remains120_and_timeout_fails(self):
        with tempfile.TemporaryDirectory() as temp,contextlib.redirect_stdout(io.StringIO()):
            args=argparse.Namespace(log=str(Path(temp)/'core-first-editor.log'),core_root=Path(temp),project=Path(temp),port=8000,ws_port=9500,godot=__file__)
            def bounded(command,timeout,record,label):
                self.assertEqual(timeout,120)
                self.assertEqual(label,'rig_clip_history')
                self.assertEqual(command[command.index('--record')+1],str(record))
                return subprocess.CompletedProcess(command,124,'RIG_CLIP_PROGRESS={"stage":"suite_start"}','MCP_GATE_TIMEOUT=actual')
            with patch.dict(sys.modules,{'gate_diagnostics':types.SimpleNamespace(bounded_run=bounded)}):
                self.assertFalse(rig_clip_history_gate(args))


if __name__=='__main__': unittest.main()
