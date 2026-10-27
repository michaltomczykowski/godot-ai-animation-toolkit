"""Pure/mocked postmortem controls: no sysctl, engine, debugger or crash executed."""
import argparse
import json
from pathlib import Path
import os
import struct
import signal
import subprocess
import tempfile
import time
import unittest
from types import SimpleNamespace
from unittest.mock import Mock,patch
import preview_postmortem as pm
import preview_native_debug as launch
import ci_rendered_preview as runner

def elf_core(pid):
    def note(kind,offset):
        desc=bytearray(64);struct.pack_into('<i',desc,offset,pid)
        return struct.pack('<III',5,len(desc),kind)+b'CORE\0\0\0\0'+desc
    notes=note(3,24)+note(1,32);header=bytearray(64);header[:6]=b'\x7fELF\x02\x01';struct.pack_into('<HH',header,16,4,62);struct.pack_into('<Q',header,32,64);struct.pack_into('<HH',header,54,56,1)
    ph=bytearray(56);struct.pack_into('<I',ph,0,4);struct.pack_into('<Q',ph,8,120);struct.pack_into('<Q',ph,32,len(notes));return bytes(header+ph)+notes

class PostmortemControls(unittest.TestCase):
    def make(self,base,pid=4321):
        x=pm.Postmortem.__new__(pm.Postmortem);x.directory=base/'private';x.directory.mkdir();x.artifact=base/'artifact';x.artifact.mkdir();x.binary=base/'godot';x.binary.write_bytes(b'exact engine');x.pid=pid;x.bound=True;x.original=None;x.pattern=None;x.started=time.time()-1;x.report={'mode':'postmortem','binary_sha256':pm.digest(x.binary)};return x
    def test_child_core_soft_limit_raised_without_changing_hard_limit(self):
        resource=SimpleNamespace(RLIMIT_CORE=4,getrlimit=Mock(return_value=(0,-1)),setrlimit=Mock())
        with patch.dict('sys.modules',{'resource':resource}):pm.enable_child_core()
        resource.setrlimit.assert_called_once_with(4,(-1,-1))
    def test_normal_launch_unchanged_and_nonlinux_refused(self):
        command=['/actual/godot','--editor','--path','space project','res://main.tscn']
        with patch.object(launch.sys,'platform','linux'):self.assertEqual(launch.launch_command(command,'postmortem'),command)
        with patch.object(launch.sys,'platform','win32'):
            with self.assertRaises(ValueError):launch.launch_command(command,'postmortem')
    def test_real_elf_pid_notes_wrongpid_and_malformed(self):
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)/'core.4321';p.write_bytes(elf_core(4321));self.assertTrue(pm.core_pid_matches(p,4321));self.assertFalse(pm.core_pid_matches(p,9999));p.write_bytes(b'not ELF');self.assertFalse(pm.core_pid_matches(p,4321))
    def test_noabort_never_reads_even_existing_core(self):
        with tempfile.TemporaryDirectory() as temp:
            x=self.make(Path(temp));core=x.directory/'core.4321';core.write_bytes(elf_core(4321));process=Mock(pid=4321);process.poll.return_value=0
            with patch.object(pm,'core_pid_matches') as inspect,patch.object(x,'_text_command') as gdb:
                self.assertEqual(x.collect(process)['status'],'no_observed_native_crash');inspect.assert_not_called();gdb.assert_not_called()
    def test_wrongpid_file_not_looked_up_or_analyzed(self):
        with tempfile.TemporaryDirectory() as temp:
            x=self.make(Path(temp));wrong=x.directory/'core.9999';wrong.write_bytes(elf_core(9999));process=Mock(pid=4321);process.poll.return_value=-signal.SIGABRT
            with patch.object(x,'_text_command') as gdb:x.collect(process);gdb.assert_not_called()
            self.assertEqual(x.report['status'],'crash_core_unavailable');x.close();self.assertTrue(wrong.exists())
    def test_matching_filename_wrong_elf_pid_refused_then_owned_cleanup(self):
        with tempfile.TemporaryDirectory() as temp:
            x=self.make(Path(temp));core=x.directory/'core.4321';core.write_bytes(elf_core(9999));process=Mock(pid=4321);process.poll.return_value=-signal.SIGABRT
            with patch.object(pm.os,'getuid',return_value=core.stat().st_uid,create=True),patch.object(x,'_text_command') as gdb:
                x.collect(process);gdb.assert_not_called();self.assertEqual(x.report['core_refusal'],'core_ELF_PID_mismatch');x.close()
            self.assertFalse(core.exists())
    def test_owned_abort_exact_binary_batch_only_and_cleanup(self):
        with tempfile.TemporaryDirectory() as temp:
            x=self.make(Path(temp));core=x.directory/'core.4321';core.write_bytes(elf_core(4321));process=Mock(pid=4321);process.poll.return_value=-signal.SIGSEGV
            with patch.object(pm.os,'getuid',return_value=core.stat().st_uid,create=True),patch.object(x,'_text_command',return_value={'returncode':0}) as gdb,patch.object(pm.shutil,'which',return_value=None):
                x.collect(process);command=gdb.call_args.args[0];self.assertEqual(command[-4:],['--se',str(x.binary),'--core',str(core)]);self.assertIn('thread apply all bt full',command);self.assertNotIn('run',command);self.assertIn('set auto-load off',command);self.assertEqual(x.report['editor_returncode_before_cleanup'],-signal.SIGSEGV);x.close()
            self.assertFalse(core.exists());self.assertFalse(x.directory.exists())
    def test_live_editor_bounded_wait_no_debugger_no_termination_here(self):
        with tempfile.TemporaryDirectory() as temp:
            x=self.make(Path(temp));process=Mock(pid=4321);process.poll.return_value=None;process.wait.side_effect=subprocess.TimeoutExpired('godot',10)
            with patch.object(x,'_text_command') as gdb:x.collect(process,failed=True);gdb.assert_not_called()
            process.wait.assert_called_once_with(timeout=10);process.terminate.assert_not_called();self.assertIsNone(x.report['editor_returncode_before_cleanup'])
    def test_debugger_timeout_text_retained_and_owned_core_removed(self):
        with tempfile.TemporaryDirectory() as temp:
            x=self.make(Path(temp));core=x.directory/'core.4321';core.write_bytes(elf_core(4321))
            def timeout(command,**kwargs):kwargs['stdout'].write(b'partial native stack');raise subprocess.TimeoutExpired(command,60)
            with patch.object(pm.subprocess,'run',side_effect=timeout):report=x._text_command(['gdb'],'postmortem-gdb.txt',60)
            self.assertTrue(report['timed_out']);self.assertEqual((x.artifact/'postmortem-gdb.txt').read_bytes(),b'partial native stack')
            with patch.object(pm.os,'getuid',return_value=core.stat().st_uid,create=True):x.close()
            self.assertFalse(core.exists())
    def test_non_disposable_setup_refused_before_kernel_command(self):
        with patch.object(pm.sys,'platform','linux'),patch.dict(pm.os.environ,{'GITHUB_ACTIONS':'true','RUNNER_ENVIRONMENT':'self-hosted'}),patch.object(pm.subprocess,'run') as command:
            with self.assertRaises(ValueError):pm.Postmortem('godot',Path('artifacts'))
            command.assert_not_called()
    def test_setup_applies_private_pattern_child_limit_and_restores(self):
        with tempfile.TemporaryDirectory() as temp:
            b=Path(temp);private=b/'owned';private.mkdir();artifact=b/'artifacts';artifact.mkdir();binary=b/'godot';binary.write_bytes(b'exact engine');state={'pattern':'|original system handler'}
            original_read=Path.read_text
            def read(path,*args,**kwargs):
                return state['pattern'] if path.as_posix()=='/proc/sys/kernel/core_pattern' else original_read(path,*args,**kwargs)
            def sysctl(command,**kwargs):state['pattern']=command[-1].split('=',1)[1];return Mock(returncode=0)
            resource=SimpleNamespace(RLIMIT_CORE=4,getrlimit=lambda kind:(0,-1))
            with patch.object(pm.sys,'platform','linux'),patch.dict(pm.os.environ,{'GITHUB_ACTIONS':'true','RUNNER_ENVIRONMENT':'github-hosted'}),patch.dict('sys.modules',{'resource':resource}),patch.object(pm.shutil,'which',return_value=str(binary)),patch.object(pm.tempfile,'mkdtemp',return_value=str(private)),patch.object(Path,'read_text',read),patch.object(pm.subprocess,'run',side_effect=sysctl) as command:
                x=pm.Postmortem('godot',artifact);self.assertEqual(state['pattern'],str(private/'core.%p'));self.assertNotIn(artifact,private.parents);self.assertEqual(x.launch_kwargs(),{'preexec_fn':pm.enable_child_core});x.close()
            self.assertEqual(state['pattern'],'|original system handler');self.assertTrue(x.report['kernel_pattern_restored']);self.assertFalse(private.exists());self.assertEqual(command.call_count,2)
    def test_kernel_restore_attempted_after_owned_core_unlink_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            x=self.make(Path(temp));core=x.directory/'core.4321';core.write_bytes(elf_core(4321));x.original='original';x.pattern='private';state={'pattern':'private'}
            def sysctl(command,**kwargs):state['pattern']='original';return Mock(returncode=0)
            with patch.object(pm.os,'getuid',return_value=core.stat().st_uid,create=True),patch.object(Path,'unlink',side_effect=PermissionError('locked')),patch.object(Path,'read_text',side_effect=lambda *a,**kw:state['pattern']),patch.object(pm.subprocess,'run',side_effect=sysctl) as command:x.close()
            command.assert_called_once();self.assertTrue(x.report['kernel_pattern_restored']);self.assertTrue(x.report['cleanup_errors']);self.assertTrue(core.exists())
    def test_changed_engine_and_wrong_owned_process_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            x=self.make(Path(temp));core=x.directory/'core.4321';core.write_bytes(elf_core(4321));x.binary.write_bytes(b'changed');process=Mock(pid=4321);process.poll.return_value=-signal.SIGABRT
            with patch.object(pm.os,'getuid',return_value=core.stat().st_uid,create=True),patch.object(x,'_text_command') as gdb:
                x.collect(process);gdb.assert_not_called();self.assertEqual(x.report['core_refusal'],'engine_binary_changed');x.close()
            with self.assertRaises(ValueError):x.collect(Mock(pid=9999))
    def test_runner_single_normal_launch_single_exercise_and_separate_status(self):
        with tempfile.TemporaryDirectory() as temp:
            b=Path(temp);project=b/'project';project.mkdir();core=b/'core';core.mkdir();output=b/'out';args=argparse.Namespace(project=project,core_root=core,output=output,godot='/exact/godot',renderer_profile='linux-mesa-llvmpipe',native_debugger='postmortem',port=8000,ws_port=9500)
            state={'mode':'postmortem'};post=Mock(report=state);post.launch_kwargs.return_value={'preexec_fn':pm.enable_child_core};post.close.return_value=state
            def collect(process,**kwargs):state.update(editor_returncode_before_cleanup=-signal.SIGABRT,status='postmortem_text_recorded')
            post.collect.side_effect=collect;commands=[]
            def spawn(command,**kwargs):
                process=Mock(pid=4321 if command[0]=='/exact/godot' else 4320);process.poll.return_value=None;commands.append((command,kwargs,process))
                if command[0]=='/exact/godot':kwargs['stdout'].write(b'OpenGL API - Compatibility - Mesa - llvmpipe\n');kwargs['stdout'].flush()
                return process
            def prepare(repo,core_root,godot,path):v={'platform':'linux','engine_command':godot};path.write_text(json.dumps(v));return v
            async def exercise(*args):return None
            with patch.object(runner.sys,'platform','linux'),patch.dict(runner.os.environ,{'DISPLAY':':99'}),patch('operation_case_collector.prepare',side_effect=prepare),patch.object(runner,'Postmortem',return_value=post),patch.object(runner,'port_open',side_effect=[False,False,True,True]),patch.object(runner.subprocess,'Popen',side_effect=spawn),patch.object(runner,'exercise',side_effect=exercise) as run:
                self.assertEqual(runner.run(args),1)
            run.assert_called_once();self.assertEqual(len(commands),2);self.assertEqual(commands[1][0][0],'/exact/godot');self.assertNotIn('gdb',commands[1][0]);self.assertEqual(commands[1][1]['preexec_fn'],pm.enable_child_core);post.bind.assert_called_once_with(commands[1][2]);post.close.assert_called_once();report=json.loads((output/'rendered-preview.json').read_text());self.assertFalse(report['passed']);self.assertEqual(report['native_debugger']['editor_returncode_before_cleanup'],-signal.SIGABRT)

if __name__=='__main__':unittest.main()
