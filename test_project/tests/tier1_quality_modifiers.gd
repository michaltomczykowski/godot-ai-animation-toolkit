extends SceneTree

## Tier-1 headless checks for the clip-quality passes: smoothing, engine-exact
## resampling, seeded micro-noise, per-track overlap and clip layering.
##
##   godot --headless --path test_project --script res://tests/tier1_quality_modifiers.gd

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecModifiers := preload("res://addons/godot_ai_animation/spec/spec_modifiers.gd")
const QualityModifiers := preload("res://addons/godot_ai_animation/spec/quality_modifiers.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	_check_smooth()
	_check_resample()
	_check_noise()
	_check_overlap()
	_check_layer()
	_check_motion_report()
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


func _expect_approx(actual: float, expected: float, message: String) -> void:
	_expect(absf(actual - expected) < 0.0001, "%s (expected %s, got %s)" % [message, expected, actual])


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _float_track(length: float, values: Array, loop: bool = false) -> Dictionary:
	var spec := ClipSpec.make(length, Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE)
	var keys: Array = []
	for index in values.size():
		keys.append({"time": length * float(index) / float(values.size() - 1), "value": float(values[index]), "transition": 1.0})
	ClipSpec.add_value_track(spec, "N:value", keys)
	return spec


# --- checks -----------------------------------------------------------------

func _check_smooth() -> void:
	var spec := _float_track(1.0, [0.0, 0.0, 1.0, 0.0, 0.0])
	var result := QualityModifiers.smooth(spec, 0.5, 1, "")
	_expect_approx(float(result.spec.tracks[0].keys[2].value), 0.5, "smooth halves an isolated spike")
	_expect_approx(float(result.spec.tracks[0].keys[0].value), 0.0, "smooth keeps an end key next to zeros")
	_expect_approx(float(spec.tracks[0].keys[2].value), 1.0, "smooth never mutates its input")
	var full := QualityModifiers.smooth(spec, 1.0, 1, "")
	_expect_approx(float(full.spec.tracks[0].keys[2].value), 0.0, "full strength removes an isolated spike")
	_expect_approx(float(full.spec.tracks[0].keys[1].value), 0.5, "full strength spreads the spike to its neighbours")
	var looped := _float_track(1.0, [0.0, 0.0, 0.0, 1.0], true)
	var wrapped := QualityModifiers.smooth(looped, 0.5, 1, "")
	_expect(float(wrapped.spec.tracks[0].keys[0].value) > 0.0, "looping clips smooth across the seam")
	var quat_spec := ClipSpec.make(1.0, Animation.LOOP_NONE)
	var q := Quaternion(Vector3.UP, deg_to_rad(60.0))
	ClipSpec.add_value_track(quat_spec, "B:rotation", [
		{"time": 0.0, "value": q, "transition": 1.0},
		{"time": 0.5, "value": q, "transition": 1.0},
		{"time": 1.0, "value": q, "transition": 1.0},
	], Animation.INTERPOLATION_LINEAR, Animation.TYPE_ROTATION_3D)
	var quat_out := QualityModifiers.smooth(quat_spec, 0.5, 1, "")
	var smoothed_q: Quaternion = quat_out.spec.tracks[0].keys[1].value
	_expect(absf(smoothed_q.get_angle() - q.get_angle()) < 0.001, "smoothing identical rotations is a no-op")


func _check_resample() -> void:
	var spec := ClipSpec.make(2.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "N:position", [
		{"time": 0.0, "value": Vector3.ZERO, "transition": 1.0},
		{"time": 1.0, "value": Vector3(1, 0, 0), "transition": 1.0},
		{"time": 2.0, "value": Vector3(3, 0, 0), "transition": 1.0},
	], Animation.INTERPOLATION_CUBIC, Animation.TYPE_POSITION_3D)
	var result := QualityModifiers.resample(spec, 10.0, Animation.INTERPOLATION_LINEAR, "")
	_expect_eq((result.spec.tracks[0].keys as Array).size(), 21, "2s at 10/s resamples to 21 keys")
	var mid: Vector3 = result.spec.tracks[0].keys[5].value
	var exact: Vector3 = SpecModifiers.sample_track_exact(spec.tracks[0], 0.5)
	_expect(mid.is_equal_approx(exact), "resampling keeps the engineered curve value")
	_expect(absf(mid.x - 0.5) > 0.01, "the cubic shape survives resampling (got %s)" % mid.x)
	_expect_approx(float(result.spec.tracks[0].keys[0].time), 0.0, "resampled keys start at 0")
	_expect_approx(float(result.spec.tracks[0].keys[20].time), 2.0, "resampled keys end at the length")
	var limited := QualityModifiers.resample(spec, 10.0, Animation.INTERPOLATION_LINEAR, "Other:position")
	_expect_eq((limited.spec.tracks[0].keys as Array).size(), 3, "a non-matching track_path passes tracks through")


func _check_noise() -> void:
	var spec := _float_track(1.0, [0.0, 0.0, 0.0])
	var first := QualityModifiers.add_noise(spec, 1.0, 2.0, 7, "")
	var second := QualityModifiers.add_noise(spec, 1.0, 2.0, 7, "")
	var third := QualityModifiers.add_noise(spec, 1.0, 2.0, 8, "")
	_expect(first.spec.tracks[0].keys == second.spec.tracks[0].keys, "add_noise is deterministic per seed")
	_expect(first.spec.tracks[0].keys != third.spec.tracks[0].keys, "a different seed gives different noise")
	var peak := 0.0
	for key in first.spec.tracks[0].keys:
		peak = maxf(peak, absf(float(key.value)))
	_expect(peak <= 1.001, "float noise stays within the amount (peak %s)" % peak)
	var rot_spec := ClipSpec.make(1.0, Animation.LOOP_NONE)
	var keys: Array = []
	for index in 5:
		keys.append({"time": float(index) * 0.25, "value": Quaternion.IDENTITY, "transition": 1.0})
	ClipSpec.add_value_track(rot_spec, "B:rotation", keys, Animation.INTERPOLATION_LINEAR, Animation.TYPE_ROTATION_3D)
	var noised := QualityModifiers.add_noise(rot_spec, 2.0, 3.0, 1, "")
	for key in noised.spec.tracks[0].keys:
		_expect((key.value as Quaternion).get_angle() <= deg_to_rad(2.001), "rotation noise stays within the amount")


func _check_overlap() -> void:
	var spec := ClipSpec.make(1.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "Rig/Arm:rotation", [{"time": 0.0, "value": 0.0}, {"time": 1.0, "value": 1.0}])
	ClipSpec.add_value_track(spec, "Rig/Leg:rotation", [{"time": 0.0, "value": 0.0}, {"time": 1.0, "value": 1.0}])
	var shifted := QualityModifiers.overlap(spec, "Rig/Arm", 0.25, false)
	_expect_eq(int(shifted.changed), 2, "overlap shifts the matched subtree only")
	var arm_keys: Array = shifted.spec.tracks[ClipSpec.find_track_index(shifted.spec, "Rig/Arm:rotation")].keys
	var leg_keys: Array = shifted.spec.tracks[ClipSpec.find_track_index(shifted.spec, "Rig/Leg:rotation")].keys
	_expect_approx(float(arm_keys[0].time), 0.25, "overlap delays the arm")
	_expect_approx(float(leg_keys[0].time), 0.0, "overlap leaves the leg alone")
	_expect_approx(float(shifted.spec.length), 1.25, "a non-wrapped overlap grows the clip")
	var wrapped := QualityModifiers.overlap(spec, "Rig/Arm", 0.25, true)
	_expect_approx(float(wrapped.spec.length), 1.0, "a wrapped overlap keeps the length")
	var wrapped_keys: Array = wrapped.spec.tracks[ClipSpec.find_track_index(wrapped.spec, "Rig/Arm:rotation")].keys
	_expect_approx(float(wrapped_keys[0].time), 0.25, "wrapped keys fold inside the length")
	_expect_eq(wrapped_keys.size(), 1, "wrapped keys landing on the same time merge")


func _check_layer() -> void:
	var base := ClipSpec.make(1.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(base, "N:value", [
		{"time": 0.0, "value": 0.0, "transition": 1.0},
		{"time": 1.0, "value": 10.0, "transition": 1.0},
	])
	var overlay := ClipSpec.make(1.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(overlay, "N:value", [
		{"time": 0.0, "value": 10.0, "transition": 1.0},
		{"time": 1.0, "value": 10.0, "transition": 1.0},
	])
	var mixed := QualityModifiers.layer(base, overlay, 0.5, "mix", "")
	var mixed_track: Dictionary = mixed.spec.tracks[ClipSpec.find_track_index(mixed.spec, "N:value")]
	_expect_approx(float(mixed_track.keys[0].value), 5.0, "mix blends the base toward the source")
	_expect_approx(float(mixed_track.keys[1].value), 10.0, "mix keeps a matching value")
	var added := QualityModifiers.layer(base, overlay, 1.0, "add", "")
	var added_track: Dictionary = added.spec.tracks[ClipSpec.find_track_index(added.spec, "N:value")]
	_expect_approx(float(added_track.keys[0].value), 0.0, "add applies the source delta (first key is neutral)")
	_expect_approx(float(added_track.keys[1].value), 10.0, "an all-equal overlay adds no motion")
	# Rotation layer: a 60-degree source over an identity base.
	var base_rot := ClipSpec.make(1.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(base_rot, "B:rotation", [
		{"time": 0.0, "value": Quaternion.IDENTITY, "transition": 1.0},
		{"time": 1.0, "value": Quaternion.IDENTITY, "transition": 1.0},
	], Animation.INTERPOLATION_LINEAR, Animation.TYPE_ROTATION_3D)
	var overlay_rot := ClipSpec.make(1.0, Animation.LOOP_NONE)
	var turn := Quaternion(Vector3.UP, deg_to_rad(60.0))
	ClipSpec.add_value_track(overlay_rot, "B:rotation", [
		{"time": 0.0, "value": Quaternion.IDENTITY, "transition": 1.0},
		{"time": 1.0, "value": turn, "transition": 1.0},
	], Animation.INTERPOLATION_LINEAR, Animation.TYPE_ROTATION_3D)
	var layered := QualityModifiers.layer(base_rot, overlay_rot, 1.0, "add", "")
	var layered_q: Quaternion = layered.spec.tracks[ClipSpec.find_track_index(layered.spec, "B:rotation")].keys[1].value
	_expect(absf(layered_q.get_angle() - deg_to_rad(60.0)) < 0.001, "add multiplies rotations")
	var remapped := QualityModifiers.layer(base, overlay, 1.0, "mix", "Other")
	var created_track := ClipSpec.find_track_index(remapped.spec, "Other:value")
	_expect(created_track >= 0, "remap_node rewrites the source node path")
	_expect_eq(int(remapped.tracks_created), 1, "a missing base track is created")


func _has_finding(findings: Array, code: String) -> bool:
	for finding in findings:
		if str(finding.get("code", "")) == code:
			return true
	return false


func _check_motion_report() -> void:
	var healthy := ClipSpec.make(1.0, Animation.LOOP_LINEAR)
	var keys: Array = []
	for index in 25:
		keys.append({"time": float(index) / 24.0, "value": sin(TAU * float(index) / 24.0), "transition": 1.0})
	ClipSpec.add_value_track(healthy, "N:value", keys)
	var clean := QualityModifiers.motion_report(healthy)
	_expect(bool(clean.healthy), "a dense closed loop reports healthy (%s)" % str(clean.findings))
	var metrics: Dictionary = clean.tracks[0]
	_expect_eq(int(metrics.keys), 25, "metrics count the keys")
	_expect(float(metrics.keys_per_second) > 20.0, "metrics report the key density")
	_expect(float(metrics.seam_gap) < 0.0001, "a closed loop has no seam gap")
	var broken := ClipSpec.make(1.0, Animation.LOOP_LINEAR)
	ClipSpec.add_value_track(broken, "N:value", [
		{"time": 0.0, "value": 0.0, "transition": 1.0},
		{"time": 0.5, "value": 1.0, "transition": 1.0},
		{"time": 1.0, "value": 5.0, "transition": 1.0},
	])
	var popped := QualityModifiers.motion_report(broken)
	_expect(_has_finding(popped.findings, "loop_seam"), "a mismatched loop reports loop_seam")
	_expect(not bool(popped.healthy), "a poppy clip is not healthy")
	var flipped := ClipSpec.make(1.0, Animation.LOOP_NONE)
	var q := Quaternion(Vector3.UP, deg_to_rad(30.0))
	ClipSpec.add_value_track(flipped, "B:rotation", [
		{"time": 0.0, "value": q, "transition": 1.0},
		{"time": 0.5, "value": -q, "transition": 1.0},
		{"time": 1.0, "value": q, "transition": 1.0},
	], Animation.INTERPOLATION_LINEAR, Animation.TYPE_ROTATION_3D)
	var flip_report := QualityModifiers.motion_report(flipped)
	_expect_eq(int(flip_report.flipped_quaternions), 2, "flipped hemispheres are counted")
	_expect(_has_finding(flip_report.findings, "hemisphere_flip"), "flips are reported")
	var sparse := ClipSpec.make(4.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(sparse, "N:value", [
		{"time": 0.0, "value": 0.0, "transition": 1.0},
		{"time": 3.0, "value": 1.0, "transition": 1.0},
	])
	_expect(_has_finding(QualityModifiers.motion_report(sparse).findings, "sparse_keys"), "sparse keys are reported")
