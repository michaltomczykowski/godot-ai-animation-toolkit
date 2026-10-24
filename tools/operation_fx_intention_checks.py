"""Independent fixed-request FX intentions and observed case-local invariants.

Never derive expected samples from generated Animation keys. This deliberately
covers the existing public inner-history requests only, not arbitrary controls.
"""
from __future__ import annotations
import math
import re
from operation_history_checks import equivalent, verify_event as verify_history

CASES = {
 'shake':{'target_path':'Camera2D','seed':7},'zoom_punch':{'target_path':'Camera2D'},
 'hit_flash':{'target_path':'Flash'},'damage_bar':{'target_path':'DamageBar','to':30.0},
 'typewriter':{'target_path':'TypeLabel'},'progress_fill':{'target_path':'FillBar','to':100.0},
 'counter':{'target_path':'ScoreLabel','to':100.0},'dialog_pop':{'target_path':'DialogPanel'},
 'transition':{'target_path':'FadeOverlay','mode':'wipe_left'},
 'wave':{'target_paths':['Card1','Card2','Card3']},'spring':{'target_path':'SpringTarget','offset':{'x':0,'y':-60}},
 'pendulum':{'target_path':'PendulumTarget'},'path_follow':{'target_path':'Drone'},
 'flipbook':{'target_path':'Sprite2D','frames':4,'fps':4},
 'audio_cue':{'target_path':'CuePlayer','stream':'res://tests/fixtures/cue.wav'},
 'sprite_frames':{'texture':'res://tests/fixtures/sheet.png','hframes':4,'vframes':1,'play':False}}
DEPENDENCIES=('test_project/tests/fx_intention_probe.gd','test_project/tests/test_fx_route_history.gd',
 'tools/operation_fx_intention_checks.py','test_project/repair_fx_fixture.tscn',
 'test_project/tests/fixtures/sheet.png','test_project/tests/fixtures/cue.wav',
 'addons/godot_ai_animation/handlers/fx.gd','addons/godot_ai_animation/spec/fx_specs.gd',
 'addons/godot_ai_animation/spec/spec_io.gd')

def vector(x,y):return {'type':'Vector2','x':x,'y':y}
def color(r,g,b,a=1):return {'type':'Color','r':r,'g':g,'b':b,'a':a}
def near(actual,expected,tolerance=0.0001):
 if isinstance(expected,bool):return type(actual) is bool and actual==expected
 if isinstance(expected,(int,float)):
  return type(actual) in (int,float) and math.isfinite(actual) and abs(actual-expected)<=tolerance
 if isinstance(expected,dict):return isinstance(actual,dict) and actual.keys()==expected.keys() and all(near(actual[k],v,tolerance) for k,v in expected.items())
 return type(actual)==type(expected) and actual==expected


def expected_samples(op):
 # Constants come from authored fixture and fixed requests/defaults, not clip output.
 spring_half=-60*(1-math.exp(-.35*4*math.pi*.5)*math.cos(4*math.pi*math.sqrt(1-.35**2)*.5))
 return {
 'shake':[(.05,'Camera2D:position',None),(.4,'Camera2D:position',vector(0,0))],
 'zoom_punch':[(.075,'Camera2D:zoom',vector(1.08,1.08)),(.25,'Camera2D:zoom',vector(1,1))],
 'hit_flash':[(.09,'Flash:modulate',color(.25,.25,.25)),(.18,'Flash:modulate',color(1,1,1))],
 'damage_bar':[(.125,'DamageBar:value',80),(.65,'DamageBar:value',30)],
 'typewriter':[(0,'TypeLabel:visible_ratio',0),(1.5,'TypeLabel:visible_ratio',1)],
 'progress_fill':[(0,'FillBar:value',10),(.8,'FillBar:value',100)],
 'counter':[(.50001,'ScoreLabel:text','50')],
 'dialog_pop':[(0,'DialogPanel:scale',vector(.85,.85)),(.21,'DialogPanel:scale',vector(1.06,1.06)),(.35,'DialogPanel:scale',vector(1,1)),(0,'DialogPanel:modulate:a',0),(.21,'DialogPanel:modulate:a',1)],
 'transition':[(0,'FadeOverlay:scale',vector(0,0)),(.5,'FadeOverlay:scale',vector(1,1)),(.5,'FadeOverlay:pivot_offset',vector(640,180))],
 'wave':[(.3,f'Card{i+1}:position',vector(80*i,12*math.sin(2*math.pi*(.3/1.2+i*.12/1.2)))) for i in range(3)],
 'spring':[(0,'SpringTarget:position',vector(0,0)),(.5,'SpringTarget:position',vector(0,spring_half)),(1,'SpringTarget:position',vector(0,-60))],
 'pendulum':[(0,'PendulumTarget:rotation',math.pi/10),(.5,'PendulumTarget:rotation',-math.pi/10)],
 'path_follow':[(0,'Drone:position',vector(0,0)),(2,'Drone:position',vector(100,80))],
 'flipbook':[(0,'Sprite2D:frame',0),(.75,'Sprite2D:frame',3)],
 'audio_cue':[(.25,'CuePlayer:playing',True)]}[op]


