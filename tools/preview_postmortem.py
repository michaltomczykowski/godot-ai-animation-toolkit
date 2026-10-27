"""Opt-in owned Linux editor core diagnostics. Core memory is never an artifact."""
import hashlib
import os
from pathlib import Path
import shutil
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import time

CRASH_SIGNALS={-signal.SIGABRT,-signal.SIGSEGV,-getattr(signal,'SIGBUS',7)}
TEXT_LIMIT=5*1024*1024

def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as source:
        for block in iter(lambda:source.read(1024*1024),b''):h.update(block)
    return h.hexdigest()

def enable_child_core():
    import resource
    soft,hard=resource.getrlimit(resource.RLIMIT_CORE)
    resource.setrlimit(resource.RLIMIT_CORE,(hard,hard))

def core_pid_matches(path,pid):
    """Only Linux x86_64 ELF core headers/notes; never load process memory pages."""
    with path.open('rb') as source:
        header=source.read(64)
        if len(header)!=64 or header[:6]!=b'\x7fELF\x02\x01' or struct.unpack_from('<HH',header,16)!=(4,62):return False
        offset=struct.unpack_from('<Q',header,32)[0];size,count=struct.unpack_from('<HH',header,54)
        if size!=56 or count>4096:return False
        statuses=[];leaders=[]
        for index in range(count):
            source.seek(offset+index*size);ph=source.read(size)
            if len(ph)!=size:return False
            if struct.unpack_from('<I',ph)[0]!=4:continue
            start=struct.unpack_from('<Q',ph,8)[0];length=struct.unpack_from('<Q',ph,32)[0]
            if length>16*1024*1024:return False
            source.seek(start);notes=source.read(length)
            if len(notes)!=length:return False
            cursor=0
            while cursor+12<=len(notes):
                namesz,descsz,kind=struct.unpack_from('<III',notes,cursor);cursor+=12
                end=cursor+namesz
                if end>len(notes):return False
                name=notes[cursor:end].rstrip(b'\0');cursor+=(namesz+3)&~3
                end=cursor+descsz
                if end>len(notes):return False
                desc=notes[cursor:end];cursor+=(descsz+3)&~3
                if name==b'CORE' and kind==1 and len(desc)>=36:statuses.append(struct.unpack_from('<i',desc,32)[0])
                if name==b'CORE' and kind==3 and len(desc)>=28:leaders.append(struct.unpack_from('<i',desc,24)[0])
        return leaders==[pid] and pid in statuses

