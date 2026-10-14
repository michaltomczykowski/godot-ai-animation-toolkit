extends SceneTree
const Motion := preload("res://addons/godot_ai_animation/handlers/motion.gd")
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func _initialize() -> void:
	var plain := Motion._setup_plans({"include_jump": true, "include_turn": true, "angle": 180.0})
	check(not plain.has("error"), "default plan")
	check(not plain.plans[1].args.has("speed") and not plain.plans[1].args.has("duration"), "omitted walk controls remain omitted")
	check(not plain.plans[2].args.has("speed") and not plain.plans[2].args.has("duration"), "omitted run controls remain omitted")
	check(not plain.plans[3].args.has("height") and not plain.plans[3].args.has("crouch"), "jump geometry retains default provenance")
	check(plain.plans[3].args.duration == 1.2 and plain.plans[3].args.root_motion, "jump wrapper timing and extraction")
	check(not plain.plans[4].args.has("duration") and not plain.plans[4].args.root_motion, "turn automatic timing and skeletal ownership")
	var explicit := Motion._setup_plans({"speed": 0.3, "run_speed": 0.8, "duration": 0.9, "run_duration": 0.7, "include_jump": true, "jump_duration": 1.6, "height": 0.2, "crouch": 0.1, "distance": 0.4, "include_turn": true, "turn_duration": 1.8, "root_motion": false})
	check(explicit.plans[1].args.speed == 0.3 and explicit.plans[1].args.duration == 0.9, "explicit walk")
	check(explicit.plans[2].args.speed == 0.8 and explicit.plans[2].args.duration == 0.7, "explicit run")
	check(explicit.plans[3].args.height == 0.2 and explicit.plans[3].args.crouch == 0.1 and explicit.plans[3].args.distance == 0.4 and explicit.plans[3].args.duration == 1.6, "explicit jump")
	check(explicit.plans[4].args.duration == 1.8 and not explicit.plans[3].args.root_motion, "explicit turn and in-place jump")
	for bad in [{"run_speed": "fast"}, {"run_duration": 0.0}, {"turn_duration": -1.0}, {"height": INF}, {"samples": NAN}, {"speed": 2.0, "run_speed": 1.0}, {"jump_fadeout": -0.1}]:
		check(Motion._setup_plans(bad).has("error"), "refuse " + str(bad))
	check(plain.plans[4].args.steps == 2, "setup180 selects two internal stages")
	for owner in ["", "/Main/Actor"]:
		var script := GDScript.new()
		script.source_code = "extends Node3D\n" + Motion._apply_snippet("/Main/Actor/AnimationTree", "parameters/Base/blend_position", "parameters/OneShot/request", owner)
		check(script.reload() == OK, "generated snippet parses for owner " + owner)
	var example := load("res://examples/setup_translation_consumer.gd") as GDScript
	check(example != null and example.can_instantiate(), "translation consumer example parses")
	print("TIER1_SETUP_PROVENANCE=" + JSON.stringify({"passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