def intention(row):
 op=row['op'];data=row.get('intention',{})
 if op=='sprite_frames':
  cells=data.get('cells',[])
  return (data.get('resource_class')=='SpriteFrames' and data.get('animation')=='generated' and data.get('playing') is False
   and near(data.get('fps'),12) and data.get('loop') is True and len(cells)==4
   and all(cell.get('class')=='AtlasTexture' and cell.get('atlas')=='res://tests/fixtures/sheet.png'
    and near(cell.get('size'),vector(16,16)) and isinstance(cell.get('region'),list) and len(cell['region'])==4
    and all(near(a,b) for a,b in zip(cell['region'],[16*i,0,16,16]))
    and near(cell.get('duration'),1) for i,cell in enumerate(cells)))
 samples=data.get('samples',[]);expected=expected_samples(op)
 if data.get('probe_mode')!='duplicate_generated_fixture_manual_player' or len(samples)!=len(expected):return False
 for sample,(at,path,value) in zip(samples,expected):
  if not near(sample.get('at'),at) or sample.get('path')!=path:return False
  actual=sample.get('actual')
  if op=='shake' and value is None:
   # Seeded noise is bounded/nonzero and settles exactly; no generator RNG echo.
   if not isinstance(actual,dict) or actual.get('type')!='Vector2' or not all(type(actual.get(k)) in (int,float) and math.isfinite(actual[k]) for k in ('x','y')):return False
   bound=8*.15**(.05/.4)
   if not 0<max(abs(actual['x']),abs(actual['y']))<=bound+.0001:return False
  elif not near(actual,value):return False
 if op=='audio_cue':
  tracks=row.get('generated',{}).get('clips',{}).get('generated',{}).get('tracks',[])
  return (len(tracks)==1 and tracks[0].get('path')=='CuePlayer' and tracks[0].get('type')==7
   and len(tracks[0].get('keys',[]))==1 and near(tracks[0]['keys'][0].get('time'),0)
   and tracks[0]['keys'][0].get('stream',{}).get('resource')=='res://tests/fixtures/cue.wav'
   and tracks[0]['keys'][0].get('stream',{}).get('class')=='AudioStreamWAV'
   and near(tracks[0]['keys'][0].get('start_offset'),0) and near(tracks[0]['keys'][0].get('end_offset'),0))
 return True


def counter_editor_pending(row):
 data=row.get('intention',{})
 if not isinstance(data,dict):return False
 samples=data.get('samples',[])
 if not isinstance(samples,list) or len(samples)!=1 or not isinstance(samples[0],dict):return False
 return (row.get('op')=='counter' and data.get('probe_mode')=='duplicate_generated_fixture_manual_player'
  and len(samples)==1 and near(samples[0].get('at'),.50001)
  and samples[0].get('path')=='ScoreLabel:text' and type(samples[0].get('actual')) is str
  and samples[0]['actual']=='0')


def request_matches(row):
 op=row.get('op');req=row.get('request',{});player=req.get('player_path','')
 if op not in CASES or not player.endswith('/FxHistory/AnimationPlayer'):return False
 fixed=dict(CASES[op],op=op,player_path=player,animation_name='generated',overwrite=row.get('mode')=='overwrite')
 fixture=player.removesuffix('/AnimationPlayer')
 if op=='path_follow':fixed['path_node']=fixture+'/PatrolPath'
 if op=='sprite_frames':fixed['sprite_path']=fixture+'/SheetSprite'
 return equivalent(req,fixed)


