"""Offline corruption controls; synthetic rows are not public/native qualification."""
import copy
import unittest
import struct
import operation_motion_sequence_history_checks as C


def row(group='motion',variant='walk_cycle',mode='local',fps=60):
    r=dict(group=group,variant=variant,mode=mode,fps=fps,case_id=f'{group}_{variant}_{mode}_{fps}',family='animation_sequence' if group=='sequence' else 'animation_motion',op='compose' if group=='sequence' else 'secondary_motion' if group=='secondary' else 'cycle' if variant.startswith('cycle_') else variant,test='test_'+group+'_'+('locked' if mode=='instanced' else mode),suite='motion_sequence_history',request={'player_path':'/Main/MotionSequenceHistory/Playback/AnimationPlayer'})
    r['request']=C.expected_request(r)
    target=r['request']['animation_name']
    b={'children':{'Character':{'type':'Node3D'}},'players':{'AnimationPlayer':{'clips':{'source/first':{'length':1,'tracks':[]}}},'OtherPlayer':{'clips':{'untouched':1}}}}
    if mode=='overwrite' or group=='secondary':b['players']['AnimationPlayer']['clips'][target]={'old':1}
    a=copy.deepcopy(b);a['players']['AnimationPlayer']['clips'][target]={'new':1}
    r.update(before=b,after_dry=copy.deepcopy(b),after_error=copy.deepcopy(b),generated=a,undone=copy.deepcopy(b),redone=copy.deepcopy(a),dry={'data':{'dry_run':True}},invalid_request=dict(r['request'],player_path='/Missing'),invalid={'error':{'code':'NODE_NOT_FOUND','message':'Missing node'}},write={'data':{}},undo_success=True,redo_success=True,source_library_identity=True,undo_library_identity=True,redo_clip_identity=True,failed_before=False,failed_after=False,assertion_count=30,errors_before=0,errors_after=0,errors=[],orphans_before=[1,2],orphans_dry=[1,2],orphans_error=[1,2],orphans_write=[1,2],source_bytes_unchanged=True,source_scene_path='user://motion_sequence_'+r['case_id']+'_source.tscn',source_scene_sha256='a'*64,source_scene_bytes=200)
    r['versions']={k:8 for k in ('before','dry','error','undo')};r['versions'].update(write=9,redo=9)
    r['versions'].update({'global_'+k:4 for k in ('before','dry','error','write','undo','redo')})
    for s in ('before','dry','error','write','undo','redo'):r['playback_'+s]={'playing':False,'speed':-1.7,'position':.2}
    for s,state in (('do',a),('undo',b),('redo',a)):
        r['persist_'+s]={'path':'user://motion_sequence_'+r['case_id']+'_'+s+'.tscn','sha256':'a'*64,'bytes':100,'matches_expected':True,'snapshot':copy.deepcopy(state)}
    inst=mode in ('instanced','editable')
    r.update(peer_before={'untouched':1} if inst else {},peer_after={'untouched':1} if inst else {},source_path='user://motion_sequence_instance_'+r['case_id']+'.tscn' if inst else '',source_sha256_before='b'*64 if inst else '',source_sha256_after='b'*64 if inst else '',source_bytes_before=300 if inst else 0,source_bytes_after=300 if inst else 0)
    return r


def span(r):
    context={'run_id':'actual-run','dependencies':{p:{'sha256':'c'*64,'git_blob':'d'*40} for p in C.DEPENDENCIES}}
    event=dict(context_sha256='e'*64,run_id='actual-run',validator='motion_sequence_history_v1',driver='test_motion_sequence_history.gd',route='public_test_run_inner_dispatch',row=r,operation=r['family']+'.'+r['op'],test_run_begin_id='begin',time_ns=200)
    req={'suite':'motion_sequence_history','verbose':True}
    begin=dict(kind='public_test_run_begin',driver='mcp_motion_sequence_history.py',route='public_godot_ai',public_tool='test_run',context_sha256='e'*64,run_id='actual-run',id='begin',request=req,execution_ns=1000,time_ns=100)
    end=dict(kind='public_support_call',driver='mcp_motion_sequence_history.py',route='public_godot_ai',context_sha256='e'*64,run_id='actual-run',id='end',public_tool='test_run',test_run_begin_id='begin',request=req,execution_ns=2000,time_ns=300,response={'results':[dict(suite=r['suite'],test=r['test'],passed=True,assertion_count=100)]})
    return event,context,[begin],[end]


