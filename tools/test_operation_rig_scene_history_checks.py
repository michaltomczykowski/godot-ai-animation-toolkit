"""Deliberate evidence corruptions; synthetic records are not execution proof."""
from copy import deepcopy
import unittest
import operation_rig_scene_history_checks as s

def fixture(op,kind='3d',mode='local',variant=None):
    family='pose' if op=='pose_apply' else 'chain' if op=='rig_chain' else 'clip'
    variant=variant or ('apply' if family=='pose' else 'create' if family=='chain' else 'clip')
    label=f'{mode}_{kind}_{op}' if family=='clip' else f'{kind}_{mode}_{variant}'
    r=dict(op=op,kind=kind,mode=mode,variant=variant,label=label,suite='rig_'+family+'_history',test=f'test_{mode}_history' if family=='clip' else f'test_{mode}_{family}_history',fixture_path='/root/Main/'+{'pose':'RigPoseHistory','chain':'RigChainHistory','clip':'RigClipHistory'}[family],scene='res://fixture.tscn',failed_before=False,failed_after=False,assertion_count=42,errors_before=0,errors_after=0,errors=[])
    r['request']=s.expected_request(r)
    skeleton=dict(type='Skeleton3D' if kind=='3d' else 'Skeleton2D',children={},bones=[dict(name='arm_L',parent=-1,rest={'x':1},pose={'x':2},enabled=True)])
    if kind=='2d':
        skeleton.pop('bones')
        skeleton['children']['arm_L']=dict(type='Bone2D',rest={'x':1},transform={'x':2},children={})
    snap=dict(type='Node',children={'Skeleton':skeleton})
    if family=='chain' and variant=='subtree':snap['children']['Branch']=dict(type='Node3D',children={'Leaf':dict(type='Node3D',transform={'x':1},children={})})
    if family=='clip':
        snap['players']={'AnimationPlayer':dict(clips={'source/input':{'keys':[1,2]},'source/next':{'keys':[3]},'unrelated':{'keys':[4]}},libraries=['source'] if mode=='missing_library' else ['','source'],root='../Character',speed=.8),'OtherPlayer':dict(clips={'other':{'keys':[5]}},libraries=[''])}
        if mode=='overwrite':snap['players']['AnimationPlayer']['clips']['generated']={'keys':[8]}
    generated=deepcopy(snap)
    if family=='clip':
        generated['players']['AnimationPlayer']['clips']['generated']={'keys':[9,10]}
        if mode=='missing_library':generated['players']['AnimationPlayer']['libraries']=['','source']
    elif family=='pose':
        if kind=='3d':generated['children']['Skeleton']['bones'][0]['pose']={'x':3}
        else:generated['children']['Skeleton']['children']['arm_L']['transform']={'x':3}
    elif variant=='append':
        if kind=='3d':generated['children']['Skeleton']['bones'].append(dict(name='tool',parent=0,rest={'x':7},pose={'x':7},enabled=True))
        else:generated['children']['Skeleton']['children']['arm_L']['children']['tool']=dict(type='Bone2D',rest={'x':7},transform={'x':7},children={})
    else:(generated['children']['Branch'] if variant=='subtree' else generated)['children']['Generated']=dict(type='Skeleton3D',bones=[dict(name='tool')],children={})
    before=dict(snapshot=snap,version=20,global_version=9,editable=mode=='editable')
    after=dict(snapshot=generated,version=21,global_version=9,editable=mode in {'locked','instanced','editable'})
    if family=='clip':before['playback']=after['playback']={'playing':False,'position':.2,'queue':['source/next']}
    r['before']=before
    r['dry']=dict(response={'data':{'dry_run':True}},state=deepcopy(before))
    invalid=deepcopy(r['request'])
    if family=='pose':invalid['pose']['bones']={'ghost':next(iter(invalid['pose']['bones'].values()))}
    else:invalid['node_path' if family=='chain' else 'player_path']='/Missing'
    r['refusal']=dict(request=invalid,response={'error':{'code':'INVALID_PARAMS' if family=='pose' else 'NODE_NOT_FOUND','message':'Expected refusal'}},state=deepcopy(before))
    r['write']=dict(response={'data':{'undoable':True}},state=after)
    r['undo']=dict(success=True,state=deepcopy(before));r['redo']=dict(success=True,state=deepcopy(after))
    for stage,value in [('undo',snap),('redo',generated)]:r['persist_'+stage]=dict(path=f'user://rig_{family}_history_{label}_{stage}.tscn',pack_result=0,save_result=0,sha256='a'*64,snapshot=deepcopy(value))
    instanced=mode not in {'local','overwrite','missing_library'}
    r.update(source_path=f'user://rig_{family}_source_{label}.tscn' if instanced else '',source_before='b'*64 if instanced else '',source_after='b'*64 if instanced else '',peer_before=deepcopy(snap) if instanced else {},peer_after=deepcopy(snap) if instanced else {},pristine=deepcopy(snap) if instanced else {})
    return r

