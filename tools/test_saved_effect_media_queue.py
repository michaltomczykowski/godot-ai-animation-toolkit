import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import saved_effect_media_queue as queue


class QueueControls(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.project=self.root/'project';self.project.mkdir()
        self.plan=self.root/'plan.json'
        self.case={'id':'animation_fx.audio_cue:new','operation':'animation_fx.audio_cue',
            'fps':60,'seconds':12,'audio_output_required':True}
        self.plan.write_text(json.dumps({'kind':'saved_effect_render_plan','cases':[self.case]}))
        self.capture=self.root/'preserved';self.capture.mkdir();(self.capture/'frame.wav').write_bytes(b'preserved actual WAV')
        self.args=argparse.Namespace(plan=self.plan,project=self.project,output=self.root/'queue',
            godot='godot',ffmpeg='ffmpeg',ffprobe='ffprobe',reuse=['0='+str(self.capture)])
        self.identity={'frames':[{'sha256':'exact'}],'wav_sha256':queue.sha(self.capture/'frame.wav')}
        self.commands=[]

    def runner(self,command,**kwargs):
        self.commands.append(command)
        checkpoint=queue.read(self.args.output/'queue.json')
        self.assertIn(checkpoint['status'],('encoding','independent_full_decode'))
        if command[0]=='ffprobe':
            return subprocess.CompletedProcess(command,0,json.dumps({'streams':[{'codec_type':'video','width':1400,'height':800,'avg_frame_rate':'60/1'},{'codec_type':'audio'}]}),'')
        if '-progress' in command:
            return subprocess.CompletedProcess(command,0,'frame=720\nout_time_us=12000000\n','')
        self.assertEqual(checkpoint['current_command'],command)
        self.assertIn(str(self.capture/'frame.wav'),command)
        Path(command[-1]).write_bytes(b'fake encoded video')
        return subprocess.CompletedProcess(command,0,'','')

    def test_exact_capture_reuse_encode_audio_and_redecode_completed_media(self):
        with patch.object(queue,'verify_inputs'),patch.object(queue,'validate_capture',return_value=self.identity):
            self.assertEqual(queue.run(self.args,self.runner),0)
            receipt=queue.read(self.args.output/'case00/media-receipt.json')
            self.assertEqual(receipt['full_decode']['frames'],720)
            self.assertEqual(receipt['capture_identity']['wav_sha256'],queue.sha(self.capture/'frame.wav'))
            self.assertEqual(receipt['visual_review'],'pending')
            self.commands.clear()
            self.assertEqual(queue.run(self.args,self.runner),0)
            self.assertFalse(any('-c:v' in cmd for cmd in self.commands))
            self.assertTrue(any('-progress' in cmd for cmd in self.commands))

    def test_changed_completed_capture_refuses_without_encoding(self):
        with patch.object(queue,'verify_inputs'),patch.object(queue,'validate_capture',return_value=self.identity):
            self.assertEqual(queue.run(self.args,self.runner),0)
        self.commands.clear()
        with patch.object(queue,'verify_inputs'),patch.object(queue,'validate_capture',return_value={'frames':[]}):
            self.assertEqual(queue.run(self.args,self.runner),1)
        self.assertEqual(self.commands,[])
        self.assertEqual(queue.read(self.args.output/'queue.json')['status'],'failed_preserved')

    def test_partial_failure_is_preserved_and_fail_stops(self):
        def fail(command,**kwargs):
            Path(command[-1]).write_bytes(b'partial video')
            raise subprocess.CalledProcessError(3,command,output='preserved stdout',stderr='controlled failure')
        with patch.object(queue,'verify_inputs'),patch.object(queue,'validate_capture',return_value=self.identity):
            self.assertEqual(queue.run(self.args,fail),1)
            self.assertTrue((self.args.output/'case00/native-comparison.mp4').exists())
            self.assertEqual(queue.run(self.args,self.runner),1)
        self.assertEqual(self.commands,[])
        self.assertFalse((self.args.output/'queue.lock').exists())

    def test_full_decode_and_dimensions_reject_plausible_partial_video(self):
        for text in ['','frame=719\nout_time_us=12000000','frame=720\nout_time_us=11000000']:
            with self.assertRaises(ValueError): queue.decode_progress(text,self.case)
        with self.assertRaises(ValueError): queue.media_metadata({'streams':[{'codec_type':'video','width':1152,'height':648,'avg_frame_rate':'60/1'}]},self.case)


    def test_resume_preserves_verified_prefix_and_skips_completed_case(self):
        previous=self.args.output
        second=dict(self.case,id='animation_fx.audio_cue:second')
        self.plan.write_text(json.dumps({'kind':'saved_effect_render_plan','cases':[self.case,second]}))
        self.args.reuse=['0='+str(self.capture),'1='+str(self.capture)]
        def fail_second(command,**kwargs):
            if 'case01' in str(command):
                raise subprocess.CalledProcessError(3,command)
            return self.runner(command,**kwargs)
        with patch.object(queue,'verify_inputs'),patch.object(queue,'validate_capture',return_value=self.identity):
            self.assertEqual(queue.run(self.args,fail_second),1)
            old=queue.sha(previous/'queue.json')
            self.args.resume_from=previous
            self.args.output=self.root/'resumed'
            self.args.reuse=['1='+str(self.capture)]
            self.commands.clear()
            self.assertEqual(queue.run(self.args,self.runner),0)
            self.assertTrue(all('case00' not in str(cmd) for cmd in self.commands))
            new=queue.read(self.args.output/'queue.json')
            self.assertEqual(new['first_plan_case'],1)
            self.assertEqual(new['preserved_prefix']['sha256'],old)
            self.assertEqual(new['cases'][0]['index'],1)
            self.assertEqual(queue.sha(previous/'queue.json'),old)
            (previous/'case00/native-comparison.mp4').write_bytes(b'changed')
            self.args.output=self.root/'corrupted-resume'
            with self.assertRaisesRegex(ValueError,'Previous complete media differs'):
                queue.run(self.args,self.runner)
            self.assertFalse(self.args.output.exists())


if __name__=='__main__': unittest.main()
