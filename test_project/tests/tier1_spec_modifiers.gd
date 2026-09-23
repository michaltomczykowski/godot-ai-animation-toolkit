extends SceneTree

## Tier-1 headless checks for the spec engine: pure modifiers, spec <-> Animation
## round-trips, and registry/schema/docs drift. No editor, no undo manager, no
## MCP. Run with:
##
##   godot --headless --path test_project --script res://tests/tier1_spec_modifiers.gd
##
## (Named without the `test_` prefix so the editor suite runner ignores it.)

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecBuilder := preload("res://addons/godot_ai_animation/spec/spec_builder.gd")
const SpecIO := preload("res://addons/godot_ai_animation/spec/spec_io.gd")
const SpecModifiers := preload("res://addons/godot_ai_animation/spec/spec_modifiers.gd")
const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	_check_spec_basics()
	_check_retime()
	_check_retarget()
	_check_reverse()
	_check_mirror()
	_check_offset()
	_check_easing()
	_check_typed_transitions()
	_check_ease_curve()
	_check_sample_track()
	_check_continuity()
	_check_trim_split()
	_check_merge()
	_check_amplitude()
	_check_loop()
	_check_key_edit()
	_check_cleanup()
	_check_roundtrip()
	_check_registry()
	_check_docs_fresh()
	if _failures == 0:
		print("TIER1 PASS (%d checks)" % _checks)
	else:
		print("TIER1 FAIL (%d/%d checks failed)" % [_failures, _checks])
	quit(0 if _failures == 0 else 1)


# --- harness ---------------------------------------------------------------

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  FAIL: %s" % message)


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _expect_approx(actual: float, expected: float, message: String) -> void:
	_expect(absf(actual - expected) < 0.0001, "%s (expected %s, got %s)" % [message, expected, actual])


