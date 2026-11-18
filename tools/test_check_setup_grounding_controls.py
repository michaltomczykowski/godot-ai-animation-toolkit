"""Offline orchestration controls; these never invoke Godot or qualify animation."""
import contextlib
import io
import json
import math
import copy
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch
import check_setup_grounding_controls as subject

class Controls(unittest.TestCase):
    def run_case(self, fault=None):
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory)
            scene=folder/"saved.tscn"
            scene.write_text("immutable saved scene",encoding="utf-8")
            route=folder/"route.json"
            route.write_text(json.dumps({"cases":[{"id":"rig", "scene":"res://saved.tscn", "scene_sha256":subject.digest(scene),
                "write":{"root_motion":True,"speed_values":{"walk":0.820639524335143,"run":1.641279048670286},"clips":{"idle":{},"walk":{},"run":{},"jump":{}}}}]}),encoding="utf-8")
            before=route.read_bytes()
            output=folder/"controls"
            def native(command, **kwargs):
                manifest=json.loads(Path(command[-2]).read_text(encoding="utf-8"))
                control=Path(command[-1]).stem
                negative=control in subject.NEGATIVE
                runs=[dict(id=row["id"], fps=fps, spec=spec, passed=not negative, grounding={"max_residual_m":1.0,"evaluation_residual_m":0.0,"target_tolerance_m":1e-5},
                           failures=["Saved grounding binding/ownership changed"] if negative else [])
                      for row in manifest["cases"] for spec in row["quality_specs"] for fps in subject.FPS]
                if fault=="godot_roundtrip":
                    for row in runs:
                        row["spec"]={key:float(format(value,".15g")) if type(value) is float else value
                                     for key,value in row["spec"].items()}
                errors=[]
                if fault=="falsepass" and control=="disabled": runs[0]["passed"]=True;runs[0]["failures"]=[]
                if fault=="wrong_identity" and control=="positive": runs[0]["id"]="different_rig"
                if fault=="engine_error" and control=="dynamic": errors=["real engine error"]
                if fault=="scene_write" and control=="positive": scene.write_text("modified",encoding="utf-8")
                Path(command[-1]).write_text(json.dumps(dict(runs=runs, passed=not negative,engine_errors=errors)),encoding="utf-8")
                return SimpleNamespace(returncode=1 if negative else 0)
            arguments=["controls", "--route",str(route),"--project-root",str(folder),"--godot","unused", "--output",str(output)]
            with patch("sys.argv",arguments), patch.object(subject.subprocess,"run",native), contextlib.redirect_stdout(io.StringIO()):
                status=subject.main()
            self.assertEqual(route.read_bytes(),before,"never rewrite source route")
            result=json.loads((output/"summary.json").read_text(encoding="utf-8"))
            self.assertEqual(status,0 if fault in (None,"godot_roundtrip") else 1)
            self.assertEqual(result["passed"],fault in (None,"godot_roundtrip"))
            self.assertEqual(result["wrapper_sha256"],subject.digest(Path(subject.__file__).resolve()))
            self.assertEqual(len(result["rows"]),12)
            self.assertEqual(len(list(output.glob("*-manifest.json"))),12)
            if fault is None:
                self.assertEqual(result["rows"][0]["runs"],15)
                self.assertEqual(result["rows"][1]["runs"],27)
            with patch("sys.argv",arguments):
                with self.assertRaises(FileExistsError): subject.main()
    def test_successful_controls(self): self.run_case()
    def test_godot_15_digit_roundtrip_controls(self): self.run_case("godot_roundtrip")
    def test_one_negative_falsepass_is_rejected(self): self.run_case("falsepass")
    def test_same_count_wrong_rig_is_rejected(self): self.run_case("wrong_identity")
    def test_engine_errors_are_fatal(self): self.run_case("engine_error")
    def test_original_scene_write_is_detected(self): self.run_case("scene_write")

