"""Fail-closed opt-in launch attachment; never changes Godot/public arguments."""
import hashlib,json,struct,sys
from pathlib import Path

EXPECTED_SHA256='8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e'
SITES={0x1cb7900:bytes.fromhex('4157'),0x1cb7992:bytes.fromhex('c6052fef2f0700'),0x1cb7855:bytes.fromhex('e8268f7502')}

def check_binary(path):
 raw=Path(path).read_bytes()
 if hashlib.sha256(raw).hexdigest()!=EXPECTED_SHA256:raise ValueError('doc watch requires exact official Linux ELF SHA256')
 if raw[:6]!=b'\x7fELF\x02\x01' or struct.unpack_from('<HH',raw,16)!=(2,62):raise ValueError('doc watch requires x86_64 little-endian ET_EXEC')
 offset=struct.unpack_from('<Q',raw,32)[0];stride,count=struct.unpack_from('<HH',raw,54)
 for address,expected in SITES.items():
  found=False
  for i in range(count):
   kind,flags,file_offset,virtual,physical,file_size,memory_size,align=struct.unpack_from('<IIQQQQQQ',raw,offset+i*stride)
   if kind==1 and flags&1 and virtual<=address and address+len(expected)<=virtual+file_size:
    start=file_offset+address-virtual;found=raw[start:start+len(expected)]==expected;break
  if not found:raise ValueError('doc watch exact instruction/site mismatch: '+hex(address))
 return EXPECTED_SHA256

def attach(launch,engine_command,debugger,directory,platform=None):
 if (platform or sys.platform)!='linux' or debugger!='gdb':raise ValueError('doc watch requires explicit Linux GDB mode')
 if '--args'not in launch or launch[launch.index('--args')+1:]!=list(engine_command):raise ValueError('doc watch actual engine command changed')
 identity=check_binary(engine_command[0]);source=Path(__file__).with_name('preview_doc_watch_gdb.py');raw=source.read_bytes()
 target=Path(directory)/'doc-watch-gdb.py'
 with target.open('xb')as stream:stream.write(raw)
 script="python exec(compile(open("+repr(str(target.resolve()))+", encoding='utf-8').read(), "+repr(str(target.resolve()))+", 'exec'))"
 index=next((i for i in range(len(launch)-1)if launch[i:i+2]==['-ex','run']),None)
 if index is None:raise ValueError('doc watch missing exact GDB run boundary')
 command=list(launch);command[index:index]=['-ex',script]
 return command,{'mode':'official_doc_vector_watch','engine_sha256':identity,'script':target.name,'script_sha256':hashlib.sha256(raw).hexdigest(),'limit':'per-writer stack quotas, all pointer write counts; no qualification or readiness claim'}

def validate_log(text):
 rows=[]
 for line in text.splitlines():
  if line.startswith('DOC_WATCH='):
   try:rows.append(json.loads(line[len('DOC_WATCH='):]))
   except ValueError:raise ValueError('malformed doc watch log')
 if not rows or not any(r.get('event')=='armed'for r in rows):raise ValueError('doc watch did not arm')
 if any(r.get('event')=='diagnostic_failure'or r.get('writer_limit_exceeded')for r in rows):raise ValueError('doc watch diagnostic failure/incomplete writer coverage')
 return {'events':len(rows),'regeneration_seen':any(r.get('event')=='regeneration_entry'for r in rows),'completed_windows':sum(r.get('event')=='window_complete'for r in rows),'qualification':False}
