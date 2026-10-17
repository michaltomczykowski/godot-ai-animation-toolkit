"""Offline synthetic adapter controls, never actual graph qualification."""
import copy
import unittest
from operation_graph_history_checks import derive,verify_event,OPS,TESTS,DEPENDENCIES,REQUESTS


def fixture(op='blend_space',mode='new'):
    root={'type':'blend_space_1d','min':0,'max':2,'points':[{'animation':name,'position':i} for i,name in enumerate(('idle','walk','run'))]}
    cls='AnimationNodeBlendSpace1D'
    if op=='state_machine':
        cls='AnimationNodeStateMachine';root={'type':'state_machine','states':[{'name':name,'node':{'type':'animation','animation':name}} for name in ('idle','walk')],'transitions':[{'from':'idle','to':'walk','xfade_time':.1}]}
    elif op in ('blend_tree','one_shot_layer','additive_lean'):
        cls='AnimationNodeBlendTree'
        nodes={'Base':{'type':'animation','animation':'idle'}}
        if op=='blend_tree':nodes.update(Walk={'type':'animation','animation':'walk'},Blend2={'class':'AnimationNodeBlend2'})
        elif op=='one_shot_layer':nodes.update(Shot={'type':'animation','animation':'jump'},OneShot={'class':'AnimationNodeOneShot'})
        else:nodes.update(Lean={'type':'animation','animation':'lean'},Add2={'class':'AnimationNodeAdd2'})
        root={'type':'blend_tree','nodes':[{'name':k,'node':v} for k,v in nodes.items()]}
    elif op=='wire':
        root={'type':'animation','animation':'idle'} if mode in ('replace','instanced') else {};cls='AnimationNodeAnimation' if root else ''
    before={'tree':False} if mode in ('new','instanced_new') else {'tree':True,'root':{'type':'animation','animation':'idle'},'active':True,'player':'../AnimationPlayer','player_resolves':True,'root_class':'AnimationNodeAnimation','parameters':{}}
    made={'tree':True,'root':root,'active':op!='wire','player':'../AnimationPlayer','player_resolves':True,'root_class':cls,'parameters':{}}
    stages=['idle','walk'] if op in ('state_machine','blend_tree') else ['walk','run'] if op in ('blend_space','locomotion') else ['jump'] if op=='one_shot_layer' else ['lean'] if op=='additive_lean' else ['neutral_hold'] if root else []
    samples=[]
    for stage in stages:
        s={'stage':stage,'x':0 if stage in ('idle','neutral_hold','jump','lean') else 90 if stage=='run' else 50,'y':-80 if stage=='jump' else 0,'rotation':.12 if stage=='lean' else 0,'clock':'native_saved_tree','player_playing':False}
        if stage!='idle':s.update(frames=6 if stage=='run' else 30,dt=1/60)
        samples.append(s)
    row={'suite':'graph_route_history','mode':mode,'test':TESTS[mode],'op':op,'request':{'op':op,'player_path':'/Main/GraphHistory/AnimationPlayer','tree_path':'/Main/GraphHistory/AnimationTree','active':op!='wire'},
         'before':before,'after_dry':copy.deepcopy(before),'after_error':copy.deepcopy(before),'generated':made,'undone':copy.deepcopy(before),'redone':copy.deepcopy(made),
         'dry':{'data':{'dry_run':True}},'invalid':{'error':{'code':'NODE_NOT_FOUND','message':'Missing node'}},'write':{'data':{'undoable':True}},
         'versions':{'before':10,'global_before':20,'dry':10,'error':10,'write':11,'global_write':20},'undo_success':True,'redo_success':True,
         'failed_before':False,'failed_after':False,'assertion_count':30,'errors_before':0,'errors_after':0,'errors':[],
         'inputs_before':{'clips':{'idle':{'keys':'actual'}}},'inputs_after':{'clips':{'idle':{'keys':'actual'}}},'fixture_sha256_before':'a'*64,'fixture_sha256_after':'a'*64}
    row['request'].update(copy.deepcopy(REQUESTS[op]))
    row['invalid_request']=dict(row['request'],player_path='/Missing')
    for stage,snapshot in (('undo',before),('redo',made)):
        row['persist_'+stage]={'path':f'user://graph_history_{op}_{mode}_{stage}.tscn','sha256':'b'*64,'pack_result':0,'save_result':0,'fixture_found':True,'snapshot':copy.deepcopy(snapshot),'native':samples if stage=='redo' else []}
    if mode.startswith('instanced'):row.update(source_path=f'user://graph_history_source_{op}_{mode}.tscn',source_sha256_before='c'*64,source_sha256_after='c'*64,peer_before={'root':'idle'},peer_after={'root':'idle'})
    return row


