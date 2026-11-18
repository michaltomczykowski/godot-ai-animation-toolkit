"""Offline setup intent/source corruptions; no engines or public mutation."""
import copy
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

import audit_setup_intent_bridge as a
import run_setup_intent_replay as runner

SETUP=Path('E:/GodotAI-toolkit-release-2.0.0/20261014/setup')
PROJECT=SETUP.parent/'validation'
REPO=Path('G:/godot-ai-dev/godot-ai-animation-toolkit')
CORE=Path('G:/godot-ai-dev/godot-ai-release-core-4.2.1')
FORWARD=[-1.35006184791564e-5,0.,1.]


def synthetic_runs():
    result=[]
    for fps in (30,60,120):
        frames=6*fps;delta=[v*a.SPEC['speed_mps']/fps for v in FORWARD]
        result.append(dict(id='dummy',fps=fps,spec=a.SPEC.copy(),leg_length_m=1.,passed=True,failures=[],nonfinite=0,rooted=True,controller_speed_mps=0.,consumer_space='owner_parent',reset_performed=False,reset_witness={},takes=[],extra_prime_signals=0,frames=frames,elapsed_s=6.,modification_processed_signals=frames,trace=[dict(time=(i+1)/fps,root_delta_parent=delta.copy(),shot_active=False,shot_phase=0.,feet={s:dict(height_m=0.,declared_contact=True)for s in ('l','r')})for i in range(frames)],consumer_position=[v*frames for v in delta],actual_world_distance_m=a.SPEC['speed_mps']*6,endpoint_reference_available=True,endpoint_error_m=0.,extraction_error_m=0.,unconsumed_actor_change_m=0.,grounded_root_delta_world_m=0.,max_bone_speed_legs_per_s=1.,max_bone_angular_speed_rad_s=1.,recovery_position_error_m=0.,recovery_rotation_error_rad=0.,feet={s:dict(knee_flips=0,frames=frames,windows=1,slide=0.,penetration=0.,height=0.)for s in ('l','r')},grounding=dict(contract_version=1,error='',status='grounded',unreachable=0,evaluations=frames,resets=2,reset_reason='inactive_tree',target_tolerance_m=1e-5,evaluation_residual_m=0.,max_residual_m=0.,max_correction_m=.01)))
    return result


class NumericControls(unittest.TestCase):
    def test_three_explicit_speed_clocks_independent_of_expected_output_metadata(self):
        runs=synthetic_runs()
        for r in runs:r['expected_world_distance_m']=-100.
        self.assertEqual(len(a.verify_numeric(runs,FORWARD)),3)

    def test_wrong_speed_signed_trace_and_false_passed_metrics_cannot_qualify(self):
        for fault in ('speed','sign','double','inert','clock','feet','knee','contact','owner','reset','take','signal','grounding','passed','duplicate','nan'):
            runs=synthetic_runs();r=runs[0]
            if fault=='speed':r['spec']['speed_mps']*=2
            elif fault in ('sign','double','inert'):
                factor={'sign':-1.,'double':2.,'inert':0.}[fault]
                for s in r['trace']:s['root_delta_parent']=[v*factor for v in s['root_delta_parent']]
                r['consumer_position']=[v*factor for v in r['consumer_position']];r['actual_world_distance_m']*=abs(factor)
            elif fault=='clock':r['trace'][0]['time']=0.
            elif fault=='feet':r['trace'][0]['feet'].pop('r')
            elif fault=='knee':r['feet']['l']['knee_flips']=1
            elif fault=='contact':r['feet']['l']['slide']=.1
            elif fault=='owner':r['controller_speed_mps']=.1
            elif fault=='reset':r['reset_performed']=True
            elif fault=='take':r['takes']=[{}]
            elif fault=='signal':r['modification_processed_signals']-=1
            elif fault=='grounding':r['grounding']['max_residual_m']=.01
            elif fault=='passed':r['passed']=False
            elif fault=='duplicate':runs[0]=copy.deepcopy(runs[1])
            else:r['trace'][0]['root_delta_parent'][0]=float('nan')
            with self.subTest(fault=fault),self.assertRaises(ValueError):a.verify_numeric(runs,FORWARD)

    def test_only_exact_two_reviewed_dependency_changes_and_one_added_helper_are_allowed(self):
        old={p:v[0] for p,v in a.CHANGES.items()};old.update({'core/example.gd':'a'*64,'toolkit/handlers/motion.gd':'b'*64})
        current=dict(old,**a.ADDITIONS)
        for p,v in a.CHANGES.items():current[p]=v[1]
        self.assertEqual(len(a.verify_candidate_dependencies(old,current)),2)
        for fault in ('missing','extra','core','motion','rig','spring'):
            x=current.copy()
            if fault=='missing':x.pop('core/example.gd')
            elif fault=='extra':x['core/other.gd']='f'*64
            else:x[{'core':'core/example.gd','motion':'toolkit/handlers/motion.gd','rig':'toolkit/handlers/rig.gd','spring':next(iter(a.ADDITIONS))}[fault]]='0'*64
            with self.subTest(fault=fault),self.assertRaises(ValueError):a.verify_candidate_dependencies(old,x)

    def test_source_line_endings_only_do_not_transform_source_content(self):
        self.assertTrue(a.source_matches(b'hello\n',a.sha(b'hello\r\n')))
        self.assertFalse(a.source_matches(b'changed\n',a.sha(b'hello\r\n')))


