"""Independent20edit native intention and actual track/path/type evidence."""
import json
import math
import re

SIMPLE={'retime':[0,50,100],'reverse':[100,50,0],'mirror':[0,-50,-100],
 'trim':[20,50,80],'amplitude':[0,25,50],'resample':[0,50,100],'layer':[0,90,180],
 'offset':[0,40,100],'loop':[0,50,100],'key_edit':[0,15,100],'overlap':[0,45,100]}
REMAINING={
 'retarget':[('walk',.5,'OtherCharacter','x',50),('walk',.5,'Character','x',0)],
 'ease_range':[('walk',.25,'Character','x',6.25),('walk',.5,'Character','x',25)],
 'set_interp':[('walk',.25,'Character','x',0),('walk',.75,'Character','x',0)],
 'split_at':[('walk_head',0,'Character','x',0),('walk_head',.25,'Character','x',25),('walk',0,'Character','x',50),('walk',.25,'Character','x',75)],
 'merge':[('walk_run',.5,'Character','x',50),('walk_run',1.5,'Character','x',100)],
 'cleanup':[('idle',0,'Character','x',0),('idle',.5,'Character','x',0)],
 'smooth':[('jump',0,'Character','y',-20),('jump',.5,'Character','y',-40)],
 'reduce':[('walk',.25,'Character','x',25),('walk',.75,'Character','x',75)],
 'add_noise':[('walk',0,'Character','x',-.9593609),('walk',0,'Character','y',-.5208515)]}
OPS=set(SIMPLE)|set(REMAINING)
REQUESTS={'retime':{'factor':.5},'reverse':{},'mirror':{'axis':'x'},'trim':{'from':.2,'to':.8},'amplitude':{'factor':.5},'resample':{'fps':30,'interpolation':'linear'},'layer':{'source_animation':'run','layer_mode':'add','weight':.4},'offset':{'delta':.2,'wrap':False},'loop':{'loop_mode':'pingpong'},'key_edit':{'action':'add','track_path':'Character:position','time':.5,'value':{'x':15,'y':0}},'overlap':{'track_path':'Character:position','delay':.1,'wrap':False},'retarget':{'from_path':'Character','to_path':'OtherCharacter'},'ease_range':{'from':0,'to':1,'transition':2},'set_interp':{'interpolation':'nearest'},'split_at':{'time':.5,'head_name':'walk_head'},'merge':{'sources':[{'animation_name':'walk'},{'animation_name':'run'}],'new_name':'walk_run'},'cleanup':{},'smooth':{'strength':.5,'passes':1},'reduce':{'value_tolerance':.01},'add_noise':{'amount':2,'frequency':2,'seed':42}}
DEPENDENCIES=('tools/operation_edit_native_checks.py','tools/mcp_edit_audit.py','tools/ci_mcp_route.py','tools/fixture_copy.py','tools/mcp_presets_audit.py','test_project/tools/edit_native_evidence.gd','test_project/repair_edit_fixture.tscn','addons/godot_ai_animation/handlers/edit.gd','addons/godot_ai_animation/spec/spec_modifiers.gd','addons/godot_ai_animation/spec/quality_modifiers.gd')


def number(v):return type(v) in (int,float) and math.isfinite(v)
def digest(v):return isinstance(v,str) and re.fullmatch('[0-9a-f]{64}',v) is not None
def equal(a,b):
    if isinstance(a,bool) or isinstance(b,bool):return type(a) is type(b) and a==b
    if number(a) and number(b):return a==b
    if type(a) is not type(b):return False
    if isinstance(a,dict):return a.keys()==b.keys() and all(equal(a[k],b[k]) for k in a)
    if isinstance(a,list):return len(a)==len(b) and all(equal(x,y) for x,y in zip(a,b))
    return a==b

def source_clip(op):return 'idle' if op=='cleanup' else 'jump' if op=='smooth' else 'walk'
def checker(op):return 'check_edit_runtime.gd' if op in SIMPLE else 'check_edit_remaining_runtime.gd'
def origin_matches(event,call):
    op=event.get('operation','').removeprefix('animation_edit.')
    if op not in OPS or call.get('driver')!='mcp_edit_audit.py' or call.get('route')!='public_godot_ai' or call.get('operation')!=event.get('operation') or call.get('scene')!=event.get('scene'):return False
    expected=dict(REQUESTS[op],op=op,player_path='/RepairGraphFixture/AnimationPlayer',animation_name=source_clip(op))
    return equal(call.get('params'),expected)


def intended(op,length):
    if op in SIMPLE:return [('walk',t,'Character','x',v) for t,v in zip((0,length*.5,length-.0001),SIMPLE[op])]
    return REMAINING[op]


