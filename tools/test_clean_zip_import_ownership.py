"""Pure process/environment controls; no Godot or backend is launched."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import clean_zip_install as clean
import ci_mcp_route as route

class ImportOwnershipControls(unittest.TestCase):
    def test_import_precedes_route_without_inherited_headless_opt_in(self):
        for inherited in ('1','true','0',None):
            with self.subTest(inherited=inherited):
                env={'KEEP_VALIDATION_ENV':'kept'}
                if inherited is not None:env['GODOT_AI_ALLOW_HEADLESS']=inherited
                calls=[];result=subprocess.CompletedProcess(['python','route.py'],0,'route proof','')
                def run(command,**kwargs):
                    calls.append((command,kwargs))
                    # Model the import backend leak the actual guard prevents.
                    if '--import' in command and kwargs['env'].get('GODOT_AI_ALLOW_HEADLESS'):
                        raise AssertionError('import would activate unowned backend')
                    return result
                command=['python','ci_mcp_route.py','--install-selection','--port','8000','--ws-port','9500']
                with patch.dict(os.environ,env,clear=True),patch.object(clean.subprocess,'run',side_effect=run):
                    self.assertIs(clean.import_then_public_route('Godot.exe',Path('fresh'),command),result)
                    self.assertEqual(os.environ.get('GODOT_AI_ALLOW_HEADLESS'),inherited)
                self.assertEqual(calls[0][0],['Godot.exe','--headless','--path','fresh','--import'])
                self.assertEqual(calls[1][0],command)
                self.assertTrue(calls[0][1]['check'])
                self.assertTrue(calls[1][1]['capture_output'])
                for _,options in calls:
                    self.assertNotIn('GODOT_AI_ALLOW_HEADLESS',options['env'])
                    self.assertEqual(options['env']['KEEP_VALIDATION_ENV'],'kept')
    def test_failed_import_never_starts_public_route(self):
        with patch.object(clean.subprocess,'run',side_effect=subprocess.CalledProcessError(1,['Godot'])) as run:
            with self.assertRaises(subprocess.CalledProcessError):clean.import_then_public_route('Godot',Path('fresh'),['python','route.py'])
            self.assertEqual(run.call_count,1)
    def test_actual_route_retains_owned_headless_activation(self):
        class StopBeforeRealProcess(Exception):pass
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp);args=argparse.Namespace(project=base,core_root=base,log=str(base/'editor.log'),existing=False,port=8000,ws_port=9500)
            captured=[]
            def fake_spawn(command,**kwargs):
                captured.append((command,kwargs['env']))
                raise StopBeforeRealProcess()
            with patch.dict(os.environ,{'KEEP_VALIDATION_ENV':'kept'},clear=True),patch.object(route,'port_open',return_value=False),patch.object(route.subprocess,'Popen',side_effect=fake_spawn):
                with self.assertRaises(StopBeforeRealProcess):route.run(args)
            self.assertEqual(len(captured),1)
            self.assertEqual(captured[0][0][1:4],['-m','godot_ai','--transport'])
            self.assertEqual(captured[0][1]['GODOT_AI_ALLOW_HEADLESS'],'1')
            self.assertEqual(captured[0][1]['KEEP_VALIDATION_ENV'],'kept')
    def test_occupied_ports_still_fail_without_spawning_or_killing(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp);args=argparse.Namespace(project=base,core_root=base,log=str(base/'editor.log'),existing=False,port=8000,ws_port=9500)
            with patch.object(route,'port_open',return_value=True),patch.object(route.subprocess,'Popen') as spawn:
                with self.assertRaisesRegex(RuntimeError,'unused backend ports'):route.run(args)
                spawn.assert_not_called()

if __name__=='__main__':unittest.main()
