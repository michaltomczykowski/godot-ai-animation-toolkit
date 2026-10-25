import copy,json,tempfile,unittest
from pathlib import Path
from PIL import Image
from prepare_motion_representatives import validate_render

class WitnessControls(unittest.TestCase):
    def report(self,jump):
        rows=[]
        for frame in range(1440):
            local=frame%360
            for view in range(2):rows.append(dict(frame=frame,rig=['dummy','xbot','short','zup_tall'][frame//360],view=view,take=local//180+1 if jump else 1,poses_world={k:[0.,0.,0.] for k in ('hips','head','hand_l','hand_r','foot_l','foot_r')},actor_world=[0.,0.,0.],root_delta_owner_parent=[0.,0.,0.],fits=True,skin_fresh=True,depth_clipped=0,points=8,skin_before=frame,skin_after=frame+1,bounds=[20.,20.,900.,850.],native_time=(local%180 if jump else local)/60))
        return dict(errors=[],guarded=True,frames=1440,fps=60,size=[1920,1080],capture_binding_sha256='binding',probe=True,png_frames=24 if jump else 16,trace=rows)
    def frames(self,path,jump):
        for i in range(1440):
            if i%(180 if jump else 360) in ([0,90,179] if jump else [0,120,240,359]):Image.new('RGB',(1920,1080)).save(path/f'{i:06d}.png')
    def test_both_exact_probe_schedules(self):
        for jump in (False,True):
            with tempfile.TemporaryDirectory() as tmp:
                p=Path(tmp);self.frames(p,jump);self.assertEqual(len(validate_render(self.report(jump),'binding',True,jump,p)),24 if jump else 16)
    def test_raw_counter_clock_bounds_identity_controls(self):
        changes=[lambda r:r.update(capture_binding_sha256='other'),lambda r:r.update(frames=1439),lambda r:r.update(probe=False),lambda r:r['trace'].pop(),lambda r:r['trace'][3].update(frame=2),lambda r:r['trace'][0].update(rig='other'),lambda r:r['trace'][0].update(take=2),lambda r:r['trace'][0].update(skin_fresh=False),lambda r:r['trace'][0].update(skin_after=0),lambda r:r['trace'][0].update(depth_clipped=1),lambda r:r['trace'][0].update(bounds=[0,0,1000,1000]),lambda r:r['trace'][0].update(native_time=1),lambda r:r['trace'][0].update(bounds=[float('nan')]*4)]
        for change in changes:
            row=self.report(False);change(row)
            with self.subTest(change=change),self.assertRaises(ValueError):validate_render(row,'binding',True,False,Path('no_frames_read_for_invalid_witness'))
    def test_missing_or_wrong_dimension_png(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp);self.frames(p,False);Image.new('RGB',(100,100)).save(p/'000000.png')
            with self.assertRaisesRegex(ValueError,'dimensions'):validate_render(self.report(False),'binding',True,False,p)
            (p/'000000.png').unlink()
            with self.assertRaisesRegex(ValueError,'schedule'):validate_render(self.report(False),'binding',True,False,p)

if __name__=='__main__':unittest.main()
