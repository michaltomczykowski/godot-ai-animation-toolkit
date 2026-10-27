"""Loaded only inside GDB for one explicitly opted-in official-ELF diagnosis."""
import json
import gdb

PREFIX='DOC_WATCH='
FLAG=0x8fb68c8
POINTER=0x8fb68b8
SIZE=0x8fb68b0
CAPACITY=0x8fb68b4

class WatchState:
 def __init__(self):self.entered=False;self.loader=None;self.counts={};self.cycles=0;self.overflow=False
 def admit(self,kind,writer,flag):
  if not self.entered or flag:return False
  key=(kind,writer)
  if key not in self.counts and len({w for _,w in self.counts})>=16:
   self.overflow=True;return False
  self.counts[key]=self.counts.get(key,0)+1
  return self.counts[key]<= (8 if writer==self.loader else 4)

state=WatchState()
def emit(kind,**kw):gdb.write(PREFIX+json.dumps(dict(event=kind,**kw),sort_keys=True)+'\n')
def number(expression):return int(gdb.parse_and_eval(expression))
def writer():
 thread=gdb.selected_thread();return str(thread.global_num)+':'+repr(thread.ptid)
def snapshot():return dict(size=number('*(unsigned int*)'+hex(SIZE)),capacity=number('*(unsigned int*)'+hex(CAPACITY)),storage=hex(number('*(unsigned long long*)'+hex(POINTER))),flag=number('*(unsigned char*)'+hex(FLAG)))
def fail(exc):emit('diagnostic_failure',message=str(exc))
def summary(event):emit(event,cycles=state.cycles,counts={k+':'+w:v for (k,w),v in state.counts.items()},writer_limit_exceeded=state.overflow)
def log(kind,registers=False):
 current=writer();flag=number('*(unsigned char*)'+hex(FLAG))
 if state.admit(kind,current,flag):
  data=snapshot()
  if registers:data.update(rdi=hex(number('$rdi')),rsi=number('$rsi'))
  emit(kind,writer=current,loader=state.loader,state=data,stack=gdb.execute('bt 12',to_string=True))

class PointerWatch(gdb.Breakpoint):
 def __init__(self):super().__init__('*(unsigned long long*)'+hex(POINTER),type=gdb.BP_WATCHPOINT,wp_class=gdb.WP_WRITE,internal=True)
 def stop(self):
  try:log('pointer_write')
  except Exception as exc:fail(exc)
  return False
class SizeWatch(gdb.Breakpoint):
 def __init__(self):super().__init__('*(unsigned int*)'+hex(SIZE),type=gdb.BP_WATCHPOINT,wp_class=gdb.WP_WRITE,internal=True)
 def stop(self):
  try:log('size_write')
  except Exception as exc:fail(exc)
  return False
class FlagWatch(gdb.Breakpoint):
 def __init__(self):super().__init__('*(unsigned char*)'+hex(FLAG),type=gdb.BP_WATCHPOINT,wp_class=gdb.WP_WRITE,internal=True)
 def stop(self):
  try:
   value=number('*(unsigned char*)'+hex(FLAG))
   emit('flag_transition',writer=writer(),value=value,cycles=state.cycles)
   if value:summary('window_complete');state.entered=False
  except Exception as exc:fail(exc)
  return False
class ReallocBreak(gdb.Breakpoint):
 def stop(self):
  try:log('before_realloc',True)
  except Exception as exc:fail(exc)
  return False
class EntryBreak(gdb.Breakpoint):
 installed=False
 def stop(self):
  try:
   state.entered=True;state.cycles+=1;state.loader=writer()
   emit('regeneration_entry',loader=state.loader,cycle=state.cycles)
   if not self.installed:
    PointerWatch();SizeWatch();FlagWatch();ReallocBreak('*0x1cb7855',internal=True);self.installed=True
   # Confirm both watches really acquired hardware resources before proceeding.
   listing=gdb.execute('maintenance info breakpoints',to_string=True)
   if listing.lower().count('hw watchpoint')<3:raise RuntimeError('three hardware write watches not established')
  except Exception as exc:fail(exc)
  return False
try:
 EntryBreak('*0x1cb7900',internal=True)
 gdb.events.exited.connect(lambda event:summary('inferior_exit'))
 emit('armed',flag=hex(FLAG),pointer=hex(POINTER),quota='8 per loader kind / 4 per other writer kind; watches never disabled by quota')
except Exception as exc:fail(exc)
