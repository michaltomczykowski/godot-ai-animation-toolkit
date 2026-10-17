"""Preserve bounded gate phase/output diagnostics without changing pass conditions."""
from __future__ import annotations
import json
import hashlib
from pathlib import Path
import re
import subprocess
import time


def progress(args, stage, **payload):
    now=time.perf_counter()
    if not hasattr(args,'_gate_started'):
        args._gate_started=now
        args._gate_progress={'events':[]}
    event={'stage':stage,'elapsed_seconds':round(now-args._gate_started,6)}
    event.update({k:v for k,v in payload.items() if k in {'suite','case_id','phase'}})
    args._gate_progress.update(payload)
    args._gate_progress['stage']=stage
    args._gate_progress['events'].append(event)
    print('MOTION_SEQUENCE_PROGRESS='+json.dumps(event,sort_keys=True),flush=True)
    record=getattr(args,'record',None)
    if record:
        record=Path(record)
        record.parent.mkdir(parents=True,exist_ok=True)
        target=record.with_suffix('.progress.json')
        pending=record.with_suffix('.progress.pending')
        pending.write_text(json.dumps(args._gate_progress,indent=2),encoding='utf-8')
        pending.replace(target)


def _text(value):
    return value.decode('utf-8',errors='replace') if isinstance(value,bytes) else value or ''


def bounded_run(command, timeout, record, label):
    """A timeout remains nonzero; preserve complete partial streams and phase state."""
    if not re.fullmatch('[a-z0-9_]+',label):
        raise ValueError('invalid diagnostic label')
    try:
        return subprocess.run(command,capture_output=True,text=True,timeout=timeout,check=False)
    except subprocess.TimeoutExpired as error:
        stdout,stderr=_text(error.stdout),_text(error.stderr)
        record=Path(record)
        record.parent.mkdir(parents=True,exist_ok=True)
        paths={name:record.with_suffix('.'+label+'.timeout.'+suffix)
               for name,suffix in [('stdout','stdout.log'),('stderr','stderr.log'),('metadata','json')]}
        raw_streams={name:value if isinstance(value,bytes) else (value or '').encode('utf-8')
                     for name,value in [('stdout',error.stdout),('stderr',error.stderr)]}
        for name,value in raw_streams.items():
            with paths[name].open('xb') as file:file.write(value)
        phase_path=record.with_suffix('.progress.json')
        try:phase=json.loads(phase_path.read_text(encoding='utf-8'))
        except (OSError,ValueError):phase={'stage':'unavailable'}
        metadata={'status':'timeout','timeout_seconds':timeout,'command':[str(x) for x in command],
                  'phase':phase,'partial_stdout':str(paths['stdout']),
                  'partial_stderr':str(paths['stderr']),
                  'stream_sha256':{name:hashlib.sha256(value).hexdigest() for name,value in raw_streams.items()}}
        with paths['metadata'].open('x',encoding='utf-8') as file:json.dump(metadata,file,indent=2)
        summary={'status':'timeout','timeout_seconds':timeout,'stage':phase.get('stage','unavailable'),
                 'metadata':str(paths['metadata']),'stdout':str(paths['stdout']),'stderr':str(paths['stderr'])}
        marker='MCP_GATE_TIMEOUT='+json.dumps(summary,sort_keys=True)
        # Append the compact phase summary last so an existing failure tail keeps it.
        return subprocess.CompletedProcess(command,124,stdout,stderr+'\n'+marker+'\n')
