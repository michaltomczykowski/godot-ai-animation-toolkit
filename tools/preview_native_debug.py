"""Optional Linux-only native crash diagnostics; never changes Godot arguments."""
import os
import signal
import subprocess
import sys


def launch_command(engine_command, debugger):
    if debugger=='none':return list(engine_command)
    if debugger!='gdb' or sys.platform!='linux':
        raise ValueError('GDB preview diagnostics require explicit gdb on Linux')
    return ['gdb','--batch','--return-child-result',
            '-ex','set pagination off','-ex','set confirm off','-ex','set debuginfod enabled off',
            '-ex','run','-ex','thread apply all bt full','-ex','info sharedlibrary',
            '--args',*engine_command]


def cleanup_debugger_group(process):
    """Only for a Popen created here with start_new_session=True on Linux."""
    if sys.platform!='linux':raise ValueError('debugger process groups are Linux-only')
    if process.pid<=1:raise ValueError('invalid owned debugger process-group identity')
    # Allow a just-crashed inferior's batch backtrace to finish before teardown.
    if process.poll() is None:
        try:process.wait(timeout=3)
        except subprocess.TimeoutExpired:pass
    pre_cleanup_returncode=process.poll()
    signals=[]
    def send(sig):
        try:os.killpg(process.pid,sig);signals.append(int(sig))
        except ProcessLookupError:pass
    # Signal the private session even when GDB exited: the inferior could remain.
    send(signal.SIGTERM)
    try:process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        send(signal.SIGKILL)
        process.wait(timeout=5)
    # An exited debugger does not prove its child exited; remove only its own group.
    send(signal.SIGKILL)
    return {'process_group':process.pid,'signals':signals,'debugger_returncode':process.returncode,
            'pre_cleanup_returncode':pre_cleanup_returncode}
