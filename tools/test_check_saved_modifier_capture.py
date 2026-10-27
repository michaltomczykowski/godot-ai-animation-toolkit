import copy
import unittest
from check_saved_modifier_capture import validate,framing,OPS

def fixture():
    deps=[dict(path='res://tools/'+p,sha256='a'*64) for p in ('render_saved_modifier_capture.gd','check_saved_modifier_capture.gd','saved_media_framing.gd')]
    cases=[dict(id=op,op=op,scene=dict(sha256='b'*64)) for op in sorted(OPS)]
    manifest=dict(cases=cases,capture_dependencies=deps)
    report=dict(passed=True,engine_errors=[],failures=[],inert_control=False,fps=60,mode='native',accepted_frames=0,manifest_sha256='c'*64,renderer_sha256='a'*64,shared_evaluator_sha256='a'*64,framing_sha256='a'*64,runs=[])
    for case in cases:
        for take in (0,1):
            for active in (False,True):
                trace=[]
                for i in range(240):
                    raw=i+1 if active else 0
                    trace.append(dict(tick=i,time=i/60,input_time_s=i/60,native_elapsed_s=(i+1)/60,raw_before=i if active else 0,raw=raw,final_before=i,final=i+1,skin_before=i,skin=i+1,active_writers=['mod','witness'] if active else ['witness'],finite=True,effect=.1 if active else 0.,pose_sha256='d'*64,source_input_pose_sha256='e'*64,focus_poses={'bone':{'name':'hand','final':[0.,0.,0.]}},bounds_min=[0,0,0],bounds_max=[1,1,1],display_envelope=dict(minimum=[0,0,0],maximum=[1,1,1],vertex_count=9)))
                report['runs'].append(dict(id=case['id'],op=case['op'],fps=60,frames=240,active=active,take=take,saved_active=False,runtime_influence=1.,scene_sha256='b'*64,config_sha256='f'*64,excluded_loading_process_frames=2,excluded_reset_process_frames=1 if case['op']=='spring_setup' else 0,trace=trace,final_pose=[1],failures=[]))
    return report,manifest

def rendered_fixture():
    reference,manifest=fixture();report=copy.deepcopy(reference)
    report.update(mode='render',accepted_frames=2400,native_preflight_sha256='9'*64)
    number=0
    for run in report['runs']:
        if not run['active']:continue
        for sample in run['trace']:
            sample.update(movie_frame=number,png_dimensions=[1920,1080],raw_after_draw=sample['raw'],final_after_draw=sample['final'],skin_after_draw=sample['skin'])
            sample['framing']=dict(points=[[100,200],[400,200],[100,600],[400,600]]*2,point_count=8,body_rect=[24,100,1872,760],bounds=[100,200,300,400],visible=True,finite=True,behind_or_clipped_depth=0)
            sample['fixed_camera']=dict(position=[4.,2.,7.],basis=[[1.,0.,0.],[0.,1.,0.],[0.,0.,1.]],size=1.,preflight_sha256='9'*64,qualified_envelope={'minimum':[0,0,0],'maximum':[1,1,1]})
            number+=1
    return report,manifest,reference