class Evidence(unittest.TestCase):
    def test_all273_identities(self):
        n=0
        for group,variants,modes in (('motion',C.MOTIONS,('local','instanced','editable','missing_library','overwrite')),('secondary',('single','branches'),('local','instanced','editable')),('sequence',C.SEQUENCES,('local','instanced','editable','missing_library','overwrite'))):
            for variant in variants:
                for mode in modes:
                    for fps in (30,60,120):
                        r=row(group,variant,mode,fps);self.assertEqual(set(C.derive(r).values()),{'pass'},r['case_id']);n+=1
        self.assertEqual(n,273)
        self.assertNotIn('valid_effect',C.derive(row()))
        self.assertNotIn('playback',C.derive(row()))
        self.assertNotIn('track_paths_types',C.derive(row()))

    def test_case_corruptions(self):
        mutations=[lambda r:r['dry']['data'].update(dry_run=False),lambda r:r['after_dry'].update(mutated=True),lambda r:r['invalid']['error'].update(code='INVALID_ARGUMENT'),lambda r:r['after_error'].update(mutated=True),lambda r:r['versions'].update(global_write=5),lambda r:r['versions'].update(write=10),lambda r:r.update(undo_success=False),lambda r:r.update(redo_success=False),lambda r:r['undone'].update(mutated=True),lambda r:r['redone'].update(mutated=True),lambda r:r['persist_redo'].update(sha256='bad'),lambda r:r['persist_undo'].update(snapshot={}),lambda r:r['persist_do'].update(bytes=0),lambda r:r['playback_redo'].update(position=.3),lambda r:r.update(source_library_identity=False),lambda r:r.update(undo_library_identity=False),lambda r:r.update(redo_clip_identity=False),lambda r:r.update(orphans_error=[1,2,3]),lambda r:r.update(orphans_write=[1,2,3]),lambda r:r.update(errors=['engine error'],errors_after=1),lambda r:r.update(errors=None),lambda r:r.update(failed_after=True),lambda r:r['request'].update(duration=9),lambda r:r['generated']['players']['OtherPlayer'].update(mutated=True),lambda r:r['generated']['players']['AnimationPlayer']['clips'].update(foreign={'new':1}),lambda r:r.update(source_scene_sha256='bad'),lambda r:r.update(source_bytes_unchanged=False)]
        for mutate in mutations:
            r=row();mutate(r)
            self.assertIn('fail',C.derive(r).values())
        for bad in (float('nan'),float('inf'),-float('inf')):
            r=row();r['persist_redo']['snapshot']['broken']=bad
            self.assertEqual(set(C.derive(r).values()),{'fail'})
        for field in ('source_sha256_after','source_bytes_after','peer_after'):
            r=row(mode='instanced');r[field]='wrong';self.assertEqual(C.derive(r)['source_unchanged'],'fail')
        for key in ('versions','write','persist_do','errors'):
            r=row();del r[key]
            with self.assertRaises(ValueError):C.derive(r)

    def test_actual_packed_key_time_shape(self):
        original={'players':{'AnimationPlayer':{'clips':{'generated':{'tracks':[{'keys':[[.008,17.,1.],[1.2,18.,1.]]}]}}}}}
        saved=copy.deepcopy(original)
        for key in saved['players']['AnimationPlayer']['clips']['generated']['tracks'][0]['keys']:
            key[0]=struct.unpack('f',struct.pack('f',key[0]))[0]
        self.assertTrue(C.snapshot_same(saved,original))
        broken=copy.deepcopy(saved)
        key=broken['players']['AnimationPlayer']['clips']['generated']['tracks'][0]['keys'][0]
        bits=struct.unpack('I',struct.pack('f',key[0]))[0]
        key[0]=struct.unpack('f',struct.pack('I',bits+1))[0]
        self.assertFalse(C.snapshot_same(broken,original))
        self.assertFalse(C.snapshot_same({'length':.008},{'length':saved['players']['AnimationPlayer']['clips']['generated']['tracks'][0]['keys'][0][0]}))
        broken=copy.deepcopy(saved)
        broken['players']['AnimationPlayer']['clips']['generated']['tracks'][0]['keys'][0][1]=17.001
        self.assertFalse(C.snapshot_same(broken,original))

    def test_source_and_public_span(self):
        args=span(row());self.assertEqual(set(C.verify_event(*args)['checks'].values()),{'pass'})
        for target,key,value in ((0,'run_id','other'),(0,'driver','other.gd'),(0,'operation','animation_motion.jump'),(0,'time_ns',301),(0,'test_run_begin_id','missing')):
            a=copy.deepcopy(args);a[target][key]=value
            with self.assertRaises(ValueError):C.verify_event(*a)
        for key,value in (('driver','wrong.py'),('context_sha256','f'*64),('route','private'),('kind','other')):
            a=copy.deepcopy(args);a[2][0][key]=value
            with self.assertRaises(ValueError):C.verify_event(*a)
        a=copy.deepcopy(args);del a[1]['dependencies'][C.DEPENDENCIES[0]]
        with self.assertRaises(ValueError):C.verify_event(*a)
        a=copy.deepcopy(args);a[3][0]['response']['results'][0]['passed']=False
        self.assertEqual(set(C.verify_event(*a)['checks'].values()),{'fail'})
        a=copy.deepcopy(args);a[3][0]['response']['results'][0]['test']='other'
        self.assertEqual(set(C.verify_event(*a)['checks'].values()),{'fail'})

    def test_booleans_and_typed_geometry(self):
        self.assertFalse(C.exact(True,1));self.assertFalse(C.exact(float('nan'),1))
        self.assertFalse(C.snapshot_same({'v':1.},{'v':1.000001}))
        self.assertTrue(C.snapshot_same({'type':'Vector3','x':1.},{'type':'Vector3','x':1.000001}))
        self.assertFalse(C.snapshot_same({'type':'Vector3','x':1.},{'type':'Vector3','x':1.001}))
        r=row('sequence','inline_pose');r['request']['segments'][1]['pose']['bones']['arm_L']['rotation']['x']=round(math_sin(),15)
        self.assertEqual(set(C.derive(r).values()),{'pass'})


def math_sin():
    import math
    return math.sin(.3)
if __name__=='__main__':unittest.main()
