"""Observe one existing external setup transaction; never repeat its write."""
import hashlib,json,os,re
from pathlib import Path
from uuid import uuid4
from mcp_presets_audit import call

SUITE='animation_motion'
class SetupWitness:
 def __init__(self,client,scene,request,project):
  self.client,self.scene,self.request,self.project=client,scene,request,Path(project)
  self.context=os.environ.get('TOOLKIT_OPERATION_CONTEXT');self.directory=os.environ.get('TOOLKIT_OPERATION_TRACE_DIR')
  if bool(self.context)!=bool(self.directory):raise ValueError('setup witness requires complete trace context')
  self.enabled=bool(self.context);self.path=None;self.marker=None
 def prepare(self,target):
  if not self.enabled:return
  text=Path(target).read_text(encoding='utf-8-sig');root=self.request['player_path'].strip('/').split('/')[0]
  player=self.request['player_path'].removeprefix('/'+root+'/')
  block=re.search(r'(?ms)^\[node name="'+re.escape(player)+r'"[^\n]*\].*?(?=^\[node|\Z)',text)
  if not block:raise ValueError('setup fixture player missing')
  binding=re.search(r'root_motion_track = NodePath\("([^"\n]*)"\)',block.group())
  names=['idle','walk','run']+(['jump']if self.request.get('include_jump',True)else[])+(['turn_left']if self.request.get('include_turn',False)else[])
  with Path(target).open('a',encoding='utf-8')as f:
   f.write('\n[node name="PublicSetupBundleHistory" type="Node" parent="."]\nmetadata/player_path = NodePath('+json.dumps(player)+')\nmetadata/tree_path = NodePath("AnimationTree")\nmetadata/before_root_motion_track = NodePath('+json.dumps(binding.group(1)if binding else'')+')\nmetadata/clip_names = PackedStringArray('+', '.join(json.dumps(n)for n in names)+')\n')
 async def snapshot(self,phase):
  if not self.enabled:return None
  if self.path is None:
   self.path=Path(self.directory)/'active-setup-history.json';self.marker={'token':uuid4().hex,'context_sha256':hashlib.sha256(Path(self.context).read_bytes()).hexdigest(),'run_id':json.loads(Path(self.context).read_text())['run_id'],'operation':'animation_motion.character_setup','scene':self.scene,'request':self.request,'phase':phase}
   with self.path.open('x',encoding='utf-8')as f:json.dump(self.marker,f)
  else:
   if not self.path.is_file()or json.loads(self.path.read_text()).get('token')!=self.marker['token']:raise RuntimeError('setup marker ownership changed')
   self.marker['phase']=phase;self.path.write_text(json.dumps(self.marker),encoding='utf-8')
  return await self.helper('test_public_setup_evidence_snapshot')
 async def helper(self,test):
  result=await call(self.client,'test_run',{'suite':SUITE,'test_name':test,'verbose':True})
  rows=[r for r in result.get('results',[])if r.get('suite')==SUITE and r.get('test')==test]
  if len(rows)!=1 or rows[0].get('passed')is not True or rows[0].get('skipped',False)or type(rows[0].get('assertion_count'))is not int or rows[0]['assertion_count']<1:raise RuntimeError('setup observer did not execute: '+test)
  return result
 async def checkpoint(self):
  if not self.enabled:return None
  history=await self.helper('test_public_setup_bundle_undo_redo')
  saved=await call(self.client,'scene_save',{})
  if saved.get('error'):raise RuntimeError('setup-only save failed')
  source=self.project/self.scene.removeprefix('res://');archive=source.with_name(source.stem+'-setup-only.tscn')
  with archive.open('xb')as f:f.write(source.read_bytes())
  reopened=await call(self.client,'scene_open',{'path':self.scene,'force_reload':True})
  if reopened.get('error'):raise RuntimeError('setup-only forced reopen failed')
  await self.snapshot('persisted')
  result={'history':history,'save':saved,'reopen':reopened,'scene_copy':str(archive),'scene_sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'stage':'before_secondary_motion'}
  self.close();return result
 def close(self):
  if self.path is not None:
   # Only remove this instance's marker; no other observer's active state.
   value=json.loads(self.path.read_text())if self.path.exists()else{}
   if value.get('token')==self.marker['token']:self.path.unlink()
   self.path=None
