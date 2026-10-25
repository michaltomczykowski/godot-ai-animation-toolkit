"""Focused fake-process controls: no engine/public mutation or retries."""
import json,os,subprocess,tempfile,unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
import check_selected_motion_intent as runner
from test_operation_idle_turn_intent_checks import bound
from mcp_run_quality_review import selected_rigs

class Controls(unittest.TestCase):
 def test_public_selector_retains_all_four_by_default_and_changes_no_request(self):
  self.assertEqual([r[0]for r in selected_rigs('idle_cycle')],['dummy','xbot','short','zup_tall'])
  self.assertEqual([r[0]for r in selected_rigs('turn_cycle','dummy')],['dummy'])
  for op,rig in [('jump','dummy'),('idle_cycle','xbot'),('idle_cycle','bad')]:
   with self.assertRaises(ValueError):selected_rigs(op,rig)
 def test_actual_completed_native_result_and_bytes_preserved_once(self):
  with tempfile.TemporaryDirectory()as d:
   root=Path(d);route=root/'route.json';e,*_=bound('idle_cycle');route.write_bytes(bytes.fromhex(e['row']['route_bytes_hex']));args=SimpleNamespace(route=route,output=root/'attempt',godot='official-godot',project_root=root);ctx=root/'context.json';ctx.write_text(json.dumps({'tested_source':'d'*40,'engine_command':'official-godot'}))
   completed=SimpleNamespace(returncode=0,stdout='untouched native stdout',stderr='untouched stderr')
   def execute(command,**kw):
    self.assertEqual(kw['timeout'],90);self.assertEqual(command[-2:],['candidate','case_id=dummy']);(args.output/'native.json').write_bytes(bytes.fromhex(e['row']['report_bytes_hex']));return completed
   with patch.dict(os.environ,TOOLKIT_OPERATION_CONTEXT=str(ctx),TOOLKIT_OPERATION_TRACE_DIR='trace'),patch.object(runner.subprocess,'run',side_effect=execute)as run,patch.object(runner,'record_native_result',return_value='actual-native')as record,patch.object(runner,'record_snapshot_result')as snapshot:
    self.assertEqual(runner.run(args),0);run.assert_called_once();record.assert_called_once();self.assertIs(record.call_args.args[-1],completed);snapshot.assert_called_once();row=snapshot.call_args.args[1];self.assertEqual(row['native_case_id'],'actual-native');self.assertEqual(bytes.fromhex(row['report_bytes_hex']),(args.output/'native.json').read_bytes())
    with self.assertRaises(FileExistsError):runner.run(args)
    run.assert_called_once()
 def test_timeout_partial_streams_retained_without_retry_or_fabricated_completion(self):
  with tempfile.TemporaryDirectory()as d:
   root=Path(d);route=root/'route.json';e,*_=bound('turn_cycle');route.write_bytes(bytes.fromhex(e['row']['route_bytes_hex']));args=SimpleNamespace(route=route,output=root/'attempt',godot='official-godot',project_root=root);ctx=root/'context.json';ctx.write_text(json.dumps({'tested_source':'d'*40,'engine_command':'official-godot'}))
   with patch.dict(os.environ,TOOLKIT_OPERATION_CONTEXT=str(ctx),TOOLKIT_OPERATION_TRACE_DIR='trace'),patch.object(runner.subprocess,'run',side_effect=subprocess.TimeoutExpired(['godot'],90,output=b'partial native',stderr=b'partial error'))as run,patch.object(runner,'record_native_result')as record:
    with self.assertRaises(subprocess.TimeoutExpired):runner.run(args)
    run.assert_called_once();record.assert_not_called();self.assertEqual((args.output/'native.partial.stdout').read_bytes(),b'partial native');self.assertEqual(json.loads((args.output/'timeout.json').read_text())['state'],'timed_out_unknown_no_retry')
 def test_missing_source_context_rejects_before_process(self):
  with patch.dict(os.environ,{},clear=True),patch.object(runner.subprocess,'run')as run:
   with self.assertRaises(ValueError):runner.run(SimpleNamespace())
   run.assert_not_called()
if __name__=='__main__':unittest.main()
