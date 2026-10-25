import copy
import unittest
from operation_saved_motion_checks import derive


def sample(op='walk_cycle'):
    checks=[dict(check='hip_bob',value=.04,budget=.12,passed=True)]
    feet={}
    for side in ('l','r'):
        checks += [dict(check='foot_slide.'+side,value=.002,budget=.016,passed=True),dict(check='ground_penetration.'+side,value=.001,budget=.008,passed=True),dict(check='knee_pole_flip.'+side,value=0,budget=0,passed=True)]
        feet[side]=dict(trace=[[i*.01,0,0] for i in range(31)],contact_time=.4,penetration_budget=.008,max_penetration=.001,worst_slide=.002)
    response=dict(hips=dict(trace=[[0,0,i*.03] for i in range(31)]),sample_count=31,length=1.,motion_kind='run' if op=='run_cycle' else 'gait',loop_mode='linear',body_travel=.82,in_place=False,checks=checks,feet=feet,support=dict(trace=[dict(state='l' if i%2 else 'r') for i in range(31)]),passed=True,failed_checks=0)
    if op=='run_cycle':
        response['flight']=dict(airborne_fraction=.1,clearance_budget=.016,peak_both_feet_clearance=.03,peak_leg_extension_ratio=.96)
        checks += [dict(check='run_flight',value=.03,budget=.016,passed=True),dict(check='run_leg_extension',value=.96,budget=.985,passed=True)]
    return dict(saved=dict(request=dict(op=op,root_motion=True,**({'preset':'walk'} if op=='cycle' else {}))),audit_request=dict(samples=31,max_slide=.016,motion_kind=response['motion_kind']),audit_response=response)

class CriteriaControls(unittest.TestCase):
    def test_positive_scopes(self):
        for op in ('walk_cycle','run_cycle','cycle'): self.assertEqual(derive(sample(op)),{'valid_effect':'pass'})
    def test_explicit_speed_pending(self):
        row=sample(); row['saved']['request']['speed']=1.; self.assertEqual(derive(row),{})
    def test_other_families_pending(self):
        row=sample(); row['saved']['request']['op']='idle_cycle'; self.assertEqual(derive(row),{})
    def test_corruptions(self):
        mutations=[lambda r:r['audit_response'].update(body_travel=.1),lambda r:r['audit_response'].update(body_travel=True),lambda r:r['audit_response'].update(body_travel=float('nan')),lambda r:r['audit_response'].update(in_place=True),lambda r:r['audit_response']['feet'].pop('l'),lambda r:r['audit_response']['feet']['l'].update(trace=[[0,0,0]]*31),lambda r:r['audit_response']['feet']['r'].update(contact_time=0),lambda r:r['audit_response']['support'].update(trace=[dict(state='both')]*31),lambda r:r['audit_response']['checks'][0].update(budget=.13),lambda r:r['audit_response']['checks'][1].update(value=.02),lambda r:r['audit_response']['checks'][1].update(budget=.02),lambda r:r['audit_response'].update(sample_count=30),lambda r:r['audit_response']['checks'].append(copy.deepcopy(r['audit_response']['checks'][0]))]
        for change in mutations:
            row=sample(); change(row)
            with self.subTest(change=change), self.assertRaises(ValueError): derive(row)
    def test_run_corruptions(self):
        for update in (dict(airborne_fraction=.04),dict(peak_both_feet_clearance=.01),dict(peak_leg_extension_ratio=1.)):
            row=sample('run_cycle'); row['audit_response']['flight'].update(update)
            with self.subTest(update=update),self.assertRaises(ValueError): derive(row)


