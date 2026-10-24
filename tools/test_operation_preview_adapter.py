import copy
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image,ImageDraw
from operation_preview_adapter import validate_preview,digest,artifact,verify_preview_bundle

class PreviewAdapter(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.context_path=self.root/'context.json'
        self.context={'schema_version':1,'kind':'operation_trace_context','run_id':'fixture-preview','platform':'linux','engine_command':'fixture-godot','dependencies':{'tools/ci_rendered_preview.py':{},'tools/operation_preview_adapter.py':{},'tools/preview_renderer_profile.py':{}}}
        self.context_path.write_text(json.dumps(self.context))
        self.params={'op':'preview','player_path':'/Fixture/Player','animation_name':'rendered_walk',
                     'width':320,'height':240,'times':[.05,.23,.47,.71],
                     'output_dir':'res://rendered_preview_pngs','basename':'walk','overwrite':False}
        self.response={'paths':['res://rendered_preview_pngs/walk_%02d.png'%i for i in range(4)],'times':self.params['times']}
        timeline={'player_path':'/Fixture/Player','animation_name':'rendered_walk','tracks':[{'path':'Skeleton:hips','keys':[0,1]}]}
        def row(i,operation,params,response):
            return {'id':'fixture:'+str(i),'operation':operation,'execution_ns':i,'params':params,'response':response}
        timeline_params={'op':'timeline','player_path':'/Fixture/Player','animation_name':'rendered_walk'}
        error={'error':'INVALID_PARAMS: expected refusal'}
        self.events=[row(1,'animation_inspect.timeline',timeline_params,timeline),
            row(2,'animation_inspect.preview',dict(self.params,dry_run=True),dict(error)),
            row(3,'animation_inspect.timeline',timeline_params,timeline),
            row(4,'animation_inspect.preview',dict(self.params,animation_name='absent'),dict(error)),
            row(5,'animation_inspect.timeline',timeline_params,timeline),
            row(6,'animation_inspect.preview',self.params,self.response),
            row(7,'animation_inspect.timeline',timeline_params,timeline),
            row(8,'animation_inspect.preview',dict(self.params),dict(error)),
            row(9,'animation_inspect.timeline',timeline_params,timeline)]
        def stored(name,value):
            path=self.root/name
            path.write_bytes(value if isinstance(value,bytes) else json.dumps(value).encode())
            return {'path':name,'sha256':digest(path)}
        scene=b'[gd_scene format=3]\n# fixture-only synthetic source'
        restore={'before_scene':stored('before-scene.tscn',scene),'after_scene':stored('restored-scene.tscn',scene),
                 'before_timeline':stored('before-timeline.json',timeline),'after_timeline':stored('after-timeline.json',timeline)}
        checkpoints={}
        for label,index in [('before_dry',1),('after_dry',3),('before_preview',5),('after_preview',7),('after_overwrite_refusal',9)]:
            checkpoints[label]={'timeline_public_case_id':'fixture:'+str(index),'scene_save_public_case_id':None,
                'scene':stored(label+'.tscn',scene),'timeline':stored(label+'.json',timeline)}
        images=[]
        for i in range(4):
            image=Image.new('RGB',(320,240),'black');ImageDraw.Draw(image).rectangle((10+i*30,20,30+i*30,80),fill='white')
            path=self.root/('walk_%02d.png'%i);image.save(path)
            images.append({'path':path.name,'sha256':digest(path),'size':[320,240],
                           'rgb_extrema':[[0,255]]*3,'unique_colors':2})
        renderer='OpenGL API 4.5 - Mesa llvmpipe fixture renderer'
        logs=[stored('editor.log',renderer.encode()),stored('backend.log',b'fixture backend log')]
        self.report={'schema_version':1,'operation':'animation_inspect.preview','passed':True,
            'context':self.context,'context_sha256':digest(self.context_path),'public_case_id':'fixture:6',
            'raw_response':self.response,'images':images,'restoration':restore,'checkpoints':checkpoints,
            'logs':logs,'renderer_identity':[renderer],'renderer_profile':'linux-mesa-llvmpipe',
            'editor_command':['fixture-godot','--editor','--rendering-method','gl_compatibility']}
        self.path=self.root/'rendered-preview.json'
    def validate(self):
        self.path.write_text(json.dumps(self.report))
        return validate_preview(self.path,self.context_path,self.context,self.events)
    def test_decoded_evidence_binds_exact_actual_call_without_visual_approval(self):
        proof=self.validate()
        self.assertEqual(proof['public_case_id'],'fixture:6')
        self.assertEqual(set(proof['checks']),{'valid_effect','file_effect','source_unchanged','typed_errors','reported_errors'})
        self.assertNotIn('visual_review',proof['checks'])
    def test_windows_profile_binds_real_complete_log_and_context(self):
        self.context['platform']='windows'
        self.context_path.write_text(json.dumps(self.context))
        self.report['context_sha256']=digest(self.context_path)
        self.report['renderer_profile']='windows-native-opengl'
        renderer='OpenGL API 3.3.0 NVIDIA 581.80 - Compatibility - Using Device: NVIDIA - NVIDIA GeForce GTX 1070 Ti'
        (self.root/'editor.log').write_text(renderer)
        self.report['logs'][0]['sha256']=digest(self.root/'editor.log')
        self.report['renderer_identity']=[renderer]
        self.assertEqual(self.validate()['checks']['file_effect'],'pass')
        for bad in (None,'linux-mesa-llvmpipe'):
            self.report['renderer_profile']=bad
            with self.assertRaises(ValueError):self.validate()
    def test_logged_identity_cannot_omit_another_actual_device(self):
        path=self.root/'editor.log'
        path.write_text(path.read_text()+'\nOpenGL API other unexpected device')
        self.report['logs'][0]['sha256']=digest(path)
        with self.assertRaisesRegex(ValueError,'identity differs'):self.validate()
    def test_explicit_profile_requires_bound_helper(self):
        del self.context['dependencies']['tools/preview_renderer_profile.py']
        self.context_path.write_text(json.dumps(self.context))
        self.report['context_sha256']=digest(self.context_path)
        with self.assertRaisesRegex(ValueError,'helper not bound'):self.validate()
        del self.report['renderer_profile']
        self.assertEqual(self.validate()['checks']['file_effect'],'pass')
    def test_wrong_case_context_or_headless_refusal_never_qualify(self):
        original=copy.deepcopy(self.report)
        for field,value in [('public_case_id','fixture:2'),('context_sha256','foreign'),('editor_command',['fixture-godot','--editor','--headless'])]:
            self.report=copy.deepcopy(original);self.report[field]=value
            with self.assertRaises(ValueError):self.validate()
        self.report=original;self.events[5]['response']={'error':'OPERATION_UNAVAILABLE: headless'}
        with self.assertRaises(ValueError):self.validate()
    def test_duplicate_actual_pixels_rejected_even_with_updated_hash(self):
        (self.root/'walk_01.png').write_bytes((self.root/'walk_00.png').read_bytes())
        self.report['images'][1]['sha256']=digest(self.root/'walk_01.png')
        with self.assertRaisesRegex(ValueError,'duplicate'):self.validate()
    def test_raw_engine_error_including_ansi_is_rejected(self):
        path=self.root/'editor.log';path.write_text('OpenGL API Mesa llvmpipe\nE\x1b[31mRROR: shutdown failure')
        self.report['logs'][0]['sha256']=digest(path)
        with self.assertRaisesRegex(ValueError,'engine/script'):self.validate()
    def test_immediate_source_checkpoint_and_typed_refusal_are_required(self):
        point=self.report['checkpoints']['after_preview'];path=self.root/point['scene']['path']
        path.write_text('changed source');point['scene']['sha256']=digest(path)
        with self.assertRaisesRegex(ValueError,'checkpoint changed'):self.validate()
        self.setUp();self.events[1]['response']={'error':'Unknown tool'}
        with self.assertRaisesRegex(ValueError,'typed'):self.validate()
    def test_checkpoint_cannot_borrow_after_call_or_escape_artifacts(self):
        self.report['checkpoints']['before_preview']['timeline_public_case_id']='fixture:7'
        with self.assertRaisesRegex(ValueError,'bracket'):self.validate()
        with self.assertRaises(ValueError):artifact(self.root,{'path':'../outside.png','sha256':'x'})
    def test_downloaded_bundle_revalidates_raw_context_and_request_binding(self):
        self.validate()
        traces=self.root/'traces';traces.mkdir()
        rows=[]
        for i,event in enumerate(self.events,1):
            rows.append(dict(event,kind='public_operation_call',route='public_godot_ai',
                public_tool='custom_animation_inspect',request=event['params'],sequence=i,
                context_sha256=digest(self.context_path),run_id='fixture-preview'))
        path=traces/'actual.jsonl';path.write_text(''.join(json.dumps(row)+'\n' for row in rows))
        self.assertEqual(verify_preview_bundle(self.root)['proof']['public_case_id'],'fixture:6')
        rows[5]['request']=dict(rows[5]['request'],op='stats')
        path.write_text(''.join(json.dumps(row)+'\n' for row in rows))
        with self.assertRaisesRegex(ValueError,'operation differs'):verify_preview_bundle(self.root)

if __name__=='__main__':unittest.main()
