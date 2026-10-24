import argparse
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from operation_derived_gate import derived_failures
class Gate(unittest.TestCase):
    def test_intentional_refusal_is_not_semantic_failure(self):
        self.assertEqual(derived_failures({'cases':[{'checks':{'mcp_invocation':'fail'}},{'checks':{}},{'checks':{'typed_errors':'pass'}}]}),[])
    def test_each_derived_failure_blocks_even_with_green_public_result(self):
        for check in ('save_reopen','track_paths_types','playback','valid_effect','reported_errors','source_unchanged'):
            report={'successful_public_operations':['animation_motion.jump'],'missing_successful_public_operations':[],'core_qualification':'released','cases':[{'id':'actual-row','operation':'animation_motion.jump','checks':{'mcp_invocation':'pass',check:'fail'}}]}
            self.assertEqual(derived_failures(report),[{'id':'actual-row','operation':'animation_motion.jump','check':check}])
    def test_no_missing_or_pending_claim_is_invented(self):
        self.assertEqual(derived_failures({'cases':[{'checks':{'valid_effect':'pending','playback':'pass'}}]}),[])
    def test_malformed_records_are_not_green(self):
        for report in ({},{'cases':None},{'cases':[{}]},{'cases':[{'checks':{'playback':False}}]}):
            with self.assertRaises(ValueError):derived_failures(report)

class EntryPoints(unittest.TestCase):
    def report(self, failed=True):
        return {'successful_public_operations':['animation_motion.jump'],
                'missing_successful_public_operations':[], 'core_qualification':'released',
                'cases':[{'id':'native-row','operation':'animation_motion.jump',
                          'checks':{'mcp_invocation':'fail',
                                    'playback':'fail' if failed else 'pass'}}]}

    def test_partial_collector_still_blocks_failed_derived_checks_and_saves_report(self):
        import operation_case_collector as collector
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder); output=root/'report.json'
            argv=['collector','collect','--context',str(root/'context.json'),
                  '--trace-dir',str(root/'traces'),'--root',str(root),
                  '--output',str(output),'--allow-partial']
            report=self.report()
            with patch.object(sys,'argv',argv), patch.object(collector,'collect',return_value=report):
                self.assertEqual(collector.main(),2)
            self.assertEqual(json.loads(output.read_text()),report)

    def test_runner_blocks_derived_failure_even_when_route_returns_zero(self):
        import ci_mcp_route as route
        import operation_case_collector as collector
        for failed, expected in ((True,1),(False,0)):
            with self.subTest(failed=failed), tempfile.TemporaryDirectory() as folder:
                output=Path(folder)/'evidence'; report=self.report(failed)
                args=argparse.Namespace(case_output_dir=output,existing=False,
                                       core_root=Path(folder),godot='fixture',
                                       require_all_public_operations=False)
                with patch.object(route,'run',return_value=0), \
                     patch.object(route,'godot_executable',return_value='fixture'), \
                     patch.object(collector,'prepare'), \
                     patch.object(collector,'collect',return_value=report):
                    self.assertEqual(route.run_with_case_collection(args),expected)
                self.assertEqual(json.loads((output/'operation-case-results.json').read_text()),report)
if __name__=='__main__':unittest.main()
