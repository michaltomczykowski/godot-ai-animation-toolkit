import copy
import unittest
import validate_setup_recording as subject

class Receipts(unittest.TestCase):
    def fixture(self):
        cases=[{'id':str(i),'scene_sha256':'a'*64,'render_spec':{'frames_per_take':180}} for i in range(4)]
        schedule={'recording':{'contract':'saved_setup_v1','fps':60,'size':[1920,1080]},'cases':cases}
        runs=[]
        for row in cases:
            for take in (1,2):
                trace=[]
                for frame in range(180):
                    trace.append([{'id':row['id'],'take':take,'view':view,'frame':frame,'time_s':(frame+1)/60,
                        'signals':frame+2,'skin_updates_before':frame+1,'skin_updates_after_draw':frame+2,
                        'framing':{'passed':True,'behind':0,'bone_count':50,'minimum_px':[25,25],'maximum_px':[920,870]}} for view in ('front','side')])
                timing={'presentation_ready':{'signals':0,'evaluations':0,'status':'inactive'},'skeleton_notified':{'signals':1,'evaluations':1,'status':'grounded'}}
                runs.append({'id':row['id'],'take':take,'scene_sha256':row['scene_sha256'],'frames':180,'preparation_signals':[0,0],'prime_signals':[1,1],'prime_timing':[copy.deepcopy(timing),copy.deepcopy(timing)],'trace':trace})
        report={'passed':True,'engine_errors':[],'schedule_sha256':'b'*64,'renderer_sha256':'c'*64,
                'checker_loader_sha256':'d'*64,'runtime_sha256':'e'*64,'cases':runs,'frames':1440,'fps':60,'size':[1920,1080]}
        return schedule,report
    def test_complete(self):
        s,r=self.fixture();self.assertTrue(subject.validate(s,r,'b'*64))
    def test_inactive_mount_signal_is_explicit(self):
        s,r=self.fixture()
        for run in r['cases']:
            run['preparation_signals']=[1,1]
            for timing in run['prime_timing']:
                timing['presentation_ready']['signals']=1;timing['skeleton_notified']['signals']=2
            for samples in run['trace']:
                for sample in samples:sample['signals']+=1
        self.assertTrue(subject.validate(s,r,'b'*64))
        r['cases'][0]['prime_timing'][0]['presentation_ready']['evaluations']=1
        self.assertFalse(subject.validate(s,r,'b'*64))
    def test_corruption_controls(self):
        for fault in ('stale_skin','missing_frame','wrong_view','wrong_take','crop','behind','bad_time','bad_signals','wrong_scene','wrong_schedule','engine_error','missing_engine_errors'):
            s,r=self.fixture();sample=r['cases'][0]['trace'][0][0]
            if fault=='stale_skin': sample['skin_updates_after_draw']=sample['skin_updates_before']
            elif fault=='missing_frame': r['cases'][0]['trace'].pop()
            elif fault=='wrong_view': sample['view']='side'
            elif fault=='wrong_take': r['cases'][0]['take']=2
            elif fault=='crop': sample['framing']['maximum_px'][0]=950
            elif fault=='behind': sample['framing']['behind']=1
            elif fault=='bad_time': sample['time_s']=0
            elif fault=='bad_signals': sample['signals']+=1
            elif fault=='wrong_scene': r['cases'][0]['scene_sha256']='x'*64
            elif fault=='wrong_schedule': r['schedule_sha256']='x'*64
            elif fault=='engine_error': r['engine_errors']=['failure']
            elif fault=='missing_engine_errors': del r['engine_errors']
            with self.subTest(fault=fault):self.assertFalse(subject.validate(s,r,'b'*64))