func _expect_vec(actual: Variant, expected: Variant, message: String) -> void:
	var same := false
	if actual is Vector2 and expected is Vector2:
		same = (actual as Vector2).is_equal_approx(expected as Vector2)
	elif actual is Vector3 and expected is Vector3:
		same = (actual as Vector3).is_equal_approx(expected as Vector3)
	_expect(same, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _key_times(track: Dictionary) -> Array:
	var times: Array = []
	for key in track.keys:
		times.append(snappedf(float(key.time), 0.0001))
	return times


func _key_values(track: Dictionary) -> Array:
	var values: Array = []
	for key in track.keys:
		values.append(key.value)
	return values


## A 3-track spec used across the modifier checks:
##   Sprite:position (Vector2, 3 keys, 0..1s)
##   Sprite:modulate:a (float, 2 keys)
##   FX:position (Vector2, 2 keys)
func _fixture() -> Dictionary:
	var spec := ClipSpec.make(1.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "Sprite:position", [
		{"time": 0.0, "value": Vector2(0, 0), "transition": 1.0},
		{"time": 0.5, "value": Vector2(10, 4), "transition": 1.0},
		{"time": 1.0, "value": Vector2(20, 0), "transition": 1.0},
	])
	ClipSpec.add_value_track(spec, "Sprite:modulate:a", [
		{"time": 0.0, "value": 0.0, "transition": 1.0},
		{"time": 1.0, "value": 1.0, "transition": 1.0},
	])
	ClipSpec.add_value_track(spec, "FX:position", [
		{"time": 0.0, "value": Vector2(5, 5), "transition": 1.0},
		{"time": 0.8, "value": Vector2(5, -5), "transition": 1.0},
	])
	ClipSpec.add_marker(spec, "hit", 0.5)
	return spec


# --- checks ----------------------------------------------------------------

func _check_spec_basics() -> void:
	var spec := _fixture()
	_expect_eq(ClipSpec.total_key_count(spec), 7, "fixture has 7 keys")
	_expect_eq((spec.tracks as Array).size(), 3, "fixture has 3 tracks")
	_expect_eq(ClipSpec.find_track_index(spec, "FX:position"), 2, "find_track_index finds FX:position")
	_expect_eq(ClipSpec.find_track_index(spec, "Nope:position"), -1, "find_track_index misses unknown paths")
	_expect_eq(ClipSpec.node_path_of("A/B:modulate:a"), "A/B", "node_path_of strips the property")
	_expect_eq(ClipSpec.property_of("A/B:modulate:a"), "modulate:a", "property_of keeps subpaths")
	_expect_eq(ClipSpec.type_name(Animation.TYPE_VALUE), "value", "type_name value")
	_expect(ClipSpec.is_supported_type(Animation.TYPE_METHOD), "method tracks are supported")
	_expect(not ClipSpec.is_supported_type(Animation.TYPE_BEZIER), "bezier tracks are not supported")
	var out_of_order := ClipSpec.make(2.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(out_of_order, "N:position", [
		{"time": 1.0, "value": 1.0}, {"time": 0.0, "value": 0.0},
	])
	var normalized := ClipSpec.normalize(out_of_order)
	_expect_approx(float(normalized.tracks[0].keys[0].time), 0.0, "normalize sorts keys")
	var empty := ClipSpec.make(0.5, Animation.LOOP_NONE)
	ClipSpec.add_value_track(empty, "N:position", [])
	ClipSpec.add_value_track(empty, "N:position", [{"time": 2.0, "value": 1.0}])
	var pruned := ClipSpec.normalize(empty)
	_expect_eq((pruned.tracks as Array).size(), 1, "normalize drops empty tracks")
	_expect_approx(float(pruned.length), 2.0, "normalize grows the length to the last key")


func _check_retime() -> void:
	var spec := _fixture()
	var half := SpecModifiers.retime(spec, 0.5, 0.0, false)
	_expect_approx(float(half.length), 0.5, "retime halves the length")
	_expect_approx(float(half.tracks[0].keys[2].time), 0.5, "retime halves key times")
	_expect_approx(float(half.markers[0].time), 0.25, "retime scales markers")
	var to_length := SpecModifiers.retime(spec, 0.0, 2.0, false)
	_expect_approx(float(to_length.length), 2.0, "retime to length sets the length")
	_expect_approx(float(to_length.tracks[0].keys[1].time), 1.0, "retime to length scales keys")
	var keys_only := SpecModifiers.retime(spec, 2.0, 0.0, true)
	_expect_approx(float(keys_only.length), 2.0, "keys_only retime sets the length")
	_expect_approx(float(keys_only.tracks[0].keys[1].time), 0.5, "keys_only retime keeps key times")
	_expect_approx(float(spec.length), 1.0, "retime never mutates its input")


func _check_retarget() -> void:
	var spec := _fixture()
	var node_mode := SpecModifiers.retarget(spec, [{"from": "Sprite", "to": "Player/Sprite", "mode": "node"}])
	_expect_eq(int(node_mode.changed), 2, "node retarget rewrites both Sprite tracks")
	_expect_eq(str(node_mode.spec.tracks[0].path), "Player/Sprite:position", "node retarget keeps the property")
	var prefix := SpecModifiers.retarget(spec, [{"from": "Sprite", "to": "Player/Sprite", "mode": "prefix"}])
	_expect_eq(str(prefix.spec.tracks[1].path), "Player/Sprite:modulate:a", "prefix retarget keeps subpath properties")
	var exact := SpecModifiers.retarget(spec, [{"from": "Sprite:position", "to": "Body:position", "mode": "exact"}])
	_expect_eq(int(exact.changed), 1, "exact retarget matches one track")
	_expect_eq(str(exact.spec.tracks[1].path), "Sprite:modulate:a", "exact retarget leaves siblings alone")
	var no_match := SpecModifiers.retarget(spec, [{"from": "SpriteX", "to": "Y", "mode": "prefix"}])
	_expect_eq(int(no_match.changed), 0, "prefix retarget does not match a longer node name")
	_expect_eq(str(no_match.spec.tracks[0].path), "Sprite:position", "non-matching tracks are untouched")


func _check_reverse() -> void:
	var spec := _fixture()
	var out := SpecModifiers.reverse(spec)
	_expect_eq(_key_times(out.tracks[0]), [0.0, 0.5, 1.0], "reverse keeps times sorted")
	_expect_vec(out.tracks[0].keys[0].value, Vector2(20, 0), "reverse mirrors the first key value")
	_expect_approx(float(out.markers[0].time), 0.5, "reverse mirrors markers")
	_expect_approx(float(out.length), 1.0, "reverse keeps the length")
	var uneven := ClipSpec.make(2.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(uneven, "N:position", [
		{"time": 0.0, "value": 0.0}, {"time": 0.5, "value": 1.0},
	])
	var uneven_out := SpecModifiers.reverse(uneven)
	_expect_approx(float(uneven_out.tracks[0].keys[0].time), 1.5, "reverse mirrors about the length")


func _check_mirror() -> void:
	var spec := _fixture()
	var x_only := SpecModifiers.mirror(spec, "x", null, false)
	_expect_vec(x_only.spec.tracks[0].keys[1].value, Vector2(-10, 4), "mirror x flips only the x component")
	_expect_eq(int(x_only.changed), 5, "mirror touches every position key")
	var about_pivot := SpecModifiers.mirror(spec, "x", Vector2(10, 0), false)
	_expect_vec(about_pivot.spec.tracks[0].keys[0].value, Vector2(20, 0), "mirror about a pivot reflects positions")
	var y_only := SpecModifiers.mirror(spec, "y", null, false)
	_expect_vec(y_only.spec.tracks[2].keys[1].value, Vector2(5, 5), "mirror y flips the y component")
	var quaternion := ClipSpec.make(1.0, Animation.LOOP_NONE)
	var quat := Quaternion(Vector3(0, 0, 1), PI / 2.0)
	ClipSpec.add_value_track(quaternion, "Body:rotation", [{"time": 0.0, "value": quat}], Animation.INTERPOLATION_LINEAR, Animation.TYPE_ROTATION_3D)
	var quat_out := SpecModifiers.mirror(quaternion, "x", null, false)
	var mirrored: Quaternion = quat_out.spec.tracks[0].keys[0].value
	_expect(absf(mirrored.z + quat.z) < 0.001, "mirror x negates the quaternion z component")
	_expect(absf(mirrored.w - quat.w) < 0.001, "mirror keeps the quaternion w component")
	var scale_spec := ClipSpec.make(1.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(scale_spec, "Sprite:scale", [{"time": 0.0, "value": Vector2(2, 3)}])
	var scale_untouched := SpecModifiers.mirror(scale_spec, "x", null, false)
	_expect_vec(scale_untouched.spec.tracks[0].keys[0].value, Vector2(2, 3), "mirror leaves scale alone by default")
	var scale_flipped := SpecModifiers.mirror(scale_spec, "x", null, true)
	_expect_vec(scale_flipped.spec.tracks[0].keys[0].value, Vector2(-2, 3), "include_scale flips scale components")
	var modulate_untouched := SpecModifiers.mirror(spec, "x", null, true)
	_expect_approx(float(modulate_untouched.spec.tracks[1].keys[1].value), 1.0, "mirror leaves modulate alone")


func _check_offset() -> void:
	var spec := _fixture()
	var shifted := SpecModifiers.offset(spec, 0.5, false)
	_expect_eq(_key_times(shifted.tracks[0]), [0.5, 1.0, 1.5], "offset shifts key times")
	_expect_approx(float(shifted.length), 1.5, "offset grows the length to fit the last key")
	var wrapped := SpecModifiers.offset(spec, 0.5, true)
	_expect_approx(float(wrapped.length), 1.0, "wrapped offset keeps the length")
	_expect_eq(_key_times(wrapped.tracks[0]), [0.0, 0.5], "wrapped offset dedupes the seam keys")
	_expect_vec(wrapped.tracks[0].keys[0].value, Vector2(10, 4), "wrapped offset rotates key values")
	var clamped := SpecModifiers.offset(spec, -0.5, false)
	_expect_eq(_key_times(clamped.tracks[0]), [0.0, 0.0, 0.5], "negative offset clamps at 0")
	var noop := SpecModifiers.offset(spec, 0.0, true)
	_expect_eq(_key_times(noop.tracks[0]), [0.0, 0.5, 1.0], "zero offset is a no-op even with wrap")


func _check_easing() -> void:
	var spec := _fixture()
	var eased := SpecModifiers.ease_range(spec, 0.0, 0.5, 2.0)
	_expect_eq(int(eased.changed), 4, "ease_range hits keys in [0, 0.5] on value tracks")
	_expect_approx(float(eased.spec.tracks[0].keys[0].transition), 2.0, "ease_range sets the transition")
	_expect_approx(float(eased.spec.tracks[0].keys[2].transition), 1.0, "ease_range leaves later keys alone")
	var interp := SpecModifiers.set_interp(spec, Animation.INTERPOLATION_NEAREST, "")
	_expect_eq(int(interp.changed), 3, "set_interp hits every value track")
	_expect_eq(int(interp.spec.tracks[1].interp), Animation.INTERPOLATION_NEAREST, "set_interp stores the mode")
	var one := SpecModifiers.set_interp(spec, Animation.INTERPOLATION_CUBIC, "FX:position")
	_expect_eq(int(one.changed), 1, "set_interp can target one track")
	_expect_eq(int(one.spec.tracks[0].interp), Animation.INTERPOLATION_LINEAR, "other tracks keep their interpolation")


func _check_typed_transitions() -> void:
	var spec := ClipSpec.make(1.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "Body:rotation", [
		{"time": 0.0, "value": Quaternion.IDENTITY, "transition": "ease_in"},
		{"time": 0.5, "value": Quaternion(Vector3(0, 1, 0), PI / 2.0), "transition": "ease_out"},
		{"time": 1.0, "value": Quaternion.IDENTITY, "transition": 1.0},
	], Animation.INTERPOLATION_LINEAR, Animation.TYPE_ROTATION_3D)
	ClipSpec.add_value_track(spec, "Body:position", [
		{"time": 0.0, "value": Vector3.ZERO, "transition": "ease_in_out"},
		{"time": 1.0, "value": Vector3(1, 0, 0), "transition": 1.0},
	], Animation.INTERPOLATION_LINEAR, Animation.TYPE_POSITION_3D)
	ClipSpec.add_value_track(spec, "Body:scale", [
		{"time": 0.0, "value": Vector3.ONE, "transition": 0.0},
		{"time": 1.0, "value": Vector3(2, 2, 2), "transition": 1.0},
	], Animation.INTERPOLATION_LINEAR, Animation.TYPE_SCALE_3D)
	var anim := SpecBuilder.to_animation(spec)
	_expect_approx(anim.track_get_key_transition(0, 0), 2.0, "rotation track keeps ease_in")
	_expect_approx(anim.track_get_key_transition(0, 1), 0.5, "rotation track keeps ease_out")
	_expect_approx(anim.track_get_key_transition(1, 0), -2.0, "position track keeps ease_in_out")
	_expect_approx(anim.track_get_key_transition(2, 0), 0.0, "scale track keeps an explicit hold")
	var mid: Quaternion = anim.rotation_track_interpolate(0, 0.25)
	_expect_approx(mid.get_angle(), PI / 8.0, "ease_in shapes the engine's rotation interpolation")
	var back := SpecIO.from_animation(anim)
	_expect_approx(float(back.tracks[0].keys[0].transition), 2.0, "round-trip keeps rotation transitions")
	_expect_approx(float(back.tracks[1].keys[0].transition), -2.0, "round-trip keeps position transitions")
	_expect_approx(float(back.tracks[2].keys[0].transition), 0.0, "round-trip keeps scale holds")


func _check_ease_curve() -> void:
	_expect_approx(SpecModifiers.ease_curve(0.5, 1.0), 0.5, "linear ease is the identity")
	_expect_approx(SpecModifiers.ease_curve(0.5, 2.0), 0.25, "ease_in squares the ramp")
	_expect_approx(SpecModifiers.ease_curve(0.5, 0.5), 0.75, "ease_out raises the ramp")
	_expect_approx(SpecModifiers.ease_curve(0.5, -2.0), 0.5, "ease_in_out is symmetric")
	_expect_approx(SpecModifiers.ease_curve(0.25, -2.0), 0.125, "ease_in_out is quadratic before the midpoint")
	_expect_approx(SpecModifiers.ease_curve(0.7, 0.0), 0.0, "transition 0 holds")


func _check_sample_track() -> void:
	var eased := {
		"type": Animation.TYPE_VALUE,
		"path": "N:value",
		"interp": Animation.INTERPOLATION_LINEAR,
		"keys": [
			{"time": 0.0, "value": 0.0, "transition": "ease_in_out"},
			{"time": 1.0, "value": 10.0, "transition": 1.0},
		],
	}
	_expect_approx(float(SpecModifiers.sample_track(eased, 0.5)), 5.0, "ease_in_out midpoint is unchanged")
	_expect_approx(float(SpecModifiers.sample_track(eased, 0.25)), 1.25, "sample_track follows the ease shape")
	_expect_approx(float(SpecModifiers.sample_track(eased, 2.0)), 10.0, "sample_track clamps past the last key")
	var hold := eased.duplicate(true)
	hold.keys[0].transition = 0.0
	_expect_approx(float(SpecModifiers.sample_track(hold, 0.9)), 0.0, "transition 0 holds the from-key value")
	var cubic := ClipSpec.make(2.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(cubic, "N:position", [
		{"time": 0.0, "value": Vector3.ZERO, "transition": 1.0},
		{"time": 1.0, "value": Vector3(1, 0, 0), "transition": 1.0},
		{"time": 2.0, "value": Vector3(3, 0, 0), "transition": 1.0},
	], Animation.INTERPOLATION_CUBIC, Animation.TYPE_POSITION_3D)
	var sampled: Vector3 = SpecModifiers.sample_track(cubic.tracks[0], 0.5)
	_expect(absf(sampled.x - 0.5) > 0.01, "cubic tracks sample through the engine (not linearly)")
	_expect(sampled.x > 0.0 and sampled.x < 1.0, "cubic sample stays smooth between keys")
	_expect_vec(SpecModifiers.sample_track(cubic.tracks[0], 0.0), Vector3.ZERO, "cubic sampling clamps before the first key")
	var nearest := ClipSpec.make(1.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(nearest, "N:value", [
		{"time": 0.0, "value": 0.0, "transition": 1.0},
		{"time": 1.0, "value": 10.0, "transition": 1.0},
	], Animation.INTERPOLATION_NEAREST)
	_expect_approx(float(SpecModifiers.sample_track(nearest.tracks[0], 0.5)), 0.0, "nearest tracks hold the from key")


func _check_continuity() -> void:
	var q := Quaternion(Vector3(0, 1, 0), PI * 0.75)
	var keys := [
		{"time": 0.0, "value": Quaternion.IDENTITY},
		{"time": 0.5, "value": q},
		{"time": 1.0, "value": -q},
	]
	ClipSpec.align_quaternions(keys)
	var q1: Quaternion = keys[1].value
	var q2: Quaternion = keys[2].value
	_expect(q1.dot(keys[0].value as Quaternion) >= 0.0, "align keeps a same-hemisphere key")
	_expect(q2.dot(q1) >= 0.0, "align flips the opposite-hemisphere key")
	var looped := [
		{"time": 0.0, "value": Quaternion.IDENTITY, "transition": 0.5},
		{"time": 0.9, "value": Quaternion(Vector3(0, 1, 0), 0.3)},
	]
	ClipSpec.close_loop(looped, 1.0)
	_expect_eq(looped.size(), 3, "close_loop appends a closing key")
	_expect_approx(float(looped[2].time), 1.0, "close_loop lands on the clip length")
	_expect((looped[2].value as Quaternion).is_equal_approx(Quaternion.IDENTITY), "close_loop copies the first value")
	_expect_approx(float(looped[2].transition), 0.5, "close_loop copies the first transition")
	var short := [{"time": 0.0, "value": 0.0}, {"time": 0.5, "value": 1.0}]
	ClipSpec.close_loop(short, 0.5)
	_expect_approx(float(short[1].value), 0.0, "close_loop overwrites a key already at the length")
	ClipSpec.close_loop([], 1.0)
	_expect(true, "close_loop tolerates empty keys")


func _check_trim_split() -> void:
	var spec := _fixture()
	var trimmed := SpecModifiers.trim(spec, 0.25, 0.75, true)
	_expect_approx(float(trimmed.length), 0.5, "trim sets the length to the range")
	_expect_eq(_key_times(trimmed.tracks[0]), [0.0, 0.25, 0.5], "trim keeps the middle key and adds boundaries")
	_expect_vec(trimmed.tracks[0].keys[0].value, Vector2(5, 2), "trim samples the boundary value")
	var trimmed_raw := SpecModifiers.trim(spec, 0.25, 0.75, false)
	_expect_eq(_key_times(trimmed_raw.tracks[0]), [0.25], "trim without keep_bounds drops the edges")
	_expect_eq((trimmed_raw.markers as Array).size(), 1, "trim keeps markers inside the range")
	var trimmed_far := SpecModifiers.trim(spec, 0.6, 0.9, false)
	_expect_eq((trimmed_far.markers as Array).size(), 0, "trim drops markers outside the range")
	var parts := SpecModifiers.split(spec, 0.5)
	_expect_approx(float(parts.head.length), 0.5, "split head length")
	_expect_approx(float(parts.tail.length), 0.5, "split tail length")
	_expect_vec(parts.tail.tracks[0].keys[0].value, Vector2(10, 4), "split tail starts at the cut value")
	_expect_eq((parts.head.markers as Array).size(), 1, "split head keeps a marker on the cut")


func _check_merge() -> void:
	var spec := _fixture()
	var other := ClipSpec.make(0.5, Animation.LOOP_NONE)
	ClipSpec.add_value_track(other, "Sprite:position", [{"time": 0.0, "value": Vector2(99, 0)}])
	ClipSpec.add_value_track(other, "Other:scale", [{"time": 0.0, "value": Vector2(1, 1)}])
	var merged := SpecModifiers.merge([spec, other], 0.0)
	_expect_approx(float(merged.length), 1.5, "merge sums the lengths")
	_expect_eq((merged.tracks as Array).size(), 4, "merge unions the tracks")
	var position_track: Dictionary = merged.tracks[ClipSpec.find_track_index(merged, "Sprite:position")]
	_expect_eq(_key_times(position_track), [0.0, 0.5, 1.0, 1.0], "merge offsets the second clip's keys")
	_expect_eq(int(merged.loop_mode), Animation.LOOP_NONE, "merge always produces LOOP_NONE")
	var gapped := SpecModifiers.merge([spec, other], 0.25)
	_expect_approx(float(gapped.length), 1.75, "merge adds the gap between clips")
	var tail_key: Dictionary = gapped.tracks[ClipSpec.find_track_index(gapped, "Other:scale")].keys[0]
	_expect_approx(float(tail_key.time), 1.25, "gap offsets the second clip")


func _check_amplitude() -> void:
	var spec := _fixture()
	var doubled := SpecModifiers.amplitude(spec, 2.0, null, false)
	_expect_vec(doubled.tracks[0].keys[1].value, Vector2(20, 8), "amplitude scales deltas about the first key")
	_expect_vec(doubled.tracks[0].keys[0].value, Vector2(0, 0), "amplitude leaves the baseline key alone")
	var flat := SpecModifiers.amplitude(spec, 0.0, null, false)
	_expect_vec(flat.tracks[0].keys[1].value, Vector2(0, 0), "amplitude 0 collapses onto the baseline")
	_expect_approx(float(flat.tracks[1].keys[1].value), 0.0, "amplitude applies per track baseline")
	var based := SpecModifiers.amplitude(spec, 0.0, Vector2(10, 0), true)
	_expect_vec(based.tracks[0].keys[0].value, Vector2(10, 0), "explicit baseline is used")


func _check_loop() -> void:
	var spec := _fixture()
	var looped := SpecModifiers.set_loop(spec, Animation.LOOP_LINEAR, false)
	_expect_eq(int(looped.loop_mode), Animation.LOOP_LINEAR, "set_loop stores the mode")
	_expect_eq(_key_times(looped.tracks[1]), [0.0, 1.0], "set_loop without seamless keeps keys")
	var seamless := SpecModifiers.set_loop(spec, Animation.LOOP_LINEAR, true)
	var modulate: Dictionary = seamless.tracks[1]
	_expect_eq(_key_times(modulate), [0.0, 1.0], "seamless overwrites an existing final key")
	_expect_approx(float(modulate.keys[1].value), 0.0, "seamless final key matches the first key")
	var position: Dictionary = seamless.tracks[0]
	_expect_approx(float(position.keys[2].value.x), 0.0, "seamless rewrites the last position key")
	_expect_approx(float(position.keys[2].value.y), 0.0, "seamless rewrites both components")


func _check_key_edit() -> void:
	var spec := _fixture()
	var added := SpecModifiers.key_edit(spec, 0, "add", 0.25, Vector2(3, 3), 1.0, 0.0, 0.001)
	_expect_eq(int(added.key_index), 1, "key_edit add reports the new index")
	_expect_eq(_key_times(added.spec.tracks[0]), [0.0, 0.25, 0.5, 1.0], "key_edit add inserts sorted")
	var replaced := SpecModifiers.key_edit(spec, 0, "add", 0.5, Vector2(7, 7), 1.0, 0.0, 0.001)
	_expect_eq((replaced.spec.tracks[0].keys as Array).size(), 3, "key_edit add replaces a key at the same time")
	_expect_vec(replaced.spec.tracks[0].keys[1].value, Vector2(7, 7), "key_edit add overwrites the value")
	var set := SpecModifiers.key_edit(spec, 0, "set", 0.5001, Vector2(1, 2), 0.5, 0.0, 0.001)
	_expect_vec(set.spec.tracks[0].keys[1].value, Vector2(1, 2), "key_edit set matches within tolerance")
	_expect_approx(float(set.spec.tracks[0].keys[1].transition), 0.5, "key_edit set updates the transition")
	var missed := SpecModifiers.key_edit(spec, 0, "set", 0.8, Vector2(1, 2), 1.0, 0.0, 0.01)
	_expect_eq(int(missed.key_index), -1, "key_edit misses outside tolerance")
	var removed := SpecModifiers.key_edit(spec, 0, "remove", 0.5, null, 1.0, 0.0, 0.001)
	_expect_eq((removed.spec.tracks[0].keys as Array).size(), 2, "key_edit remove drops the key")
	var moved := SpecModifiers.key_edit(spec, 0, "move", 0.5, null, 1.0, 0.75, 0.001)
	_expect_eq(_key_times(moved.spec.tracks[0]), [0.0, 0.75, 1.0], "key_edit move retimes the key")
	_expect_eq((spec.tracks[0].keys as Array).size(), 3, "key_edit never mutates its input")


func _check_cleanup() -> void:
	var spec := ClipSpec.make(2.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "N:position", [
		{"time": 0.0, "value": Vector2(0, 0), "transition": 1.0},
		{"time": 0.5, "value": Vector2(0, 0), "transition": 1.0},
		{"time": 1.0, "value": Vector2(0, 0), "transition": 1.0},
		{"time": 1.5, "value": Vector2(5, 0), "transition": 1.0},
	])
	ClipSpec.add_value_track(spec, "Empty:position", [])
	var result := SpecModifiers.cleanup(spec, 0.0001, 0.0, true)
	_expect_eq(int(result.removed), 3, "cleanup reports the duplicate keys and the empty track")
	_expect_eq(_key_times(result.spec.tracks[0]), [1.0, 1.5], "cleanup keeps the last key of a hold")
	_expect_eq((result.spec.tracks as Array).size(), 1, "cleanup drops empty tracks")
	_expect_approx(float(result.spec.length), 2.0, "cleanup preserves the clip length")
	var sparse := ClipSpec.make(2.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(sparse, "N:position", [
		{"time": 0.0, "value": Vector2(0, 0), "transition": 1.0},
		{"time": 0.2, "value": Vector2(3, 0), "transition": 1.0},
		{"time": 1.5, "value": Vector2(5, 0), "transition": 1.0},
	])
	var gapped := SpecModifiers.cleanup(sparse, 0.0001, 0.4, false)
	_expect_eq(_key_times(gapped.spec.tracks[0]), [0.0, 1.5], "min_gap drops keys closer than the gap")


func _check_roundtrip() -> void:
	var spec := _fixture()
	ClipSpec.add_method_track(spec, "Root", [{"time": 0.25, "method": "on_hit", "args": [1, "a"]}])
	ClipSpec.add_audio_track(spec, "Root", [{"time": 0.0, "stream": AudioStreamWAV.new(), "start_offset": 0.0, "end_offset": 0.5}])
	var anim := SpecBuilder.to_animation(spec)
	_expect_eq(anim.get_track_count(), 5, "builder creates every track")
	_expect_approx(anim.length, 1.0, "builder sets the length")
	_expect_eq(anim.get_marker_names().size(), 1, "builder carries markers")
	var back := SpecIO.from_animation(anim)
	_expect_eq(ClipSpec.total_key_count(back), ClipSpec.total_key_count(spec), "round-trip keeps the key count")
	_expect_eq((back.tracks as Array).size(), 5, "round-trip keeps the track count")
	_expect_approx(float(back.tracks[0].keys[1].time), 0.5, "round-trip keeps key times")
	_expect_vec(back.tracks[0].keys[1].value, Vector2(10, 4), "round-trip keeps vector values")
	_expect_approx(float(back.tracks[1].keys[1].value), 1.0, "round-trip keeps float values")
	_expect_eq(str(back.tracks[3].keys[0].method), "on_hit", "round-trip keeps method names")
	_expect_eq((back.tracks[3].keys[0].args as Array).size(), 2, "round-trip keeps method args")
	_expect(back.tracks[4].keys[0].stream != null, "round-trip keeps audio streams")
	_expect_approx(float(back.tracks[4].keys[0].end_offset), 0.5, "round-trip keeps audio offsets")
	_expect(SpecIO.unsupported_tracks(anim).is_empty(), "a built clip has no unsupported tracks")
	var bezier := Animation.new()
	bezier.add_track(Animation.TYPE_BEZIER)
	bezier.track_set_path(0, NodePath("N:value"))
	_expect_eq(SpecIO.unsupported_tracks(bezier).size(), 1, "bezier tracks are reported as unsupported")
	_expect(not SpecIO.describe_unsupported(bezier).is_empty(), "unsupported tracks have a description")
	var invalid := SpecBuilder.validate({"length": 1.0, "tracks": [{"type": Animation.TYPE_BEZIER, "path": "X", "keys": []}]})
	_expect(invalid.has("error"), "builder validation rejects unsupported track types")


func _check_registry() -> void:
	var families := OpRegistry.families()
	_expect_eq(families.size(), 8, "eight tool families are registered")
	for family_name in OpRegistry.family_names():
		var info: Dictionary = families[family_name]
		var description := str(info.get("description", ""))
		_expect(not description.is_empty(), "%s has a description" % family_name)
		_expect(description.length() <= OpRegistry.MAX_DESCRIPTION_CHARS,
			"%s description fits the %d-char cap (got %d)" % [family_name, OpRegistry.MAX_DESCRIPTION_CHARS, description.length()])
		_expect(ResourceLoader.exists(str(info.get("handler", ""))), "%s handler exists" % family_name)
		## The plugin's own gate uses Godot's compact JSON.stringify, but the
		## Godot AI server re-measures the pushed schema with python json.dumps,
		## whose default separators are ", " and ": " - a few hundred bytes
		## larger. Count the separators to stay on the server's side of the cap.
		var serialized := JSON.stringify(info.get("schema", {}))
		var server_bytes: int = serialized.to_utf8_buffer().size() \
			+ serialized.count(":") + serialized.count(",")
		_expect(server_bytes <= OpRegistry.MAX_SCHEMA_BYTES,
			"%s schema fits the %d-byte server cap (got ~%d)" % [family_name, OpRegistry.MAX_SCHEMA_BYTES, server_bytes])
		var schema: Dictionary = info.get("schema", {})
		var properties: Dictionary = schema.get("properties", {})
		var op_enum: Array = properties.get("op", {}).get("enum", [])
		var descriptor_names: Array = []
		for descriptor in info.get("ops", []):
			descriptor_names.append(descriptor.name)
			_expect(op_enum.has(descriptor.name), "%s/%s is in the schema enum" % [family_name, descriptor.name])
			_expect(not str(descriptor.get("summary", "")).is_empty(), "%s/%s has a summary" % [family_name, descriptor.name])
			_expect(not (descriptor.get("example", {}) as Dictionary).is_empty(), "%s/%s has an example" % [family_name, descriptor.name])
			for param in descriptor.get("params", []):
				_expect(properties.has(param),
					"%s/%s param '%s' is declared in the schema" % [family_name, descriptor.name, param])
		for op_name in op_enum:
			_expect(descriptor_names.has(op_name), "%s enum op '%s' has a descriptor" % [family_name, op_name])
		for required in schema.get("required", []):
			_expect(properties.has(required), "%s required param '%s' is declared" % [family_name, required])
		for param_name in properties:
			var used := false
			for descriptor in info.get("ops", []):
				if (descriptor.get("params", []) as Array).has(param_name):
					used = true
					break
			if param_name != "op":
				_expect(used, "%s param '%s' is used by at least one op" % [family_name, param_name])


func _check_docs_fresh() -> void:
	var repo_root := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var docs_path := repo_root.path_join("docs").path_join("op-index.md")
	_expect(FileAccess.file_exists(docs_path), "docs/op-index.md exists")
	if not FileAccess.file_exists(docs_path):
		return
	var on_disk := FileAccess.get_file_as_string(docs_path).replace("\r\n", "\n")
	var rendered := OpRegistry.render_markdown()
	_expect(on_disk == rendered, "docs/op-index.md is up to date (run tools/gen_docs.ps1)")
	if on_disk != rendered:
		print("  hint: docs differ, regenerate with tools/gen_docs.ps1")
