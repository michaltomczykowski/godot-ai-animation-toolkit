"""Strict seven-writer graph case evidence; never derive effect from changed dump."""
import math
import re

OPS={'state_machine','blend_space','blend_tree','wire','locomotion','one_shot_layer','additive_lean'}
TESTS={'new':'test_new_graph_scene_history','replace':'test_replaced_graph_scene_history',
       'instanced':'test_instanced_graph_scene_history','instanced_new':'test_instanced_new_graph_scene_history'}
DEPENDENCIES=('test_project/tests/test_graph_route_history.gd','test_project/tests/graph_history_trace.gd',
              'test_project/tests/operation_history_trace.gd','tools/operation_graph_history_checks.py',
              'tools/mcp_presets_audit.py','addons/godot_ai_animation/handlers/graph.gd',
              'addons/godot_ai_animation/spec/graph_builders.gd','test_project/repair_graph_fixture.tscn')


def number(v):return type(v) in (int,float) and math.isfinite(v)
def digest(v):return isinstance(v,str) and re.fullmatch('[0-9a-f]{64}',v) is not None

REQUESTS={
 'state_machine':{'states':[{'name':'idle','animation':'idle'},{'name':'walk','animation':'walk'}],'transitions':[{'from':'idle','to':'walk','xfade':.1}]},
 'blend_space':{'dimensions':1,'min':0,'max':2,'points':[{'animation':name,'position':i} for i,name in enumerate(('idle','walk','run'))]},
 'blend_tree':{'root':{'type':'blend2','inputs':[{'type':'animation','animation':'idle'},{'type':'animation','animation':'walk'}]}},
 'wire':{},'locomotion':{'mode':'blend_space'},'one_shot_layer':{'animation':'jump','base':'idle'},'additive_lean':{'animation':'lean','base':'idle'}}

def request_matches(row):
    request=row.get('request',{});op=row.get('op')
    player=request.get('player_path')
    if not isinstance(player,str) or not player.endswith('/GraphHistory/AnimationPlayer'):return False
    expected=dict(REQUESTS[op],op=op,player_path=player,tree_path=player.removesuffix('AnimationPlayer')+'AnimationTree',active=op!='wire')
    return request==expected


def shape(row):
    op=row['op'];state=row['generated'];root=state.get('root',{})
    if state.get('tree') is not True or state.get('player')!='../AnimationPlayer' or state.get('player_resolves') is not True or state.get('active') is not (op!='wire'):return False
    classes={'state_machine':'AnimationNodeStateMachine','blend_space':'AnimationNodeBlendSpace1D',
             'locomotion':'AnimationNodeBlendSpace1D','blend_tree':'AnimationNodeBlendTree',
             'one_shot_layer':'AnimationNodeBlendTree','additive_lean':'AnimationNodeBlendTree'}
    if op=='wire':return (state.get('root_class')=='AnimationNodeAnimation' and root=={'type':'animation','animation':'idle'}) if row['mode'] in ('replace','instanced') else (state.get('root_class')=='' and root=={})
    if state.get('root_class')!=classes[op]:return False
    if op=='state_machine':
        states=root.get('states',[]);links=root.get('transitions',[])
        return root.get('type')=='state_machine' and {x.get('name'):x.get('node') for x in states}=={k:{'type':'animation','animation':k} for k in ('idle','walk')} and any(x.get('from')=='idle' and x.get('to')=='walk' and number(x.get('xfade_time')) and abs(x['xfade_time']-.1)<1e-6 for x in links)
    if op in ('blend_space','locomotion'):
        points=root.get('points',[])
        return root.get('type')=='blend_space_1d' and root.get('min')==0 and root.get('max')==2 and len(points)==3 and {(x.get('animation'),x.get('position')) for x in points}=={('idle',0),('walk',1),('run',2)}
    nodes={x.get('name'):x.get('node',{}) for x in root.get('nodes',[])}
    if root.get('type')!='blend_tree':return False
    if op=='one_shot_layer':return nodes.get('Base')=={'type':'animation','animation':'idle'} and nodes.get('Shot')=={'type':'animation','animation':'jump'} and nodes.get('OneShot',{}).get('class')=='AnimationNodeOneShot'
    if op=='additive_lean':return nodes.get('Base')=={'type':'animation','animation':'idle'} and nodes.get('Lean')=={'type':'animation','animation':'lean'} and nodes.get('Add2',{}).get('class')=='AnimationNodeAdd2'
    # Builder names internal leaf nodes. Require exactly idle/walk and Blend2,
    # then native branch values independently prove the connection intention.
    return sum(x=={'type':'animation','animation':'idle'} for x in nodes.values())==1 and sum(x=={'type':'animation','animation':'walk'} for x in nodes.values())==1 and any(x.get('class')=='AnimationNodeBlend2' for x in nodes.values())


