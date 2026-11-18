"""Synthetic20edit native adapter controls, not qualification evidence."""
import copy
import json
import unittest
import operation_edit_native_checks as s


def fixture(op):
    length={'retime':.5,'trim':.6,'offset':1.2,'overlap':1.1}.get(op,1.)
    values=s.intended(op,length)
    observations=[{'clip':clip,'time':t,'node':node,'axis':axis,'measured':v,'assigned_animation':clip,'player_position':t} for clip,t,node,axis,v in values]
    clips={}
    for name in {v[0] for v in values}:
        clips[name]={'length':.5 if op=='split_at' else 2 if op=='merge' else length,'loop_mode':2 if op=='loop' else 1,'tracks':[{'path':'OtherCharacter:position' if op=='retarget' else 'Character:position','type':0,'enabled':True,'node_resolved':True,'node_class':'Node2D','property':'position','property_type':5,'key_count':2,'key_times':[0,1],'interpolation':0 if op=='set_interp' else 1}]}
    for clip in clips.values():
        if op in ('resample','add_noise'):
            clip['tracks'][0].update(key_count=31,key_times=[i/30 for i in range(31)])
        if op=='cleanup':clip['tracks'][0].update(key_count=1,key_times=[1])
    raw={'schema':'edit_native_intention_v1','scene_sha256':'a'*64,'fixture_sha256':'b'*64,'fixture_class':'Node2D','player_class':'AnimationPlayer','player_path':'AnimationPlayer','root_node':'..','root_resolves_fixture':True,'clock':'native_seek_advance_zero','clips':clips}
    report={'op':op,'scene':'res://saved.tscn','length':length,'raw':raw,'engine_errors':[],'worst_error':0.}
    if op in s.SIMPLE:report.update(observations=observations,samples=[x['measured'] for x in observations],expected=[x['measured'] for x in observations])
    else:report['samples']=observations
    return report


def event(op,report=None):
    report=fixture(op) if report is None else report
    prefix='EDIT_RUNTIME=' if op in s.SIMPLE else 'EDIT_REMAINING='
    e={'operation':'animation_edit.'+op,'scene':'res://saved.tscn','driver':'ci_mcp_route.py','route':'native_godot','returncode':0,'stdout':prefix+json.dumps(report),'stderr':'','command':['godot','--headless','--path','project','--script','res://tools/'+s.checker(op),'--','res://saved.tscn',op]}
    c={'engine_command':'godot','dependencies':{p:{'sha256':'b'*64,'git_blob':'c'*40} for p in (*s.DEPENDENCIES,'test_project/tools/'+s.checker(op))}}
    return e,c


