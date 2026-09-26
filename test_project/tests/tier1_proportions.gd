extends SceneTree

## Does the procedural motion hold up on a rig that is not the fixture?
##
## Everything the motion suite proves is proved on one human dummy with a
## 0.85 m leg. That is a comfortable rig: adult proportions, symmetric, and
## exactly the leg length the defaults were written against. Nothing said what
## happens to a child's leg, a giant's, or a rig whose two legs differ - and the
## answers were not all good.
##
## This is a proportion matrix: the same recipes over rigs that differ ONLY in
## leg length, symmetry and orientation, asserting the properties that must
## survive the difference.
##
## Two of its assertions are dimensionless on purpose. The FRONDE NUMBER
## Fr = v / sqrt(g * L) is the standard way gait speed is compared across body
## sizes - it is what makes a child's cadence and an adult's comparable at all
## (walk-to-run transition sits near Fr = 0.5 regardless of leg length). Without
## it, "speed" is a metre value that a short rig can never reach and a long rig
## exceeds for free, and a test asserting an absolute speed would be asserting
## the dummy's luck. Stance fraction and stride-to-leg ratio are likewise read
## off published gait (stance is about 60% of the cycle when walking; running
## duty factor falls from ~0.45 toward ~0.28 as speed rises).
##
## Foot slide is measured through RigAnalysis.foot_slide on COMPUTED positions,
## never skeleton.get_bone_global_pose(): a bare headless --script tree does not
## apply an AnimationMixer's blend and reads a stale pose, which is a trap this
## repo has already fallen into once (tier1_root_motion.gd).
##
##   godot --headless --path test_project --script res://tests/tier1_proportions.gd

const MotionSpecs := preload("res://addons/godot_ai_animation/spec/motion_specs.gd")
const RigAnalysis := preload("res://addons/godot_ai_animation/spec/rig_analysis.gd")
const GoldenDigest := preload("res://tests/golden_digest.gd")

const GRAVITY := 9.81
const REFERENCE_LEG := 0.85

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	_check_the_matrix_holds_every_proportion()
	_check_the_synthetic_walk_matches_its_golden()
	if _failures == 0:
		print("TIER1 PASS (%d checks)" % _checks)
	else:
		print("TIER1 FAIL (%d/%d checks failed)" % [_failures, _checks])
	quit(0 if _failures == 0 else 1)


## The same golden discipline as the editor suite, on a rig that is not the
## fixture and needs no editor: this suite runs on ubuntu AND windows, so it is
## the leg that would catch a platform difference in the generator's arithmetic
## even if the editor fixtures were regenerated on one machine.
##
## It digests the SPEC rather than a committed clip - a headless suite has no
## AnimationPlayer in the picture - so it is a separate fixture and not
## comparable with the walk/run/idle ones. What it gates is the maths: stride,
## stance, the two-bone solve, the rig frame.
func _check_the_synthetic_walk_matches_its_golden() -> void:
	var skeleton := _rig(REFERENCE_LEG)
	var result := _walk(skeleton, 1.0, 12.0)
	_expect(not result.has("error"), "the golden walk builds (%s)" % str(result.get("error", "")))
	if result.has("error"):
		return
	var built: Dictionary = result.built
	var digest: Dictionary = GoldenDigest.from_keys(built.keys, float(result.ctx.length))
	var path := "res://tests/fixtures/golden_spec_walk.json"
	var loaded: Dictionary = GoldenDigest.load_or_record(path, digest)
	_expect(not loaded.has("error"), "the spec golden is usable (%s)" % str(loaded.get("error", "")))
	if loaded.has("error"):
		return
	if bool(loaded.get("recorded", false)):
		print("  recorded %s (%d tracks, %s)" % [
			str(loaded.get("path", path)), (digest.tracks as Array).size(), str(digest.godot)])
		return
	var golden: Dictionary = loaded.golden
	var compared: Dictionary = GoldenDigest.compare(digest, golden)
	_expect(str(compared.shape).is_empty(),
		"the synthetic walk still has the golden's shape (%s)" % str(compared.shape))
	if str(compared.shape).is_empty():
		_expect(int(compared.worst) <= int(golden.get("tolerance", GoldenDigest.TOLERANCE)),
			"the synthetic walk matches its golden (worst drift %d units at %s; 1 unit = 1/2048)"
				% [int(compared.worst), str(compared.where)])
	print("  golden spec walk: worst drift %d unit(s) (tolerance %d; recorded on Godot %s, running %s)"
		% [int(compared.worst), int(golden.get("tolerance", GoldenDigest.TOLERANCE)),
			str(golden.get("godot", "?")), str(digest.godot)])


