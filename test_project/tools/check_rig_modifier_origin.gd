extends SceneTree

## Independent engine playback: no toolkit handler, registry or test imports.
class CaptureErrors extends Logger:
	var errors: Array[String] = []
	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _notify: bool, type: int, _backtraces: Array) -> void:
		if type != 1: errors.append(rationale if not rationale.is_empty() else code)
class Witness extends SkeletonModifier3D:
	func _process_modification_with_delta(_delta: float) -> void: pass

var _failures: Array[String] = []
var _logger := CaptureErrors.new()
func _initialize() -> void:
	OS.add_logger(_logger)
	call_deferred("_run")
func _check(ok: bool, message: String) -> void:
	if not ok: _failures.append(message)
func _sample(skeleton: Skeleton3D, modifier: LookAtModifier3D, witness: Witness, active: bool, weight: float) -> Dictionary:
	modifier.active = active
	modifier.influence = weight
	skeleton.reset_bone_poses()
	var capture := {"raw_count": 0, "final_count": 0, "raw": Quaternion.IDENTITY, "final": Quaternion.IDENTITY}
	var index := skeleton.find_bone("chest")
	var raw := func():
		capture.raw_count += 1
		capture.raw = skeleton.get_bone_global_pose(index).basis.get_rotation_quaternion()
	# Skeleton3D applies influence after the modifier emits its signal. An inert
	# last modifier observes that blended result inside modification_processed.
	var final := func():
		capture.final_count += 1
		capture.final = skeleton.get_bone_global_pose(index).basis.get_rotation_quaternion()
	modifier.modification_processed.connect(raw)
	witness.modification_processed.connect(final)
	skeleton.notification(50)
	modifier.modification_processed.disconnect(raw)
	witness.modification_processed.disconnect(final)
	return capture
func _run() -> void:
	var packed := load("user://rig_modifier_external_origin.tscn") as PackedScene
	_check(packed != null, "saved external-origin fixture exists")
	var rows: Array = []
	if packed != null:
		var scene := packed.instantiate()
		root.add_child(scene)
		var skeleton := scene.get_node("ModifierAllocation/Source") as Skeleton3D
		var modifier := skeleton.get_node("Modifier2") as LookAtModifier3D
		var target := scene.get_node("ModifierAllocation/Targets/ExistingTarget") as Node3D
		var origin := scene.get_node("ModifierAllocation/Targets/Origin") as Node3D
		_check(modifier.get_node_or_null(modifier.target_node) == target, "saved target resolves")
		_check(modifier.get_node_or_null(modifier.origin_external_node) == origin, "saved external origin resolves")
		var witness := Witness.new()
		witness.name = "PlaybackWitness"
		skeleton.add_child(witness)
		await process_frame
		var full := _sample(skeleton, modifier, witness, true, 1.0)
		var expected := (target.global_position - origin.global_position).normalized()
		var played := skeleton.global_basis * (Basis(full.final) * Vector3.BACK)
		_check(full.raw_count == 1 and full.final_count == 1, "active signal samples")
		_check(played.normalized().dot(expected) > 0.9999, "played forward points from external origin to target")
		rows.append({"active": true, "influence": 1.0, "alignment": played.normalized().dot(expected)})
		for variant in [{"active": false, "weight": 1.0}, {"active": true, "weight": 0.0}, {"active": true, "weight": 0.5}]:
			var sample := _sample(skeleton, modifier, witness, variant.active, variant.weight)
			_check(sample.final_count == 1, "witness signal sample " + str(variant))
			_check(sample.raw_count == (1 if variant.active else 0), "active/inactive processing " + str(variant))
			var expected_rotation := Quaternion.IDENTITY.slerp(full.final, variant.weight if variant.active else 0.0)
			_check(sample.final.is_equal_approx(expected_rotation), "engine influence blend " + str(variant))
			rows.append({"active": variant.active, "influence": variant.weight, "angle": sample.final.get_angle()})
		scene.free()
	OS.remove_logger(_logger)
	print("RIG_MODIFIER_ORIGIN_RUNTIME=" + JSON.stringify({"failures": _failures, "engine_errors": _logger.errors, "played_states": rows.size(), "states": rows}))
	quit(0 if _failures.is_empty() and _logger.errors.is_empty() and rows.size() == 4 else 1)
