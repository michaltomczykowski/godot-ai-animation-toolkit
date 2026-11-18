import copy
import hashlib
import json
import unittest
import operation_library_file_checks as checks
import operation_case_collector as collector
import test_operation_case_collector as collector_fixtures


class LibraryFiles(unittest.TestCase):
    def fixture(self,op='template_save'):
        clip={'length':1.0,'loop':0,'markers':{},'tracks':[{'type':0,'path':'Widget:position:x','enabled':True,'interp':1,'wrap':True,'update':0,'keys':[[0.,10.,1.],[1.,30.,1.]]}]}
        scene={'class':'Node','children':{'AnimationPlayer':{'clips':{'unrelated':clip}}}}
        path=checks.DIRECTORY+('recipes.json' if op.startswith('template_') else 'export.json')
        entry={'tool':'animation_presets','op':'bounce','description':'','params':{'intensity':.25}}
        library={'format':'godot-ai-animation-library','version':1,'templates':{'bounce':entry}}
        def observed(value):
            if value is None:return {'path':path,'exists':False}
            raw=json.dumps(value).encode('utf-8')
            return {'path':path,'exists':True,'bytes_hex':raw.hex(),'sha256':hashlib.sha256(raw).hexdigest()}
        request={'op':op,'library_path':path,'name':'bounce','tool':'animation_presets','forward_op':'bounce','intensity':.25}
        data={'template_count':1,'overwritten':False,'params':{'intensity':.25},'undoable':False}
        before=None;after=library
        if op=='template_list':
            before=library
            request={'op':op,'library_path':path}
            data={'library_path':path,'exists':True,'template_count':1,'templates':[dict(entry,name='bounce',param_count=1)]}
        elif op=='template_delete':
            before=library;after=dict(library,templates={})
            request={'op':op,'library_path':path,'name':'bounce'}
            data={'template_count':0,'undoable':False}
        elif op.startswith('spec_'):
            after=checks.exported_clip(clip)
            request={'op':op,'path':path}
            if op=='spec_export':
                request.update(player_path='/Main/LibraryContracts/AnimationPlayer',animation_name='unrelated',overwrite=False)
                data={'path':path,'undoable':False}
            else:
                before=after
                data={'path':path,'length':1.,'loop_mode':'none','track_count':1,'key_count':2,'track_types':{'value':1},'paths':['Widget:position:x'],'issues':[]}
        row={'suite':'library_contracts','test':checks.TEST,'mode':'file_contract','ordinal':1,'op':op,'request':request,
             'response':{'data':data},'before':scene,'after':copy.deepcopy(scene),'file_before':observed(before),'file_after':observed(after),
             'history_before':10,'history_after':10,'global_before':0,'global_after':0,
             'errors_before':0,'errors_after':0,'errors':[],'failed_before':False,'assertion_count_before':0}
        dependencies=('test_project/tests/test_library_contracts.gd','test_project/tests/operation_history_trace.gd',
                      'test_project/tests/test_preset_library_history.gd','test_project/tests/test_edit_route_history.gd',
                      'test_project/tests/test_fx_route_history.gd','test_project/tests/test_graph_route_history.gd',
                      'tools/mcp_presets_audit.py','tools/operation_library_file_checks.py')
        context={'dependencies':{path:{} for path in dependencies}}
        event={'id':'file:1','driver':'test_library_contracts.gd','route':'public_test_run_inner_dispatch','validator':'library_file_v1',
               'operation':'animation_library.'+op,'test_run_begin_id':'begin','row':row}
        begin={'id':'begin','execution_ns':1,'request':{'suite':'library_contracts','verbose':True}}
        end={'id':'end','execution_ns':2,'public_tool':'test_run','test_run_begin_id':'begin','request':copy.deepcopy(begin['request']),
             'response':{'results':[{'suite':'library_contracts','test':checks.TEST,'passed':True,'assertion_count':50}]}}
        return row,context,event,[begin],[end]

    def test_five_actual_file_and_read_semantics_have_only_applicable_checks(self):
        for op in checks.OPS:
            with self.subTest(op=op):
                row,context,event,begins,support=self.fixture(op)
                proof=checks.verify_event(event,context,begins,support)
                self.assertEqual(set(proof['checks'].values()),{'pass'})
                self.assertIn('valid_effect',proof['checks'])
                self.assertEqual('file_effect' in proof['checks'],op in {'template_save','template_delete','spec_export'})
                self.assertNotIn('mcp_invocation',proof['checks']);self.assertNotIn('undo_redo',proof['checks'])

    def test_dry_creation_and_existing_file_dry_must_preserve_exact_bytes(self):
        for op in ('template_save','template_delete','spec_export'):
            row,*_=self.fixture(op);row['request']['dry_run']=True
            row['response']['data'].update(dry_run=True,undoable=False)
            row['file_after']=copy.deepcopy(row['file_before'])
            self.assertEqual(checks.derive(row)['dry_run'],'pass')
            row['file_after']=self.fixture(op)[0]['file_after']
            self.assertEqual(checks.derive(row)['dry_run'],'fail')

    def test_actual_duplicate_and_missing_refusals_require_typed_code_and_no_effect(self):
        row,*_=self.fixture();row['response']={'error':{'code':'INVALID_PARAMS','message':'already exists'}}
        row['file_before']=copy.deepcopy(row['file_after'])
        self.assertEqual(checks.derive(row)['typed_errors'],'pass')
        row['response']['error']['code']='UNKNOWN'
        self.assertEqual(checks.derive(row)['typed_errors'],'fail')
        row['response']['error']['code']='INVALID_PARAMS';row['history_after']=11
        self.assertEqual(checks.derive(row)['typed_errors'],'fail')

    def test_hash_path_and_absence_cannot_be_fabricated(self):
        row,*_=self.fixture();row['file_after']['sha256']='0'*64
        with self.assertRaisesRegex(ValueError,'hash'):checks.derive(row)
        row,*_=self.fixture();row['file_before']['bytes_hex']=''
        with self.assertRaisesRegex(ValueError,'absent'):checks.derive(row)
        row,*_=self.fixture();row['request']['library_path']='res://outside.json'
        with self.assertRaisesRegex(ValueError,'paths'):checks.derive(row)

    def test_wrong_file_recipe_exported_metadata_and_read_summary_fail(self):
        row,*_=self.fixture();row['response']['data']['params']['intensity']=.9
        self.assertEqual(checks.derive(row)['valid_effect'],'fail')
        row,*_=self.fixture('spec_export');row['before']['children']['AnimationPlayer']['clips']['unrelated']['tracks'][0]['keys'][1][1]=80.
        self.assertEqual(checks.derive(row)['file_effect'],'fail')
        row,*_=self.fixture('spec_import');row['response']['data']['key_count']=3
        self.assertEqual(checks.derive(row)['valid_effect'],'fail')
        row,*_=self.fixture('template_list');row['response']['data']['templates'][0]['params']['intensity']=.9
        self.assertEqual(checks.derive(row)['valid_effect'],'fail')

    def test_scene_history_and_engine_errors_remain_independent_failures(self):
        row,*_=self.fixture();row['after']['changed']=True
        self.assertEqual(checks.derive(row)['source_unchanged'],'fail')
        self.assertEqual(checks.derive(row)['valid_effect'],'fail')
        row,*_=self.fixture();row['errors_after']=1;row['errors']=['actual engine error']
        self.assertEqual(checks.derive(row)['reported_errors'],'fail')

    def test_wrong_operation_source_or_span_and_suite_totals_do_not_qualify(self):
        for field,value in [('operation','animation_library.spec_apply'),('driver','test_other.gd'),('test_run_begin_id','another')]:
            row,context,event,begins,support=self.fixture();event[field]=value
            with self.assertRaises(ValueError):checks.verify_event(event,context,begins,support)
        row,context,event,begins,support=self.fixture();support[0]['response']={'passed':4,'failed':0}
        self.assertEqual(set(checks.verify_event(event,context,begins,support)['checks'].values()),{'fail'})
        row,context,event,begins,support=self.fixture();support[0]['response']['results'][0]['skipped']=True
        self.assertEqual(set(checks.verify_event(event,context,begins,support)['checks'].values()),{'fail'})