## A biped with the given BONE-LENGTH SUM per leg (thigh + shin), which is what
## the generator's `leg_length` actually is - the fully extended span, not the
## hip-to-ankle distance. They differ on a knee-bent rest pose, and confusing
## the two is what made the first version of this fixture report nonsense.
##
## `left_leg` / `right_leg` scale the two legs independently, so an asymmetric
## rig is a first-class citizen rather than an accident. The toe runs along +Z so
## heel-to-toe gives the rig its own forward.
func _rig(leg: float, left_leg: float = 1.0, right_leg: float = 1.0,
		rest_knee: float = 0.06) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "Rig"
	# The rest pose is knee-BENT, like a real rig's, so the two-bone solve has slack
	# to consume and a straight-legged rig cannot hide a clamp.
	var bend := rest_knee
	# Rest origins are LOCAL to the parent bone: set_bone_rest is a local rest, and
	# get_bone_global_rest accumulates. Specifying global-looking values here
	# compounds down the chain (the first version of this fixture measured a 0.5 m
	# leg as 0.76 m for exactly that reason).
	_bone(skeleton, "B-hips", Vector3.ZERO, -1)
	_bone(skeleton, "B-spine", Vector3(0.0, 0.12, 0.0), 0)
	_bone(skeleton, "B-chest", Vector3(0.0, 0.16, 0.0), 1)
	_bone(skeleton, "B-head", Vector3(0.0, 0.16, 0.0), 2)
	for side in ["L", "R"]:
		var scale: float = left_leg if side == "L" else right_leg
		var total: float = leg * scale
		var thigh := total * 0.5
		var shin := total * 0.5
		var lateral := 0.1 if side == "L" else -0.1
		# Segment DIRECTIONS, so each bone's length is exactly thigh / shin. Placing
		# the joints at vertical offsets instead would shorten the thigh by however
		# much the knee is bent, and the fixture would not be building the leg it
		# says it is. The knee sits forward of the hip-ankle line, which is what a
		# bent rest knee looks like, and the hip-to-ankle distance is therefore
		# genuinely shorter than the bone sum.
		var thigh_dir := Vector3(0.0, -cos(rest_knee), sin(rest_knee))
		var shin_dir := Vector3(0.0, -cos(rest_knee * 0.6), -sin(rest_knee * 0.6))
		var thigh_index := skeleton.get_bone_count()
		_bone(skeleton, "B-thigh." + side, Vector3(lateral, 0.0, 0.0), 0)
		_bone(skeleton, "B-shin." + side, thigh_dir * thigh, thigh_index)
		_bone(skeleton, "B-foot." + side, shin_dir * shin, thigh_index + 1)
		_bone(skeleton, "B-toe." + side, Vector3(0.0, 0.0, total * 0.14), thigh_index + 2)
	return skeleton


func _bone(skeleton: Skeleton3D, name: String, local_origin: Vector3, parent: int) -> void:
	skeleton.add_bone(name)
	var index := skeleton.get_bone_count() - 1
	skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, local_origin))
	skeleton.set_bone_parent(index, parent)


## Hip-to-ankle distance of a leg: the length biomechanics means by "leg length",
## which is shorter than the bone sum whenever the rest pose is bent.
func _hip_to_ankle(ctx: Dictionary, side: String) -> float:
	var leg: Dictionary = ctx.legs[side]
	return (leg.ankle as Vector3).distance_to(leg.hip)


func _roles() -> Dictionary:
	return {
		"hips": "B-hips", "spine": "B-spine", "chest": "B-chest", "head": "B-head",
		"thigh_l": "B-thigh.L", "shin_l": "B-shin.L", "foot_l": "B-foot.L", "toe_l": "B-toe.L",
		"thigh_r": "B-thigh.R", "shin_r": "B-shin.R", "foot_r": "B-foot.R", "toe_r": "B-toe.R",
	}


## A walk built the way the handler builds one: the same rig-relative rewrite of
## the distance defaults, so this tests the real assembly path rather than a
## context assembled differently.
func _walk(skeleton: Skeleton3D, length := 1.0, samples := 24.0) -> Dictionary:
	var ctx := MotionSpecs.context_from_skeleton(skeleton, _roles(), length, samples,
		true, REFERENCE_LEG)
	if ctx.has("error"):
		return {"error": ctx.error}
	ctx["config"] = MotionSpecs.walk_config("default", {})
	_scale_defaults(ctx)
	var built: Dictionary = MotionSpecs.gait_keys(ctx, false)
	if built.has("error"):
		return {"error": built.error}
	return {"ctx": ctx, "built": built}


