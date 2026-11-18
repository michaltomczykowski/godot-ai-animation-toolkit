"""Bracket each selected original read once; never retry its operation."""
import json,os
from pathlib import Path
from uuid import uuid4
from mcp_presets_audit import call
from operation_case_collector import sha
SUITE='remaining_read_witness'
def checked(result,test):
 rows=[r for r in result.get('results',[])if r.get('suite')==SUITE and r.get('test')==test]
 if len(rows)!=1 or rows[0].get('passed')is not True or rows[0].get('skipped',False)or type(rows[0].get('assertion_count'))is not int or rows[0]['assertion_count']<1:raise RuntimeError('remaining read witness did not execute: '+test)
async def witnessed_read(client,tool,request,scene,stage):
 context=os.environ.get('TOOLKIT_OPERATION_CONTEXT');directory=os.environ.get('TOOLKIT_OPERATION_TRACE_DIR')
 if not context and not directory:return await call(client,tool,request)
 if not context or not directory:raise RuntimeError('complete remaining read trace context required')
 family='animation_graph'if tool=='custom_animation_graph'else'animation_rig'
 if tool not in ('custom_animation_graph','custom_animation_rig')or family+'.'+request['op']not in ('animation_graph.graph_get','animation_rig.rig_get','animation_rig.pose_list')or stage not in ('valid','refusal'):raise ValueError('unsupported remaining read activation')
 marker={'token':uuid4().hex,'context_sha256':sha(context),'run_id':json.loads(Path(context).read_text())['run_id'],'operation':family+'.'+request['op'],'request':request,'scene':scene,'stage':stage}
 path=Path(directory)/'active-remaining-read.json'
 with path.open('x',encoding='utf-8')as f:json.dump(marker,f)
 began=False;primary=False
 try:
  began=True;checked(await call(client,'test_run',{'suite':SUITE,'test_name':'test_begin','verbose':True}),'test_begin')
  return await call(client,tool,request)
 except BaseException:
  primary=True;raise
 finally:
  try:
   if began:checked(await call(client,'test_run',{'suite':SUITE,'test_name':'test_end','verbose':True}),'test_end')
  except Exception:
   if not primary:raise
  finally:
   if path.exists()and json.loads(path.read_text()).get('token')==marker['token']:path.unlink()