def derive(row):
 if not request_matches(row):raise ValueError('FX intention request differs from fixed public case')
 clean=row.get('failed_before') is False and row.get('failed_after') is False
 before=row.get('before',{});generated=row.get('generated',{})
 errors=(type(row.get('errors_before')) is int and row['errors_before']>=0 and type(row.get('errors_after')) is int and row.get('errors_after')==row['errors_before'] and row.get('errors')==[])
 targets=CASES[row['op']].get('target_paths',[CASES[row['op']].get('target_path','SheetSprite')])
 original=before.get('clips',{});current=generated.get('clips',{})
 source=(isinstance(original,dict) and isinstance(current,dict) and all(name in current and equivalent(clip,current[name]) for name,clip in original.items() if name!='generated')
  and bool(before.get('props')) and before['props'].keys()==generated.get('props',{}).keys()
  and all(equivalent(values,generated['props'][name]) for name,values in before['props'].items() if name not in targets)
  and equivalent(generated,row.get('after_probe'))
  and bool(before.get('path_points')) and equivalent(before.get('path_points'),generated.get('path_points'))
  and bool(before.get('player_state')) and equivalent(before.get('player_state'),generated.get('player_state')))
 inputs=row.get('input_files_before',{})
 source=source and set(inputs)=={'res://repair_fx_fixture.tscn','res://tests/fixtures/sheet.png','res://tests/fixtures/cue.wav'} and all(isinstance(v,str) and re.fullmatch('[0-9a-f]{64}',v) for v in inputs.values()) and inputs==row.get('input_files_after')
 if row['op']!='sprite_frames':source=source and all(equivalent(before.get(k),generated.get(k)) for k in ('frames','animation','playing'))
 if row.get('mode')=='instanced':
  digest=row.get('source_sha256_before','')
  source=source and re.fullmatch('[0-9a-f]{64}',digest) is not None and row.get('source_path')=='user://fx_history_source.tscn' and row.get('source_sha256_after')==digest and bool(row.get('peer_before')) and equivalent(row['peer_before'],row.get('peer_after')) and equivalent(before,row.get('pristine'))
 checks={k:'pass' if clean and v else 'fail' for k,v in [('valid_effect',False if row['op']=='counter' else intention(row)),('reported_errors',errors),('source_unchanged',source)]}
 if row['op']=='counter':checks['valid_effect']='pending' if clean and counter_editor_pending(row) else 'fail'
 return checks


def verify_event(event,context,begins,support):
 if any(path not in context.get('dependencies',{}) for path in DEPENDENCIES):raise ValueError('FX intention dependencies absent')
 if event.get('validator')!='fx_intention_history_v1':raise ValueError('unknown FX intention validator')
 proof=verify_history(dict(event,validator='fx_history_v1'),context,begins,support)
 start=next(x for x in begins if x.get('id')==event.get('test_run_begin_id'))
 end=next(x for x in support if x.get('id')==proof['public_test_run_case_id'])
 if not event['row'].get('scene') or event['row']['scene']!=start.get('scene') or start.get('scene')!=end.get('scene'):raise ValueError('FX scene does not match exact public span')
 if not start.get('time_ns',0)<event.get('time_ns',0)<end.get('time_ns',0):raise ValueError('FX assertion outside exact public time span')
 for path,digest in event['row'].get('input_files_before',{}).items():
  rel='test_project/'+path.removeprefix('res://')
  if digest!=context['dependencies'].get(rel,{}).get('sha256'):raise ValueError('FX fixed input hash differs from bound context')
 checks=derive(event['row'])
 if any(v=='fail' for v in proof['checks'].values()):checks={k:'fail' for k in checks}
 proof['checks'].update(checks)
 if event['row']['op']=='counter':
  from operation_fx_counter_native_checks import verify_native
  native=verify_native(event,context,support,end)
  prerequisites=all(value=='pass' for key,value in proof['checks'].items() if key!='valid_effect') and checks['valid_effect']=='pending'
  proof['checks'].update(native['checks'] if prerequisites else {'valid_effect':'fail','playback':'fail'})
  proof['counter_native']=native
 proof['limits']='Counter editor zero is pending because engine editor_hint suppresses method tracks; only exact saved native counter50 joins semantic/playback evidence. Fixed FX history requests only. Request-derived values sampled on duplicate generated fixture via manual Player; shake bounded noise/settle, SpriteFrames exact resource/cells, audio scheduled stream + playing event. Source covers unrelated clips/non-target whitelisted properties and instanced peer/pristine/packed source; not every Resource property. Case Logger covers synchronous work through cleanup, not future asynchronous errors or full editor session. No audible-output/visual/general-control approval.'
 return proof
