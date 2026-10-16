"""Exact preset/library apply inner-history proofs; no suite-total inference."""
import copy
import math
import re


def same(a,b):
    if isinstance(a,bool) or isinstance(b,bool): return type(a) is bool and type(b) is bool and a==b
    if isinstance(a,(int,float)) and isinstance(b,(int,float)): return math.isfinite(a) and math.isfinite(b) and abs(a-b)<.00001
    if isinstance(a,dict) and isinstance(b,dict): return a.keys()==b.keys() and all(same(a[k],b[k]) for k in a)
    if isinstance(a,list) and isinstance(b,list): return len(a)==len(b) and all(same(x,y) for x,y in zip(a,b))
    return type(a) is type(b) and a==b

def vector(kind,*values): return dict(type=kind,**dict(zip(('r','g','b','a') if kind=='Color' else ('x','y','z','w'),values)))
V2=lambda *v:vector('Vector2',*v)
V3=lambda *v:vector('Vector3',*v)
Q=vector('Quaternion',0,math.sqrt(.5),0,math.sqrt(.5))
EXPECTED={
 'pulse':[(.5,'Target3D','scale',V3(1.4,1.4,1.4))],
 'bounce':[(.35,'Widget','scale',V2(2.4,2.4))],
 'template_preset':[(.35,'Widget','scale',V2(2.4,2.4))],
 'orbit':[(.25,'Target3D','position',V3(2,3,6))],
 'sweep':[(.25,'Widget','rotation',math.pi/2)],
 'drift':[(.5,'Target3D','position',V3(4,3,4))],
 'spin':[(.25,'Target3D','quaternion',Q)],
 'float':[(.5,'Target3D','position',V3(2,4,4)),(.5,'Target3D','scale',V3(1.25,1.25,1.25))],
 'stagger':[(.5,'Widget','modulate:a',.75),(.5,'OtherWidget','modulate:a',.51)],
 'template_fx':[(.5,'Widget','modulate',vector('Color',1,0,0,1))],
 'spec_apply':[(.5,'Widget','position:x',20)],
 'showcase':[(.14,'ReviewShowcase/BounceButton','scale',V2(1.15,1.15)),(.75,'ReviewShowcase/OrbitDot','position',V2(900,210)),(.5,'ReviewShowcase/SweepPivot','rotation',math.pi/2),(1,'ReviewShowcase/DriftLine','position:x',860),(.6,'ReviewShowcase/PulseLabel','modulate:a',1),(1.2,'ReviewShowcase/World3D/FloatCube','position:y',.35),(.75,'ReviewShowcase/World3D/SpinCube','quaternion',Q)]}

def digest(value): return isinstance(value,str) and re.fullmatch('[0-9a-f]{64}',value) is not None

