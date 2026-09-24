extends SceneTree

## Tier-1 headless checks for spine-chain detection. The chain drives the twist
## distribution, so it has to be genuinely ancestral: a chain of unrelated bones
## would twist an arm.
##
##   godot --headless --path test_project --script res://tests/tier1_spine_chain.gd

const RigAnalysis := preload("res://addons/godot_ai_animation/spec/rig_analysis.gd")
const SpineTwist := preload("res://addons/godot_ai_animation/spec/spine_twist.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	_check_humanoid_chain()
	_check_long_chain()
	_check_no_spine_bone()
	_check_odd_names()
	_check_no_head()
	_check_missing_hips()
	_check_limits()
	_check_caps_and_validation()
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


## A four-bone torso plus the branches hanging off it.
func _humanoid() -> Dictionary:
	return {
		"B-root": "",
		"B-hips": "B-root",
		"B-spine": "B-hips",
		"B-chest": "B-spine",
		"B-head": "B-chest",
		"B-shoulder.L": "B-chest",
		"B-upperArm.L": "B-shoulder.L",
		"B-thigh.L": "B-hips",
	}


func _roles(hips := "B-hips", spine := "B-spine", chest := "B-chest", head := "B-head") -> Dictionary:
	var roles: Dictionary = {}
	if not hips.is_empty():
		roles["hips"] = hips
	if not spine.is_empty():
		roles["spine"] = spine
	if not chest.is_empty():
		roles["chest"] = chest
	if not head.is_empty():
		roles["head"] = head
	return roles


func _check_humanoid_chain() -> void:
	var chain: Array = RigAnalysis.spine_chain(_humanoid(), _roles())
	_expect_eq(chain, ["B-hips", "B-spine", "B-chest", "B-head"],
		"a humanoid rig returns hips -> spine -> chest -> head")


func _check_long_chain() -> void:
	# upperChest and neck add two more bones; the head still ends the chain.
	var parent_of := {
		"B-root": "", "B-hips": "B-root", "B-spine1": "B-hips", "B-spine2": "B-spine1",
		"B-chest": "B-spine2", "B-upperChest": "B-chest", "B-neck": "B-upperChest",
		"B-head": "B-neck",
	}
	var chain: Array = RigAnalysis.spine_chain(parent_of, _roles("B-hips", "B-spine2", "B-chest", "B-head"))
	_expect_eq(chain.size(), 7, "a seven-bone torso is walked whole")
	_expect_eq(str(chain[chain.size() - 1]), "B-head", "the chain still ends at the head")
	_expect(chain.has("B-neck"), "the neck is part of the chain")
	# The weights resample to the chain length and still sum to the total.
	var values: Array = SpineTwist.amplitudes(chain.size(), 18.0)
	var total := 0.0
	for value in values:
		total += float(value)
	_expect(absf(total - 18.0) < 0.001, "a seven-bone chain still sums to the requested twist")


func _check_no_spine_bone() -> void:
	# Rigs with only a chest: the chain runs hips -> chest -> head.
	var parent_of := {
		"B-root": "", "B-hips": "B-root", "B-chest": "B-hips", "B-head": "B-chest",
	}
	var chain: Array = RigAnalysis.spine_chain(parent_of, _roles("B-hips", "", "B-chest", "B-head"))
	_expect_eq(chain, ["B-hips", "B-chest", "B-head"], "a rig with no spine bone walks hips -> chest -> head")


func _check_odd_names() -> void:
	# "B-bone03" names nothing torso-like, but it sits between the hips and the
	# head, so it is torso by position.
	var parent_of := {
		"root": "", "pelvis": "root", "B-bone03": "pelvis", "B-bone07": "B-bone03", "skull": "B-bone07",
	}
	var chain: Array = RigAnalysis.spine_chain(parent_of, {
		"hips": "pelvis", "chest": "B-bone07", "head": "skull",
	})
	_expect_eq(chain, ["pelvis", "B-bone03", "B-bone07", "skull"],
		"an oddly named intermediate is torso by position")


func _check_no_head() -> void:
	var parent_of := {
		"B-root": "", "B-hips": "B-root", "B-spine": "B-hips", "B-chest": "B-spine",
		"B-armRoot": "B-chest", "B-upperArm.L": "B-armRoot",
	}
	var chain: Array = RigAnalysis.spine_chain(parent_of, _roles("B-hips", "B-spine", "B-chest", ""))
	_expect_eq(chain, ["B-hips", "B-spine", "B-chest"], "without a head the walk stops at the chest")
	_expect(not chain.has("B-upperArm.L"), "the walk never wanders into an arm")


func _check_missing_hips() -> void:
	var parent_of := {
		"B-root": "", "B-chest": "B-root", "B-head": "B-chest", "B-hips": "B-head",
	}
	var from_chest: Array = RigAnalysis.spine_chain(parent_of, _roles("", "", "B-chest", "B-head"))
	_expect_eq(from_chest, ["B-chest", "B-head"], "a rig with no detected hips starts at the chest")
	_expect_eq(RigAnalysis.spine_chain(_humanoid(), {}).size(), 0,
		"no torso roles means no chain")


func _check_limits() -> void:
	# A pathological chain of torso-named bones is capped.
	var parent_of := {"root": ""}
	var previous := "root"
	for index in 12:
		var name := "B-spine%02d" % index
		parent_of[name] = previous
		previous = name
	var chain: Array = RigAnalysis.spine_chain(parent_of, _roles("B-spine00", "", "", ""), 6)
	_expect_eq(chain.size(), 6, "the chain is capped at max_bones")
	# The default cap is the module constant.
	var long_enough := RigAnalysis.spine_chain(parent_of, _roles("B-spine00", "", "", ""))
	_expect_eq(long_enough.size(), RigAnalysis.SPINE_CHAIN_MAX, "the default cap is SPINE_CHAIN_MAX")


func _check_caps_and_validation() -> void:
	# A head that is not ancestral to the hips is refused rather than faked.
	var parent_of := {
		"B-root": "", "B-hips": "B-root", "B-chest": "B-hips", "head": "B-root",
	}
	var chain: Array = RigAnalysis.spine_chain(parent_of, _roles("B-hips", "", "B-chest", "head"))
	_expect_eq(chain, ["B-hips", "B-chest"],
		"a head on another branch is not appended to the chain")
	# Every returned bone must exist in the parent map.
	for bone in chain:
		_expect(parent_of.has(str(bone)), "chain bone '%s' exists in the skeleton" % str(bone))