class Identity(unittest.TestCase):
    def test_missing_or_nonlist_engine_error_receipt_is_rejected(self):
        manifest={"cases":[{"id":"rig","quality_specs":[{"kind":"blend","speed":1.0}]}]}
        report={"passed":True,"engine_errors":[],"runs":[dict(id="rig",fps=fps,spec={"kind":"blend","speed":1.0},passed=True) for fps in subject.FPS]}
        self.assertTrue(subject.qualifies_report(manifest,report,0,"positive"))
        missing=copy.deepcopy(report);missing.pop("engine_errors")
        self.assertFalse(subject.qualifies_report(manifest,missing,0,"positive"))
        for invalid in (None,"",{},0,False):
            with self.subTest(value=invalid):
                corrupt=copy.deepcopy(report);corrupt["engine_errors"]=invalid
                self.assertFalse(subject.qualifies_report(manifest,corrupt,0,"positive"))
    def test_actual_machine_echo_and_integer_spelling(self):
        self.assertTrue(subject.same_serialized_value({"speed":.4103197621675715,"duration":6.0},
                                                      {"speed":.410319762167571,"duration":6}))
    def test_real_numeric_change_is_rejected(self):
        self.assertFalse(subject.same_serialized_value(.4103197621675715,.4103197621676215))
    def test_nonfinite_is_rejected_even_when_equal(self):
        for value in (math.inf,-math.inf,math.nan):
            self.assertFalse(subject.same_serialized_value(value,value))
    def test_bool_does_not_alias_numbers(self):
        for value in (0,0.0,1,1.0):
            self.assertFalse(subject.same_serialized_value(True,value))
            self.assertFalse(subject.same_serialized_value(value,False))
    def test_zero_integer_and_json_structure_remain_exact(self):
        for left,right in ((0.0,1e-300),(10**16,10**16+1),({"speed":1.0},{}),
                           ({"speed":1.0},{"speed":1.0,"extra":0}),
                           ({"kind":"blend"},{"kind":"jump"}),("1",1)):
            self.assertFalse(subject.same_serialized_value(left,right))
    def test_cell_matching_is_one_to_one_and_exact_for_id_fps(self):
        manifest={"cases":[{"id":"rig","quality_specs":[{"kind":"blend","speed":.4103197621675715}]}]}
        runs=[dict(id="rig",fps=fps,spec={"kind":"blend","speed":.410319762167571}) for fps in subject.FPS]
        self.assertTrue(subject.identities_match(manifest,list(reversed(runs))))
        for key,value in (("id","other"),("fps",30.0),("fps",True),("fps",31)):
            corrupt=copy.deepcopy(runs);corrupt[0][key]=value
            self.assertFalse(subject.identities_match(manifest,corrupt))
        duplicate=copy.deepcopy(runs);duplicate[-1]=copy.deepcopy(duplicate[0])
        self.assertFalse(subject.identities_match(manifest,duplicate))
        ambiguous=copy.deepcopy(manifest);ambiguous["cases"][0]["quality_specs"]*=2
        self.assertFalse(subject.identities_match(ambiguous,runs+runs))

if __name__=="__main__": unittest.main()


class NewTake(unittest.TestCase):
    def test_distinct_specs_leave_legacy_unchanged(self):
        row={"write":{"speed_values":{"walk":1.0,"run":2.0},"clips":{},"root_motion":True}}
        self.assertEqual(subject.dynamic_specs(row)[-1]["reset_at_s"],3.0)
        positive=subject.new_take_specs(row)[0]
        negative=subject.new_take_specs(row,True)[0]
        self.assertEqual(positive["reset_at_s"],2.6)
        self.assertEqual(positive["reset_contract"],"new_take_v1")
        self.assertNotIn("omit_new_take_prime",positive)
        self.assertTrue(negative["omit_new_take_prime"])

    def test_unprimed_requires_endpoint_counterexample(self):
        spec={"reset_at_s":2.6}
        manifest={"cases":[{"id":"rig","quality_specs":[spec]}]}
        runs=[{"id":"rig","fps":fps,"spec":spec,"passed":False,
               "failures":["New-take endpoint differs from exact requested distance"]} for fps in subject.FPS]
        report={"runs":runs,"passed":False,"engine_errors":[]}
        self.assertTrue(subject.qualifies_report(manifest,report,1,"new_take_unprimed"))
        runs[0]["failures"]=["unrelated failure"]
        self.assertFalse(subject.qualifies_report(manifest,report,1,"new_take_unprimed"))

    def test_positive_requires_warm_reset_signal_witness(self):
        spec={"reset_at_s":2.6}
        manifest={"cases":[{"id":"rig","quality_specs":[spec]}]}
        witness={"cleared":True,"warm_anchors":1,"warm_phases":2,"prime_omitted":False}
        runs=[{"id":"rig","fps":fps,"spec":spec,"passed":True,"reset_performed":True,
               "extra_prime_signals":1,"takes":[{},{}],"reset_witness":dict(witness)} for fps in subject.FPS]
        report={"runs":runs,"passed":True,"engine_errors":[]}
        self.assertTrue(subject.qualifies_report(manifest,report,0,"new_take"))
        runs[0]["reset_witness"]["warm_anchors"]=0
        self.assertFalse(subject.qualifies_report(manifest,report,0,"new_take"))

