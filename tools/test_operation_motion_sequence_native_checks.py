"""Synthetic corruption controls only; no native engine is launched."""
import copy
import json
import math
import unittest
import operation_motion_sequence_native_checks as N
from test_operation_motion_sequence_history_checks import row,span

def pair(group='sequence',variant='gap'):
    p=row(group,variant);p.update(reference_path='user://motion_sequence_'+p['case_id']+'_reference.tres',reference_sha256='a'*64)
    n={k:p[k] for k in ('group','variant','mode','fps')};n.update(id=p['case_id'],params=p['request'],source=dict(path=p['source_scene_path'],sha256=p['source_scene_sha256'],bytes=p['source_scene_bytes']),reference=dict(path=p['reference_path'],sha256=p['reference_sha256'],bytes=300),states={s:{k:p['persist_'+s][k] for k in ('path','sha256','bytes')} for s in ('do','undo','redo')},thresholds=N.THRESHOLDS.copy(),failure_count=0,engine_errors=[],plays=[],travel=[])
    length=p['request']['duration']
    t=dict(path='Skeleton:hips',type=2,target_class='Skeleton3D',bone='hips',bone_index=0,subnames=1,times=[0.,length],finite_values=True,normalized=True)
    q=[0.,0.,0.,1.];zero=dict(actual=[0.,0.,0.],reference=[0.,0.,0.],error=0.,time=0.,path='')
    for state in ('do','undo','redo'):
        for fps in (30,60,120):
            times=sorted(set([0.,length]+[k/fps for k in range(1,math.ceil(length*fps))]))
            witness=dict(actual=q,reference=q,error=0.,time=0.,path='Skeleton:hips')
            change=dict(actual=[math.sin(.2),0,0,math.cos(.2)],reference=q,error=.4,time=length,path='Skeleton:hips')
            n['plays'].append(dict(state=state,fps=fps,clock='native_manual_advance',length=length,loop_mode=0,root_motion_track='',times=times,actual_tracks=[copy.deepcopy(t)],reference_tracks=[copy.deepcopy(t)],pose_samples=len(times),key_samples=2,intermediate_samples=len(times)-2,errors=dict(rotation=witness,root_delta=copy.deepcopy(zero)),reference_span=dict(rotation=change)))
    return p,n

def batch(p,n):
    event,ctx,begins,ends=span(p)
    ctx['engine_command']='godot.exe';ctx['dependencies'].update({x:dict(sha256='a'*64,git_blob='b'*40) for x in N.DEPENDENCIES})
    ids={f'{g}_{v}_{m}_{fps}' for g,variants,modes in (('motion',N.MOTIONS,('local','instanced','editable','missing_library','overwrite')),('secondary',('single','branches'),('local','instanced','editable')),('sequence',N.SEQUENCES,('local','instanced','editable','missing_library','overwrite'))) for v in variants for m in modes for fps in (30,60,120)}
    rows=[n]+[dict(n,id=i) for i in sorted(ids-{n['id']})]
    report=dict(native_dependencies={x:'a'*64 for x in N.DEPENDENCIES[:3]},evidence_schema='motion_sequence_native_v1',manifest_sha256='f'*64,native_cases=rows,failures=[],engine_errors=[])
    b=dict(kind='native_saved_output',run_id=ctx['run_id'],context_sha256=event['context_sha256'],operation='animation_sequence.compose',scene='user://motion_sequence_saved_matrix.json',driver='mcp_motion_sequence_history.py',route='native_godot',command=['godot.exe','--headless','--path','isolated/project','--script','res://tools/check_motion_sequence_history.gd'],returncode=0,stdout='MOTION_SEQUENCE_HISTORY_RUNTIME='+json.dumps(report),stderr='',execution_ns=3000)
    return event,ctx,begins,ends+[b]