class EditNative(unittest.TestCase):
    def test_all20_fixed_contracts(self):
        self.assertEqual(len(s.OPS),20)
        for op in s.OPS:
            e,c=event(op);checks,errors=s.verify_native(e,c)
            self.assertTrue(all(x=='pass' for x in checks.values()),(op,checks,errors))
            call={'driver':'mcp_edit_audit.py','route':'public_godot_ai','operation':e['operation'],'scene':e['scene'],'params':dict(s.REQUESTS[op],op=op,player_path='/RepairGraphFixture/AnimationPlayer',animation_name=s.source_clip(op))}
            self.assertTrue(s.origin_matches(e,call),op)
    def test_every_operation_wrong_measured_value_fails_despite_expected_echo(self):
        for op in s.OPS:
            report=fixture(op);samples=report['observations'] if op in s.SIMPLE else report['samples']
            samples[0].update(measured=999,expected=999)
            report['expected']=[999]*3;report['worst_error']=0
            self.assertEqual(s.derive(report,op,'b'*64)['valid_effect'],'fail',op)
    def test_actual_path_type_and_clock_corruptions(self):
        for fault in ('path','track_type','bool_type','disabled','unresolved','class','property_type','root','player','clock','time','clip','node','axis','nonfinite','bool_measure','count','length','missing_errors','engine_error','fixture','scene_hash','interp','dtposition','cleanup_not_reduced','reduce_not_reduced','noise_not_prepared'):
            report=fixture('set_interp' if fault=='interp' else 'cleanup' if fault=='cleanup_not_reduced' else 'reduce' if fault=='reduce_not_reduced' else 'add_noise' if fault=='noise_not_prepared' else 'retime');op=report['op'];sample=(report['observations'] if op in s.SIMPLE else report['samples'])[0];track=next(iter(report['raw']['clips'].values()))['tracks'][0]
            if fault=='path':track['path']='Other:position'
            elif fault=='track_type':track['type']=1
            elif fault=='bool_type':track['type']=False
            elif fault=='disabled':track['enabled']=False
            elif fault=='unresolved':track['node_resolved']=False
            elif fault=='class':track['node_class']='Node3D'
            elif fault=='property_type':track['property_type']=3
            elif fault=='root':report['raw']['root_resolves_fixture']=False
            elif fault=='player':report['raw']['player_path']='Wrong'
            elif fault=='clock':report['raw']['clock']='generated_curve'
            elif fault=='time':sample['time']=.3
            elif fault=='clip':sample['clip']='other'
            elif fault=='node':sample['node']='OtherCharacter'
            elif fault=='axis':sample['axis']='y'
            elif fault=='nonfinite':sample['measured']=float('nan')
            elif fault=='bool_measure':sample['measured']=True
            elif fault=='count':report['observations'].pop()
            elif fault=='length':report['length']=2
            elif fault=='missing_errors':del report['engine_errors']
            elif fault=='engine_error':report['engine_errors']=['real error']
            elif fault=='fixture':report['raw']['fixture_sha256']='f'*64
            elif fault=='scene_hash':report['raw']['scene_sha256']='bad'
            elif fault=='interp':track['interpolation']=1
            elif fault in ('cleanup_not_reduced','reduce_not_reduced','noise_not_prepared'):track.update(key_count=3,key_times=[0,.5,1])
            elif fault=='dtposition':sample['player_position']=.1
            with self.subTest(fault=fault):self.assertIn('fail',s.derive(report,op,'b'*64).values())
    def test_original_strict_thresholds_not_relaxed(self):
        for op,limit in [('retime',1.),('smooth',.25)]:
            r=fixture(op);samples=r['observations'] if op in s.SIMPLE else r['samples']
            samples[0]['measured']+=limit;r['worst_error']=limit
            self.assertEqual(s.derive(r,op,'b'*64)['valid_effect'],'fail')
    def test_exact_source_command_and_public_origin_required(self):
        for fault in ('engine','source','driver','operation','scene','exit','error','prefix','args'):
            e,c=event('retime')
            if fault=='engine':e['command'][0]='other'
            elif fault=='source':c['dependencies'].pop(s.DEPENDENCIES[0])
            elif fault=='driver':e['driver']='other.py'
            elif fault=='operation':e['operation']='animation_edit.reverse'
            elif fault=='scene':e['scene']='res://other.tscn'
            elif fault=='exit':e['returncode']=1
            elif fault=='error':e['stderr']='ERROR: real failure'
            elif fault=='prefix':e['stdout']+='\n'+e['stdout']
            elif fault=='args':e['command'][-1]='reverse'
            with self.subTest(fault=fault):
                try:checks,_=s.verify_native(e,c)
                except ValueError:continue
                self.assertTrue(all(x=='fail' for x in checks.values()))
        e,c=event('retime');call={'driver':'mcp_edit_audit.py','route':'public_godot_ai','operation':e['operation'],'scene':e['scene'],'params':dict(s.REQUESTS['retime'],op='retime',player_path='/RepairGraphFixture/AnimationPlayer',animation_name='walk')}
        for key,value in [('driver','other.py'),('scene','res://other.tscn'),('operation','animation_edit.reverse')]:
            changed=copy.deepcopy(call);changed[key]=value;self.assertFalse(s.origin_matches(e,changed))
        changed=copy.deepcopy(call);changed['params']['factor']=True;self.assertFalse(s.origin_matches(e,changed))
