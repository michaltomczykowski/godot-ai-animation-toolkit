import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import operation_case_collector as c

class Collector(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        (self.root/'dependency.py').write_text('fixture-only test dependency')
        self.context=self.root/'context.json'
        self.context.write_text(json.dumps({'kind':'operation_trace_context','run_id':'unit-fixture',
            'trace_producer_sha256':c.sha(c.__file__),'tested_source':'fixture-source',
            'engine':'4.7.2.fixture','platform':'linux','core_version':'4.2.1',
            'core_commit':'fixture-core','core_qualification':'released',
            'dependencies':{'dependency.py':{'sha256':c.sha(self.root/'dependency.py'),'git_blob':'blob'}}}))
        self.traces=self.root/'traces'
        c._context_cache=None;c._trace_file=None;c._sequence=0
        self.env=patch.dict(os.environ,{'TOOLKIT_OPERATION_CONTEXT':str(self.context),'TOOLKIT_OPERATION_TRACE_DIR':str(self.traces)})
        self.env.start();self.addCleanup(self.env.stop)
    def collect(self):
        with patch.object(c,'git',return_value='blob'):
            return c.collect(self.context,self.traces,self.root)
    def test_only_exact_successful_real_operation_claims_invocation(self):
        c.record_public_call('custom_animation_fx',{'op':'shake'}, {'track_count':1})
        report=self.collect()
        self.assertEqual(report['successful_public_operations'],['animation_fx.shake'])
        self.assertEqual(report['cases'][0]['checks'],{'mcp_invocation':'pass'})
        self.assertNotIn('valid_effect',report['cases'][0]['checks'])
        self.assertEqual(len(report['missing_successful_public_operations']),102)
    def test_dry_refusal_and_generic_empty_success_do_not_qualify(self):
        for params,response in [({'op':'shake','dry_run':True},{'dry_run':True}),
                                ({'op':'shake'},{'error':'VALUE_OUT_OF_RANGE: nope'}),
                                ({'op':'shake'}, {})]:
            c.record_public_call('custom_animation_fx',params,response)
        self.assertEqual(self.collect()['successful_public_operations'],[])
    def test_nested_manage_binds_actual_family_and_params(self):
        c.record_public_call('custom_manage',{'op':'invoke','params':{'tool_name':'animation_sequence','params':{'op':'compose'}}},{'key_count':2})
        self.assertEqual(self.collect()['successful_public_operations'],['animation_sequence.compose'])
    def test_suite_total_unknown_and_cross_family_ops_are_not_operation_proof(self):
        c.record_public_call('test_run',{'suite':'fx_route_history'},{'passed':100,'failed':0})
        c.record_public_call('custom_animation_fx',{'op':'__unknown__'},{'data':True})
        c.record_public_call('custom_animation_fx',{'op':'pose_save'},{'data':True})
        self.assertEqual(self.collect()['cases'],[])
    def test_changed_source_dependency_rejected(self):
        c.record_public_call('custom_animation_fx',{'op':'shake'},{'data':True})
        (self.root/'dependency.py').write_text('changed')
        with self.assertRaisesRegex(ValueError,'dependency changed'):
            self.collect()
    def test_wrong_operation_binding_and_foreign_context_rejected(self):
        c.record_public_call('custom_animation_fx',{'op':'shake'},{'data':True})
        file=next(self.traces.glob('*.jsonl'))
        original=file.read_text()
        event=json.loads(original)
        for field,value in [('operation','animation_fx.counter'),('context_sha256','foreign')]:
            bad=dict(event);bad[field]=value
            file.write_text(json.dumps(bad)+'\n')
            with self.assertRaises(ValueError):self.collect()
        file.write_text(original+original)
        with self.assertRaisesRegex(ValueError,'duplicate'):
            self.collect()
    def test_released_core_identity_not_inferred_from_suite_pass(self):
        context=json.loads(self.context.read_text());context['core_qualification']='advisory';context['core_version']=None
        self.context.write_text(json.dumps(context))
        c.record_public_call('custom_animation_fx',{'op':'shake'},{'data':True})
        self.assertEqual(self.collect()['core_qualification'],'advisory')
if __name__=='__main__':unittest.main()
