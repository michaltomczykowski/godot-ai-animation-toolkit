"""Independent setup mutation mask, atomic refusal and case-local Logger evidence."""
from copy import deepcopy
from operation_setup_history_checks import complete, equal, semantic, require

GROUNDING='res://addons/godot_ai_animation/runtime/setup_grounding.gd'
ADDED={'AnimationTree':'AnimationTree','Dummy/Skeleton3D/SetupGrounding':'SkeletonModifier3D'}
PLAYER='AnimationPlayer'
SKELETON='Dummy/Skeleton3D'
LIMITS=('Source preservation covers native stored properties/resources/bones, existing clip data and observed file hashes outside the fixed setup authoring mask; not imported-scene editable-instance flags absent from this snapshot. '
        'Logger proof is synchronous and case-local around the existing refusal and dry/write authoring calls, not the entire editor session or later save/history/asynchronous work. No effect/playback/visual promotion.')


def projection(row, after):
 state=deepcopy(row['stored']);nodes=state['nodes']
 if after:
  for path,kind in ADDED.items():
   require(nodes.get(path,{}).get('class')==kind,'expected setup-owned node absent/type differs')
   del nodes[path]
  nodes['.']['children']=[x for x in nodes['.']['children']if x!='AnimationTree']
  nodes[SKELETON]['children']=[x for x in nodes[SKELETON]['children']if x!='SetupGrounding']
 player=nodes[PLAYER]
 for key in ('libraries','root_motion_track','root_motion_local'):player['properties'].pop(key,None)
 for key in ('libraries','clips'):player.pop(key,None)
 return state


def source_preserved(rows,context):
 before=rows['before'];require(complete(before),'incomplete source observation')
 base=before['stored'];nodes=base['nodes']
 require(not(set(ADDED)&set(nodes)),'setup mask requires fresh scene')
 require(before['clips']=={} and nodes[PLAYER].get('libraries')=={} and nodes[PLAYER].get('clips')=={},'setup source mask requires empty root player')
 expected={'idle','walk','run','jump','turn_left'}
 projected=projection(before,False);baseline=semantic(projected)
 for phase in ('after_write','redone','persisted'):
  row=rows[phase];require(complete(row),'incomplete written source observation')
  state=row['stored'];require(set(state['nodes'])==set(nodes)|set(ADDED),'unexpected added/removed node')
  require(set(row['clips'])==expected,'generated clip set differs from fixed setup request')
  props=state['nodes'][PLAYER]['properties']
  require(props.get('root_motion_track')=={'type':'NodePath','value':'Dummy:position'} and props.get('root_motion_local')is True,'root motion ownership differs')
  require(equal(semantic(projection(row,True)),baseline),'non-target stored source differs')
  if phase!='persisted':
   require(all(state['nodes'][p]['id']==n['id']for p,n in nodes.items()),'existing source node replaced')
  oldfiles={k:v for k,v in base['files'].items()if k!=base['scene']}
  files={k:v for k,v in state['files'].items()if k!=base['scene']}
  require(set(files) in (set(oldfiles),set(oldfiles)|{GROUNDING}),'unexpected external/toolkit file added')
  require(all(files.get(k)==v for k,v in oldfiles.items()),'existing external/toolkit file changed')
  if GROUNDING in files:
   require(files[GROUNDING]==context['dependencies'][GROUNDING.removeprefix('res://')]['sha256'],'grounding script file differs from source')
  if phase!='persisted':require(state['files'].get(base['scene'])==base['files'][base['scene']],'source scene written before explicit save')
 return True


def logger_clean(rows,first,last):
 start=rows[first].get('error_boundary');end=rows[last].get('error_observation')
 if start is None and end is None:return None
 token=rows[first]['marker']['token']
 require(isinstance(start,dict)and isinstance(end,dict),'missing Logger boundary')
 require(start.get('complete')is True and end.get('complete')is True and start.get('token')==end.get('token')==token and start.get('begin_phase')==end.get('begin_phase')==first and end.get('end_phase')==last,'Logger scope mismatch')
 require(type(end.get('errors_before'))is int and type(end.get('errors_after'))is int and isinstance(end.get('errors'),list)and end['errors_before']==0 and end['errors_after']==len(end['errors']),'incomplete Logger entries/counts')
 for entry in end['errors']:
  require(isinstance(entry,dict)and {'function','file','line','code','message','type'}<=set(entry),'malformed raw Logger entry')
 return not end['errors']


def verify_extra(rows,spans,public,context):
 checks={k:'pending'for k in ('source_unchanged','reported_errors','typed_errors')};ids=[]
 # A failed exact predicate is explicit failure, never hidden by other green checks.
 try:source_preserved(rows,context);checks['source_unchanged']='pass'
 except (ValueError,KeyError,TypeError):checks['source_unchanged']='fail'
 if 'before_refusal'not in rows and 'after_refusal'not in rows:return checks,ids
 require('before_refusal'in rows and 'after_refusal'in rows,'partial refusal snapshots')
 before,after=rows['before_refusal'],rows['after_refusal'];marker=before['marker'];scene=marker['scene']
 wanted=dict(marker['request'],speed=8.,run_speed=10.)
 calls=[p for p in public if p.get('operation')=='animation_motion.character_setup'and p.get('driver')=='mcp_motion_setup_secondary.py'and p.get('scene')==scene and p.get('params')==wanted and p.get('route')=='public_godot_ai']
 require(len(calls)==1,'requires exact original unreachable setup call')
 call=calls[0];ids.append(call['id'])
 require(spans['before_refusal'][1]['execution_ns']<call['execution_ns']<spans['after_refusal'][0]['execution_ns']and spans['after_refusal'][1]['execution_ns']<spans['before'][0]['execution_ns'],'refusal observation/public order mismatch')
 error=call.get('response',{}).get('error')
 if isinstance(error,str):code,_,message=error.partition(': ')
 elif isinstance(error,dict):code,message=error.get('code'),error.get('message')
 else:code,message=None,None
 atomic=(complete(before)and complete(after)and equal(before['stored'],after['stored'])and equal(before['clips'],after['clips']))
 typed=code=='VALUE_OUT_OF_RANGE'and isinstance(message,str)and 'reachable'in message.lower()
 checks['typed_errors']='pass'if atomic and typed else'fail'
 scopes=[logger_clean(rows,'before_refusal','after_refusal'),logger_clean(rows,'before','after_write')]
 if all(x is not None for x in scopes):checks['reported_errors']='pass'if all(scopes)else'fail'
 return checks,ids