def native(row):
    samples=row['persist_redo'].get('native',[]);op=row['op']
    if op=='wire' and row['mode'] in ('new','instanced_new'):return None
    expected=['idle','walk'] if op in ('state_machine','blend_tree') else ['walk','run'] if op in ('blend_space','locomotion') else ['jump'] if op=='one_shot_layer' else ['lean'] if op=='additive_lean' else ['neutral_hold']
    if [s.get('stage') for s in samples]!=expected:return False
    if any(s.get('clock')!='native_saved_tree' or s.get('player_playing') is not False for s in samples):return False
    for sample in samples:
        stage=sample['stage']
        if stage=='idle':
            if not number(sample.get('x')) or abs(sample['x'])>.01:return False
        else:
            if sample.get('frames')!=(6 if stage=='run' else 30) or not number(sample.get('dt')) or abs(sample['dt']-1/60)>1e-14:return False
            if stage=='walk' and (not number(sample.get('x')) or sample['x']<20):return False
            if stage=='run' and (not number(sample.get('x')) or sample['x']<=samples[0]['x']+10):return False
            if stage=='jump' and (not number(sample.get('y')) or sample['y']>-20):return False
            if stage=='lean' and (not number(sample.get('rotation')) or sample['rotation']<.05):return False
            if stage=='neutral_hold' and (not number(sample.get('x')) or not number(sample.get('y')) or abs(sample['x'])>.01 or abs(sample['y'])>.01):return False
    return True


def derive(row):
    required={'request','dry','invalid_request','invalid','write','before','after_dry','after_error','generated','undone','redone','versions','persist_undo','persist_redo','undo_success','redo_success','inputs_before','inputs_after','failed_before','failed_after','assertion_count','errors_before','errors_after','errors'}
    if not required.issubset(row):raise ValueError('missing raw graph case stages')
    if row.get('op') not in OPS or row.get('mode') not in TESTS:raise ValueError('unknown graph case')
    clean=request_matches(row) and row['failed_before'] is False and row['failed_after'] is False and type(row['assertion_count']) is int and row['assertion_count']>=20
    v=row['versions'];before=row['before'];generated=row['generated']
    dry=clean and row['dry'].get('data',{}).get('dry_run') is True and not row['dry'].get('error') and before==row['after_dry'] and v.get('dry')==v.get('before')
    err=row['invalid'].get('error',{});invalid=dict(row['request'],player_path='/Missing')
    typed=clean and row['invalid_request']==invalid and err.get('code')=='NODE_NOT_FOUND' and isinstance(err.get('message'),str) and bool(err['message']) and before==row['after_error'] and v.get('error')==v.get('before')
    history=clean and 'data' in row['write'] and not row['write'].get('error') and before!=generated and row['undo_success'] is True and row['redo_success'] is True and before==row['undone'] and generated==row['redone'] and v.get('write')==v.get('before',-2)+1 and v.get('global_write')==v.get('global_before')
    def persisted(stage,state):
        p=row['persist_'+stage]
        return p.get('path')=='user://graph_history_%s_%s_%s.tscn'%(row['op'],row['mode'],stage) and digest(p.get('sha256')) and p.get('fixture_found') is True and type(p.get('pack_result')) is int and p['pack_result']==0 and type(p.get('save_result')) is int and p['save_result']==0 and p.get('snapshot')==state
    saved=clean and persisted('undo',before) and persisted('redo',generated)
    errors=clean and type(row['errors_before']) is int and row['errors_after']==row['errors_before'] and row['errors']==[]
    source=clean and bool(row['inputs_before'].get('clips')) and row['inputs_before']==row['inputs_after'] and digest(row.get('fixture_sha256_before')) and row.get('fixture_sha256_before')==row.get('fixture_sha256_after')
    if row['mode'].startswith('instanced'):
        source=source and row.get('source_path')=='user://graph_history_source_%s_%s.tscn'%(row['op'],row['mode']) and digest(row.get('source_sha256_before')) and row.get('source_sha256_after')==row['source_sha256_before'] and row.get('peer_before')==row.get('peer_after') and bool(row.get('peer_before'))
    graph=clean and shape(row)
    result={k:'pass' if value else 'fail' for k,value in [('dry_run',dry),('typed_errors',typed),('undo_redo',history),('save_reopen',saved),('reported_errors',errors),('source_unchanged',source),('track_paths_types',graph)]}
    played=native(row)
    if played is not None:
        result['valid_effect']='pass' if clean and saved and graph and played else 'fail'
        result['playback']=result['valid_effect']
    return result