def derive(report,op,fixture_sha256):
    raw=report.get('raw',{});clips=raw.get('clips',{})
    required_length={'retime':.5,'trim':.6,'offset':1.2,'overlap':1.1}
    length=report.get('length',1.0)
    fixed_length=required_length.get(op,1.0)
    observations=report.get('observations') if op in SIMPLE else report.get('samples')
    expected=intended(op,fixed_length)
    clean=report.get('engine_errors')==[] and isinstance(report.get('engine_errors'),list) and raw.get('schema')=='edit_native_intention_v1' and raw.get('fixture_sha256')==fixture_sha256 and digest(raw.get('scene_sha256')) and raw.get('fixture_class')=='Node2D' and raw.get('player_class')=='AnimationPlayer' and raw.get('player_path')=='AnimationPlayer' and raw.get('root_node')=='..' and raw.get('root_resolves_fixture') is True and raw.get('clock')=='native_seek_advance_zero'
    valid=clean and isinstance(observations,list) and len(observations)==len(expected)
    if op in SIMPLE:valid=valid and number(length) and abs(length-fixed_length)<1e-6
    limit=1.0 if op in SIMPLE else .25
    worst=0
    if valid:
        for actual,(clip,t,node,axis,want) in zip(observations,expected):
            valid=valid and (actual.get('clip'),actual.get('node'),actual.get('axis'))==(clip,node,axis) and number(actual.get('time')) and abs(actual['time']-t)<1e-6 and actual.get('assigned_animation')==clip and number(actual.get('player_position')) and abs(actual['player_position']-t)<1e-6 and number(actual.get('measured'))
            if not valid:break
            error=abs(actual['measured']-want);worst=max(worst,error)
            valid=valid and error<limit
    valid=valid and number(report.get('worst_error')) and abs(report['worst_error']-worst)<1e-5 and report['worst_error']<limit
    names={x[0] for x in expected};paths=clean and isinstance(clips,dict) and set(clips)==names
    for name in names:
        meta=clips.get(name,{});tracks=meta.get('tracks',[])
        wantlength=.5 if op=='split_at' else 2.0 if op=='merge' else fixed_length
        paths=paths and number(meta.get('length')) and abs(meta['length']-wantlength)<1e-6 and isinstance(tracks,list) and len(tracks)==1
        for track in tracks:
            path='OtherCharacter:position' if op=='retarget' else 'Character:position'
            paths=paths and track.get('path')==path and type(track.get('type')) is int and track['type']==0 and track.get('enabled') is True and track.get('node_resolved') is True and track.get('node_class')=='Node2D' and track.get('property')=='position' and type(track.get('property_type')) is int and track['property_type']==5 and type(track.get('key_count')) is int and track['key_count']>0 and len(track.get('key_times',[]))==track['key_count'] and all(number(x) for x in track['key_times'])
            if op=='set_interp':paths=paths and type(track.get('interpolation')) is int and track.get('interpolation')==0 and track.get('key_times')==[0,1]
            if op=='cleanup':paths=paths and track.get('key_count')==1 and len(track.get('key_times',[]))==1 and 0<=track['key_times'][0]<=meta['length']
            if op=='reduce':paths=paths and track.get('key_count')==2 and track.get('key_times')==[0,1]
            if op in ('resample','add_noise'):paths=paths and track.get('key_count')==31 and abs(track['key_times'][0])<1e-6 and abs(track['key_times'][-1]-1)<1e-6
            if op=='loop':paths=paths and meta.get('loop_mode')==2
    checks={'valid_effect':'pass' if valid and paths else 'fail','playback':'pass' if valid and paths else 'fail','track_paths_types':'pass' if paths else 'fail','reported_errors':'pass' if clean else 'fail'}
    return checks


def verify_native(event,context):
    op=event.get('operation','').removeprefix('animation_edit.')
    if op not in OPS:raise ValueError('unknown edit operation')
    source='test_project/tools/'+checker(op)
    for path in (*DEPENDENCIES,source):
        identity=context.get('dependencies',{}).get(path,{})
        if not digest(identity.get('sha256')) or re.fullmatch('[0-9a-f]{40}',str(identity.get('git_blob',''))) is None:raise ValueError('unbound edit native source '+path)
    command=event.get('command',[])
    try:script=command[command.index('--script')+1];args=command[command.index('--')+1:]
    except (ValueError,IndexError):raise ValueError('native command missing explicit checker arguments')
    if not command or command[0]!=context.get('engine_command') or script!='res://tools/'+checker(op) or args!=[event.get('scene'),op] or event.get('driver')!='ci_mcp_route.py' or event.get('route')!='native_godot':raise ValueError('edit native command/driver identity differs')
    prefix='EDIT_RUNTIME=' if op in SIMPLE else 'EDIT_REMAINING='
    rows=[line[len(prefix):] for line in event.get('stdout','').splitlines() if line.startswith(prefix)]
    report=json.loads(rows[0]) if len(rows)==1 else {}
    if report.get('op')!=op or report.get('scene')!=event.get('scene'):raise ValueError('edit native output operation/scene differs')
    checks=derive(report,op,context['dependencies']['test_project/repair_edit_fixture.tscn']['sha256'])
    failures=[]
    if type(event.get('returncode')) is not int or event['returncode']!=0 or 'ERROR:' in event.get('stdout','')+event.get('stderr',''):
        checks={k:'fail' for k in checks};failures.append('native exit or engine error')
    if any(v=='fail' for v in checks.values()):failures.append('independent native intention/path/type predicate failed')
    return checks,failures