class RigHistory(unittest.TestCase):
    def test_existing_93_case_identities(self):
        rows=[]
        for mode in ('local','locked','editable'):
            for kind in ('3d','2d'):
                rows += [fixture('pose_apply',kind,mode,v) for v in ('apply','blend','reset','reset_blend','mirror')]
                rows += [fixture('rig_chain',kind,mode,v) for v in ('create','append','subtree')]
        for mode in ('local','overwrite','missing_library','instanced','editable'):
            rows += [fixture(op,'3d',mode) for op in s.WRITERS]+[fixture('pose_to_clip','2d',mode)]
        self.assertEqual(len(rows),93)
        for row in rows:self.assertEqual(set(s.derive(row).values()),{'pass'},row['label'])

    def test_each_operation_rejects_corrupt_native_history(self):
        for op in s.OPS:
            for stage in ('dry','refusal','undo','redo'):
                r=fixture(op);r[stage]['state']['snapshot']['children']['surprise']={'type':'Node'}
                check='dry_run' if stage=='dry' else 'typed_errors' if stage=='refusal' else 'undo_redo'
                self.assertEqual(s.derive(r)[check],'fail',(op,stage))
            r=fixture(op);r['write']['state']['version']=True
            self.assertTrue(all(x=='fail' for x in s.derive(r).values()))
            r=fixture(op);r['refusal']['response']['error']['code']='WRONG_TYPE'
            self.assertEqual(s.derive(r)['typed_errors'],'fail')
            r=fixture(op);r['persist_redo']['sha256']='missing'
            self.assertEqual(s.derive(r)['save_reopen'],'fail')
            r=fixture(op);r['errors']=['engine error'];r['errors_after']=1
            self.assertEqual(s.derive(r)['reported_errors'],'fail')
            r=fixture(op)
            for state in [r['before']]+[r[k]['state'] for k in ('dry','refusal','write','undo','redo')]:state['editable']=True
            self.assertEqual(set(s.derive(r).values()),{'fail'},op)

    def test_observed_sources_and_saved_state_must_match(self):
        for op in s.OPS:
            r=fixture(op,mode='editable')
            r['peer_after']['children']['foreign']={'type':'Node'}
            self.assertEqual(s.derive(r)['source_unchanged'],'fail',op)
            r=fixture(op,mode='editable');r['source_after']='c'*64
            self.assertEqual(s.derive(r)['source_unchanged'],'fail',op)
            r=fixture(op);r['write']['state']['snapshot']['children']['Skeleton']['bones'][0]['rest']['x']=99
            self.assertEqual(s.derive(r)['source_unchanged'],'fail',op)
            r=fixture(op);r['persist_undo']['snapshot']['children']['Skeleton']['bones'][0]['rest']['x']=99
            self.assertEqual(s.derive(r)['save_reopen'],'fail',op)
        r=fixture('walk_cycle');r['write']['state']['playback']={'playing':True}
        self.assertEqual(s.derive(r)['undo_redo'],'fail')
        for op in s.WRITERS:
            for libraries in ([''],['','extra','source'],['source'],[]):
                r=fixture(op,mode='missing_library')
                r['write']['state']['snapshot']['players']['AnimationPlayer']['libraries']=libraries
                self.assertEqual(s.derive(r)['source_unchanged'],'fail',(op,libraries))

    def test_binding_missing_stages_wrong_requests_and_public_span(self):
        r=fixture('squat');r['request']['bob']=.8
        with self.assertRaises(ValueError):s.derive(r)
        r=fixture('squat');del r['undo']
        with self.assertRaises(ValueError):s.derive(r)
        r=fixture('squat');r['failed_before']=True
        self.assertEqual(set(s.derive(r).values()),{'fail'})
        r=fixture('squat');ctx={'run_id':'run','dependencies':{p:dict(sha256='a'*64,git_blob='b'*40) for p in s.DEPENDENCIES}}
        e=dict(row=r,validator='rig_scene_history_v1',driver='test_rig_clip_history.gd',route='public_test_run_inner_dispatch',operation='animation_rig.squat',run_id='run',test_run_begin_id='begin',time_ns=20)
        req=dict(suite=r['suite'],verbose=True)
        start=dict(id='begin',request=req,scene=r['scene'],execution_ns=1,time_ns=10)
        end=dict(id='end',test_run_begin_id='begin',public_tool='test_run',request=req,scene=r['scene'],execution_ns=2,time_ns=30,response={'results':[dict(suite=r['suite'],test=r['test'],passed=True,assertion_count=100)]})
        self.assertEqual(set(s.verify_event(e,ctx,[start],[end])['checks'].values()),{'pass'})
        for fault in ('run','source','time','scene','result'):
            event,c,a,b=deepcopy((e,ctx,start,end))
            if fault=='run':event['run_id']='other'
            elif fault=='source':c['dependencies'].pop(s.DEPENDENCIES[0])
            elif fault=='time':event['time_ns']=40
            elif fault=='scene':b['scene']='res://other.tscn'
            else:b['response']['results'][0]['passed']=False
            try:proof=s.verify_event(event,c,[a],[b])
            except ValueError:continue
            self.assertEqual(set(proof['checks'].values()),{'fail'},fault)

if __name__=='__main__':unittest.main()
