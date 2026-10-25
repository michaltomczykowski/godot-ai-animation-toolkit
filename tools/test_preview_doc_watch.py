"""Offline GDB/process-command controls only; no engine/debugger launch."""
import hashlib,importlib.util,json,struct,sys,tempfile,types,unittest
from pathlib import Path
from unittest.mock import patch
import preview_doc_watch as helper


def elf():
 raw=bytearray(8192);raw[:6]=b'\x7fELF\x02\x01';struct.pack_into('<HH',raw,16,2,62);struct.pack_into('<Q',raw,32,64);struct.pack_into('<HH',raw,54,56,1);struct.pack_into('<IIQQQQQQ',raw,64,1,5,256,0x1cb7800,0,4096,4096,4096)
 for address,value in helper.SITES.items():start=256+address-0x1cb7800;raw[start:start+len(value)]=value
 return bytes(raw)


def fake_gdb():
 fake=types.ModuleType('gdb');fake.BP_WATCHPOINT=1;fake.WP_WRITE=2;fake.lines=[];fake.breakpoints=[];fake.memory={'flag':1,'storage':0,'size':0,'capacity':0};fake.thread=types.SimpleNamespace(global_num=4,ptid=(100,104,0))
 class Break:
  def __init__(self,*a,**kw):self.enabled=True;fake.breakpoints.append(self)
 fake.Breakpoint=Break
 fake.write=fake.lines.append;fake.selected_thread=lambda:fake.thread
 def evaluate(expression):
  if '0x8fb68c8'in expression:return fake.memory['flag']
  if '0x8fb68b8'in expression:return fake.memory['storage']
  if '0x8fb68b0'in expression:return fake.memory['size']
  if '0x8fb68b4'in expression:return fake.memory['capacity']
  if expression=='$rdi':return 4096
  if expression=='$rsi':return 132440
  raise ValueError(expression)
 fake.parse_and_eval=evaluate;fake.execute=lambda command,**kw:'hw watchpoint\nhw watchpoint\nhw watchpoint'if command.startswith('maintenance')else'#0 exact_mock_frame\n';fake.events=types.SimpleNamespace(exited=types.SimpleNamespace(connect=lambda cb:setattr(fake,'exit',cb)))
 spec=importlib.util.spec_from_file_location('watch_test',Path(helper.__file__).with_name('preview_doc_watch_gdb.py'));module=importlib.util.module_from_spec(spec)
 with patch.dict(sys.modules,gdb=fake):spec.loader.exec_module(module)
 return module,fake


class Controls(unittest.TestCase):
 def test_active_window_thread_identity_and_loader_quota_does_not_hide_other_writers(self):
  m,g=fake_gdb();entry=g.breakpoints[0];entry.stop();m.log('size_write');self.assertFalse(m.state.counts)
  g.memory['flag']=0
  for _ in range(20):m.log('size_write')
  rows=[json.loads(x[len(m.PREFIX):])for x in g.lines];self.assertEqual(sum(x['event']=='size_write'for x in rows),8)
  g.thread=types.SimpleNamespace(global_num=1,ptid=(100,100,0));m.log('size_write');m.log('pointer_write');m.log('before_realloc',True)
  rows=[json.loads(x[len(m.PREFIX):])for x in g.lines];other=[x for x in rows if x.get('writer','').startswith('1:')];self.assertEqual(len(other),3);self.assertIn('stack',other[0]);self.assertEqual(other[-1]['state']['rsi'],132440)
  self.assertTrue(all(b.enabled for b in g.breakpoints));self.assertEqual(m.state.counts[('size_write',m.state.loader)],20)
 def test_completion_inactive_changes_and_exit_summary(self):
  m,g=fake_gdb();g.breakpoints[0].stop();g.memory['flag']=0;m.log('pointer_write');g.memory['flag']=1
  flag=next(x for x in g.breakpoints if isinstance(x,m.FlagWatch));flag.stop();m.log('pointer_write');g.exit(None)
  rows=[json.loads(x[len(m.PREFIX):])for x in g.lines];self.assertEqual(sum(r['event']=='pointer_write'for r in rows),1);self.assertTrue(any(r['event']=='window_complete'for r in rows));self.assertEqual(rows[-1]['event'],'inferior_exit')
 def test_memory_or_hardware_failures_and_writer_overflow_visible(self):
  m,g=fake_gdb();g.execute=lambda *a,**kw:'software watchpoint';g.breakpoints[0].stop();self.assertIn('diagnostic_failure',''.join(g.lines))
  g.memory['flag']=0
  for i in range(18):g.thread=types.SimpleNamespace(global_num=i+1,ptid=(100,i+1,0));m.log('size_write')
  self.assertTrue(m.state.overflow);m.summary('window_complete')
  with self.assertRaises(ValueError):helper.validate_log(''.join(g.lines))
 def test_exact_elf_hash_instruction_and_platform_refusals(self):
  with tempfile.TemporaryDirectory()as d:
   path=Path(d)/'godot';raw=elf();path.write_bytes(raw)
   with self.assertRaises(ValueError):helper.check_binary(path)
   with patch.object(helper,'EXPECTED_SHA256',hashlib.sha256(raw).hexdigest()):self.assertEqual(helper.check_binary(path),hashlib.sha256(raw).hexdigest())
   raw=bytearray(raw);raw[256+0x1cb7855-0x1cb7800]=0
   path.write_bytes(raw)
   with patch.object(helper,'EXPECTED_SHA256',hashlib.sha256(raw).hexdigest()):
    with self.assertRaises(ValueError):helper.check_binary(path)
   for platform,mode in [('win32','gdb'),('linux','none'),('linux','postmortem')]:
    with self.assertRaises(ValueError):helper.attach([],['godot'],mode,d,platform)
 def test_prefix_insertion_retains_actual_engine_args_and_exclusive_artifact(self):
  with tempfile.TemporaryDirectory()as d:
   command=['/official/godot','--editor','--path','a space','--rendering-driver','opengl3','res://main.tscn'];launch=['gdb','--batch','--return-child-result','-ex','run','-ex','thread apply all bt full','--args',*command]
   with patch.object(helper,'check_binary',return_value=helper.EXPECTED_SHA256):
    result,report=helper.attach(launch,command,'gdb',d,'linux');self.assertEqual(result[result.index('--args')+1:],command);self.assertEqual(result[:3],launch[:3]);self.assertLess(result.index('-ex'),result.index('run'));self.assertEqual(hashlib.sha256((Path(d)/report['script']).read_bytes()).hexdigest(),report['script_sha256'])
    with self.assertRaises(FileExistsError):helper.attach(launch,command,'gdb',d,'linux')
    with self.assertRaises(ValueError):helper.attach(launch,command+['extra'],'gdb',d,'linux')
 def test_log_is_diagnostic_not_qualification_and_rejects_failures(self):
  prefix='DOC_WATCH='
  good=prefix+json.dumps({'event':'armed'})+'\n'+prefix+json.dumps({'event':'window_complete','writer_limit_exceeded':False})
  self.assertFalse(helper.validate_log(good)['qualification'])
  for raw in ('',prefix+'{bad',good+'\n'+prefix+json.dumps({'event':'diagnostic_failure'}),good+'\n'+prefix+json.dumps({'event':'window_complete','writer_limit_exceeded':True})):
   with self.assertRaises(ValueError):helper.validate_log(raw)
if __name__=='__main__':unittest.main()