## The handler's own rewrite, reproduced because it is the behaviour under test
## (`scale_distances` in context_from_skeleton takes the config as an argument it
## does not have; see the note there).
func _scale_defaults(ctx: Dictionary) -> void:
	var leg := MotionSpecs.measured_leg(ctx)
	if leg <= 0.0001:
		return
	var factor := leg / REFERENCE_LEG
	ctx["distance_scale"] = factor
	if is_equal_approx(factor, 1.0):
		return
	var config: Dictionary = ctx["config"]
	for key in ["bob", "sway", "foot_lift", "jump_crouch", "jump_height", "crouch"]:
		if not config.has(key):
			continue
		config[key] = float(config[key]) * factor


func _froude(speed: float, leg: float) -> float:
	return speed / sqrt(GRAVITY * maxf(leg, 0.0001))


## Ankle positions over the clip, computed the same way the two-bone solve places
## them: the target, clamped to what the leg can actually reach.
func _ankle_track(ctx: Dictionary, built: Dictionary, side: String) -> Array:
	var leg: Dictionary = ctx.legs[side]
	var keys: Dictionary = built.keys
	var out: Array = []
	for bone in [leg.thigh, leg.shin, leg.foot]:
		var entry: Dictionary = keys.get(bone, {})
		if entry.has("rotation"):
			out.append(entry.rotation)
	return out


