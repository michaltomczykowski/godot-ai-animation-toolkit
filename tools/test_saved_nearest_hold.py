import copy
import unittest
from check_saved_effects import check
from saved_effect_contracts import apply_representative_contract
from test_saved_effects import RemainingObservations


class HeldOutputControls(unittest.TestCase):
    def fixture(self):
        case,report=RemainingObservations().fixture('set_interp')
        case=apply_representative_contract(case)
        for index,row in enumerate(report['samples']):
            row['states']=[{'Character':{'position':f'({(index%60)*100/60}, 0)'}},{'Character':{'position':'(0, 0)'}}]
            row['players'][0]=copy.deepcopy(row['players'][1])
            row['players'][0]['AnimationPlayer']['position']=(index%60)/60
        report['playback_contracts']=[{'state':state,'player':'AnimationPlayer','length':1.0,'loop_mode':1,
            'tracks':[{'path':'Character:position','type':0,'enabled':True,'interpolation':interpolation,
                'keys':[{'time':0.0,'value':'(0, 0)'},{'time':1.0,'value':'(100, 0)'}]}]}
            for state,interpolation in [('undo',1),('redo',0)]]
        return case,report

    def test_exact_nearest_hold_with_animated_reference_passes(self):
        case,report=self.fixture()
        self.assertTrue(check(case,report)['native_observation_pass'])

    def test_no_static_or_wrong_metadata_shortcut(self):
        for mutation in ['metadata','linear','disabled','source_keys','reference_static','redo_moves','undo_manual','missing_contract','wrong_undo_clip','wrong_reference_axis']:
            case,report=self.fixture()
            if mutation=='metadata': report['playback_contracts']=[]
            if mutation=='linear': report['playback_contracts'][1]['tracks'][0]['interpolation']=1
            if mutation=='disabled': report['playback_contracts'][1]['tracks'][0]['enabled']=False
            if mutation=='missing_contract': case.pop('held_output_contract')
            if mutation=='source_keys': report['playback_contracts'][1]['tracks'][0]['keys'][1]['value']='(90, 0)'
            for row in report['samples']:
                if mutation=='reference_static': row['states'][0]['Character']['position']='(0, 0)'
                if mutation=='redo_moves': row['states'][1]['Character']['position']='(1, 0)'
                if mutation=='undo_manual': row['players'][0]['AnimationPlayer']['callback_mode_process']=2
                if mutation=='wrong_undo_clip': row['players'][0]['AnimationPlayer']['assigned_animation']='another_clip'
                if mutation=='wrong_reference_axis': row['states'][0]['Character']['position']=f'(0, {row["players"][0]["AnimationPlayer"]["position"]*100})'
            self.assertFalse(check(case,report)['native_observation_pass'],mutation)

    def test_other_operations_keep_progression_requirement(self):
        case={'operation':'animation_edit.offset','variant':'offset','require_progression':True}
        self.assertEqual(apply_representative_contract(case),case)


if __name__=='__main__': unittest.main()