def verify_event(event,context,begins,support):
    if any(path not in context.get('dependencies',{}) for path in DEPENDENCIES):raise ValueError('graph source dependencies not bound')
    for path in DEPENDENCIES:
        identity=context['dependencies'][path]
        if not digest(identity.get('sha256')) or not isinstance(identity.get('git_blob'),str) or re.fullmatch('[0-9a-f]{40}',identity['git_blob']) is None:raise ValueError('graph dependency lacks exact source identity')
    if event.get('run_id')!=context.get('run_id') or not isinstance(context.get('run_id'),str) or not context['run_id']:raise ValueError('graph event belongs to another source run')
    if event.get('validator')!='graph_history_v1' or event.get('driver')!='test_graph_route_history.gd' or event.get('route')!='public_test_run_inner_dispatch':raise ValueError('unknown graph evidence source')
    row=event.get('row',{})
    if row.get('suite')!='graph_route_history' or TESTS.get(row.get('mode'))!=row.get('test') or event.get('operation')!='animation_graph.'+row.get('op','') or row.get('request',{}).get('op')!=row.get('op'):raise ValueError('graph operation/test case mismatch')
    begin=event.get('test_run_begin_id');starts=[x for x in begins if x.get('id')==begin];ends=[x for x in support if x.get('public_tool')=='test_run' and x.get('test_run_begin_id')==begin]
    if len(starts)!=1 or len(ends)!=1:raise ValueError('no unique actual public test span')
    start,end=starts[0],ends[0];request=start.get('request',{})
    if request!=end.get('request') or request.get('suite')!=row['suite'] or request.get('verbose') is not True or start.get('execution_ns',0)>=end.get('execution_ns',0):raise ValueError('graph public span request/order mismatch')
    stamp=event.get('time_ns')
    if type(stamp) is not int or not start.get('time_ns',0)<=stamp<=end.get('time_ns',0):raise ValueError('graph case outside its public invocation span')
    checks=derive(row)
    fixture=context['dependencies']['test_project/repair_graph_fixture.tscn']
    if row.get('fixture_sha256_before')!=fixture.get('sha256'):
        checks={key:'fail' for key in checks}
    matches=[x for x in end.get('response',{}).get('results',[]) if x.get('suite')==row['suite'] and x.get('test')==row['test']]
    if len(matches)!=1 or matches[0].get('passed') is not True or matches[0].get('skipped',False) or type(matches[0].get('assertion_count')) is not int or matches[0]['assertion_count']<row['assertion_count']:checks={k:'fail' for k in checks}
    return {'checks':checks,'public_test_run_case_id':end['id'],'limits':'Exact case-local graph history/save/source/resource-path/type checks and saved-clone native fixed-branch values where present. Wire seeded cases prove neutral idle hold only; new/rootless wire has no valid_effect claim. track_paths_types names the saved graph resource classes/player path only, not authored track metadata. No graph_get accuracy, individual external invocation, visual approval or arbitrary-graph connection inference.'}