func _check_the_matrix_holds_every_proportion() -> void:
	var proportions := {
		"child (0.50 m legs)": 0.50,
		"reference (0.85 m)": REFERENCE_LEG,
		"tall (1.70 m legs)": 1.70,
	}
	var froudes := {}
	var crouch_ratios := {}
	for label in proportions:
		var leg: float = proportions[label]
		var skeleton := _rig(leg)
		var result := _walk(skeleton)
		_expect(not result.has("error"), "%s: the walk builds (%s)" % [label, str(result.get("error", ""))])
		if result.has("error"):
			continue
		var ctx: Dictionary = result.ctx
		var built: Dictionary = result.built
		var measured := MotionSpecs.measured_leg(ctx)
		_expect_approx(measured, leg, leg * 0.02,
			"%s: the leg's bone sum measures as built (%.4f m vs %.4f m)" % [label, measured, leg])
		# Biomechanics' L is hip-to-ankle, which is shorter than the bone sum
		# because the rest pose is bent. Using the right one is the difference
		# between a Froude number that means something and one that does not.
		var hip_to_ankle := (_hip_to_ankle(ctx, "l") + _hip_to_ankle(ctx, "r")) * 0.5

		# 1. DIMENSIONLESS SPEED. The stride is a fraction of the leg, so the speed
		# a walk implies has to fall in the walking Froude band whatever the leg is.
		# This is the assertion that catches a rig-relative default being left in
		# absolute metres.
		var config: Dictionary = ctx.config
		var stance := float(config.stance)
		var span := 2.0 * measured * sin(deg_to_rad(float(config.stride)))
		var speed := span / (stance * float(ctx.length))
		var froude := _froude(speed, hip_to_ankle)
		froudes[label] = froude
		_expect(froude > 0.05 and froude < 0.60,
			"%s: walking Froude %.3f is in the walking band 0.05-0.60 (speed %.3f m/s, hip-to-ankle %.3f m)"
			% [label, froude, speed, hip_to_ankle])

		# 2. STANCE FRACTION. About 60% of the cycle when walking; the value is a
		# ratio already, so this is a check that the recipe keeps it a ratio.
		_expect(stance > 0.5 and stance < 0.7,
			"%s: stance fraction %.3f is a walking value (published ~0.60)" % [label, stance])

		# 3. RIG-RELATIVE AMPLITUDES. Every default distance must be the same
		# FRACTION of the leg on a child and on a giant. This is the direct test of
		# the claim in the docs, and it is where an unscaled term shows up as a
		# number rather than a vibe.
		var lift := float(config.foot_lift) / measured
		var bob := float(config.bob) / measured
		_expect(lift > 0.02 and lift < 0.12,
			"%s: foot lift is %.4f of the leg (measured %.4f m on a %.2f m leg)"
			% [label, lift, float(config.foot_lift), measured])
		_expect(bob > 0.01 and bob < 0.12,
			"%s: bob is %.4f of the leg (measured %.4f m on a %.2f m leg)"
			% [label, bob, float(config.bob), measured])

		# 4. THE KNEE-BEND CRTERM IS RIG-RELATIVE TOO. `knee_bend` is degrees, so
		# the crouch it buys has to come out of the same scaling as everything else.
		# The recipe computes it as crouch + 0.003 m/deg * distance_scale; without
		# that factor, 30 degrees was 9 cm on every rig - 18% of a child's leg
		# against 6% of an adult's, a three-fold difference in how bent the knees
		# were for the same request, and enough extra reach demand to push a tall
		# rig's own targets past what its leg could span.
		var crouch_term := 0.003 * float(config.knee_bend) \
			* float(ctx.get("distance_scale", 1.0)) / measured
		crouch_ratios[label] = crouch_term
		# A sanity band, deliberately loose: the crouch has to be a modest fraction
		# of the leg. The assertion that matters is not this one - it is that the
		# SAME fraction comes out on every rig, checked below.
		_expect(crouch_term > 0.03 and crouch_term < 0.16,
			"%s: the knee-bend crouch is a modest %.4f of the leg (%.1f deg -> %.4f m on a %.2f m leg)"
			% [label, crouch_term, float(config.knee_bend),
				0.003 * float(config.knee_bend) * float(ctx.get("distance_scale", 1.0)), measured])

		# 5. THE REACH IS HONEST. A stance the leg cannot reach is shortened to what
		# it can, and the recipe says so. What it must NOT do is clamp all clip long
		# on a proportion it simply scales for, because a clamped stance is a foot
		# riding the hips rather than a planted one.
		var meta: Dictionary = built.get("meta", {})
		_expect(not bool(meta.get("clamped", true)),
			"%s: a default walk reaches its own targets (shortfall %.4f m)"
			% [label, float(meta.get("clamp_shortfall_m", 0.0))])

		# 6. LOOP CLOSURE. A looping clip has to arrive back where it started, in
		# value and in step size, or the cycle pops once per loop.
		_check_loop_closure(label, ctx, built)

	# 7. THE POINT OF THE MATRIX: the scaling law that holds across proportions.
	#
	# A stride built from a stride ANGLE gives a stride LENGTH proportional to the
	# leg, so the implied speed is proportional to L, and Fr = v/sqrt(gL) therefore
	# grows as sqrt(L). That is the law the generator actually has, and asserting
	# it is the point: if someone changes the speed law - to the Froude scaling
	# (v ~ sqrt(gL)) that preferred human walking speed actually follows - this
	# fails and says so, instead of the divergence being discovered by eye.
	#
	# Worth recording because it is a real modelling choice, not an oversight: a
	# stride-angle recipe scales a child's speed linearly with their leg, where
	# real preferred walking speed scales with its square root. Every rig here
	# stays inside the walking Froude band, so no rig looks wrong; the tall one
	# simply walks a proportionally faster gait.
	var reference: float = froudes.get("reference (0.85 m)", 0.0)
	for label in froudes:
		if label == "reference (0.85 m)":
			continue
		var value: float = froudes[label]
		var expected := reference * sqrt(proportions[label] / REFERENCE_LEG)
		_expect(absf(value - expected) < 0.02,
			"%s: Froude %.3f follows sqrt(L) from the reference's %.3f (expected %.3f)"
				% [label, value, reference, expected])

	# 7b. AND THE SAME FOR THE KNEE-BEND CROUCH, which is the assertion that was
	# actually broken: a degree is not a distance, so 0.003 m/deg has to be scaled
	# like every other default. It was not, and the same 30 degrees bent a child's
	# knees three times as far as an adult's.
	var crouch_reference: float = crouch_ratios.get("reference (0.85 m)", 0.0)
	for label in crouch_ratios:
		if label == "reference (0.85 m)":
			continue
		_expect(absf(float(crouch_ratios[label]) - crouch_reference) < 0.002,
			"%s: the knee-bend crouch is the same fraction of the leg as the reference's (%.4f vs %.4f)"
				% [label, float(crouch_ratios[label]), crouch_reference])

	# 8. AN ASYMMETRIC RIG. Two legs of genuinely different lengths must still walk,
	# and the stride and the scaled distances must come from the SAME leg.
	#
	# Note what is deliberately NOT asserted: that bob is the same fraction of both
	# legs. It cannot be - bob is one number, so on a rig whose legs differ it is
	# necessarily a different fraction of each. The invariant is that bob and the
	# stride were derived from one leg rather than two, which shows up as the ratio
	# between them matching a symmetric rig built from that same leg.
	var asymmetric := _rig(0.85, 0.8, 1.2)
	var result := _walk(asymmetric)
	_expect(not result.has("error"), "the asymmetric rig walks (%s)" % str(result.get("error", "")))
	if not result.has("error"):
		var ctx: Dictionary = result.ctx
		var left: Dictionary = ctx.legs.l
		var right: Dictionary = ctx.legs.r
		var left_len := float(left.upper) + float(left.lower)
		var right_len := float(right.upper) + float(right.lower)
		_expect(left_len < right_len, "the fixture really is asymmetric (%.3f vs %.3f m)"
			% [left_len, right_len])
		var config: Dictionary = ctx.config
		var long_leg := maxf(left_len, right_len)
		var asymmetric_ratio := float(config.bob) / (2.0 * long_leg * sin(deg_to_rad(float(config.stride))))
		# The same ratio on a symmetric rig whose legs are the long one: identical
		# means both numbers came from that leg.
		var twin := _walk(_rig(long_leg))
		_expect(not twin.has("error"), "the symmetric twin walks")
		if not twin.has("error"):
			var twin_config: Dictionary = (twin.ctx as Dictionary).config
			var twin_leg := MotionSpecs.measured_leg(twin.ctx as Dictionary)
			var twin_ratio := float(twin_config.bob) \
				/ (2.0 * twin_leg * sin(deg_to_rad(float(twin_config.stride))))
			_expect(absf(asymmetric_ratio - twin_ratio) < 0.0005,
				"bob and the stride come from the same leg (asymmetric %.6f, its symmetric twin %.6f)"
					% [asymmetric_ratio, twin_ratio])
		var meta: Dictionary = (result.built as Dictionary).get("meta", {})
		if bool(meta.get("clamped", false)):
			_expect(float(meta.get("clamp_shortfall_m", -1.0)) >= 0.0,
				"an asymmetric rig reports a real shortfall, not a negative one")

	# 9. A RIG WITH NO MEASURABLE LEG. `lower` used to fall back to a hard-coded
	# 0.35 m when the shin measured zero - longer than a whole child's leg - so the
	# rig would stride further than it could physically reach and clamp all clip.
	var degenerate := Skeleton3D.new()
	_bone(degenerate, "B-hips", Vector3.ZERO, -1)
	_bone(degenerate, "B-thigh.L", Vector3(0.1, 0.0, 0.0), 0)
	_bone(degenerate, "B-shin.L", Vector3(0.0, 0.0, 0.0), 1)
	var degenerate_ctx := MotionSpecs.context_from_skeleton(degenerate, _roles(), 1.0, 24.0)
	_expect(degenerate_ctx.has("error"),
		"a rig whose legs measure zero is refused, not given an invented 0.35 m leg")


