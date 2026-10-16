import copy
import json
import unittest
from operation_history_checks import derive,verify_event
import test_operation_case_collector as collector_tests
import operation_case_collector as collector


class HistoryChecks(unittest.TestCase):
    def fixture(self):
        before={'clips':{'unrelated':{'length':2}},'props':{},'frames':{}}
        generated=copy.deepcopy(before);generated['clips']['generated']={'length':1,'keys':[0,1]}
        def saved(snapshot,stage):return {'path':'user://fx_history_shake_new_'+stage+'.tscn','sha256':'a'*64,'pack_result':0,'save_result':0,'fixture_found':True,'snapshot':copy.deepcopy(snapshot)}
        row={'suite':'fx_route_history','test':'test_new_clip_scene_history','mode':'new','op':'shake',
             'request':{'op':'shake','animation_name':'generated','player_path':'/Main/FxHistory/AnimationPlayer'},
             'before':before,'after_dry':copy.deepcopy(before),'after_error':copy.deepcopy(before),
             'generated':generated,'undone':copy.deepcopy(before),'redone':copy.deepcopy(generated),
             'dry':{'data':{'dry_run':True}},'write':{'data':{'track_count':1}},
             'invalid':{'status':'error','error':{'code':'NODE_NOT_FOUND','message':'Missing node'}},
             'versions':{'before':10,'dry':10,'error':10,'write':11,'global_before':0,'global_write':0},
             'undo_success':True,'redo_success':True,'persist_undo':saved(before,'undo'),'persist_redo':saved(generated,'redo'),
             'failed_before':False,'failed_after':False,'assertion_count':23}
        row['invalid_request']=dict(row['request'],player_path='/Missing',sprite_path='/Missing')
        context={'dependencies':{path:{} for path in ('test_project/tests/test_fx_route_history.gd','test_project/tests/operation_history_trace.gd','tools/mcp_presets_audit.py','tools/operation_history_checks.py')}}
        event={'id':'inner:1','operation':'animation_fx.shake','driver':'test_fx_route_history.gd','validator':'fx_history_v1','route':'public_test_run_inner_dispatch','test_run_begin_id':'begin','row':row}
        begin={'id':'begin','request':{'suite':'fx_route_history','verbose':True},'execution_ns':1}
        end={'id':'end','public_tool':'test_run','test_run_begin_id':'begin','request':copy.deepcopy(begin['request']),
             'execution_ns':10,'response':{'results':[{'suite':'fx_route_history','test':row['test'],'passed':True,'assertion_count':23*16}]}}
        return row,context,event,[begin],[end]

    def test_exact_raw_inner_case_closes_only_actual_checked_stages(self):
        row,context,event,begins,ends=self.fixture()
        proof=verify_event(event,context,begins,ends)
        self.assertEqual(proof['checks'],{'dry_run':'pass','typed_errors':'pass','undo_redo':'pass','save_reopen':'pass'})
        self.assertNotIn('mcp_invocation',proof['checks']);self.assertNotIn('valid_effect',proof['checks'])
        self.assertEqual(proof['public_test_run_case_id'],'end')

    def test_changed_dry_error_history_and_saved_snapshots_fail_independently(self):
        mutations=[('after_dry',{'changed':True},'dry_run'),('undone',{'changed':True},'undo_redo'),
                   ('invalid',{'error':{'code':'UNKNOWN','message':'generic'}},'typed_errors'),
                   ('persist_redo',{'fixture_found':False},'save_reopen')]
        for field,value,check in mutations:
            with self.subTest(field=field):
                row,*_=self.fixture();row[field]=value;self.assertEqual(derive(row)[check],'fail')
        row,*_=self.fixture();row['versions']['write']=12
        self.assertEqual(derive(row)['undo_redo'],'fail')
        row,*_=self.fixture();row['persist_undo']['path']='user://fx_history_counter_new_undo.tscn'
        self.assertEqual(derive(row)['save_reopen'],'fail')
        row,*_=self.fixture();row['before']['props']={'value':1000.0};row['undone']['props']={'value':1000.00005}
        self.assertEqual(derive(row)['undo_redo'],'fail')

    def test_sticky_failure_skips_and_suite_totals_cannot_become_case_passes(self):
        row,context,event,begins,ends=self.fixture();row['failed_before']=True
        self.assertEqual(set(derive(row).values()),{'fail'})
        for response in [{'passed':5,'failed':0}, {'results':[{'suite':row['suite'],'test':row['test'],'passed':True,'skipped':True,'assertion_count':100}]}]:
            row,context,event,begins,ends=self.fixture();ends[0]['response']=response
            self.assertEqual(set(verify_event(event,context,begins,ends)['checks'].values()),{'fail'})

    def test_other_operation_test_source_and_public_span_are_rejected(self):
        for field,value in [('operation','animation_fx.counter'),('test_run_begin_id','other'),('driver','test_other.gd')]:
            row,context,event,begins,ends=self.fixture();event[field]=value
            with self.assertRaises(ValueError):verify_event(event,context,begins,ends)
        row,context,event,begins,ends=self.fixture();row['test']='test_other'
        with self.assertRaises(ValueError):verify_event(event,context,begins,ends)


