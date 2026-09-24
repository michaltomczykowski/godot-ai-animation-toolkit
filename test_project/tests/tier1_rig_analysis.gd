extends SceneTree

## Tier-1 headless checks for the pure rig analysis: role detection with ranked
## candidates, T/A pose classification, capabilities, sample/contact math and
## rig-profile validation. No editor, no skeleton. Run with:
##
##   godot --headless --path test_project --script res://tests/tier1_rig_analysis.gd

const RigAnalysis := preload("res://addons/godot_ai_animation/spec/rig_analysis.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	_check_role_detection()
	_check_detection_edges()
	_check_arm_pose()
	_check_capabilities()
	_check_sample_times()
	_check_contacts()
	_check_profile_validation()
	if _failures == 0:
		print("TIER1 PASS (%d checks)" % _checks)
	else:
		print("TIER1 FAIL (%d/%d checks failed)" % [_failures, _checks])
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  FAIL: %s" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _expect_approx(actual: float, expected: float, message: String) -> void:
	_expect(absf(actual - expected) < 0.001, "%s (expected %s, got %s)" % [message, expected, actual])


func _humanoid() -> Array:
	return [
		"B-hips", "B-spine", "B-chest", "B-neck", "B-head",
		"B-shoulder.L", "B-upperArm.L", "B-forearm.L", "B-hand.L",
		"B-shoulder.R", "B-upperArm.R", "B-forearm.R", "B-hand.R",
		"B-thigh.L", "B-shin.L", "B-foot.L", "B-toe.L",
		"B-thigh.R", "B-shin.R", "B-foot.R", "B-toe.R",
	]


func _check_role_detection() -> void:
	var detected := RigAnalysis.detect_roles(_humanoid())
	var roles: Dictionary = detected.roles
	_expect_eq(str(roles.hips), "B-hips", "hips is detected")
	_expect_eq(str(roles.spine), "B-spine", "spine is detected")
	_expect_eq(str(roles.chest), "B-chest", "chest is detected")
	_expect_eq(str(roles.head), "B-head", "head is detected")
	_expect_eq(str(roles.arm_l), "B-upperArm.L", "the left upper arm is detected")
	_expect_eq(str(roles.forearm_l), "B-forearm.L", "the left forearm is detected")
	_expect_eq(str(roles.hand_r), "B-hand.R", "the right hand is detected")
	_expect_eq(str(roles.shoulder_l), "B-shoulder.L", "the left shoulder is detected")
	_expect_eq(str(roles.thigh_r), "B-thigh.R", "the right thigh is detected")
	_expect_eq(str(roles.shin_l), "B-shin.L", "the left shin is detected")
	_expect_eq(str(roles.foot_r), "B-foot.R", "the right foot is detected")
	_expect_eq(str(roles.toe_l), "B-toe.L", "the left toe is detected")
	_expect(not roles.has("eye_l"), "no eye role is invented")
	var candidates: Dictionary = detected.candidates
	_expect_eq(str(candidates.arm_l), str(["B-upperArm.L"]), "arm candidates list the only match")
	var unmatched: Array = detected.unmatched
	_expect_eq(unmatched, ["B-neck"], "unmatched bones are reported (%s)" % str(unmatched))
	_expect_eq(RigAnalysis.side_of("B-upperArm.L"), "l", ".L marks the left side")
	_expect_eq(RigAnalysis.side_of("hand_r"), "r", "_r marks the right side")
	_expect_eq(RigAnalysis.side_of("LeftHand"), "l", "'Left' marks the left side")
	_expect_eq(RigAnalysis.side_of("B-spine"), "", "bones without a marker have no side")


func _check_detection_edges() -> void:
	var weak := RigAnalysis.detect_roles(["B-arm.L"])
	_expect_eq(str(weak.roles.arm_l), "B-arm.L", "a plain 'arm' bone is a fallback upper arm")
	var strong := RigAnalysis.detect_roles(["B-arm.L", "B-upperArm.L"])
	_expect_eq(str(strong.roles.arm_l), "B-upperArm.L",
		"the upper arm wins over the plain arm regardless of order")
	_expect_eq(str(strong.candidates.arm_l), str(["B-upperArm.L", "B-arm.L"]),
		"candidates are ranked strong first")
	var shoulder := RigAnalysis.detect_roles(["B-shoulder.R", "B-clavicle.R"])
	_expect_eq(str(shoulder.roles.shoulder_r), "B-shoulder.R", "shoulder beats clavicle")
	_expect(not shoulder.roles.has("arm_r"), "a shoulder bone does not steal the arm role")
	var foot := RigAnalysis.detect_roles(["B-ankle.L", "B-toe.L"])
	_expect_eq(str(foot.roles.foot_l), "B-ankle.L", "ankle is a foot fallback")
	_expect_eq(str(foot.roles.toe_l), "B-toe.L", "the toe stays a toe")
	var pelvis := RigAnalysis.detect_roles(["pelvis"])
	_expect_eq(str(pelvis.roles.hips), "pelvis", "pelvis maps to hips")
	var proxy := RigAnalysis.detect_roles(["B-spine_proxy"])
	_expect(not proxy.roles.has("spine"), "spine proxies are ignored")
	var fallback_chest := RigAnalysis.detect_roles(["B-spine", "B-ribcage"])
	_expect_eq(str(fallback_chest.roles.chest), "B-spine", "chest falls back to the spine bone")
	var chest_wins := RigAnalysis.detect_roles(["B-spine", "B-chest"])
	_expect_eq(str(chest_wins.roles.chest), "B-chest", "a chest bone beats the spine fallback")
	_expect_eq(str(chest_wins.candidates.chest), str(["B-chest", "B-spine"]),
		"chest candidates are ranked by keyword")
	var eyes := RigAnalysis.detect_roles(["eyelid.L", "eye.R"])
	_expect_eq(str(eyes.roles.eye_l), "eyelid.L", "eyelids count as eyes")
	_expect_eq(str(eyes.roles.eye_r), "eye.R", "an eye bone is detected")


func _check_arm_pose() -> void:
	var t_pose := RigAnalysis.arm_pose({"l": Vector3(1, 0, 0), "r": Vector3(-1, 0, 0)})
	_expect_eq(str(t_pose.pose), "T", "horizontal arms are a T-pose")
	_expect_approx(float(t_pose.arm_angle_degrees), 90.0, "T-pose angle is 90 degrees")
	var a_pose := RigAnalysis.arm_pose({"l": Vector3(0.7, -0.7, 0)})
	_expect_eq(str(a_pose.pose), "A", "45-degree arms are an A-pose")
	var down := RigAnalysis.arm_pose({"l": Vector3(0, -1, 0), "r": Vector3(0, -1, 0)})
	_expect_eq(str(down.pose), "arms_down", "hanging arms are arms_down")
	_expect_approx(float(down.arm_angle_degrees), 0.0, "arms_down angle is 0 degrees")
	var mixed := RigAnalysis.arm_pose({"l": Vector3(0, -1, 0), "r": Vector3(1, 0, 0)})
	_expect_eq(str(mixed.pose), "T", "the widest arm decides the classification")
	var unknown := RigAnalysis.arm_pose({})
	_expect_eq(str(unknown.pose), "unknown", "no arm directions means unknown")
	var zero := RigAnalysis.arm_pose({"l": Vector3.ZERO})
	_expect_eq(str(zero.pose), "unknown", "zero-length directions are skipped")


func _check_capabilities() -> void:
	var detected := RigAnalysis.detect_roles(_humanoid())
	var caps := RigAnalysis.capabilities(detected.roles, 21)
	_expect(bool(caps.idle_cycle), "the humanoid can idle")
	_expect(bool(caps.walk_cycle), "the humanoid can walk")
	_expect(bool(caps.run_cycle), "the humanoid can run")
	_expect(bool(caps.jump), "the humanoid can jump")
	_expect(bool(caps.turn_cycle), "the humanoid can turn")
	_expect(bool(caps.jumping_jack), "the humanoid can do a jumping jack")
	_expect(bool(caps.squat), "the humanoid can squat")
	_expect(bool(caps.punch), "the humanoid can punch")
	_expect(not bool(caps.blink), "no eyes means no blink")
	_expect(bool(caps.ik_setup) and bool(caps.spring_setup), "bone count enables IK and springs")
	var legless := RigAnalysis.detect_roles(["B-hips", "B-head", "B-upperArm.L", "B-forearm.L"])
	var legless_caps := RigAnalysis.capabilities(legless.roles, 4)
	_expect(not bool(legless_caps.idle_cycle), "no legs means no idle")
	_expect(not bool(legless_caps.walk_cycle), "no legs means no walk")
	_expect(not bool(legless_caps.punch), "a single arm is not enough to punch")
	var missing := RigAnalysis.missing_roles(detected.roles)
	_expect(missing.core.is_empty(), "the humanoid misses no core role")
	_expect(missing.locomotion.is_empty(), "the humanoid misses no locomotion role")
	_expect_eq(str(missing.optional), str(["eye_l", "eye_r"]), "only the eyes are missing")
	var suggestions := RigAnalysis.suggestions(detected.roles, caps)
	_expect(not suggestions.is_empty(), "suggestions are produced")
	var joined := " ".join(suggestions as Array)
	_expect(joined.contains("character_setup"), "a walkable rig is pointed at character_setup")
	_expect(joined.contains("sample"), "the FK probe is suggested")


func _check_sample_times() -> void:
	var times := RigAnalysis.sample_times(1.0, 5)
	_expect_eq(times.size(), 5, "five samples are produced")
	_expect_approx(float(times[0]), 0.0, "the first sample is at 0")
	_expect_approx(float(times[4]), 1.0, "the last sample lands on the clip end")
	_expect_approx(float(times[2]), 0.5, "the middle sample is halfway")
	_expect_eq(RigAnalysis.sample_times(2.0, 1), [0.0], "one sample means time 0")
	_expect_eq(RigAnalysis.sample_times(1.0, 0).size(), 1, "a zero sample count clamps to one")
	_expect_eq(RigAnalysis.sample_times(1.0, 999).size(), 240, "the sample count is capped")
	var explicit := RigAnalysis.explicit_times([0.25, -1.0, 9.0], 2.0)
	_expect_eq(explicit.size(), 3, "explicit times survive")
	_expect_approx(float(explicit[1]), 0.0, "negative times clamp to 0")
	_expect_approx(float(explicit[2]), 2.0, "times past the end clamp to the length")
	var capped := RigAnalysis.explicit_times(range(300), 1.0, 240)
	_expect_eq(capped.size(), 240, "explicit times are capped")


func _check_contacts() -> void:
	var times := [0.0, 0.25, 0.5, 0.75, 1.0]
	var heights := [0.10, 0.0, 0.01, 0.10, 0.12]
	var windows := RigAnalysis.contact_windows(times, heights, 0.02)
	_expect_eq(windows.size(), 1, "one contact window is found")
	_expect_approx(float(windows[0].start), 0.25, "the window starts at the first contact")
	_expect_approx(float(windows[0].end), 0.5, "the window ends at the last contact")
	var flat := RigAnalysis.contact_windows(times, [0.0, 0.0, 0.0, 0.0, 0.0], 0.02)
	_expect_eq(flat.size(), 1, "a flat foot is in contact the whole clip")
	_expect_approx(float(flat[0].start), 0.0, "the flat window starts at 0")
	_expect_approx(float(flat[0].end), 1.0, "the flat window ends at the clip end")
	var airborne := RigAnalysis.contact_windows(times, [0.5, 0.5, 0.5, 0.5, 0.5], 0.02)
	_expect_eq(airborne.size(), 1, "a level foot still reads as contact (relative to its lowest height)")
	_expect(RigAnalysis.contact_windows([], [], 0.02).is_empty(), "no samples means no windows")
	_expect(RigAnalysis.contact_windows(times, [0.0], 0.02).is_empty(),
		"mismatched heights are refused")


func _check_profile_validation() -> void:
	var profile := {
		"format": RigAnalysis.PROFILE_FORMAT,
		"version": RigAnalysis.PROFILE_VERSION,
		"roles": {"hips": "B-hips", "thigh_l": "B-thigh.L", "empty": ""},
	}
	var parsed := RigAnalysis.profile_roles(profile)
	_expect(not parsed.has("error"), "a well-formed profile parses")
	_expect_eq(str(parsed.roles.hips), "B-hips", "profile roles are returned")
	_expect(not parsed.roles.has("empty"), "empty role values are dropped")
	var wrong_format := RigAnalysis.profile_roles({"format": "other", "roles": {"hips": "B-hips"}})
	_expect(wrong_format.has("error"), "a foreign format is refused")
	var no_roles := RigAnalysis.profile_roles({"format": RigAnalysis.PROFILE_FORMAT})
	_expect(no_roles.has("error"), "a profile without roles is refused")
	var not_a_dict := RigAnalysis.profile_roles([])
	_expect(not_a_dict.has("error"), "arrays are refused with an error")
	_expect(RigAnalysis.profile_roles("text").has("error"), "strings are refused with an error")
