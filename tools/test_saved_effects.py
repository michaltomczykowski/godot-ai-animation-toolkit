import copy
import unittest
from check_saved_effects import check

class NativeObservations(unittest.TestCase):
    def fixture(self):
        case = {'operation':'animation_fx.damage_bar','id':'damage:new','scenes':{'undo':{'sha256':'a'},'redo':{'sha256':'b'}},'dependencies':{},'fps':60,'seconds':12,'take_seconds':6}
        samples=[]
        for i in range(720):
            t=i%360
            samples.append({'frame':i+1,'time':(i+1)/60,'take':1 if i<360 else 2,'states':[{'DamageBar':{'value':'80'}},{'DamageBar':{'value':str(80-50*min(t/60,1))}}]})
        return case, {'operation':case['operation'],'case_id':case['id'],'scenes':case['scenes'],'dependencies_verified':{},'frames':720,'max_delta_error':0,'engine_errors':[],'capture_geometry':{'logical_size':[1400,800],'render_size':[1400,800],'window_size':[1152,648],'content_scale_mode':2,'content_scale_aspect':1},'samples':samples}
    def test_real_target_and_independent_endpoint_required(self):
        case, report=self.fixture()
        self.assertTrue(check(case, report)['native_observation_pass'])
        report['samples'][-1]['states'][1]['DamageBar']['value']='31'
        self.assertFalse(check(case, report)['native_observation_pass'])
    def test_engine_error_or_missing_capture_fails_otherwise_green_observation(self):
        case,report=self.fixture()
        for errors in ([{'message':'viewport canvas map failure'}],None):
            report['engine_errors']=errors
            self.assertFalse(check(case,report)['native_observation_pass'])
    def test_camera_numbers_cannot_replace_enabled_native_camera_output(self):
        case,report=self.fixture()
        case['operation']='animation_fx.zoom_punch';report['operation']=case['operation']
        for row in report['samples']:
            row['states']=[{'Camera2D':{'zoom':'(1, 1)'}}, {'Camera2D':{'zoom':f'({1+row["frame"]%20/100}, 1)'}}]
        report['camera_presentation']='fixed_comparison_frame'
        report['native_camera_states']=[{'enabled':True,'current':True}]*2
        self.assertFalse(check(case,report)['native_observation_pass'])
        report['camera_presentation']='native_camera_static_calibration_grid'
        report['native_camera_states'][1]={'enabled':False,'current':False}
        self.assertFalse(check(case,report)['native_observation_pass'])
        report['native_camera_states'][1]={'enabled':True,'current':True}
        self.assertTrue(check(case,report)['native_observation_pass'])
    def test_static_target_cannot_borrow_other_progression(self):
        case, report=self.fixture()
        for row in report['samples']:
            row['states'][1]={'DamageBar':{'value':'30'},'Other':{'value':row['frame']}}
        self.assertFalse(check(case, report)['native_observation_pass'])
    def test_missing_take_wrong_identity_and_duplicate_clock_rejected(self):
        case, report=self.fixture()
        for mutation in ('take','identity','clock','fixed'):
            bad=copy.deepcopy(report)
            if mutation=='take': bad['samples']=bad['samples'][:360]
            if mutation=='identity': bad['operation']='animation_fx.counter'
            if mutation=='clock': bad['samples'][20]['frame']=20
            if mutation=='fixed': bad['max_delta_error']=0.01
            self.assertFalse(check(case,bad)['native_observation_pass'],mutation)
class RemainingObservations(unittest.TestCase):
    def fixture(self, op='offset'):
        case={'operation':'animation_edit.'+op,'variant':op,'id':op+':local',
              'scenes':{'undo':{'sha256':'a'},'redo':{'sha256':'b'}},'dependencies':{},
              'fps':60,'seconds':12,'take_seconds':6,
              'require_progression':op!='cleanup','require_visible_difference':op!='cleanup'}
        samples=[]
        for i in range(720):
            t=(i%360+1)/60
            redo=0 if op=='cleanup' else max(0,min(100*(t-.2),100))
            samples.append({'frame':i+1,'time':(i+1)/60,'take':1 if i<360 else 2,
                'states':[{'Character':{'position':'(0, 0)'}}, {'Character':{'position':f'({redo}, 0)'}}],
                'players':[{}, {'AnimationPlayer':{'position':min(t,1)}}]})
        return case, {'operation':case['operation'],'case_id':case['id'],'scenes':case['scenes'],
                      'dependencies_verified':{},'frames':720,'max_delta_error':0,'engine_errors':[],'capture_geometry':{'logical_size':[1400,800],'render_size':[1400,800],'window_size':[1152,648],'content_scale_mode':2,'content_scale_aspect':1},'samples':samples}
    def test_native_position_bound_sample_rejects_plausible_wrong_effect(self):
        case,report=self.fixture()
        self.assertTrue(check(case,report)['native_observation_pass'])
        for row in report['samples']:
            row['states'][1]['Character']['position']='(1, 0)' if row['frame']%2 else '(2, 0)'
        self.assertFalse(check(case,report)['native_observation_pass'])
    def test_expected_static_cleanup_does_not_require_invented_motion(self):
        case,report=self.fixture('cleanup')
        result=check(case,report)
        self.assertTrue(result['native_observation_pass'])
        self.assertEqual(result['checks']['take_1_target_progression'],'not_applicable')
        self.assertEqual(result['visual_assessment'],'pending')
    def test_missing_required_native_player_cannot_pass_static_case(self):
        case,report=self.fixture('cleanup')
        report['runtime_failures']=['Missing required saved player']
        self.assertFalse(check(case,report)['native_observation_pass'])

if __name__=='__main__': unittest.main()