def derive(row):
    required={'request','dry','invalid_request','invalid','write','before','after_dry','after_error','generated','undone','redone','versions','undo_success','redo_success','persist_undo','persist_redo','failed_before','failed_after','assertion_count','recipe_path','recipe_sha256_before','recipe_sha256_after','errors_before','errors_after','errors'}
    if not required<=row.keys(): raise ValueError('preset case lacks exact raw stages')
    variant=row['variant'];before=row['before'];generated=row['generated'];v=row['versions']
    clean=row['failed_before'] is False and row['failed_after'] is False and type(row['assertion_count']) is int and row['assertion_count']>=19
    dry=clean and row['dry'].get('data',{}).get('dry_run') is True and not row['dry'].get('error') and same(before,row['after_dry']) and v.get('dry')==v.get('before') and v.get('global_dry')==v.get('global_before')
    invalid=dict(row['request'],**({'parent_path':'/Missing'} if variant=='showcase' else {'player_path':'/Missing'}))
    error=row['invalid'].get('error',{})
    typed=clean and same(invalid,row['invalid_request']) and error.get('code')=='NODE_NOT_FOUND' and bool(error.get('message')) and same(before,row['after_error']) and v.get('error')==v.get('before') and v.get('global_error')==v.get('global_before')
    history=clean and 'data' in row['write'] and not row['write'].get('error') and row['write']['data'].get('undoable') is True and not same(before,generated) and row['undo_success'] is True and row['redo_success'] is True and same(before,row['undone']) and same(generated,row['redone']) and v.get('write')==v.get('before',-2)+1 and v.get('global_write')==v.get('global_before')
    if variant!='showcase':
        identity=row.get('original_library_id');clips=row.get('original_clip_ids')
        identities_valid=(identity==0 and clips=={}) if row['mode']=='missing_library' else (type(identity) is int and identity!=0 and isinstance(clips,dict) and bool(clips) and all(type(value) is int and value!=0 for value in clips.values()))
        history=history and identities_valid and identity==row.get('undo_library_id') and clips==row.get('undo_clip_ids')
    def persisted(value,expected,stage):
        label=('showcase_'+row['mode']) if variant=='showcase' else row['mode']+'_'+variant
        return value.get('path')=='user://preset_library_history_'+label+'_'+stage+'.tscn' and digest(value.get('sha256')) and value.get('pack_result')==0 and value.get('save_result')==0 and value.get('fixture_found') is True and same(value.get('snapshot'),expected)
    saved=clean and persisted(row['persist_undo'],before,'undo') and persisted(row['persist_redo'],generated,'redo')
    recipe=row['recipe_path']=='res://animation_toolkit/history_phase_library.json' and digest(row['recipe_sha256_before']) and row['recipe_sha256_before']==row['recipe_sha256_after']
    if variant=='showcase':
        unchanged=copy.deepcopy(generated);unchanged.get('children',{}).pop('ReviewShowcase',None)
        source=same(unchanged,before)
    else:
        a=before.get('children',{});b=generated.get('children',{})
        source=bool(a.get('OtherPlayer')) and same(a['OtherPlayer'],b.get('OtherPlayer'))
        clips=a.get('AnimationPlayer',{}).get('clips',{});actual=b.get('AnimationPlayer',{}).get('clips',{})
        source=source and all(name in actual and same(value,actual[name]) for name,value in clips.items() if name!='generated')
    if row['mode'] in {'instanced','editable'}:
        path='user://showcase_source_%s.tscn'%row['mode'] if variant=='showcase' else 'user://preset_library_source_%s_%s.tscn'%(row['mode'],variant)
        source=source and row.get('source_path')==path and digest(row.get('source_sha256_before')) and row.get('source_sha256_before')==row.get('source_sha256_after') and bool(row.get('peer_before')) and same(row['peer_before'],row.get('peer_after'))
        if variant!='showcase':
            pristine=copy.deepcopy(before);pristine['owner']=''
            source=source and same(pristine,row.get('pristine'))
    errors=clean and type(row['errors_before']) is int and row['errors_after']==row['errors_before'] and row['errors']==[]
    samples=row['persist_redo'].get('native',[]);expected=EXPECTED[variant]
    native=clean and len(samples)==len(expected)
    tracks=native
    for sample,want in zip(samples,expected):
        time,node,prop,value=want
        native=native and sample.get('clock')=='native_manual_mixer' and same(sample.get('time'),time) and sample.get('node')==node and sample.get('property')==prop and same(sample.get('actual'),value) and same(sample.get('expected'),value)
        path=node.removeprefix('ReviewShowcase/')+':'+prop
        typed_tracks=sample.get('tracks',[])
        tracks=tracks and bool(typed_tracks) and any(track.get('path')==path for track in typed_tracks) and all(track.get('type')==0 for track in typed_tracks)
    return {name:'pass' if result else 'fail' for name,result in [('dry_run',dry),('typed_errors',typed),('undo_redo',history),('save_reopen',saved),('source_unchanged',clean and recipe and source),('reported_errors',errors),('valid_effect',native),('playback',native),('track_paths_types',tracks)]}

def verify_event(event,context,begins,support):
    deps=context.get('dependencies',{})
    for path in ('test_project/tests/test_preset_library_history.gd','test_project/tests/operation_history_trace.gd','tools/operation_preset_history_checks.py','tools/mcp_presets_audit.py'):
        if path not in deps: raise ValueError('preset case dependency missing: '+path)
    if event.get('validator')!='preset_library_history_v1' or event.get('driver')!='test_preset_library_history.gd' or event.get('route')!='public_test_run_inner_dispatch': raise ValueError('unknown preset history source')
    row=event.get('row',{});variant=row.get('variant')
    if variant not in EXPECTED or row.get('suite')!='preset_library_history': raise ValueError('unknown preset history case')
    family='animation_library' if variant in {'template_fx','template_preset','spec_apply'} else 'animation_presets'
    op='template_apply' if variant.startswith('template_') else variant
    test='test_showcase_subtree_history' if variant=='showcase' else 'test_'+str(row.get('mode'))+'_history'
    modes={'root','local','instanced','editable'} if variant=='showcase' else {'local','overwrite','missing_library','instanced','editable'}
    if row.get('mode') not in modes or row.get('test')!=test or row.get('family')!=family or row.get('op')!=op or row.get('request',{}).get('op')!=op or event.get('operation')!=family+'.'+op: raise ValueError('preset operation/mode/request binding differs')
    begin=event.get('test_run_begin_id');starts=[x for x in begins if x.get('id')==begin];ends=[x for x in support if x.get('public_tool')=='test_run' and x.get('test_run_begin_id')==begin]
    if len(starts)!=1 or len(ends)!=1: raise ValueError('preset case lacks exact public span')
    start,end=starts[0],ends[0]
    if start.get('request')!=end.get('request') or start.get('request',{}).get('suite')!='preset_library_history' or start['request'].get('verbose') is not True or start.get('execution_ns',0)>=end.get('execution_ns',0): raise ValueError('preset public span request/order mismatch')
    checks=derive(row)
    tests=[result for result in end.get('response',{}).get('results',[]) if result.get('suite')==row['suite'] and result.get('test')==test]
    if len(tests)!=1 or tests[0].get('passed') is not True or tests[0].get('skipped',False) or tests[0].get('assertion_count',0)<row['assertion_count']: checks={name:'fail' for name in checks}
    return {'checks':checks,'public_test_run_case_id':end['id'],'limits':'Exact inner preset/library apply dispatcher cases, history/persisted snapshots/recipe and non-target invariants plus fixed native sample values on reopened clones. Not individual external MCP invocations, visual/audio approval or whole-source qualification.'}