class PublicSpan(unittest.TestCase):
    # Reuse the real temporary trace/context fixture, but no editor or transport.
    setUp=collector_tests.Collector.setUp
    collect=collector_tests.Collector.collect
    def test_public_span_binds_one_actual_test_request_and_rejects_overlap(self):
        params={'suite':'fx_route_history','verbose':True}
        with collector.public_test_run_span('test_run',params):
            active=json.loads((self.traces/'active-public-test-run.json').read_text())
            with self.assertRaises(FileExistsError):
                with collector.public_test_run_span('test_run',params):pass
            end=collector.record_public_call('test_run',params,{'results':[]})
        self.assertFalse((self.traces/'active-public-test-run.json').exists())
        events=[json.loads(line) for f in self.traces.glob('*.jsonl') for line in f.read_text().splitlines()]
        self.assertEqual(events[0]['id'],active['begin_id'])
        self.assertEqual(events[-1]['test_run_begin_id'],active['begin_id'])
        self.assertEqual(events[-1]['id'],end)
        self.assertEqual(self.collect()['cases'],[])

    def test_collect_binds_raw_inner_case_without_external_operation_invocation(self):
        row,dependencies,event,_,ends=HistoryChecks().fixture()
        context=json.loads(self.context.read_text())
        for rel in dependencies['dependencies']:
            path=self.root/rel;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('fixture source')
            context['dependencies'][rel]={'sha256':collector.sha(path),'git_blob':'blob'}
        self.context.write_text(json.dumps(context))
        with collector.public_test_run_span('test_run',{'suite':'fx_route_history','verbose':True}):
            event['test_run_begin_id']=collector._active_test_run['begin_id']
            collector._emit('editor_history_assertions',{key:value for key,value in event.items() if key not in {'id','sequence','kind'}})
            collector.record_public_call('test_run',{'suite':'fx_route_history','verbose':True},ends[0]['response'])
        result=self.collect()
        self.assertEqual(len(result['cases']),1)
        self.assertEqual(result['cases'][0]['operation'],'animation_fx.shake')
        self.assertEqual(set(result['cases'][0]['checks'].values()),{'pass'})
        self.assertEqual(result['successful_public_operations'],[])