class BindingControls(unittest.TestCase):
    def bound(self):
        from operation_saved_motion_checks import DEPS
        row=sample(); request=row['saved']['request']; request.update(player_path='/R/P',skeleton_path='/R/S',animation_name='walk_cycle')
        row['audit_request'].update(player_path='/R/P',skeleton_path='/R/S',animation_name='walk_cycle')
        row['audit_response'].update(player_path='/R/P',skeleton_path='/R/S',animation_name='walk_cycle')
        saved=row['saved']; saved.update(scene='res://run/one.tscn',scene_sha256='a'*64,context_sha256='c'*64,save_witness_id='w',save_command=['python','mcp_motion_remaining_cycles.py'],save_response={'path':'res://run/one.tscn'})
        row.update(audit_command=['python','mcp_motion_audit_saved.py','--run-id','run'],before_sha256='a'*64,after_sha256='a'*64,opened=dict(path='res://run/one.tscn',reloaded_from_disk=True))
        witness=dict(id='w',time_ns=3,validator='motion_saved_file_v1',driver='mcp_motion_remaining_cycles.py',row={k:v for k,v in saved.items() if k!='save_witness_id'})
        event=dict(id='e',time_ns=6,validator='motion_saved_audit_v1',driver='mcp_motion_audit_saved.py',operation='animation_motion.walk_cycle',context_sha256='c'*64,row=row)
        public=[dict(id='g',time_ns=1,driver='mcp_motion_remaining_cycles.py',operation=event['operation'],scene=saved['scene'],request=copy.deepcopy(request),response={}),dict(id='a',time_ns=5,driver='mcp_motion_audit_saved.py',operation='animation_inspect.motion_audit',scene=saved['scene'],request=copy.deepcopy(row['audit_request']),response=copy.deepcopy(row['audit_response']))]
        support=[dict(time_ns=2,driver='mcp_motion_remaining_cycles.py',public_tool='scene_save',scene=saved['scene'],response=copy.deepcopy(saved['save_response'])),dict(time_ns=4,driver='mcp_motion_audit_saved.py',public_tool='scene_open',request=dict(path=saved['scene'],force_reload=True),response=copy.deepcopy(row['opened']))]
        context=dict(run_id='actual-run',dependencies={k:dict(git_blob='d'*40,sha256='e'*64) for k in DEPS})
        for value,kind in [(event,'operation_snapshot_assertions'),(witness,'operation_snapshot_assertions')]+[(v,'public_operation_call') for v in public]+[(v,'public_support_call') for v in support]:
            value.update(schema_version=1,kind=kind,route='public_godot_ai',run_id='actual-run',context_sha256='c'*64)
            value.setdefault('id','support:'+str(value['time_ns']))
        witness['operation']=event['operation']
        return event,context,public,support,[witness]
    def test_exact_binding(self):
        from operation_saved_motion_checks import verify_event
        self.assertEqual(verify_event(*self.bound())['checks'],{'valid_effect':'pass'})
    def test_binding_corruptions(self):
        from operation_saved_motion_checks import verify_event
        for change in (lambda a:a[0]['row'].update(before_sha256='b'*64),lambda a:a[0]['row']['saved'].update(context_sha256='other'),lambda a:a[0]['row']['opened'].update(reloaded_from_disk=False),lambda a:a[2][0].update(scene='res://other.tscn'),lambda a:a[2][1]['response'].update(body_travel=999),lambda a:a[4].clear(),lambda a:a[1]['dependencies'].clear(),lambda a:a[3][1].update(time_ns=0),lambda a:a[2][0].update(context_sha256='f'*64),lambda a:a[2][1].update(run_id='foreign'),lambda a:a[3][0].update(route='fabricated'),lambda a:a[4][0].update(kind='other'),lambda a:a[1]['dependencies'].update({next(iter(a[1]['dependencies'])):{}})):
            args=list(self.bound());change(args)
            with self.subTest(change=change),self.assertRaises(ValueError):verify_event(*args)


    def test_other_tab_navigation_bound(self):
        from operation_saved_motion_checks import verify_event
        args=list(self.bound()); nav=copy.deepcopy(args[3][1]);nav.update(id='nav',time_ns=3.5);nav['time_ns']=35
        # Use integer native wall-clock units for all fixtures.
        for value in [args[0],*args[2],*args[3],*args[4]]:value['time_ns']*=10
        nav['response']['reloaded_from_disk']=False
        args[0]['row']['navigation']=copy.deepcopy(nav['response']);args[3].append(nav)
        self.assertEqual(verify_event(*args)['checks'],{'valid_effect':'pass'})
        args[3].pop()
        with self.assertRaises(ValueError):verify_event(*args)

if __name__=='__main__': unittest.main()
