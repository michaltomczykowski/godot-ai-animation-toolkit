import copy
import unittest
from operation_snapshot_checks import derive,verify_event

class SnapshotChecks(unittest.TestCase):
    def fixture(self):
        before={'describe':{'error':'missing'},'timeline':{'error':'missing'}}
        after={'describe':{'clips':[{'name':'shake','tracks':[{'path':'Camera2D:position','node_resolved':True}]}]},'timeline':{'tracks':[{'path':'Camera2D:position','keys':[0,1]}]}}
        row={'op':'shake','scene':'res://fixture.tscn','request':{'op':'shake','player_path':'/Fixture/Player','animation_name':'shake'},
             'before':before,'after_dry':copy.deepcopy(before),'after':after,'persisted':copy.deepcopy(after),
             'open':{'opened':True},'dry':{'dry_run':True},'write':{'track_count':1},'save':{'saved':True},'reopen':{'switched':True}}
        context={'dependencies':{'tools/mcp_fx_audit.py':{},'tools/operation_snapshot_checks.py':{}}}
        event={'id':'assertion','operation':'animation_fx.shake','driver':'mcp_fx_audit.py','validator':'fx_snapshot_v1','row':row,'checks':derive('fx_snapshot_v1',row),'execution_ns':90}
        public=[]
        def probe(at,snapshot):
            for index,(op,key) in enumerate([('describe','describe'),('timeline','timeline')]):
                public.append({'id':str(at+index),'operation':'animation_inspect.'+op,'scene':row['scene'],
                    'params':{'op':op,'player_path':'/Fixture/Player','animation_name':'shake'},
                    'response':copy.deepcopy(snapshot[key]),'execution_ns':at+index})
        probe(10,row['before']);probe(30,row['after_dry']);probe(50,row['after']);probe(80,row['persisted'])
        for at,stage,params in [(20,'dry',dict(row['request'],dry_run=True)),(40,'write',row['request'])]:
            public.append({'id':stage,'operation':'animation_fx.shake','scene':row['scene'],'params':copy.deepcopy(params),'response':copy.deepcopy(row[stage]),'execution_ns':at})
        support=[{'id':'save','public_tool':'scene_save','scene':row['scene'],'request':{},'response':row['save'],'execution_ns':60},
                 {'id':'open','public_tool':'scene_open','scene':row['scene'],'request':{'path':row['scene'],'force_reload':True},'response':row['reopen'],'execution_ns':70}]
        return row,context,event,public,support
    def test_actual_dry_and_forced_saved_reopen_bind_raw_probes(self):
        row,context,event,public,support=self.fixture()
        proof=verify_event(event,context,public,support)
        self.assertEqual(proof['checks'],{'dry_run':'pass','save_reopen':'pass'})
        self.assertEqual(proof['public_case_ids'],['write'])
        self.assertNotIn('undo_redo',proof['checks']);self.assertNotIn('valid_effect',proof['checks'])
    def test_equal_snapshots_cannot_replace_missing_actual_reopen(self):
        row,context,event,public,support=self.fixture()
        proof=verify_event(event,context,public,support[:1])
        self.assertEqual(proof['checks']['save_reopen'],'fail')
        self.assertEqual(proof['checks']['dry_run'],'pass')
    def test_mutated_dry_or_missing_saved_clip_fails(self):
        row,_,_,_,_=self.fixture()
        row['after_dry']={'changed':True}
        self.assertEqual(derive('fx_snapshot_v1',row)['dry_run'],'fail')
        row['after']={'describe':{'error':'absent'},'timeline':{'error':'absent'}}
        row['persisted']=copy.deepcopy(row['after'])
        self.assertEqual(derive('fx_snapshot_v1',row)['save_reopen'],'fail')
    def test_declared_wrong_checks_operation_or_other_public_request_rejected(self):
        row,context,event,public,support=self.fixture()
        event['checks']['save_reopen']='fail'
        with self.assertRaisesRegex(ValueError,'declared'):verify_event(event,context,public,support)
        event['checks']=derive('fx_snapshot_v1',row);event['operation']='animation_fx.counter'
        with self.assertRaisesRegex(ValueError,'operation'):verify_event(event,context,public,support)
        event['operation']='animation_fx.shake';public[-1]['params']['animation_name']='other_clip'
        with self.assertRaisesRegex(ValueError,'exact actual'):verify_event(event,context,public,support)
    def test_spriteframes_save_ignores_only_nondurable_running_frame(self):
        row,_,_,_,_=self.fixture();row['op']='sprite_frames'
        row['after']={'assigned':True,'animation':'frames','frame':1};row['persisted']={'assigned':True,'animation':'frames','frame':2}
        self.assertEqual(derive('fx_snapshot_v1',row)['save_reopen'],'pass')
        row['persisted']['animation']='other'
        self.assertEqual(derive('fx_snapshot_v1',row)['save_reopen'],'fail')
    def test_only_actual_typed_wrap_refusals_claim_error_check(self):
        row,_,_,_,_=self.fixture();row['op']='offset_wrap_reject';row['request']['op']='offset'
        row['after']=copy.deepcopy(row['before']);row['persisted']=copy.deepcopy(row['before'])
        row['dry']={'error':'VALUE_OUT_OF_RANGE: wrap'};row['write']={'error':{'code':'VALUE_OUT_OF_RANGE'}}
        self.assertEqual(derive('edit_snapshot_v1',row),{'typed_errors':'pass'})
        row['write']={'error':'Unknown tool'}
        self.assertEqual(derive('edit_snapshot_v1',row),{'typed_errors':'fail'})
if __name__=='__main__':unittest.main()
