extends SceneTree

## Tier-1 headless checks for the procedural motion math: curve sampling,
## periodic noise, rest-relative rotation conversion, the two-bone leg solve and
## smoothing. Pure functions only - no editor, no skeleton, no MCP. Run with:
##
##   godot --headless --path test_project --script res://tests/tier1_motion_drivers.gd
##
## (Named without the `test_` prefix so the editor suite runner ignores it.)

const MotionDrivers := preload("res://addons/godot_ai_animation/spec/motion_drivers.gd")
const MotionSpecs := preload("res://addons/godot_ai_animation/spec/motion_specs.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	_check_sampling()
	_check_signals()
	_check_channels()
	_check_rotation_conversion()
	_check_aim()
	_check_world_delta()
	_check_knee()
	_check_spring()
	_check_smoothing()
	_check_foot_trajectory()
	if _failures == 0:
		print("TIER1 PASS (%d checks)" % _checks)
	else:
		print("TIER1 FAIL (%d/%d checks failed)" % [_failures, _checks])
	quit(0 if _failures == 0 else 1)


## The foot's lift profile. It used to be 1.0 across the whole swing, so the
## ankle jumped to full height at toe-off and dropped at heel strike - a step,
## not an arc. The contract: exactly 0 at both contacts, a single peak in
## between, and no plateau anywhere.
func _check_foot_trajectory() -> void:
	var stance := 0.6
	var span := 0.7
	var samples := 200
	# Rooted (the real walk: the ankle is a world point) and unrooted.
	for rooted in [true, false]:
		var label := "rooted" if rooted else "in-place"
		var heights: Array = []
		var apex := 0.0
		var apex_at := 0.0
		for index in samples + 1:
			var p := float(index) / float(samples)
			var foot: Dictionary = MotionSpecs._foot_trajectory(p, stance, span, 1.4, 1.0, rooted)
			var height := float(foot.height)
			heights.append(height)
			if height > apex:
				apex = height
				apex_at = p
			if p < stance:
				_expect_approx(height, 0.0, "%s: the stance foot is on the ground (p=%.3f)" % [label, p])
		# Heel strike is the wrap point: the lift has to arrive back at 0 there.
		var last: Dictionary = MotionSpecs._foot_trajectory(
			1.0 - 0.0005, stance, span, 1.4, 1.0, rooted)
		_expect(float(last.height) < 0.01,
			"%s: the swing lands back at ground level (got %.4f)" % [label, float(last.height)])
		_expect(apex > 0.9, "%s: the swing lifts nearly full height (%.3f)" % [label, apex])
		# The apex sits inside the swing, and before its middle (a foot clears the
		# ground early and comes down late).
		var swing_start := stance
		_expect(apex_at > swing_start + 0.1 and apex_at < swing_start + (1.0 - swing_start) * 0.75,
			"%s: the apex is inside the swing at p=%.3f" % [label, apex_at])
		# No plateau: a run of identical non-zero values means the foot is parked
		# in the air, which is the defect this replaces.
		var plateau := 0
		for index in range(1, heights.size()):
			if absf(float(heights[index]) - float(heights[index - 1])) < 0.0001 \
					and float(heights[index]) > 0.05:
				plateau += 1
		_expect(plateau < heights.size() / 20,
			"%s: the lift is a curve, not a plateau (%d flat samples)" % [label, plateau])
		# It rises and then falls exactly once.
		var rises := 0
		for index in range(1, heights.size()):
			if float(heights[index]) > float(heights[index - 1]) + 0.0005:
				rises += 1
		_expect(rises >= 1 and rises < heights.size() / 2,
			"%s: one rise, one fall (%d rising samples)" % [label, rises])
		# Smoothstep at both ends: the foot leaves and lands horizontally, so the
		# first and last steps of the arc are tiny.
		var first_step: float = float(heights[0]) - 0.0
		var contact_step := -1.0
		for index in range(1, heights.size()):
			if float(heights[index]) < 0.05:
				contact_step = absf(float(heights[index]) - float(heights[index - 1]))
				break
		_expect(first_step < 0.02 or contact_step < 0.02,
			"%s: the arc leaves and lands softly (%.4f)" % [label, minf(first_step, contact_step)])


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  FAIL: %s" % message)


func _expect_approx(actual: float, expected: float, message: String) -> void:
	_expect(absf(actual - expected) < 0.0001, "%s (expected %s, got %s)" % [message, expected, actual])


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _expect_vec(actual: Vector3, expected: Vector3, message: String) -> void:
	_expect(actual.is_equal_approx(expected), "%s (expected %s, got %s)" % [message, expected, actual])


# --- checks -----------------------------------------------------------------

func _check_sampling() -> void:
	var times := MotionDrivers.sample_times(1.0, 24.0)
	_expect_eq(times.size(), 25, "24 samples/s over 1s gives 25 timed keys")
	_expect_approx(times[0], 0.0, "sampling starts at 0")
	_expect_approx(times[24], 1.0, "sampling ends at the length")
	_expect_eq(MotionDrivers.sample_count(0.001, 24.0), 2, "tiny clips still get two intervals")
	var sparse := MotionDrivers.sample_times(2.0, 8.0)
	_expect_eq(sparse.size(), 17, "2s at 8/s gives 17 keys")
	_expect_approx(sparse[8], 1.0, "sample times are evenly spaced")


func _check_signals() -> void:
	_expect_approx(MotionDrivers.signal_value("sine", 0.0), 0.0, "sine starts at 0")
	_expect_approx(MotionDrivers.signal_value("sine", 0.25), 1.0, "sine peaks a quarter in")
	_expect_approx(MotionDrivers.signal_value("cosine", 0.0), 1.0, "cosine starts at 1")
	_expect_approx(MotionDrivers.signal_value("triangle", 0.0), 1.0, "triangle starts high")
	_expect_approx(MotionDrivers.signal_value("triangle", 0.5), -1.0, "triangle dips at the midpoint")
	_expect_approx(MotionDrivers.signal_value("triangle", 0.75), 0.0, "triangle rises through the middle")
	var noise_a := MotionDrivers.channel_samples(
		{"amplitude": 1.0, "frequency": 1.0, "shape": "noise", "seed": 7, "harmonics": 4}, 1.0, 16.0)
	var noise_b := MotionDrivers.channel_samples(
		{"amplitude": 1.0, "frequency": 1.0, "shape": "noise", "seed": 8, "harmonics": 4}, 1.0, 16.0)
	_expect(noise_a != noise_b, "different seeds give different noise")
	_expect_approx(noise_a[0], noise_a[noise_a.size() - 1], "noise closes its loop exactly")
	var peak := 0.0
	for value in noise_a:
		peak = maxf(peak, absf(value))
	_expect(peak <= 1.0001, "noise stays bounded (peak %s)" % peak)


func _check_channels() -> void:
	var channel := {"axis": Vector3.UP, "amplitude": 10.0, "frequency": 1.0, "phase": 0.25, "shape": "sine"}
	_expect_approx(MotionDrivers.channel_value(channel, 0.0), 10.0, "phase shifts the sine to its peak")
	_expect_approx(MotionDrivers.channel_value(channel, 0.5), -10.0, "the same channel reverses half a cycle later")
	var constant := {"amplitude": 0.0, "offset": 4.5}
	_expect_approx(MotionDrivers.channel_value(constant, 0.7), 4.5, "a zero-amplitude channel is its offset")
	var lagged := {"axis": Vector3.UP, "amplitude": 10.0, "frequency": 1.0, "phase": 0.25, "lag": 0.25, "shape": "sine"}
	_expect_approx(MotionDrivers.channel_value(lagged, 0.25), 10.0, "lag delays the curve")
	_expect_approx(MotionDrivers.channel_value(lagged, 0.0), 0.0, "lagged channel has not peaked yet")
	var single := MotionDrivers.compose_rotation([
		{"axis": Vector3.RIGHT, "amplitude": 0.0, "offset": 90.0},
	], 0.0)
	_expect_vec((Basis(single) * Vector3.UP).normalized(), Vector3.BACK, "a single right-axis rotation tips up to back")
	var composed := MotionDrivers.compose_rotation([
		{"axis": Vector3.UP, "amplitude": 0.0, "offset": 90.0},
		{"axis": Vector3.RIGHT, "amplitude": 0.0, "offset": 90.0},
	], 0.0)
	var rotated := (Basis(composed) * Vector3.UP).normalized()
	_expect_vec(rotated, Vector3.RIGHT, "compose_rotation multiplies in list order")
	_expect(MotionDrivers.compose_rotation([], 0.3).is_equal_approx(Quaternion.IDENTITY), "no channels is identity")


func _check_rotation_conversion() -> void:
	var rest := Basis.from_euler(Vector3(0.3, -0.7, 0.2))
	var world := Quaternion(Vector3(0.2, 1.0, 0.3).normalized(), 0.8)
	var delta := MotionDrivers.rotation_delta(rest, world)
	var composed := rest * Basis(delta)
	_expect(composed.is_equal_approx(Basis(world) * rest), "local delta reproduces the world rotation")
	_expect(MotionDrivers.rotation_delta(rest, Quaternion.IDENTITY).is_equal_approx(Quaternion.IDENTITY),
		"identity world rotation keeps the rest pose")


func _check_aim() -> void:
	var parent_rest := Basis.from_euler(Vector3(0.0, 0.4, 0.0))
	var bone_rest := Basis.from_euler(Vector3(0.2, 0.4, -0.1))
	var desired := Vector3(1.0, 0.3, -0.6).normalized()
	var solve := MotionDrivers.aim_delta(parent_rest, parent_rest, bone_rest, desired)
	_expect_vec((solve.global * Vector3.UP).normalized(), desired, "aim points the bone at the target")
	var parent_animated := Basis(Quaternion(Vector3.UP, PI / 2.0)) * parent_rest
	var solve_animated := MotionDrivers.aim_delta(parent_animated, parent_rest, bone_rest, desired)
	_expect_vec((solve_animated.global * Vector3.UP).normalized(), desired, "aim works with an animated parent")
	var rest_dir := (bone_rest * Vector3.UP).normalized()
	var no_op := MotionDrivers.aim_delta(parent_rest, parent_rest, bone_rest, rest_dir)
	_expect(no_op.delta.is_equal_approx(Quaternion.IDENTITY), "aiming at the rest direction is identity")


func _check_world_delta() -> void:
	var parent_rest := Basis.from_euler(Vector3(0.0, 0.4, 0.0))
	var parent_animated := Basis(Quaternion(Vector3.UP, PI / 3.0)) * parent_rest
	var bone_rest := Basis.from_euler(Vector3(0.2, 0.4, -0.1))
	var world_rotation := Quaternion(Vector3.RIGHT, 0.5)
	var delta := MotionDrivers.world_delta(parent_animated, parent_rest, bone_rest, world_rotation)
	var animated_rest := parent_animated * parent_rest.inverse() * bone_rest
	_expect((animated_rest * Basis(delta)).is_equal_approx(Basis(world_rotation) * animated_rest),
		"world_delta applies its rotation in world space around the animated rest")
	_expect(MotionDrivers.world_delta(parent_rest, parent_rest, bone_rest, Quaternion.IDENTITY)
		.is_equal_approx(Quaternion.IDENTITY), "world_delta with an identity rotation is a no-op")


func _check_knee() -> void:
	var hip := Vector3(0, 1.0, 0)
	var ankle := Vector3(0, 0.0, 0.4)
	var knee := MotionDrivers.knee_position(hip, ankle, 0.55, 0.55, Vector3(0, 0, 1))
	_expect_approx((knee - hip).length(), 0.55, "knee sits at the thigh length")
	_expect_approx((ankle - knee).length(), 0.55, "knee sits at the shin length")
	_expect((knee - Vector3(0, 0.5, 0.2)).dot(Vector3(0, 0, 1)) > 0.0, "knee bends with the forward axis")
	var unreachable := MotionDrivers.knee_position(hip, Vector3(0, 0, 0), 0.2, 0.2, Vector3(0, 0, 1))
	_expect_approx((unreachable - hip).length(), 0.2, "an over-stretched target still respects the thigh length")
	_check_leg_reach()


## The honest part of the two-bone solve: it reports an unreachable target
## instead of silently substituting a reachable one, and both bones aim at the
## SAME reachable point, so the foot lands where the leg can actually get to.
func _check_leg_reach() -> void:
	var hip := Vector3(0, 1.0, 0)
	var upper := 0.5
	var lower := 0.5
	var reach := upper + lower
	# A target well inside the reach: nothing is clamped.
	var inside := MotionDrivers.solve_leg(hip, Vector3(0, 0.4, 0), upper, lower, Vector3(0, 0, 1))
	_expect(not bool(inside.clamped), "a reachable target is not clamped")
	_expect_approx(float(inside.shortfall), 0.0, "a reachable target has no shortfall")
	_expect_approx((inside.knee - hip).length(), upper, "the thigh is fully used")
	_expect_approx(((inside.effective_ankle as Vector3) - (inside.knee as Vector3)).length(), lower,
		"the shin is fully used")
	# A target beyond the leg: clamped to the reach, reported, and the foot ends
	# up on the EFFECTIVE ankle rather than the unreachable one.
	var far := MotionDrivers.solve_leg(hip, Vector3(0, -2.0, 0), upper, lower, Vector3(0, 0, 1))
	_expect(bool(far.clamped), "an over-stretched target is reported as clamped")
	_expect(float(far.shortfall) > 1.0, "the shortfall is measured (%.3f m)" % float(far.shortfall))
	var effective: Vector3 = far.effective_ankle
	_expect_approx((effective - hip).length(), reach - 0.001,
		"the effective ankle sits at the edge of the reach")
	_expect_approx((far.knee as Vector3).distance_to(effective), lower,
		"the shin still reaches the effective ankle exactly")
	_expect_approx((far.knee as Vector3).distance_to(hip), upper,
		"and the thigh is fully extended")
	# A target INSIDE the minimum fold (|upper-lower|) is clamped too - the leg
	# cannot fold through itself.
	var folded := MotionDrivers.solve_leg(hip, hip + Vector3(0, 0.01, 0), 0.5, 0.2, Vector3(0, 0, 1))
	_expect(bool(folded.clamped), "a target inside the minimum fold is clamped")
	# The pole follows the hint, including when the hint is parallel to the leg
	# (the singular case a cross product against UP could not answer).
	var hip_high := Vector3(0, 1.0, 0)
	var straight_down := Vector3(0, -1, 0)
	var forward := MotionDrivers.solve_leg(hip_high, hip_high + straight_down * 0.6, 0.5, 0.5, Vector3(0, 0, 1))
	var backward := MotionDrivers.solve_leg(hip_high, hip_high + straight_down * 0.6, 0.5, 0.5, Vector3(0, 0, -1))
	_expect(not (forward.knee as Vector3).is_equal_approx(backward.knee as Vector3),
		"the measured rest bend decides which way a straight leg folds")
	_expect((forward.knee as Vector3).z > 0.0, "a +z hint folds the knee forward")
	_expect((backward.knee as Vector3).z < 0.0, "a -z hint folds it backward")


func _check_spring() -> void:
	var steady: Array = []
	for index in 40:
		steady.append(Quaternion.IDENTITY)
	var at_rest := MotionDrivers.follow_spring(steady, 120.0, 12.0, 0.02, Quaternion.IDENTITY)
	_expect((at_rest[at_rest.size() - 1] as Quaternion).is_equal_approx(Quaternion.IDENTITY),
		"a spring at rest stays at rest")
	var step: Array = []
	var target := Quaternion(Vector3.UP, deg_to_rad(45.0))
	for index in 120:
		step.append(target)
	var followed := MotionDrivers.follow_spring(step, 120.0, 12.0, 0.02, Quaternion.IDENTITY)
	_expect((followed[0] as Quaternion).get_angle() < target.get_angle() * 0.5,
		"the spring lags behind a step target")
	_expect((followed[followed.size() - 1] as Quaternion).angle_to(target) < deg_to_rad(2.0),
		"the spring settles on the target (%s deg)" % rad_to_deg((followed[followed.size() - 1] as Quaternion).angle_to(target)))
	var again := MotionDrivers.follow_spring(step, 120.0, 12.0, 0.02, Quaternion.IDENTITY)
	_expect(followed == again, "the spring simulation is deterministic")
	var slow := MotionDrivers.follow_spring(step, 20.0, 1.0, 0.02, Quaternion.IDENTITY)
	_expect((slow[slow.size() - 1] as Quaternion).angle_to(target)
		> (followed[followed.size() - 1] as Quaternion).angle_to(target),
		"a softer spring settles slower")


func _check_smoothing() -> void:
	_expect_approx(MotionDrivers.smoothstep(0.0), 0.0, "smoothstep starts at 0")
	_expect_approx(MotionDrivers.smoothstep(1.0), 1.0, "smoothstep ends at 1")
	_expect_approx(MotionDrivers.smoothstep(0.5), 0.5, "smoothstep is symmetric")
	var values := PackedFloat32Array([0.0, 0.0, 1.0, 0.0, 0.0])
	var half := MotionDrivers.smooth_series(values, 0.5, false)
	_expect_approx(half[2], 0.5, "half smoothing keeps half the spike")
	var full := MotionDrivers.smooth_series(values, 1.0, false)
	_expect_approx(full[2], 0.0, "full smoothing removes an isolated spike")
	var constant := PackedFloat32Array([3.0, 3.0, 3.0, 3.0])
	_expect_approx(MotionDrivers.smooth_series(constant, 1.0, true)[1], 3.0, "smoothing keeps constants")
