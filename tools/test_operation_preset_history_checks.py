import copy
import unittest
from operation_preset_history_checks import derive,verify_event,EXPECTED


def fixture(variant='bounce',mode='local'):
    family='animation_library' if variant in {'template_preset','template_fx','spec_apply'} else 'animation_presets'
    op='template_apply' if variant.startswith('template_') else variant
    before={'owner':'Main','children':{'OtherPlayer':{'clips':{'unrelated':{'value':2}}},'AnimationPlayer':{'clips':{'unrelated':{'value':1}}}}}
    generated=copy.deepcopy(before)
    if variant=='showcase': generated['children']['ReviewShowcase']={'class':'Node2D'}
    else: generated['children']['AnimationPlayer']['clips']['generated']={'value':'new'}
    label='showcase_'+mode if variant=='showcase' else mode+'_'+variant
    native=[{'time':time,'node':node,'property':prop,'actual':copy.deepcopy(value),'expected':copy.deepcopy(value),
        'clock':'native_manual_mixer','tracks':[{'path':node.removeprefix('ReviewShowcase/')+':'+prop,'type':0}]}
        for time,node,prop,value in EXPECTED[variant]]
    row={'suite':'preset_library_history','test':'test_showcase_subtree_history' if variant=='showcase' else 'test_'+mode+'_history',
        'mode':mode,'family':family,'variant':variant,'op':op,'request':{'op':op,'player_path':'/Main/PresetHistory/AnimationPlayer'},
        'dry':{'data':{'dry_run':True}},'invalid':{'error':{'code':'NODE_NOT_FOUND','message':'Missing'}},'write':{'data':{'undoable':True}},
        'before':before,'after_dry':copy.deepcopy(before),'after_error':copy.deepcopy(before),'generated':generated,
        'undone':copy.deepcopy(before),'redone':copy.deepcopy(generated),'undo_success':True,'redo_success':True,
        'versions':{'before':10,'dry':10,'error':10,'write':11,'global_before':8,'global_dry':8,'global_error':8,'global_write':8},
        'failed_before':False,'failed_after':False,'assertion_count':30,'errors_before':0,'errors_after':0,'errors':[],
        'recipe_path':'res://animation_toolkit/history_phase_library.json','recipe_sha256_before':'a'*64,'recipe_sha256_after':'a'*64,
        'original_library_id':1,'undo_library_id':1,'original_clip_ids':{'unrelated':2},'undo_clip_ids':{'unrelated':2}}
    row['invalid_request']=dict(row['request'],**({'parent_path':'/Missing'} if variant=='showcase' else {'player_path':'/Missing'}))
    if mode=='missing_library': row.update(original_library_id=0,undo_library_id=0,original_clip_ids={},undo_clip_ids={})
    for state,snapshot in [('undo',before),('redo',generated)]:
        row['persist_'+state]={'path':'user://preset_library_history_'+label+'_'+state+'.tscn','sha256':'b'*64,
            'pack_result':0,'save_result':0,'fixture_found':True,'snapshot':copy.deepcopy(snapshot),'native':native if state=='redo' else []}
    if mode in {'instanced','editable'}:
        row.update(source_sha256_before='c'*64,source_sha256_after='c'*64,peer_before={'untouched':1},peer_after={'untouched':1})
        row['source_path']='user://showcase_source_%s.tscn'%mode if variant=='showcase' else 'user://preset_library_source_%s_%s.tscn'%(mode,variant)
        row['pristine']=copy.deepcopy(before);row['pristine']['owner']=''
    return row


class PresetProofControls(unittest.TestCase):
    def test_every_known_variant_and_layout_has_positive_raw_control(self):
        for variant in EXPECTED:
            for mode in (['root','local','instanced','editable'] if variant=='showcase' else ['local','overwrite','missing_library','instanced','editable']):
                self.assertTrue(all(value=='pass' for value in derive(fixture(variant,mode)).values()),(variant,mode))

    def test_changed_dry_history_recipe_peer_and_saved_snapshot_fail(self):
        for mutation in ['dry','history','recipe','peer','saved','errors','sticky']:
            row=fixture(mode='instanced')
            if mutation=='dry': row['after_dry']['owner']='changed'
            if mutation=='history': row['versions']['write']=12
            if mutation=='recipe': row['recipe_sha256_after']='d'*64
            if mutation=='peer': row['peer_after']={'untouched':2}
            if mutation=='saved': row['persist_redo']['snapshot']['owner']='wrong'
            if mutation=='errors': row['errors']=[{'message':'native error'}]
            if mutation=='sticky': row['failed_before']=True
            self.assertIn('fail',derive(row).values(),mutation)

    def test_authored_echo_cannot_replace_independent_native_intention(self):
        row=fixture('pulse')
        row['persist_redo']['native'][0]['actual']['x']=9
        row['persist_redo']['native'][0]['expected']['x']=9
        self.assertEqual(derive(row)['valid_effect'],'fail')
        row=fixture('pulse');row['persist_redo']['native'][0]['tracks'][0]['type']=3
        self.assertEqual(derive(row)['track_paths_types'],'fail')

    def test_exact_public_test_span_not_suite_total_is_required(self):
        row=fixture();event={'validator':'preset_library_history_v1','driver':'test_preset_library_history.gd',
            'route':'public_test_run_inner_dispatch','operation':'animation_presets.bounce','test_run_begin_id':'begin','row':row}
        context={'dependencies':{path:{} for path in ['test_project/tests/test_preset_library_history.gd','test_project/tests/operation_history_trace.gd','tools/operation_preset_history_checks.py','tools/mcp_presets_audit.py']}}
        request={'suite':'preset_library_history','verbose':True}
        begins=[{'id':'begin','request':request,'execution_ns':1}]
        support=[{'id':'end','public_tool':'test_run','test_run_begin_id':'begin','request':request,'execution_ns':2,
            'response':{'results':[{'suite':row['suite'],'test':row['test'],'passed':True,'assertion_count':30}]}}]
        self.assertTrue(all(value=='pass' for value in verify_event(event,context,begins,support)['checks'].values()))
        support[0]['response']={'passed':1000}
        self.assertTrue(all(value=='fail' for value in verify_event(event,context,begins,support)['checks'].values()))
        with self.assertRaises(ValueError): verify_event(event,context,[],support)


if __name__=='__main__': unittest.main()