@unittest.skipUnless((SETUP/'native-matrix-r009/execution.json').is_file(),'private historical evidence unavailable')
class HistoricalControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.bundle=a.read_evidence(SETUP,PROJECT)

    def test_source_bound_real_record_join_and_all_three_actual_blend_traces(self):
        proof=a.verify_evidence(self.bundle)
        self.assertEqual(proof['checks'],{'valid_effect':'pass'})
        self.assertTrue(proof['original_public_event_ids'][1].endswith(':16'))
        self.assertEqual([x['fps']for x in proof['native_observations']],[30,60,120])

    def test_original_producer_reusers_group_request_scene_and_dependency_corruptions(self):
        for fault in ('producer','reuse','chain','request','scene','group','deps','passed','call','reload','native','transform'):
            b=copy.deepcopy(self.bundle)
            if fault=='producer':b['routes'][0]['source_head']=a.PUBLIC_SOURCES[-1]
            elif fault=='reuse':b['routes'][2]['cases'][0]['reused_from']='other/route.json'
            elif fault=='chain':b['routes'].pop()
            elif fault=='request':b['routes'][0]['cases'][0]['request']['include_turn']=True
            elif fault=='scene':b['routes'][0]['cases'][0]['scene_sha256']='0'*64
            elif fault=='group':b['execution']['groups'][0]['id']='other-group'
            elif fault=='deps':b['matrices'][0]['production_dependencies']['toolkit/handlers/motion.gd']='0'*64
            elif fault=='passed':b['native']['runs'][0]['feet']['l']['slide']=.2
            elif fault=='call':b['events']=[e for e in b['events']if not e['id'].endswith(':16')]
            elif fault=='reload':b['events']=[e for e in b['events']if not e['id'].endswith(':26')]
            elif fault=='native':b['native']['checker_sha256']='0'*64
            else:b['scene_text']=b['scene_text'].replace('[node name="Dummy" parent="."','[node name="Dummy" parent="."',1).replace('[node name="SetupGrounding"','position = Vector3(1,0,0)\n\n[node name="SetupGrounding"',1)
            with self.subTest(fault=fault),self.assertRaises(ValueError):a.verify_evidence(b)

    def test_actual_candidate_dependency_bridge_retains_missing_historical_loaded_rig_join(self):
        r=a.audit(SimpleNamespace(repo=REPO,core_root=CORE,setup_root=SETUP,project_root=PROJECT))
        self.assertEqual(r['checks'],{'valid_effect':'pending'});self.assertEqual(r['historical_effect_checks'],{'valid_effect':'pass'})
        self.assertEqual(r['original_public_source'],a.PUBLIC_SOURCES[0]);self.assertEqual(r['native_executor_source'],a.NATIVE_SOURCE)
        self.assertEqual(r['dependency_comparison']['core_exact'],567);self.assertEqual(r['dependency_comparison']['toolkit_exact'],44)
        self.assertEqual(len(r['missing_joins']),1)

    def test_preparation_is_exclusive_copies_inputs_and_never_launches_engine(self):
        with tempfile.TemporaryDirectory()as d:
            args=SimpleNamespace(repo=REPO,core_root=CORE,setup_root=SETUP,project_root=PROJECT,output=Path(d)/'prepared')
            with patch.object(runner,'process')as process:
                receipt=runner.prepare(args);process.assert_not_called()
                self.assertFalse((args.output/'project/.godot').exists());self.assertEqual(receipt['expected_native_plays'],3)
                self.assertEqual(runner.hashes(args.output/'project',receipt['immutable_project_inputs']),receipt['immutable_project_inputs'])
                with self.assertRaises(ValueError):runner.prepare(args)

    def test_changed_prepared_model_refuses_before_any_engine_process(self):
        with tempfile.TemporaryDirectory()as d:
            args=SimpleNamespace(repo=REPO,core_root=CORE,setup_root=SETUP,project_root=PROJECT,output=Path(d)/'prepared')
            runner.prepare(args);(args.output/'project/models/human_dummy/HumanCharacterDummy_F.fbx').write_bytes(b'changed')
            with patch.object(runner,'process')as process,self.assertRaisesRegex(ValueError,'input bytes changed'):
                runner.run(SimpleNamespace(prepared=args.output,godot=Path(d)/'fake-godot'))
            process.assert_not_called()


if __name__=='__main__':unittest.main()