class CollectorPath(unittest.TestCase):
    setUp=collector_fixtures.Collector.setUp
    collect=collector_fixtures.Collector.collect

    def test_actual_span_event_uses_new_file_adapter_without_manufacturing_invocation(self):
        row,dependencies,event,_,ends=LibraryFiles().fixture()
        context=json.loads(self.context.read_text())
        for rel in dependencies['dependencies']:
            path=self.root/rel;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('fixture source')
            context['dependencies'][rel]={'sha256':collector.sha(path),'git_blob':'blob'}
        self.context.write_text(json.dumps(context))
        request={'suite':'library_contracts','verbose':True}
        with collector.public_test_run_span('test_run',request):
            event['test_run_begin_id']=collector._active_test_run['begin_id']
            collector._emit('editor_history_assertions',{key:value for key,value in event.items() if key not in {'id','sequence','kind'}})
            collector.record_public_call('test_run',request,ends[0]['response'])
        report=self.collect()
        self.assertEqual(report['successful_public_operations'],[])
        self.assertEqual(report['cases'][0]['operation'],'animation_library.template_save')
        self.assertEqual(report['cases'][0]['checks']['file_effect'],'pass')
        self.assertEqual(report['cases'][0]['mode'],'file_contract')

if __name__=='__main__':unittest.main()
