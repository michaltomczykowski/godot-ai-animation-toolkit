import tempfile
from pathlib import Path
import unittest
import asyncio
from PIL import Image, ImageDraw
from ci_rendered_preview import validate_images, require_error, require_success, validate_editor_log, scene_ready, wait_scene


class RenderedPreviewControls(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.paths = []
        for i in range(4):
            image = Image.new('RGB', (320,240), 'black')
            ImageDraw.Draw(image).rectangle((10+i*20,20,30+i*20,80),fill='white')
            path = self.directory/f'walk_{i:02}.png'
            image.save(path)
            self.paths.append(path)

    def test_actual_decoded_pixels_and_hashes(self):
        rows = validate_images(self.paths,self.directory)
        self.assertEqual(len(rows),4)
        self.assertEqual(len({row['sha256'] for row in rows}),4)
        self.assertTrue(all(row['unique_colors']==2 for row in rows))

    def test_uniform_image_is_rejected(self):
        Image.new('RGB',(320,240),'black').save(self.paths[2])
        with self.assertRaisesRegex(ValueError,'blank'): validate_images(self.paths,self.directory)

    def test_duplicate_frames_are_rejected(self):
        self.paths[1].write_bytes(self.paths[0].read_bytes())
        with self.assertRaisesRegex(ValueError,'identical'): validate_images(self.paths,self.directory)

    def test_missing_frame_and_wrong_dimensions_are_rejected(self):
        with self.assertRaises(ValueError): validate_images(self.paths[:3],self.directory)
        Image.new('RGB',(64,64),'white').save(self.paths[0])
        with self.assertRaisesRegex(ValueError,'dimensions'): validate_images(self.paths,self.directory)

    def test_confined_paths_are_required(self):
        with self.assertRaisesRegex(ValueError,'escaped'): validate_images(self.paths,self.directory/'nested')

    def test_typed_error_and_success_controls(self):
        require_error({'error':'INVALID_PARAMS: refusal'},'INVALID_PARAMS')
        require_error({'error':{'code':'INVALID_PARAMS'}},'INVALID_PARAMS')
        with self.assertRaises(ValueError): require_error({},'INVALID_PARAMS')
        with self.assertRaises(ValueError): require_success({'error':'refusal'})

    def test_engine_script_and_shutdown_errors_fail_complete_log(self):
        validate_editor_log('OpenGL API Mesa llvmpipe\nWARNING: diagnostic')
        for failure in ['ERROR: engine failure','SCRIPT ERROR: invalid call','\x1b[31mERROR:\x1b[0m shutdown leak']:
            with self.assertRaisesRegex(ValueError,'engine/script'):
                validate_editor_log('Rendered four frames\n'+failure)

    def test_scene_readiness_requires_exact_scene_and_real_sentinels(self):
        required=('/RepairRigFixture/AnimationPlayer','/RepairRigFixture/Dummy/Skeleton3D')
        state={'current_scene':'res://repair_rendered_preview.tscn'}
        hierarchy={'nodes':[{'path':path} for path in required]}
        self.assertTrue(scene_ready(state,hierarchy,state['current_scene'],required))
        self.assertFalse(scene_ready({'current_scene':'res://main.tscn'},hierarchy,state['current_scene'],required))
        self.assertFalse(scene_ready(state,{'nodes':[]},state['current_scene'],required))

    def test_startup_scene_race_resets_stability_without_retrying_mutations(self):
        target='res://repair_rendered_preview.tscn'
        scenes=iter([target,target,'res://main.tscn',target,target,target])
        calls=[]
        async def call(name,params):
            calls.append(name)
            return {'current_scene':next(scenes)} if name=='editor_state' else {'nodes':[{'path':'/sentinel'}]}
        async def pause(_): pass
        report=asyncio.run(wait_scene(call,target,('/sentinel',),pause=pause))
        self.assertEqual(report['stable_reads'],3)
        self.assertEqual(len(calls),12)
        self.assertEqual(set(calls),{'editor_state','scene_get_hierarchy'})
        with self.assertRaises(TimeoutError): asyncio.run(wait_scene(call,target,timeout=0,pause=pause))


if __name__ == '__main__': unittest.main()