class Postmortem:
    def __init__(self,engine,artifact_dir):
        self.artifact=Path(artifact_dir).resolve();self.directory=None;self.original=None;self.pattern=None
        self.pid=None;self.bound=False;self.started=time.time();self.binary=None
        self.report={'mode':'postmortem','status':'not_prepared','core_uploaded':False}
        try:
            self._prepare(engine)
        except BaseException as exc:
            exc.postmortem_report=self.close()
            raise

    def _prepare(self,engine):
        if sys.platform!='linux' or os.environ.get('GITHUB_ACTIONS')!='true' or os.environ.get('RUNNER_ENVIRONMENT')!='github-hosted':
            raise ValueError('postmortem requires explicit Linux disposable github-hosted runner')
        import resource
        soft,hard=resource.getrlimit(resource.RLIMIT_CORE)
        if hard==0:raise ValueError('postmortem core hard limit is zero')
        binary=shutil.which(str(engine))
        if not binary:raise ValueError('postmortem exact engine binary unavailable')
        self.binary=Path(binary).resolve(strict=True)
        self.report.update(binary=str(self.binary),binary_sha256=digest(self.binary),rlimit_core_before=[soft,hard],rlimit_core_child=[hard,hard])
        self.directory=Path(tempfile.mkdtemp(prefix='gai-core-',dir='/tmp')).resolve();self.directory.chmod(0o700)
        if self.directory==self.artifact or self.artifact in self.directory.parents:raise ValueError('core directory must be outside uploaded artifacts')
        self.pattern=str(self.directory/'core.%p')
        if len(self.pattern.encode())>=128:raise ValueError('core pattern too long')
        self.original=Path('/proc/sys/kernel/core_pattern').read_text().rstrip('\n')
        subprocess.run(['sudo','-n','sysctl','-w','kernel.core_pattern='+self.pattern],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10)
        if Path('/proc/sys/kernel/core_pattern').read_text().rstrip('\n')!=self.pattern:raise ValueError('kernel core pattern did not apply')
        self.report.update(status='prepared',core_pattern=self.pattern,core_pattern_before=self.original)

    def launch_kwargs(self):return {'preexec_fn':enable_child_core}

    def bind(self,process):
        if self.pid is not None or type(process.pid) is not int or process.pid<=1:raise ValueError('invalid owned editor PID')
        self.pid=process.pid;self.started=time.time()
        self.report['owned_editor_pid']=self.pid
        # Popen owns this PID; no process/port discovery or unrelated executable lookup.
        observed=Path('/proc')/str(self.pid)/'exe'
        try:self.bound=observed.resolve(strict=True)==self.binary
        except FileNotFoundError:self.bound=False
        self.report['proc_executable_matches']=self.bound
        if self.bound:
            limits=(Path('/proc')/str(self.pid)/'limits').read_text()
            line=next((line for line in limits.splitlines() if line.startswith('Max core file size')),None)
            self.report['actual_core_limit_line']=line
            if line is None or len(line.split())<6 or '0' in line.split()[4:6]:raise ValueError('owned editor core limit was not enabled')
        if not self.bound:raise ValueError('owned editor executable binding unavailable or differs')

    def collect(self,process,failed=False):
        if process.pid!=self.pid:raise ValueError('postmortem process identity mismatch')
        code=process.poll()
        if code is None and failed:
            try:code=process.wait(timeout=10)
            except subprocess.TimeoutExpired:pass
        self.report['editor_returncode_before_cleanup']=code
        if code not in CRASH_SIGNALS:
            self.report['status']='no_observed_native_crash';return self.report
        self.report.update(status='crash_core_unavailable',signal=-code)
        if not self.bound:return self.report
        core=self.directory/('core.'+str(self.pid))
        try:
            info=core.lstat()
        except FileNotFoundError:return self.report
        if not stat.S_ISREG(info.st_mode) or info.st_nlink!=1 or info.st_uid!=os.getuid() or info.st_mtime<self.started:
            self.report['core_refusal']='unsafe_or_stale_core';return self.report
        if not core_pid_matches(core,self.pid):
            self.report['core_refusal']='core_ELF_PID_mismatch';return self.report
        self.report.update(core_size=info.st_size,core_PID_verified=True)
        if digest(self.binary)!=self.report['binary_sha256']:
            self.report['core_refusal']='engine_binary_changed';return self.report
        gdb=['gdb','--nx','--batch','-iex','set auto-load off','-ex','set debuginfod enabled off',
             '-ex','set pagination off','-ex','set print elements 64','-ex','set print max-depth 6',
             '-ex','set backtrace limit 64','-ex','info inferiors','-ex','thread apply all bt full',
             '-ex','info sharedlibrary','-ex','info files','--se',str(self.binary),'--core',str(core)]
        self.report['gdb']=self._text_command(gdb,'postmortem-gdb.txt',60)
        if shutil.which('readelf'):
            self.report['binary_build_id']=self._text_command(['readelf','-n',str(self.binary)],'postmortem-binary-notes.txt',10)
        self.report['status']='postmortem_text_recorded' if self.report['gdb'].get('returncode')==0 else 'postmortem_analysis_incomplete'
        return self.report

    def _text_command(self,command,name,timeout):
        path=self.artifact/name;result={'command':command,'path':name,'timeout_seconds':timeout}
        # Filesize limit bounds debugger text, including error/timeout paths.
        def text_limit():
            import resource
            resource.setrlimit(resource.RLIMIT_FSIZE,(TEXT_LIMIT,TEXT_LIMIT))
        with path.open('xb') as output:
            try:
                completed=subprocess.run(command,stdout=output,stderr=subprocess.STDOUT,timeout=timeout,preexec_fn=text_limit)
                result['returncode']=completed.returncode
            except subprocess.TimeoutExpired:result['timed_out']=True
            except OSError as exc:result['error']=str(exc)
        result.update(sha256=digest(path),bytes=path.stat().st_size)
        return result

    def close(self):
        # Every cleanup is attempted even when another fails. Only our exact PID path.
        errors=[]
        if self.directory is not None and self.pid is not None:
            path=self.directory/('core.'+str(self.pid))
            try:
                info=path.lstat()
                if stat.S_ISREG(info.st_mode) and info.st_uid==os.getuid() and info.st_nlink==1:
                    path.unlink();self.report['owned_core_deleted']=True
                else:
                    self.report['owned_core_deleted']=False;errors.append('unsafe expected core path retained outside artifacts')
            except FileNotFoundError:self.report['owned_core_deleted']=True
            except OSError as exc:errors.append('owned core cleanup: '+str(exc))
        if self.original is not None:
            try:
                current=Path('/proc/sys/kernel/core_pattern').read_text().rstrip('\n')
                if current==self.pattern:
                    subprocess.run(['sudo','-n','sysctl','-w','kernel.core_pattern='+self.original],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10)
                    self.report['kernel_pattern_restored']=Path('/proc/sys/kernel/core_pattern').read_text().rstrip('\n')==self.original
                    if not self.report['kernel_pattern_restored']:errors.append('kernel pattern restore verification failed')
                else:
                    self.report['kernel_pattern_restored']=False;errors.append('kernel pattern changed externally; not overwritten')
            except (OSError,subprocess.SubprocessError) as exc:errors.append('kernel pattern restore: '+str(exc))
            self.original=None
        if self.directory is not None:
            try:self.directory.rmdir();self.report['private_directory_removed']=True
            except OSError:self.report['private_directory_removed']=False
        if errors:self.report.setdefault('cleanup_errors',[]).extend(errors)
        return self.report
