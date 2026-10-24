"""Saved setup scheduling controls: no engine invocation."""
import copy
import unittest
import plan_setup_recording as subject

class Schedule(unittest.TestCase):
    def route(self):
        return {'cases':[{'id':str(i),'scene':'res://saved.tscn','scene_sha256':'a'*64,'write':{
            'clips':{'idle':{'length':2},'walk':{'length':1},'run':{'length':.6},'jump':{'length':1.201}},
            'speed_values':{'walk':1,'run':2},'root_motion':True}} for i in range(4)]}
    def test_all_scoped_conditions_preserve_input_and_two_fresh_takes(self):
        route=self.route(); before=copy.deepcopy(route)
        for condition,speed in [('half_idle_walk',.5),('half_walk_run',1.5),('jump',0)]:
            result=subject.build(route,condition)
            self.assertEqual(result['recording']['size'],[1920,1080])
            for row in result['cases']:
                self.assertEqual(row['render_spec']['takes'],2)
                self.assertEqual(row['render_spec']['frames_per_take'],180)
                self.assertEqual(row['render_spec']['speed_mps'],speed)
                self.assertEqual(row['render_spec']['controller_speed_mps'],0)
        self.assertEqual(route,before)
    def test_inplace_controller_matches_request(self):
        route=self.route()
        for row in route['cases']: row['write']['root_motion']=False
        self.assertEqual(subject.build(route,'half_walk_run')['cases'][0]['render_spec']['controller_speed_mps'],1.5)
    def test_truncated_cycle_and_jump_refused(self):
        for clip in ('walk','jump'):
            route=self.route();route['cases'][0]['write']['clips'][clip]['length']=4
            with self.assertRaises(ValueError):subject.build(route,'jump')
    def test_bad_duration_and_rig_scope_refused(self):
        for seconds in (0,float('nan'),2.99,3.001):
            with self.assertRaises(ValueError):subject.build(self.route(),'jump',seconds)
        route=self.route();route['cases'][0]['id']='1'
        with self.assertRaises(ValueError):subject.build(route,'jump')

    def test_nonfinite_bool_speed_and_missing_hash_refused(self):
        for value in (float('nan'),float('inf'),True,-1):
            route=self.route();route['cases'][0]['write']['speed_values']['run']=value
            with self.assertRaises(ValueError):subject.build(route,'half_walk_run')
        route=self.route();route['cases'][0]['scene_sha256']='wrong'
        with self.assertRaises(ValueError):subject.build(route,'jump')