class GraphProof(unittest.TestCase):
    def test_all28_case_shapes_with_only_seeded_wire_effect(self):
        for op in OPS:
            for mode in TESTS:
                r=fixture(op,mode);checks=derive(r)
                self.assertTrue(all(x=='pass' for x in checks.values()),(op,mode,checks))
                self.assertEqual('valid_effect' in checks,op!='wire' or mode in ('replace','instanced'))
    def test_independent_native_intention_not_changed_snapshot(self):
        for op in OPS-{'wire'}:
            row=fixture(op);row['persist_redo']['native'][-1]['x']=0;row['persist_redo']['native'][-1]['y']=0;row['persist_redo']['native'][-1]['rotation']=0
            self.assertEqual(derive(row)['valid_effect'],'fail',op)
    def test_corruptions_fail_observed_gate(self):
        for fault in ('dry','error','undo','redo','save','source','peer','fixture','history','global','sticky','engine','path','class','clip','competing','clock','dt','framecount','missing_native','echo','wrong_request','wrong_tree_request'):
            row=fixture(mode='instanced')
            if fault=='dry':row['after_dry']={}
            elif fault=='error':row['invalid']['error']['code']='OTHER'
            elif fault=='undo':row['undone']={}
            elif fault=='redo':row['redone']={}
            elif fault=='save':row['persist_redo']['snapshot']={}
            elif fault=='source':row['inputs_after']={}
            elif fault=='peer':row['peer_after']={}
            elif fault=='fixture':row['fixture_sha256_after']='d'*64
            elif fault=='history':row['versions']['write']=12
            elif fault=='global':row['versions']['global_write']=21
            elif fault=='sticky':row['failed_before']=True
            elif fault=='engine':row['errors']=['native error']
            elif fault=='path':row['generated']['player']='../Wrong'
            elif fault=='class':row['generated']['root_class']='AnimationNodeAnimation'
            elif fault=='clip':row['generated']['root']['points'][0]['animation']='wrong'
            elif fault=='competing':row['persist_redo']['native'][0]['player_playing']=True
            elif fault=='clock':row['persist_redo']['native'][0]['clock']='synthetic'
            elif fault=='dt':row['persist_redo']['native'][0]['dt']=.1
            elif fault=='framecount':row['persist_redo']['native'][0]['frames']=1
            elif fault=='missing_native':row['persist_redo']['native']=[]
            elif fault=='wrong_request':row['request']['max']=4
            elif fault=='wrong_tree_request':row['request']['tree_path']='/Other/AnimationTree'
            elif fault=='echo':row['persist_redo']['native'][0].update(x=0,expected_x=0)
            with self.subTest(fault=fault):self.assertIn('fail',derive(row).values())
    def test_exact_public_span_test_source_binding(self):
        row=fixture();event={'validator':'graph_history_v1','driver':'test_graph_route_history.gd','route':'public_test_run_inner_dispatch','operation':'animation_graph.blend_space','test_run_begin_id':'begin','time_ns':15,'run_id':'run','row':row}
        ctx={'run_id':'run','dependencies':{p:{'sha256':'a'*64,'git_blob':'b'*40} for p in DEPENDENCIES}};request={'suite':'graph_route_history','verbose':True}
        starts=[{'id':'begin','request':request,'execution_ns':10,'time_ns':10}];ends=[{'id':'end','public_tool':'test_run','test_run_begin_id':'begin','request':request,'execution_ns':20,'time_ns':20,'response':{'results':[{'suite':row['suite'],'test':row['test'],'passed':True,'assertion_count':30}]}}]
        self.assertTrue(all(x=='pass' for x in verify_event(event,ctx,starts,ends)['checks'].values()))
        for fault in ('suite_total','wrong_test','skipped','weak_assertions','fixture_hash','duplicate','source','operation','span_order','out_of_span','other_run','unbound_blob'):
            c,e,a,b=copy.deepcopy((ctx,event,starts,ends))
            if fault=='suite_total':b[0]['response']={'passed':1000}
            elif fault=='wrong_test':b[0]['response']['results'][0]['test']='other'
            elif fault=='skipped':b[0]['response']['results'][0]['skipped']=True
            elif fault=='weak_assertions':b[0]['response']['results'][0]['assertion_count']=1
            elif fault=='fixture_hash':c['dependencies']['test_project/repair_graph_fixture.tscn']['sha256']='f'*64
            elif fault=='duplicate':a.append(copy.deepcopy(a[0]))
            elif fault=='source':c['dependencies'].pop(DEPENDENCIES[0])
            elif fault=='operation':e['operation']='animation_graph.wire'
            elif fault=='span_order':b[0]['execution_ns']=1
            elif fault=='out_of_span':e['time_ns']=30
            elif fault=='other_run':e['run_id']='another'
            elif fault=='unbound_blob':c['dependencies'][DEPENDENCIES[0]]['git_blob']='wrong'
            with self.subTest(fault=fault):
                try:checks=verify_event(e,c,a,b)['checks']
                except ValueError:continue
                self.assertTrue(all(x=='fail' for x in checks.values()))
