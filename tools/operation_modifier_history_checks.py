"""Exact modifier matrix inner cases plus independently configured native rows."""
import json,math,re
from operation_preset_history_checks import same
OPS={'ik_setup','spring_setup','look_at_setup','twist_setup','retarget_setup'}
def expected_class(row):
 if row['op']=='ik_setup':return {'two_bone':'TwoBoneIK3D','ccdik':'CCDIK3D','fabrik':'FABRIK3D','spline':'SplineIK3D'}.get(row['request'].get('kind','two_bone'))
 return {'spring_setup':'SpringBoneSimulator3D','look_at_setup':'LookAtModifier3D','twist_setup':'BoneTwistDisperser3D','retarget_setup':'RetargetModifier3D'}[row['op']]
def digest(v):return isinstance(v,str)and re.fullmatch('[0-9a-f]{64}',v)is not None
def number(v):return type(v)in(int,float)and math.isfinite(v)
def status(v):return 'pass'if v else'fail'
def property_same(a,b):
 # JSON.stringify serializes native Vector3 properties as parenthesized text.
 # Match the existing checker's Vector3.is_equal_approx, not string rounding.
 if isinstance(a,str)and isinstance(b,str)and re.fullmatch(r'\([-+0-9.eE, ]+\)',a)and re.fullmatch(r'\([-+0-9.eE, ]+\)',b):
  x=[float(v)for v in a[1:-1].split(',')];y=[float(v)for v in b[1:-1].split(',')]
  return len(x)==len(y)==3 and all(math.isfinite(i)and math.isfinite(j)and abs(i-j)<=.00001*max(1,abs(i))for i,j in zip(x,y))
 return same(a,b)
def derive(row):
 op=row.get('op');assert op in OPS
 clean=row.get('failed_before')is False and row.get('failed_after')is False
 if row.get('single_refusal'):
  v=row.get('versions',{});code=row.get('response',{}).get('error',{}).get('code');atomic=same(row.get('before'),row.get('after'))and v.get('before')==v.get('after')and v.get('global_before')==v.get('global_after')and row.get('orphans_before')==row.get('orphans_after');typed=clean and isinstance(code,str)and bool(code)and (not row.get('expected_code')or code==row['expected_code']);errors=row.get('errors')==[]and row.get('error_count_before')==row.get('error_count_after')
  return {k:status(ok)for k,ok in {'typed_errors':typed and atomic,'source_unchanged':clean and atomic,'reported_errors':clean and errors}.items()}
 v=row.get('versions',{});base=row.get('before');dry=row.get('dry',{});write=row.get('write',{});refusal=row.get('refusal')is True
 dry_ok=clean and same(base,row.get('after_dry'))and v.get('dry')==v.get('before')and v.get('global_dry')==v.get('global_before')and row.get('orphans_dry')==row.get('orphans_before')
 dry_ok=dry_ok and bool(dry.get('error',{}).get('code'))if refusal else dry_ok and dry.get('data',{}).get('dry_run')is True
 source=clean and same(row.get('peer_before'),row.get('peer_after'))and same(row.get('peer_before'),row.get('pristine'))and row.get('shared_resource_identity')is True
 for prefix in ('source','inner'):source=source and digest(row.get(prefix+'_hash_before'))and row[prefix+'_hash_before']==row.get(prefix+'_hash_after')
 source=source and v.get('global_after')==v.get('global_before')
 errors=clean and row.get('errors')==[]and row.get('errors_before')==row.get('errors_after')
 checks={'dry_run':status(dry_ok),'source_unchanged':status(source),'reported_errors':status(errors)}
 if refusal:
  atomic=same(base,row.get('generated'))and v.get('write')==v.get('before')and row.get('orphans_write')==row.get('orphans_before');checks['typed_errors']=status(clean and bool(write.get('error',{}).get('code'))and atomic);return checks
 history=clean and bool(write.get('data'))and row.get('undo_success')is True and row.get('redo_success')is True and same(base,row.get('undone'))and same(row.get('generated'),row.get('redone'))and not same(base,row.get('generated'))and same(row.get('identities_before'),row.get('identities_undo'))and type(row.get('modifier_identity_do'))is int and row['modifier_identity_do']>0 and row['modifier_identity_do']==row.get('modifier_identity_redo')and v.get('write')==v.get('before',0)+1 and v.get('global_write')==v.get('global_before')
 saved=clean
 for stage,expected in [('do',row.get('generated')),('undo',base),('redo',row.get('redone'))]:
  p=row.get('persisted',{}).get(row.get('id','')+'_'+stage,{})
  saved=saved and p.get('path')=='user://modifier_history_'+row.get('id','')+'_'+stage+'.tscn'and digest(p.get('sha256'))and p.get('pack_result')==0 and p.get('save_result')==0 and same(p.get('snapshot'),expected)
 checks.update(undo_redo=status(history),save_reopen=status(saved));return checks

