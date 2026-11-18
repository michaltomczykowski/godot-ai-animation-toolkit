"""Bracket an existing public read once; support calls do not retry the operator."""
import json
import os
from pathlib import Path
import uuid
from mcp_presets_audit import call
from operation_case_collector import sha

SUITE='inspect_read_witness'

def checked_helper(result,test):
 matches=[r for r in result.get('results',[]) if r.get('suite')==SUITE and r.get('test')==test]
 if len(matches)!=1 or matches[0].get('passed') is not True or matches[0].get('skipped',False) or type(matches[0].get('assertion_count')) is not int or matches[0]['assertion_count']<1:
  raise RuntimeError('read witness helper did not execute: '+test)

async def witnessed_call(client,request,scene,stage):
 context=os.environ.get('TOOLKIT_OPERATION_CONTEXT');directory=os.environ.get('TOOLKIT_OPERATION_TRACE_DIR')
 if not context and not directory:return await call(client,'custom_animation_inspect',request),None
 if not context or not directory:raise RuntimeError('read witness requires the complete operation trace context')
 token=uuid.uuid4().hex;path=Path(directory)/'active-inspect-read.json'
 marker={'token':token,'context_sha256':sha(context),'run_id':json.loads(Path(context).read_text())['run_id'],
         'operation':'animation_inspect.'+request['op'],'request':request,'scene':scene,'stage':stage}
 with path.open('x',encoding='utf-8') as file:json.dump(marker,file)
 began=False;primary=False
 try:
  began=True
  checked_helper(await call(client,'test_run',{'suite':SUITE,'test_name':'test_begin','verbose':True}),'test_begin')
  return await call(client,'custom_animation_inspect',request),token
 except BaseException:
  primary=True
  raise
 finally:
  try:
   if began:checked_helper(await call(client,'test_run',{'suite':SUITE,'test_name':'test_end','verbose':True}),'test_end')
  except Exception:
   if not primary:raise
  finally:path.unlink()
