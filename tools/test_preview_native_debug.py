"""Mock-only native debugger command, identity and owned-group controls."""
import argparse
import json
import signal
import subprocess
import tempfile
from pathlib import Path
import unittest
from unittest.mock import Mock,patch
import preview_native_debug as debug
import ci_rendered_preview as runner

class NativeDebuggerControls(unittest.TestCase):
    def setUp(self):
        fake_signal=patch.object(debug.signal,"SIGKILL",9,create=True)
        fake_signal.start();self.addCleanup(fake_signal.stop)
    def test_prefix_preserves_actual_godot_and_all_arguments(self):
        actual=['/actual/godot','--editor','--path','/fresh project','--rendering-method','gl_compatibility','--rendering-driver','opengl3','res://main.tscn']
        self.assertEqual(debug.launch_command(actual,'none'),actual)
        with patch.object(debug.sys,'platform','linux'):command=debug.launch_command(actual,'gdb')
        self.assertIn('--return-child-result',command)
        self.assertEqual(command[command.index('--args')+1:],actual)
        self.assertIn('thread apply all bt full',command)
        self.assertLess(command.index('run'),command.index('thread apply all bt full'))
    def test_non_linux_debugging_and_unknown_modes_refused(self):
        for host in ('win32','darwin'):
            with patch.object(debug.sys,'platform',host):
                with self.assertRaises(ValueError):debug.launch_command(['Godot.exe'],'gdb')
        with self.assertRaises(ValueError):debug.launch_command(['godot'],'invented')
    def test_private_group_cleanup_even_after_debugger_exits(self):
        process=Mock(pid=12345,returncode=134);process.poll.return_value=134
        with patch.object(debug.sys,'platform','linux'),patch.object(debug.os,'killpg',create=True) as kill:
            report=debug.cleanup_debugger_group(process)
        self.assertEqual(kill.call_args_list[0].args,(12345,signal.SIGTERM))
        self.assertEqual(kill.call_args_list[-1].args,(12345,signal.SIGKILL))
        self.assertTrue(all(c.args[0]==12345 for c in kill.call_args_list))
        self.assertEqual(report['debugger_returncode'],134)
    def test_hung_debugger_gets_bounded_wait_then_private_group_kill(self):
        process=Mock(pid=23456,returncode=-9);process.poll.return_value=None
        process.wait.side_effect=[subprocess.TimeoutExpired('gdb',3),subprocess.TimeoutExpired('gdb',10),-9]
        with patch.object(debug.sys,'platform','linux'),patch.object(debug.os,'killpg',create=True) as kill:debug.cleanup_debugger_group(process)
        self.assertEqual([c.kwargs['timeout'] for c in process.wait.call_args_list],[3,10,5])
        self.assertTrue(all(c.args[0]==23456 for c in kill.call_args_list))
    def test_disappeared_group_is_safe_invalid_group_refused(self):
        process=Mock(pid=34567,returncode=0);process.poll.return_value=0
        with patch.object(debug.sys,'platform','linux'),patch.object(debug.os,'killpg',side_effect=ProcessLookupError,create=True):debug.cleanup_debugger_group(process)
        process.pid=1
        with patch.object(debug.sys,'platform','linux'),patch.object(debug.os,'killpg',create=True) as kill:
            with self.assertRaises(ValueError):debug.cleanup_debugger_group(process)
            kill.assert_not_called()
    def test_allocator_and_debugger_native_fatals_are_never_success(self):
        for text in ['double free or corruption (!prev)','malloc(): corrupted top size','free(): invalid pointer','Program received signal SIGABRT, Aborted.','Program terminated with signal SIGSEGV, Segmentation fault.']:
            with self.subTest(text=text),self.assertRaises(ValueError):runner.validate_editor_log(text)
        runner.validate_editor_log('Program received signal SIGTERM, Terminated.\nOwned teardown')
    def test_runner_context_and_command_remain_actual_engine(self):
        with tempfile.TemporaryDirectory() as temp:
            base=Path(temp);project=base/'project';project.mkdir();core=base/'core';core.mkdir();output=base/'receipt'
            args=argparse.Namespace(project=project,core_root=core,output=output,godot='/actual/godot',renderer_profile='linux-mesa-llvmpipe',native_debugger='gdb',port=8000,ws_port=9500)
            commands=[];exercised=[]
            def prepare(repo,core_root,godot,path):
                self.assertEqual(godot,'/actual/godot');context={'platform':'linux','engine_command':godot};path.write_text(json.dumps(context));return context
            def spawn(command,**kwargs):
                process=Mock(pid=45678 if command[0]=='gdb' else 45677,returncode=0);process.poll.return_value=None;process.wait.return_value=0
                commands.append((command,kwargs,process))
                if command[0]=='gdb':kwargs['stdout'].write(b'OpenGL API 4.5 - Compatibility - Using Device: Mesa - llvmpipe\n');kwargs['stdout'].flush()
                return process
            async def exercise(received,report):exercised.append(received)
            with patch.object(runner.sys,'platform','linux'),patch.dict(runner.os.environ,{'DISPLAY':':99'}),patch('operation_case_collector.prepare',side_effect=prepare),patch.object(runner,'port_open',side_effect=[False,False,True,True]),patch.object(runner.subprocess,'Popen',side_effect=spawn),patch.object(runner,'exercise',side_effect=exercise),patch.object(runner,'cleanup_debugger_group',return_value={'process_group':45678}) as cleanup:
                self.assertEqual(runner.run(args),0)
            report=json.loads((output/'rendered-preview.json').read_text())
            self.assertEqual(report['context']['engine_command'],'/actual/godot')
            self.assertEqual(report['editor_command'][0],'/actual/godot')
            actual=commands[1][0];self.assertEqual(actual[actual.index('--args')+1:],report['editor_command'])
            self.assertTrue(commands[1][1]['start_new_session'])
            self.assertNotIn('start_new_session',commands[0][1])
            cleanup.assert_called_once_with(commands[1][2]);self.assertEqual(exercised,[args])

if __name__=='__main__':unittest.main()
