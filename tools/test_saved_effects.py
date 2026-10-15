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
        return case, {'operation':case['operation'],'case_id':case['id'],'scenes':case['scenes'],'dependencies_verified':{},'frames':720,'max_delta_error':0,'samples':samples}
    def test_real_target_and_independent_endpoint_required(self):
        case, report=self.fixture()
        self.assertTrue(check(case, report)['native_observation_pass'])
        report['samples'][-1]['states'][1]['DamageBar']['value']='31'
        self.assertFalse(check(case, report)['native_observation_pass'])
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
if __name__=='__main__': unittest.main()
