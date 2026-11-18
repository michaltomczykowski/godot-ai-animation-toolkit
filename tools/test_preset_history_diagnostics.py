import argparse
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
from mcp_preset_library_history import progress,valid_suite
from ci_mcp_route import preset_library_history_gate


class PresetHistoryDiagnostics(unittest.TestCase):
    def test_suite_payload_is_durable_before_next_phase(self):
        with tempfile.TemporaryDirectory() as temp,contextlib.redirect_stdout(io.StringIO()):
            args=argparse.Namespace(record=Path(temp)/'gate.json')
            progress(args,'suite_start',suite='preset_library_history')
            result={'passed':7,'results':[{'test':'actual_suite_row'}]}
            progress(args,'suite_returned',suite='preset_library_history',result=result)
            progress(args,'suite_start',suite='library_contracts')
            saved=json.loads(args.record.with_suffix('.progress.json').read_text())
            self.assertEqual(saved['stage'],'suite_start')
            self.assertEqual(saved['suite'],'library_contracts')
            self.assertEqual(saved['result'],result)
            self.assertEqual([e['stage'] for e in saved['events']],['suite_start','suite_returned','suite_start'])

    def test_outer_timeout_remains120_and_nonzero_cannot_pass(self):
        with tempfile.TemporaryDirectory() as temp,contextlib.redirect_stdout(io.StringIO()):
            args=argparse.Namespace(log=str(Path(temp)/'core-first-editor.log'),core_root=Path(temp),project=Path(temp),port=8000,ws_port=9500,godot=__file__)
            def bounded(command,timeout,record,label):
                self.assertEqual(timeout,120)
                self.assertEqual(label,'preset_library_history')
                self.assertEqual(command[command.index('--record')+1],str(record))
                return subprocess.CompletedProcess(command,124,'PRESET_LIBRARY_PROGRESS={"stage":"suite_start"}','MCP_GATE_TIMEOUT=actual')
            with patch.dict(sys.modules,{'gate_diagnostics':types.SimpleNamespace(bounded_run=bounded)}):
                self.assertFalse(preset_library_history_gate(args))

    def test_original_suite_assertion_gate_remains_strict(self):
        self.assertFalse(valid_suite({'passed':1,'failed':0,'total':1,'results':[{'test':'sample','passed':True,'assertion_count':1}]},{'sample':2}))


if __name__=='__main__': unittest.main()