class Controls(unittest.TestCase):
    def test_reset_barrier_is_explicit_and_only_before_spring_samples(self):
        for op in OPS:
            r,m=fixture();run=next(v for v in r['runs'] if v['op']==op)
            run['excluded_reset_process_frames']=0 if op=='spring_setup' else 1
            with self.assertRaisesRegex(ValueError,'reset barrier'):validate(r,m,'c'*64)
    def test_native_positive(self):
        r,m=fixture();self.assertEqual(validate(r,m,'c'*64)['native_samples'],4800)
    def test_qualified_native_corruptions(self):
        mutations=[lambda r:r.update(engine_errors=None),lambda r:r.update(inert_control=True),lambda r:r.update(shared_evaluator_sha256='wrong'),lambda r:r['runs'].pop(),lambda r:r['runs'][0]['trace'].pop(),lambda r:r['runs'][0]['trace'][0].update(skin=0),lambda r:r['runs'][0]['trace'][0].update(final=0),lambda r:r['runs'][0]['trace'][0].update(native_elapsed_s=.5),lambda r:r['runs'][0]['trace'][0].update(active_writers=[]),lambda r:r['runs'][0].update(config_sha256='bad'),lambda r:r['runs'][0]['trace'][0].update(focus_poses={}),lambda r:r['runs'][0]['trace'][0].update(effect=.1),lambda r:r['runs'][0].update(final_pose=[999])]
        for change in mutations:
            r,m=fixture();change(r)
            with self.assertRaises(ValueError):validate(r,m,'c'*64)
    def test_rendered_fixed_camera_receipts(self):
        r,m,n=rendered_fixture();self.assertEqual(validate(r,m,'c'*64,reference=n,reference_sha='9'*64)['accepted_frames'],2400)
    def test_missing_nonfinite_drift_camera_and_source_controls(self):
        for fault in ('missing','position','position_bool','basis','basis_nan','zero_size','negative_size','infinite_size','source','envelope_min','envelope_max','envelope_bool','same_take_drift','fresh_take_drift','wrong_native_mode'):
            r,m,n=rendered_fixture();runs=[x for x in r['runs'] if x['active']];sample=runs[0]['trace'][0];camera=sample['fixed_camera']
            if fault=='missing':sample.pop('fixed_camera')
            elif fault=='position':camera['position']=[0,0]
            elif fault=='position_bool':camera['position'][0]=False
            elif fault=='basis':camera['basis'].pop()
            elif fault=='basis_nan':camera['basis'][0][0]=float('nan')
            elif fault=='zero_size':camera['size']=0
            elif fault=='negative_size':camera['size']=-1
            elif fault=='infinite_size':camera['size']=float('inf')
            elif fault=='source':camera['preflight_sha256']='8'*64
            elif fault=='envelope_min':camera['qualified_envelope']['minimum'][0]=.01
            elif fault=='envelope_max':camera['qualified_envelope']['maximum'][2]=.99
            elif fault=='envelope_bool':camera['qualified_envelope']['maximum'][0]=True
            elif fault=='same_take_drift':runs[0]['trace'][1]['fixed_camera']['position'][0]+=.1
            elif fault=='fresh_take_drift':runs[1]['trace'][0]['fixed_camera']['size']+=.1
            elif fault=='wrong_native_mode':n['mode']='render'
            with self.assertRaises(ValueError,msg=fault):validate(r,m,'c'*64,reference=n,reference_sha='9'*64)
    def test_camera_union_includes_other_take_inactive_native_envelopes(self):
        r,m,n=rendered_fixture();case=n['runs'][0]['id']
        # A non-rendered control from the other fresh take expands the envelope.
        original=next(x for x in n['runs'] if x['id']==case and x['active'] is False and x['take']==1)
        copied=next(x for x in r['runs'] if x['id']==case and x['active'] is False and x['take']==1)
        for run in (original,copied):run['trace'][-1]['display_envelope'].update(minimum=[-2,0,0],maximum=[1,3,1])
        with self.assertRaises(ValueError):validate(r,m,'c'*64,reference=n,reference_sha='9'*64)
        for run in r['runs']:
            if run['id']==case and run['active']:
                for sample in run['trace']:sample['fixed_camera']['qualified_envelope']={'minimum':[-2,0,0],'maximum':[1,3,1]}
        self.assertEqual(validate(r,m,'c'*64,reference=n,reference_sha='9'*64)['accepted_frames'],2400)
    def test_complete_projection_corners(self):
        points=[[100,200],[400,200],[100,600],[400,600]]*2
        f=dict(points=points,point_count=8,body_rect=[24,100,1872,760],bounds=[100,200,300,400],visible=True,finite=True,behind_or_clipped_depth=0)
        framing(f)
        for change in (lambda v:v['points'][0].__setitem__(0,24),lambda v:v.update(behind_or_clipped_depth=1),lambda v:v['points'].pop(),lambda v:v.update(bounds=[100,200,1,1])):
            bad=copy.deepcopy(f);change(bad)
            with self.assertRaises(ValueError):framing(bad)
if __name__=='__main__':unittest.main()