class Native(unittest.TestCase):
    def test_positive_and_scope(self):
        for group,variant in (('motion','walk_cycle'),('secondary','single'),('sequence','gap')):
            p,n=pair(group,variant);checks=N.derive(p,n)
            self.assertEqual(set(checks.values()),{'pass'})
            self.assertEqual('valid_effect' in checks,group!='motion')
            proof=N.verify_event(*batch(p,n));self.assertEqual(set(proof['checks'].values()),{'pass'})

    def test_raw_corruptions(self):
        changes=[lambda n:n['plays'][0]['errors']['rotation'].update(actual=[1.,0.,0.,0.]),lambda n:n['plays'][0]['errors']['root_delta'].update(actual=[1.,0.,0.]),lambda n:n['plays'][0]['actual_tracks'][0].update(bone_index=-1),lambda n:n['plays'][0]['actual_tracks'][0].update(finite_values=False),lambda n:n['plays'][0]['reference_tracks'][0].update(path='Wrong:hips'),lambda n:n['plays'][0].update(times=[0.,1.6]),lambda n:n['plays'][0].update(pose_samples=1),lambda n:n['plays'][0].update(clock='seek_only'),lambda n:n.update(failure_count=1),lambda n:n.update(engine_errors=['real error']),lambda n:n['plays'][0]['actual_tracks'][0].update(normalized=False),lambda n:n['plays'][0]['errors']['rotation'].update(time=999),lambda n:n['plays'][0]['errors']['rotation'].update(path='wrong')]
        for mutate in changes:
            p,n=pair();mutate(n);self.assertIn('fail',N.derive(p,n).values())
        for mutate in (lambda n:n.update(id='wrong'),lambda n:n.pop('reference'),lambda n:n['source'].update(sha256='b'*64),lambda n:n['states']['redo'].update(sha256='b'*64),lambda n:n['thresholds'].update(rotation=1),lambda n:n['plays'].pop()):
            p,n=pair();mutate(n)
            with self.assertRaises(ValueError):N.derive(p,n)
        p,n=pair()
        for play in n['plays']:play['reference_span']['rotation'].update(error=0.,actual=[0.,0.,0.,1.])
        self.assertEqual(N.derive(p,n)['valid_effect'],'fail')

    def test_native_command_and_binding(self):
        a=batch(*pair());self.assertEqual(set(N.verify_event(*a)['checks'].values()),{'pass'})
        for key,value in (('driver','wrong.py'),('context_sha256','b'*64),('run_id','wrong'),('scene','other'),('command',['godot.exe','--script','other.gd'])):
            b=copy.deepcopy(a);b[3][-1][key]=value
            with self.assertRaises(ValueError):N.verify_event(*b)
        for mutate in (lambda r:r['native_dependencies'].update({N.DEPENDENCIES[0]:'b'*64}),lambda r:r['native_cases'][0].update(id='wrong'),lambda r:r.pop('manifest_sha256')):
            b=copy.deepcopy(a);report=json.loads(b[3][-1]['stdout'].split('=',1)[1]);mutate(report);b[3][-1]['stdout']='MOTION_SEQUENCE_HISTORY_RUNTIME='+json.dumps(report)
            with self.assertRaises(ValueError):N.verify_event(*b)
        b=copy.deepcopy(a);b[3][-1]['returncode']=1
        self.assertEqual(N.verify_event(*b)['checks']['playback'],'fail')
        b=copy.deepcopy(a);b[3].pop()
        self.assertNotIn('playback',N.verify_event(*b)['checks'])
        b=copy.deepcopy(a);b[3].append(copy.deepcopy(b[3][-1]))
        with self.assertRaises(ValueError):N.verify_event(*b)

    def test_thresholds_not_relaxed(self):
        self.assertEqual(N.THRESHOLDS,dict(position=.0001,rotation=.001,scale=.0001,root_delta=.0001))
        for field,limit in N.THRESHOLDS.items():
            for factor,expected in ((.999,True),(1.001,False)):
                d=limit*factor
                a=[math.sin(d/2),0.,0.,math.cos(d/2)] if field=='rotation' else [d,0.,0.]
                b=[0.,0.,0.,1.] if field=='rotation' else [0.,0.,0.]
                self.assertEqual(N.metric(dict(actual=a,reference=b,error=d,time=0.),limit,field=='rotation'),expected)
if __name__=='__main__':unittest.main()
