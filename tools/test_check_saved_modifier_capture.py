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
                report['runs'].append(dict(id=case['id'],op=case['op'],fps=60,frames=240,active=active,take=take,saved_active=False,runtime_influence=1.,scene_sha256='b'*64,config_sha256='f'*64,excluded_loading_process_frames=2,trace=trace,final_pose=[1],failures=[]))
    return report,manifest
class Controls(unittest.TestCase):
    def test_native_positive(self):
        r,m=fixture();self.assertEqual(validate(r,m,'c'*64)['native_samples'],4800)
    def test_qualified_native_corruptions(self):
        mutations=[lambda r:r.update(engine_errors=None),lambda r:r.update(inert_control=True),lambda r:r.update(shared_evaluator_sha256='wrong'),lambda r:r['runs'].pop(),lambda r:r['runs'][0]['trace'].pop(),lambda r:r['runs'][0]['trace'][0].update(skin=0),lambda r:r['runs'][0]['trace'][0].update(final=0),lambda r:r['runs'][0]['trace'][0].update(native_elapsed_s=.5),lambda r:r['runs'][0]['trace'][0].update(active_writers=[]),lambda r:r['runs'][0].update(config_sha256='bad'),lambda r:r['runs'][0]['trace'][0].update(focus_poses={}),lambda r:r['runs'][0]['trace'][0].update(effect=.1),lambda r:r['runs'][0].update(final_pose=[999])]
        for change in mutations:
            r,m=fixture();change(r)
            with self.assertRaises(ValueError):validate(r,m,'c'*64)
    def test_complete_projection_corners(self):
        points=[[100,200],[400,200],[100,600],[400,600]]*2
        f=dict(points=points,point_count=8,body_rect=[24,100,1872,760],bounds=[100,200,300,400],visible=True,finite=True,behind_or_clipped_depth=0)
        framing(f)
        for change in (lambda v:v['points'][0].__setitem__(0,24),lambda v:v.update(behind_or_clipped_depth=1),lambda v:v['points'].pop(),lambda v:v.update(bounds=[100,200,1,1])):
            bad=copy.deepcopy(f);change(bad)
            with self.assertRaises(ValueError):framing(bad)
if __name__=='__main__':unittest.main()