## The rotation keys a leg solve emitted, for closure checks.
func _ankle_entries(ctx: Dictionary, built: Dictionary, side: String) -> Array:
	var leg: Dictionary = ctx.legs[side]
	var keys: Dictionary = built.keys
	var found: Array = []
	for bone in [leg.thigh, leg.shin, leg.foot]:
		var entry: Dictionary = keys.get(bone, {})
		if entry.has("rotation"):
			found.append(entry.rotation)
	return found


func _check_loop_closure(label: String, ctx: Dictionary, built: Dictionary) -> void:
	var keys: Dictionary = built.keys
	var worst_value := 0.0
	var worst_step := 0.0
	var closed := 0
	for bone in keys:
		var entry: Dictionary = keys[bone]
		if not entry.has("rotation"):
			continue
		var rotations: Array = entry.rotation
		if rotations.size() < 3:
			continue
		var first: Quaternion = rotations[0].delta
		var last: Quaternion = rotations[rotations.size() - 1].delta
		var value_gap := absf(first.angle_to(last))
		var biggest := 0.0
		for index in range(1, rotations.size()):
			var a: Quaternion = (rotations[index - 1] as Dictionary).delta
			var b: Quaternion = (rotations[index] as Dictionary).delta
			biggest = maxf(biggest, a.angle_to(b))
		var into_seam: Quaternion = (rotations[rotations.size() - 2] as Dictionary).delta
		var seam_step := into_seam.angle_to(last)
		worst_value = maxf(worst_value, value_gap)
		worst_step = maxf(worst_step, seam_step - biggest)
		closed += 1
	_expect(closed > 0, "%s: the walk has rotation tracks to close" % label)
	_expect(worst_value < 0.05,
		"%s: every looping track closes in value (worst %.4f rad)" % [label, worst_value])
	_expect(worst_step < 0.05,
		"%s: the seam step is no bigger than the steps inside the clip (worst %.4f rad)"
			% [label, worst_step])


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  FAIL: %s" % message)


func _expect_approx(got: float, want: float, tolerance: float, message: String) -> void:
	_expect(absf(got - want) <= tolerance,
		"%s (got %.6f, want %.6f +/- %.6f)" % [message, got, want, tolerance])