class EditHistoryChecks(unittest.TestCase):
    def fixture(self,mode='local',op='retime',variant='base'):
        row,context,event,begins,ends=HistoryChecks().fixture()
        row.update(suite='edit_route_history',op=op,mode=mode,variant=variant,
                   test={'local':'test_local_scene_history','instanced':'test_instanced_scene_history','editable':'test_editable_instance_scene_history'}[mode],
                   original_library_id=100,dry_library_id=100,undo_library_id=100,
                   original_clip_ids={'walk':101,'run':102},undo_clip_ids={'walk':101,'run':102},
                   errors_before=0,errors_after=0,errors=[])
        before={'clips':{'walk':{'length':1},'run':{'length':1}},'other':{'walk':{'length':1}}}
        after=copy.deepcopy(before)
        after['clips']['walk' if op!='merge' else 'walk_run']={'length':.5}
        row.update(before=before,after_dry=copy.deepcopy(before),after_error=copy.deepcopy(before),
                   generated=after,undone=copy.deepcopy(before),redone=copy.deepcopy(after))
        row['request'].update(op=op,animation_name='walk')
        row['invalid_request']=dict(row['request'],player_path='/Missing')
        row['versions']['global_dry_error']=0
        for stage,snapshot in [('undo',before),('redo',after)]:
            row['persist_'+stage].update(path=f'user://edit_history_{mode}_{op}_{variant}_{stage}.tscn',snapshot=copy.deepcopy(snapshot))
        if mode!='local':
            row.update(source_path=f'user://edit_source_{mode}_{op}_{variant}.tscn',
                       source_sha256_before='b'*64,source_sha256_after='b'*64,
                       peer_before=copy.deepcopy(before),peer_after=copy.deepcopy(before),pristine=copy.deepcopy(before))
        for path in ('test_project/tests/test_edit_route_history.gd','test_project/tests/test_graph_route_history.gd'):context['dependencies'][path]={}
        event.update(operation='animation_edit.'+op,driver='test_edit_route_history.gd',validator='edit_history_v1')
        begins[0]['request']['suite']='edit_route_history';ends[0]['request']['suite']='edit_route_history'
        ends[0]['response']['results'][0].update(suite='edit_route_history',test=row['test'])
        return row,context,event,begins,ends

    def test_existing_exact_local_and_instanced_cases_have_only_scoped_checks(self):
        for mode in ('local','instanced','editable'):
            row,context,event,begins,ends=self.fixture(mode)
            proof=verify_event(event,context,begins,ends)
            self.assertEqual(set(proof['checks']),{'dry_run','typed_errors','undo_redo','save_reopen','source_unchanged','reported_errors'})
            self.assertEqual(set(proof['checks'].values()),{'pass'})
            self.assertNotIn('valid_effect',proof['checks'])

    def test_non_target_clip_and_other_player_changes_cannot_pass(self):
        for mutate in ('unrelated','other'):
            row,*_=self.fixture()
            if mutate=='unrelated':row['generated']['clips']['run']['length']=.7
            else:row['generated']['other']['walk']['length']=.7
            self.assertEqual(derive(row)['source_unchanged'],'fail')

    def test_peer_pristine_and_real_source_file_identity_are_required(self):
        for field,value in [('peer_after',{}),('pristine',{}),('source_sha256_after','c'*64),('source_path','user://another.tscn')]:
            with self.subTest(field=field):
                row,*_=self.fixture('instanced');row[field]=value
                self.assertEqual(derive(row)['source_unchanged'],'fail')

    def test_identical_snapshots_do_not_replace_original_resource_identity(self):
        for field,value,check in [('dry_library_id',200,'dry_run'),('undo_library_id',200,'undo_redo'),('undo_clip_ids',{'walk':201,'run':102},'undo_redo')]:
            row,*_=self.fixture();row[field]=value
            self.assertEqual(derive(row)[check],'fail')

    def test_engine_errors_are_not_hidden_by_other_passing_snapshots(self):
        for field,value in [('errors_after',1),('errors',['actual engine error'])]:
            row,*_=self.fixture();row[field]=value
            self.assertEqual(derive(row)['reported_errors'],'fail')

    def test_only_actual_variants_and_the_exact_edit_public_test_are_eligible(self):
        row,context,event,begins,ends=self.fixture(variant='cross')
        with self.assertRaisesRegex(ValueError,'variant'):verify_event(event,context,begins,ends)
        row,context,event,begins,ends=self.fixture();ends[0]['request']['suite']='fx_route_history'
        with self.assertRaisesRegex(ValueError,'request'):verify_event(event,context,begins,ends)
        row,context,event,begins,ends=self.fixture();context['dependencies'].pop('test_project/tests/test_graph_route_history.gd')
        with self.assertRaisesRegex(ValueError,'logger'):verify_event(event,context,begins,ends)

if __name__=='__main__':unittest.main()
