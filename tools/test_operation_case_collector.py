import json
import os
from pathlib import Path
import tempfile
import subprocess
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
            'engine':'4.7.2.fixture','engine_command':'fixture-godot','platform':'linux','core_version':'4.2.1',
            'core_commit':'fixture-core','core_qualification':'released',
            'dependencies':{'dependency.py':{'sha256':c.sha(self.root/'dependency.py'),'git_blob':'blob'}}}))
        self.traces=self.root/'traces'
        c._context_cache=None;c._trace_file=None;c._sequence=0;c._active_scene=""
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
    def native_fixture(self, public=True, scene='res://shake.tscn'):
        checker=self.root/'test_project/tools/check_fx_runtime.gd'
        checker.parent.mkdir(parents=True,exist_ok=True)
        checker.write_text('fixture-only source identity')
        context=json.loads(self.context.read_text())
        context['dependencies']['test_project/tools/check_fx_runtime.gd']={'sha256':c.sha(checker),'git_blob':'blob'}
        self.context.write_text(json.dumps(context))
        if public:
            c.record_public_call('scene_open',{'path':scene},{'opened':True})
            c.record_public_call('custom_animation_fx',{'op':'shake','animation_name':'shake'},{'track_count':1})
        command=['fixture-godot','--headless','--script','res://tools/check_fx_runtime.gd','--',scene,'shake']
        payload={'op':'shake','scene':scene,'failures':[],'checks':[{'actual':'native-value'}]}
        return command,payload
    def test_actual_native_fx_result_links_exact_public_case_and_narrow_checks(self):
        command,payload=self.native_fixture()
        c.record_native_result('animation_fx.shake','res://shake.tscn',command,
            subprocess.CompletedProcess(command,0,'FX_RUNTIME='+json.dumps(payload),'') )
        report=self.collect();native=report['cases'][-1]
        self.assertEqual(native['checks'],{'playback':'pass','track_paths_types':'pass'})
        self.assertEqual(native['public_case_ids'],[report['cases'][0]['id']])
        self.assertNotIn('valid_effect',native['checks'])
    def test_native_green_cannot_borrow_unrelated_or_absent_public_scene(self):
        command,payload=self.native_fixture(public=False)
        c.record_native_result('animation_fx.shake','res://shake.tscn',command,
            subprocess.CompletedProcess(command,0,'FX_RUNTIME='+json.dumps(payload),'') )
        native=self.collect()['cases'][-1]
        self.assertEqual(native['checks']['playback'],'fail')
        self.assertEqual(native['public_case_ids'],[])
    def test_native_wrong_operation_or_engine_binding_rejected(self):
        command,payload=self.native_fixture()
        payload['op']='counter'
        c.record_native_result('animation_fx.shake','res://shake.tscn',command,
            subprocess.CompletedProcess(command,0,'FX_RUNTIME='+json.dumps(payload),'') )
        with self.assertRaisesRegex(ValueError,'operation/scene'): self.collect()
        file=next(self.traces.glob('*.jsonl'));events=[json.loads(line) for line in file.read_text().splitlines()]
        events[-1]['command'][0]='different-engine'
        file.write_text(''.join(json.dumps(event)+'\n' for event in events))
        with self.assertRaisesRegex(ValueError,'engine command'):self.collect()
    def test_native_engine_error_and_ambiguous_marker_cannot_be_green(self):
        command,payload=self.native_fixture()
        c.record_native_result('animation_fx.shake','res://shake.tscn',command,
            subprocess.CompletedProcess(command,0,'FX_RUNTIME='+json.dumps(payload),'ERROR: engine failed'))
        self.assertEqual(self.collect()['cases'][-1]['checks']['playback'],'fail')
        file=next(self.traces.glob('*.jsonl'));events=[json.loads(line) for line in file.read_text().splitlines()]
        events[-1]['stderr']='';events[-1]['stdout']+='\n'+events[-1]['stdout']
        file.write_text(''.join(json.dumps(event)+'\n' for event in events))
        self.assertEqual(self.collect()['cases'][-1]['checks']['playback'],'fail')

    def test_other_native_contracts_require_source_operation_scene_and_real_metrics(self):
        scene='res://native.tscn'
        players=['AnimBounce','AnimOrbit','AnimSweep','AnimDrift','AnimPulse','AnimFloat','AnimSpin']
        fixtures=[
          ('animation_edit.retime','check_edit_runtime.gd','EDIT_RUNTIME=',{'op':'retime','scene':scene,'samples':[0,50,100],'worst_error':0},True),
          ('animation_edit.retarget','check_edit_remaining_runtime.gd','EDIT_REMAINING=',{'op':'retarget','scene':scene,'samples':[{'measured':50}],'worst_error':0},True),
          ('animation_presets.pulse','check_presets_saved_playback.gd','PRESET_SAVED_PLAYBACK=',{'op':'pulse','scene':scene,'maximum_change':.2},True),
          ('animation_presets.showcase','check_presets_saved_playback.gd','PRESET_SHOWCASE_PLAYBACK=',{'rows':[{'player':p,'track':'Target:position','maximum_change':.2} for p in players],'failures':[]},True),
          ('animation_motion.run_cycle','check_motion_remaining_runtime.gd','MOTION_REMAINING_RUNTIME=',{'clip':'run_cycle','checked':4,'moving':4,'worst_error':0,'failures':[]},True),
          ('animation_motion.character_setup','check_motion_setup_runtime.gd','MOTION_SETUP_RUNTIME=',{'scene':scene,'thigh_change':.1,'root_extraction':.2,'failures':[]},False),
          ('animation_motion.secondary_motion','check_motion_setup_runtime.gd','MOTION_SETUP_RUNTIME=',{'scene':scene,'jaw_range':.1,'jaw_play_error':0,'failures':[]},False),
          ('animation_rig.walk_cycle','check_rig_recipe_runtime.gd','RIG_RECIPE_RUNTIME=',{'scene':scene,'op':'walk_cycle','checked':4,'moving':4,'worst_error':0,'failures':[]},True),
          ('animation_rig.pose_to_clip','check_rig_pose_clip_runtime.gd','RIG_POSE_CLIP=',{'scene':scene,'samples':[{}, {}, {}],'worst_error':0},False),
          ('animation_rig.bake_pose_sequence','check_rig_bake_runtime.gd','RIG_BAKE_RUNTIME=',{'scene':scene,'samples':24,'worst_error':0},False),
          ('animation_sequence.compose','check_sequence_runtime.gd','SEQUENCE_RUNTIME=',{'scene':scene,'contact_impact':True,'early_angle':0,'late_angle':.6,'impact_time':1.1,'saved_pose_angle':.6},False),
          ('animation_library.template_apply','check_library_runtime.gd','LIBRARY_RUNTIME=',{'scene':scene,'samples':[{'clip':'templated_drift','target_x':30,'source_x':0},{'clip':'imported_walk','target_x':50,'source_x':0}],'worst_error':0},False),
          ('animation_library.spec_apply','check_library_runtime.gd','LIBRARY_RUNTIME=',{'scene':scene,'samples':[{'clip':'templated_drift','target_x':30,'source_x':0},{'clip':'imported_walk','target_x':50,'source_x':0}],'worst_error':0},False),
        ]
        for operation,script,prefix,payload,parameterized in fixtures:
            with self.subTest(operation=operation):
                context={'engine_command':'fixture-godot','dependencies':{'test_project/tools/'+script:{}}}
                command=['fixture-godot','--script','res://tools/'+script,'--',scene]
                if parameterized:command.append(operation.split('.')[1])
                event={'operation':operation,'scene':scene,'command':command,'returncode':0,'stdout':prefix+json.dumps(payload),'stderr':''}
                self.assertEqual(c.native_checks(event,context)[0],{'playback':'pass'})
                bad=dict(event,returncode=1)
                self.assertEqual(c.native_checks(bad,context)[0],{'playback':'fail'})
                bad=dict(event,stderr='ERROR: native runtime failed')
                self.assertEqual(c.native_checks(bad,context)[0],{'playback':'fail'})
                bad=dict(event,scene='res://different-scene.tscn')
                with self.assertRaisesRegex(ValueError,'scene'):c.native_checks(bad,context)
    def test_graph_plaintext_is_case_bound_and_read_operation_is_not_producer(self):
        script='verify_saved_graph_playback.gd';scene='res://graph.tscn'
        context={'engine_command':'fixture-godot','dependencies':{'test_project/tools/'+script:{}}}
        command=['fixture-godot','--script','res://tools/'+script,'--',scene]
        event={'operation':'animation_graph.state_machine','scene':scene,'command':command,'returncode':0,
               'stdout':'GRAPH_SAVED_PLAYBACK_PASS: '+scene+' walk_x=30.000 player_idle=true','stderr':''}
        self.assertEqual(c.native_checks(event,context)[0],{'playback':'pass'})
        event['stdout']=event['stdout'].replace(scene,'res://other.tscn')
        self.assertEqual(c.native_checks(event,context)[0],{'playback':'fail'})
        event['operation']='animation_graph.graph_get'
        self.assertEqual(c.native_checks(event,context)[0],{})

if __name__=='__main__':unittest.main()
