import copy,json,tempfile,unittest
from pathlib import Path
from PIL import Image
from prepare_motion_representatives import validate_render,quoted_resource_paths,admission_arguments,validate_admission,ADMISSION_CONTROLS

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

class ResourcePathControls(unittest.TestCase):
    def test_actual_spaced_path_and_import_array(self):
        expected='res://models/x_bot/X Bot.fbx'
        text='[ext_resource type="PackedScene" path="'+expected+'" id="1"]\nsource_file="'+expected+'"\ndest_files=["res://.godot/imported/X Bot.fbx-123.scn"]'
        self.assertEqual(quoted_resource_paths(text),[expected,'res://.godot/imported/X Bot.fbx-123.scn'])
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);asset=root/expected.removeprefix('res://');asset.parent.mkdir(parents=True);asset.write_bytes(b'exact spaced asset')
            self.assertEqual((root/quoted_resource_paths(text)[0].removeprefix('res://')).read_bytes(),b'exact spaced asset')
            self.assertFalse((root/'models/x_bot/X').exists())
    def test_escaped_quote_backslash_and_unicode(self):
        expected=['res://folder/a "quoted" name.tres','res://folder/back\\slash.tres','res://folder/za\u017c\u00f3\u0142\u0107.tres']
        text='paths=['+','.join(json.dumps(value,ensure_ascii=True) for value in expected)+']'
        self.assertEqual(quoted_resource_paths(text),expected)
    def test_bad_escape_and_truncated_string_refuse(self):
        for text in ('path="res://broken',r'path="res://bad\q.tres"'):
            with self.subTest(text=text),self.assertRaises(ValueError):quoted_resource_paths(text)
    def test_unquoted_or_nonresource_text_not_invented(self):
        self.assertEqual(quoted_resource_paths('res://unquoted path="uid://123" id="resource"'),[])

class AdmissionMappingControls(unittest.TestCase):
    def report(self,control,extracted):
        reasons={'foreign_tree':'Foreign active mixer before normalization','active_modifier':'Active modifier before normalization','wrong_root_track':'Saved extraction binding missing' if extracted else 'Unextracted clip has extraction owner'}
        return dict(passed=True,control=control,effective_control='' if control=='positive' else control,route_sha256='route',script_sha256='guard',rows=[dict(id=i,errors=[] if control=='positive' else [reasons[control]]) for i in ('dummy','xbot','short','zup_tall')])
    def test_explicit_nonempty_cli_and_effective_mapping(self):
        for control in ADMISSION_CONTROLS:
            args=admission_arguments('route.json','report.json',control)
            self.assertEqual(args[-1],control);self.assertNotIn('',args)
            for extracted in (False,True):validate_admission(self.report(control,extracted),control,'route','guard',extracted)
    def test_unknown_and_omitted_control_refuse(self):
        for control in ('','unknown','POSITIVE',None):
            with self.subTest(control=control),self.assertRaises(ValueError):admission_arguments('route','report',control)
    def test_forged_mapping_or_missing_witness_refuse(self):
        for change in (lambda r:r.update(effective_control='positive'),lambda r:r.update(control='foreign_tree'),lambda r:r['rows'][0].update(errors=['some unrelated error']),lambda r:r['rows'].pop(),lambda r:r.update(route_sha256='other')):
            r=self.report('positive',True);change(r)
            with self.subTest(change=change),self.assertRaises(ValueError):validate_admission(r,'positive','route','guard',True)
        r=self.report('wrong_root_track',True);r['rows'][0]['errors']=[]
        with self.assertRaises(ValueError):validate_admission(r,'wrong_root_track','route','guard',True)

if __name__=='__main__':unittest.main()

