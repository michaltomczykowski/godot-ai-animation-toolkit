import unittest
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
if __name__=='__main__':unittest.main()