def native_checks(row,event,context):
 checks={'playback':'fail','valid_effect':'fail'};cmd=event.get('command',[])
 if event.get('scene')!='user://rig_modifier_history.json'or event.get('route')!='native_godot'or not cmd or cmd[0]!=context.get('engine_command'):raise ValueError('modifier native identity differs')
 try:script=cmd[cmd.index('--script')+1]
 except(ValueError,IndexError):raise ValueError('modifier native script missing')
 if script!='res://tools/check_rig_modifier_history.gd'or len(cmd)!=6 or cmd[1:3]!=['--headless','--path']or cmd[4]!='--script':raise ValueError('native matrix filters/command changes not permitted')
 raw=event.get('stdout','')+'\n'+event.get('stderr','');prefix='RIG_MODIFIER_HISTORY_RUNTIME=';payload=[x[len(prefix):]for x in event.get('stdout','').splitlines()if x.startswith(prefix)]
 if event.get('returncode')!=0 or 'ERROR:'in raw or len(payload)!=1:return checks
 report=json.loads(payload[0]);selected=[x for x in report.get('rows',[])if x.get('id')==row['id']];expected={(state,fps,native)for fps in (30,60,120)for state,native in [('do',False),('undo',False),('redo',False),('do',True)]}
 if len(selected)!=12 or {(x.get('state'),x.get('fps'),x.get('native'))for x in selected}!=expected:return checks
 valid=row.get('modifier_class')==expected_class(row)
 for x in selected:
  p=row['persisted'][row['id']+'_'+x['state']];valid=valid and x.get('op')==row['op']and same(x.get('params'),row['request'])and x.get('scene')==p['path']and x.get('scene_sha256')==p['sha256']and x.get('case_failures')==[]and x.get('case_engine_errors')==[]and number(x.get('samples'))and x['samples']>=1
  if x['state']!='undo':valid=valid and x.get('influences')==[0,.5,1]and number(x.get('influence_error'))and x['influence_error']<.001 and x.get('influence_contract')==('source_rest'if row['op']=='retarget_setup'else'pose_blend')
  if x['native']:
   props=x.get('native_requested_properties',{});saved=props.get('saved',{});native=props.get('independent_native',{});keys=[k for k in native if '/joints/'not in k and not k.endswith('/joint_count')];valid=valid and bool(keys)and all(k in saved and property_same(saved[k],native[k])for k in keys)
 pairs=[x for x in report.get('comparisons',[])if x.get('id')==row['id']];parity=len(pairs)==3 and {x.get('fps')for x in pairs}=={30,60,120}
 parity=parity and all(x.get('op')==row['op']and same(x.get('params'),row['request'])and number(x.get('native_reference_error'))and x['native_reference_error']<.001 and number(x.get('redo_error'))and x['redo_error']<.001 and all(x.get('states',{}).get(stage)==row['persisted'][row['id']+'_'+stage]['path']for stage in ('do','undo','redo'))for x in pairs)
 checks['playback']=status(valid);checks['valid_effect']=status(valid and parity);return checks

def verify_event(event,context,begins,support):
 deps=context.get('dependencies',{})
 for path in ['test_project/tests/test_rig_modifier_history.gd','test_project/tests/operation_history_trace.gd','tools/operation_modifier_history_checks.py','tools/operation_preset_history_checks.py','test_project/tools/check_rig_modifier_history.gd','test_project/tools/modifier_native_reference.gd','tools/mcp_rig_modifier_history.py','tools/mcp_presets_audit.py']:
  if path not in deps:raise ValueError('modifier dependency missing: '+path)
 row=event.get('row',{});op=row.get('op');test=row.get('test');mode=row.get('mode');variant=row.get('variant')
 if event.get('validator')!='rig_modifier_history_v1'or event.get('driver')!='test_rig_modifier_history.gd'or event.get('route')!='public_test_run_inner_dispatch'or row.get('suite')!='rig_modifier_history'or op not in OPS or event.get('operation')!='animation_rig_modifiers.'+op or row.get('request',{}).get('op')!=op:raise ValueError('modifier operation identity mismatch')
 expected_test='test_predictable_refusals'if row.get('single_refusal')else'test_dummy_history'if variant=='dummy'else'test_nested_history'if str(mode).startswith('nested_')else'test_'+op.replace('_setup','')+'_variants'if variant!='base'else'test_'+str(mode)+'_history'
 if test!=expected_test or mode not in {'local','editable','locked','nested_00','nested_01','nested_10','nested_11'}:raise ValueError('modifier test/layout identity mismatch')
 if not row.get('single_refusal')and row.get('id')!=mode+'_'+op+'_'+variant:raise ValueError('modifier exact case ID mismatch')
 begin=event.get('test_run_begin_id');starts=[x for x in begins if x.get('id')==begin];ends=[x for x in support if x.get('public_tool')=='test_run'and x.get('test_run_begin_id')==begin]
 if len(starts)!=1 or len(ends)!=1:raise ValueError('modifier exact public test span missing')
 start,end=starts[0],ends[0]
 if start.get('request')!=end.get('request')or start.get('request')!={'suite':'rig_modifier_history','verbose':True}or start.get('execution_ns',0)>=end.get('execution_ns',0):raise ValueError('modifier public span request/order differs')
 checks=derive(row)
 if not row.get('refusal'):
  natives=[x for x in support if x.get('kind')=='native_saved_output'and x.get('operation')==event['operation']and x.get('execution_ns',0)>end['execution_ns']and 'res://tools/check_rig_modifier_history.gd'in x.get('command',[])]
  if len(natives)==1:checks.update(native_checks(row,natives[0],context))
 tests=[x for x in end.get('response',{}).get('results',[])if x.get('suite')==row['suite']and x.get('test')==test]
 if len(tests)!=1 or tests[0].get('passed')is not True or tests[0].get('skipped',False)or tests[0].get('assertion_count',0)<row.get('assertion_count',1):checks={k:'fail'for k in checks}
 return {'checks':checks,'public_test_run_case_id':end['id'],'limits':'Exact inner modifier matrix cases and optional source-bound saved/native-reference per-case30/60/120FPS rows. Stacks/live restart/visuals/external invocation remain separate; no suite-total promotion. Missing native batch leaves playback/intended pending; no generic effect flag.'}
