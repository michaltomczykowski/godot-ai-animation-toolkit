@tool
extends RefCounted

## Cycle definitions for the `animation_motion` family, built on the pure
## `motion_drivers` math. Each builder returns a key dictionary in the shape
## `bone_animation._commit_procedural_clip` consumes:
##
##   { bone_name: {"rotation": [{time, delta, transition}], "position": [...]} }
##
## Everything is sampled at `ctx.samples` keys per second, so curves are smooth
## and the clips stay portable. Dense samples use linear transitions on purpose:
## the curve shape is in the samples.

const MotionDrivers := preload("res://addons/godot_ai_animation/spec/motion_drivers.gd")
const SpineTwist := preload("res://addons/godot_ai_animation/spec/spine_twist.gd")
const ValueCodec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")
const RigAnalysis := preload("res://addons/godot_ai_animation/spec/rig_analysis.gd")

const STYLE_NAMES := ["default", "responsive", "grounded", "relaxed", "heavy", "sneaky"]

## Exact accepted r004 walk recipes. Each motion has a separate profile table.
const _WALK_PROFILES := {
	"responsive": {
		"arm_swing": 20.0, "elbow": 7.0, "elbow_swing": 22.0, "lag": 0.025,
		"elbow_lag": 0.06, "wrist_swing": 7.0, "wrist_lag": 0.085,
		"hip_yaw": 7.0, "hip_roll": 2.8, "torso_twist": 9.0,
		"torso_flex": 2.6, "torso_roll": 0.8, "head_nod": 2.4,
		"head_roll": 0.45, "head_lag": 0.035, "head_stabilize": 0.6,
		"forearm_twist": 6.5, "wrist_sway": 3.0, "arm_variation": 1.2,
		"variation_seed": 241, "hand_relax": 18.0,
	},
	"grounded": {
		"arm_swing": 17.0, "elbow": 8.0, "elbow_swing": 18.0, "lag": 0.04,
		"elbow_lag": 0.075, "wrist_swing": 6.0, "wrist_lag": 0.1,
		"hip_yaw": 8.0, "hip_roll": 3.2, "torso_twist": 8.0,
		"torso_flex": 1.8, "torso_roll": 1.2, "head_nod": 2.0,
		"head_roll": 0.35, "head_lag": 0.025, "head_stabilize": 0.55,
		"forearm_twist": 5.5, "wrist_sway": 2.5, "arm_variation": 0.9,
		"variation_seed": 241, "hand_relax": 20.0,
	},
}

## Running keeps its bent elbows, flight and cadence. These angular controls
## use measured rig geometry; distance defaults below still scale with the rig.
## R2 candidate: continuous human review is required before fixture promotion.
const _RUN_PROFILES := {
	"responsive": {
		"arm_swing": 28.0, "elbow": 55.0, "elbow_swing": 16.0, "lag": 0.025,
		"elbow_lag": 0.03, "wrist_swing": 4.5, "wrist_lag": 0.055,
		"torso_twist": 12.0, "torso_flex": 2.2, "torso_roll": 0.8,
		"head_nod": 1.8, "head_roll": 0.3, "head_lag": 0.025, "head_stabilize": 0.65,
		"forearm_twist": 5.0, "wrist_sway": 1.8, "arm_variation": 0.7,
		"variation_seed": 241, "hand_relax": 26.0,
	},
	"grounded": {
		"arm_swing": 24.0, "elbow": 58.0, "elbow_swing": 14.0, "lag": 0.04,
		"elbow_lag": 0.045, "wrist_swing": 3.0, "wrist_lag": 0.065,
		"torso_twist": 10.0, "torso_flex": 1.7, "torso_roll": 0.9,
		"head_nod": 1.4, "head_roll": 0.25, "head_lag": 0.025, "head_stabilize": 0.7,
		"forearm_twist": 4.0, "wrist_sway": 1.2, "arm_variation": 0.5,
		"variation_seed": 241, "hand_relax": 24.0,
	},
}

## Overlay run variants without mutating the shared walk/other-motion table.
const _RUN_STYLE_MULTIPLIERS := {
	"relaxed": {"elbow": 1.0, "elbow_swing": 0.9, "torso_twist": 0.85,
		"torso_flex": 0.9, "head_nod": 0.9, "wrist_swing": 1.1, "hand_relax": 0.95},
	"heavy": {"elbow": 1.05, "elbow_swing": 0.8, "torso_twist": 0.9,
		"torso_flex": 0.8, "head_nod": 0.8, "forearm_twist": 0.8,
		"wrist_swing": 0.8, "hand_relax": 1.05},
	"sneaky": {"elbow": 1.15, "elbow_swing": 0.8, "torso_twist": 0.7,
		"torso_flex": 0.65, "head_nod": 0.65, "forearm_twist": 0.8,
		"wrist_swing": 0.7, "wrist_sway": 0.75, "hand_relax": 0.9},
}


static func resolved_style(style: String) -> String:
	return "responsive" if style == "default" else style


static func config_for_kind(kind: String, style: String, overrides: Dictionary = {}) -> Dictionary:
	match kind:
		"run": return run_config(style, overrides)
		"idle": return idle_config(style, overrides)
		"jump": return jump_config(style, overrides)
		"turn": return turn_config(style, overrides)
		"strafe": return strafe_config(style, overrides)
		_: return walk_config(style, overrides)

## Style presets are multipliers over the base config, applied before
## `overrides` so callers can still tune individual values.
const _STYLE_MULTIPLIERS := {
	"default": {},
	"relaxed": {
		"stride": 0.85, "arm_swing": 0.8, "bob": 0.8, "sway": 1.25,
		"hip_yaw": 0.8, "lean": 0.8, "foot_lift": 0.8, "lag": 1.4, "elbow": 1.2,
	},
	"heavy": {
		"stride": 0.9, "arm_swing": 0.7, "bob": 1.5, "sway": 1.2,
		"hip_roll": 1.5, "lean": 1.3, "foot_lift": 0.6, "elbow": 1.1,
		"crouch_add": 0.02,
	},
	"sneaky": {
		"stride": 0.7, "arm_swing": 0.35, "knee_bend": 1.8, "bob": 0.5,
		"lean": 1.6, "foot_lift": 1.2, "sway": 0.6, "elbow": 1.6, "hip_yaw": 0.6,
	},
}


# --- configs ----------------------------------------------------------------

static func walk_config(style: String, overrides: Dictionary = {}) -> Dictionary:
	return _resolve_config({
		"stride": 18.0,
		"knee_bend": 8.0,
		"arm_swing": 20.0,
		"bob": 0.05,
		"sway": 0.02,
		"hip_yaw": 6.0,
		"hip_roll": 2.0,
		"chest_yaw": 5.0,
		"lean": 3.0,
		"foot_lift": 0.05,
		"elbow": 8.0,
		"elbow_swing": 12.0,
		"lag": 0.06,
		"stance": 0.62,
		"crouch": 0.0,
	}, style, overrides, "walk")


static func run_config(style: String, overrides: Dictionary = {}) -> Dictionary:
	return _resolve_config({
		"stride": 25.0,
		"knee_bend": 36.0,
		"arm_swing": 28.0,
		"bob": 0.08,
		"sway": 0.015,
		"hip_yaw": 8.0,
		"hip_roll": 2.5,
		"chest_yaw": 7.0,
		"lean": 15.0,
		"foot_lift": 0.11,
		"elbow": 55.0,
		"elbow_swing": 12.0,
		"lag": 0.08,
		"stance": 0.36,
		"crouch": 0.04,
	}, style, overrides, "run")


static func idle_config(style: String, overrides: Dictionary = {}) -> Dictionary:
	return _resolve_config({
		"amplitude": 1.6,
		"head_amplitude": 0.8,
		"look": 18.0,
		## The *total* torso twist in degrees, shared over the spine chain: the old
		## value was 12 with every bone taking its own multiplier, which summed to
		## roughly twice this number.
		"twist": 22.0,
		"bob": 0.006,
		"sway": 0.018,
		"shift": 1.4,
		"noise": 0.35,
		"lean": 1.5,
		"arm_sway": 1.4,
		"elbow": 14.0,
	}, style, overrides)


static func _resolve_config(base: Dictionary, style: String, overrides: Dictionary, kind: String = "") -> Dictionary:
	var config := base.duplicate(true)
	var profile := "grounded" if style == "grounded" else "responsive"
	if kind == "walk":
		config.merge(_WALK_PROFILES[profile], true)
	elif kind == "run":
		config.merge(_RUN_PROFILES[profile], true)
	var multipliers: Dictionary = _STYLE_MULTIPLIERS.get(style, {}).duplicate(true)
	if kind == "run":
		multipliers.merge(_RUN_STYLE_MULTIPLIERS.get(style, {}), true)
	for key in multipliers:
		var value := float(multipliers[key])
		if key == "crouch_add":
			if config.has("crouch"):
				config["crouch"] = float(config.crouch) + value
			elif config.has("jump_crouch"):
				config["jump_crouch"] = float(config.jump_crouch) + value
		elif config.has(key):
			config[key] = float(config[key]) * value
	for key in overrides:
		config[str(key)] = overrides[key]
	return config


# --- gait (walk / run) ------------------------------------------------------

static func gait_keys(ctx: Dictionary, run: bool) -> Dictionary:
	var config: Dictionary = ctx.config
	var length := maxf(float(ctx.length), 0.001)
	var rate := float(ctx.samples)
	var times := MotionDrivers.sample_times(length, rate)
	var steps := times.size() - 1
	var keys := {}
	var up: Vector3 = ctx.up
	var forward: Vector3 = ctx.forward
	var lateral: Vector3 = ctx.lateral
	var roles: Dictionary = ctx.roles
	var hips := str(ctx.get("hips", ""))
	var hips_origin: Vector3 = ctx.get("hips_origin", Vector3.ZERO)
	var signs := _axis_signs(ctx)
	# The knee-bend crouch is bought with DEGREES, and a degree is not a distance,
	# so the 0.003 m/deg has to come out of the same rig-relative scaling as every
	# other default. It did not: it was added after the handler had already scaled
	# `config.crouch`, so 30 degrees of knee bend was 9 cm on every rig - 18% of a
	# child's leg against 6% of an adult's, a three-fold difference in how bent the
	# knees were for the same request.
	var crouch := float(config.crouch) \
		+ 0.003 * float(config.knee_bend) * float(ctx.get("distance_scale", 1.0))
	var stance := clampf(float(config.stance), 0.2, 0.8)
	# The stride comes from the LONGEST leg, which is the same leg the handler
	# scaled the distances from. It used to come from the left leg alone, so on a
	# rig whose legs differ the stride was built from one and the bob from the
	# other - the short leg then got a stride scaled for the long one.
	var leg_length := measured_leg(ctx)
	var warnings: Array = []
	var clamped := false
	var clamp_shortfall := 0.0
	var stride_degrees := float(config.stride)
	var speed_target := float(ctx.get("speed", 0.0))
	var max_stride := float(ctx.get("max_stride", 55.0))
	if speed_target <= 0.0:
		# No speed was asked for, so the gait is scaled by the FROUDE NUMBER: the
		# dimensionless speed v/sqrt(gL) that gait is compared by across body sizes,
		# because it is the only speed that means the same thing on a short rig and
		# a tall one. Real preferred walking speed scales this way.
		#
		# It used to be derived from the stride ANGLE, which scales speed with leg
		# length and therefore Fr with sqrt(L) - so the same config walked at Fr
		# 0.301, 0.373 and 0.556 on a 0.50 / 0.80 / 1.64 m leg, and the tall rig
		# crossed the ~0.5 walk-to-run transition and was handed a gait that was
		# not a walk. Holding Fr instead gives every rig the same dimensionless
		# walk, which is what "scales with the rig" is supposed to mean.
		#
		# The target is the Froude number the CONFIG implies at the reference leg,
		# so each gait keeps its own character - a run stays a run, a stroll stays a
		# stroll - and only the body-size dependence is removed. Nothing is
		# hard-coded per recipe.
		# A run's implicit ground speed describes the rig and the requested
		# stride style, not the keyframe duration. Shortening a loop should
		# increase cadence and reduce per-step travel at the same speed; deriving
		# speed from the shortened duration instead made the short rig run faster
		# and kept its foot target outside leg reach.
		var reference_duration := 1.0 if run else length
		var froude_target := _reference_froude(float(config.stride), stance, reference_duration)
		speed_target = froude_target * sqrt(9.81 * maxf(_hip_to_ankle(ctx), 0.0001))
	if speed_target > 0.0:
		# Solve the stride from the ground speed:
		# span = 2 * leg_length * sin(stride), speed = span / (stance * duration).
		var sin_needed := (speed_target * stance * length) / maxf(2.0 * leg_length, 0.001)
		if sin_needed > sin(deg_to_rad(max_stride)):
			var max_duration := (2.0 * leg_length * sin(deg_to_rad(max_stride))) / maxf(speed_target * stance, 0.0001)
			warnings.append(
				"speed %s m/s needs a stride past the %d deg cap at duration %ss; use duration <= %ss or lower the speed"
				% [snappedf(speed_target, 0.01), int(max_stride), snappedf(length, 0.01), snappedf(max_duration, 0.01)])
			sin_needed = sin(deg_to_rad(max_stride))
		stride_degrees = rad_to_deg(asin(clampf(sin_needed, 0.0, 1.0)))
	var span := 2.0 * leg_length * sin(deg_to_rad(stride_degrees))
	var lateral_capped := false
	var lateral_speed_cap := INF
	var rooted := bool(ctx.get("root_motion", false))
	if bool(ctx.get("lateral_step", false)):
		# An in-place shuffle still uses the symmetric gait and must fit within
		# the rest ankle spacing. With extracted root travel, lead/trail swings
		# occur in separate windows, so the limit is the rig's lateral reach.
		var foot_width := absf(((ctx.legs.l.ankle as Vector3) -
			(ctx.legs.r.ankle as Vector3)).dot(lateral))
		var safe_span := 0.5 * leg_length * stance if rooted else 0.8 * foot_width
		lateral_speed_cap = safe_span / (stance * length)
		if span > safe_span:
			lateral_capped = true
			warnings.append("lateral stride capped to %.3f m by %s" % [
				snappedf(safe_span, 0.001),
				"leg reach" if rooted else "rest ankle spacing"])
			span = safe_span
			stride_degrees = rad_to_deg(asin(clampf(span / maxf(2.0 * leg_length, 0.001), 0.0, 1.0)))
	var ground_speed := span / (stance * length)
	var rooted_strafe := bool(ctx.get("lateral_step", false)) and rooted
	var travel_axis: Vector3 = ctx.get("step_axis", forward)
	var lag := float(config.lag)
	var hip_yaw := float(config.hip_yaw) * float(signs.yaw)
	var hip_roll := float(config.hip_roll) * float(signs.roll)
	# The torso counter-rotation: the hips lead, the spine and chest follow the
	# other way, the head stabilises. Expressed as chain weights so it holds on
	# any spine, and `chest_yaw` (previously shadowed by a local of the same name
	# and therefore dead) now scales the counter for rigs that want more or less.
	var counter := absf(float(config.get("chest_yaw", -0.8))) * 0.8
	var lean := float(config.lean) * float(signs.lean)

	var pelvis_rotation := [
		_channel(up, hip_yaw, 1.0, 0.0, 0.0, "cosine"),
		_channel(forward, hip_roll, 1.0, 0.0, 0.0, "sine"),
		_channel(lateral, 0.0, 1.0, 0.0, 0.0, "sine", 0.5 * lean),
	]
	# hips lead forward, everything above counter-rotates: [hips, spine, chest,
	# head] as [-counter on the torso, half back on the head to stabilise].
	var torso_weights := [0.0, -counter, -counter, counter * 0.5]
	if config.has("torso_twist"):
		torso_weights = [0.0, -1.0, -1.0, 0.5]
	var torso_amount := float(config.torso_twist) * float(signs.yaw) if config.has("torso_twist") else hip_yaw
	var torso_channels := _twist_channels(
		ctx, config, torso_amount, up, torso_weights, _spread(config), lag)
	var bob_channel := _channel(up, -0.5 * float(config.bob), 2.0, 0.0, 0.0, "cosine")
	# `lateral` points from the right hip toward the left. At t=0.25 the
	# left foot is in stance and the right foot is swinging, so positive sine
	# shifts the pelvis onto the supporting leg instead of away from it.
	var sway_channel := _channel(lateral, float(config.sway), 1.0, 0.0, 0.0, "sine")

	var chain := _twist_chain(ctx, roles)
	var chest := str(roles.get("chest", ""))
	var head := str(roles.get("head", ""))
	# The lean is split across the torso, with the head counter-leaning. `chain`
	# has to exist first, so the shares are computed here rather than next to the
	# other channels.
	var lean_shares := _lean_shares(chain, head, -0.35)
	var pelvis_offsets: Array = []
	var reach_drop := 0.0
	if not run and not bool(ctx.get("lateral_step", false)):
		var reach_plan := _walk_pelvis_plan(ctx, times, pelvis_rotation,
			bob_channel, sway_channel, crouch, span, stance, length, rooted)
		if not bool(reach_plan.feasible):
			var low := 0.0
			var high := span
			for _iteration in 12:
				var candidate := (low + high) * 0.5
				var attempt := _walk_pelvis_plan(ctx, times, pelvis_rotation,
					bob_channel, sway_channel, crouch, candidate, stance, length, rooted)
				if bool(attempt.feasible):
					low = candidate
					reach_plan = attempt
				else:
					high = candidate
			if not bool(reach_plan.feasible):
				return {"keys": {}, "meta": {"reach_error":
					"Rest pose or pelvis bob/foot targets cannot be reached even at zero stride; inspect leg roles and rest pose or reduce bob"}}
			var feasible_speed := low / (stance * length)
			if float(ctx.get("speed", 0.0)) > 0.0:
				return {"keys": {}, "meta": {"reach_error":
					"Requested walk speed %.3f m/s exceeds this rig's reachable %.3f m/s at duration %.3f s; lower speed or shorten duration" % [
						float(ctx.speed), feasible_speed, length],
					"max_feasible_speed": feasible_speed}}
			warnings.append("default walk stride reduced to %.3f m/s to keep both foot targets reachable" % feasible_speed)
			span = low
			ground_speed = feasible_speed
			stride_degrees = rad_to_deg(asin(clampf(span / maxf(2.0 * leg_length, 0.001), 0.0, 1.0)))
		pelvis_offsets = reach_plan.offsets
		reach_drop = float(reach_plan.max_drop)
	# Re-evaluate speed-related metadata after any implicit reach adjustment.
	var froude := ground_speed / sqrt(9.81 * maxf(_hip_to_ankle(ctx), 0.0001))
	if not run and not bool(ctx.get("lateral_step", false)) and froude >= 0.5:
		warnings.append(
			"stride %d deg on a %.2f m leg implies %.2f m/s, Froude %.2f - at or past the ~0.5 walk-to-run transition, so this is not a walk; shorten duration or the stride to stay under it"
			% [int(round(stride_degrees)), _hip_to_ankle(ctx), snappedf(ground_speed, 0.01),
				snappedf(froude, 0.01)])
	var travel := ground_speed * length if rooted else 0.0
	var lift_base := float(config.get("foot_lift", 0.05))
	if run and not bool(ctx.get("foot_lift_explicit", false)):
		# Linear distance scaling leaves a short rig's implicit run barely
		# airborne at high cadence. Keep a minimum swing arc that scales with
		# sqrt(leg length), like the rig-relative Froude speed. At the reference
		# leg the configured 11 cm remains above this 10.5 cm floor; the floor
		# only raises smaller rigs. An explicit foot_lift remains exact.
		lift_base = maxf(lift_base, 0.105 * sqrt(maxf(leg_length, 0.001) / REFERENCE_LEG))
	var lift := lift_base * clampf(ground_speed, 0.6, 1.8)
	ctx["foot_lift_scaled"] = lift

	for index in times.size():
		var t := float(index) / float(steps)
		var time := float(times[index])
		var pelvis_world := MotionDrivers.compose_rotation(pelvis_rotation, t)
		var hips_animated := Basis(pelvis_world) * _rest_basis(ctx, hips)
		var offset: Vector3 = pelvis_offsets[index] if not pelvis_offsets.is_empty() else (
			up * (MotionDrivers.channel_value(bob_channel, t) - crouch)
			+ (travel_axis * _strafe_support_shift(t, float(config.sway))
				if rooted_strafe else lateral * MotionDrivers.channel_value(sway_channel, t))
		)
		if not hips.is_empty():
			_append_rotation(keys, hips, time, MotionDrivers.rotation_delta(_rest_basis(ctx, hips), pelvis_world))
			_append_hips_position(ctx, keys, hips, time, offset)
		var left := _solve_leg(ctx, keys, "l", t, time, offset, pelvis_world, hips_animated, hips_origin, stance, span, ground_speed, rooted, length)
		var right := _solve_leg(ctx, keys, "r", t, time, offset, pelvis_world, hips_animated, hips_origin, stance, span, ground_speed, rooted, length)
		# A target the leg cannot reach is shortened to what it CAN reach, and the
		# worst shortfall of the clip is reported rather than hidden.
		for solved in [left, right]:
			if bool((solved as Dictionary).get("clamped", false)):
				clamped = true
				clamp_shortfall = maxf(clamp_shortfall, float((solved as Dictionary).get("shortfall", 0.0)))
		# The hips carry no twist share (the pelvis channels already lead), so
		# every chain bone above them is keyed from the distributed torso channels.
		for slot in chain:
			var bone := str(slot)
			if bone == hips or bone.is_empty():
				continue
			# The lean is this bone's share of the total, so the fold a viewer sees
			# is the requested lean whatever the spine length.
			var own: Array = [_channel(lateral, 0.0, 1.0, 0.0, 0.0, "sine",
				lean * float(lean_shares.get(bone, 0.0)))]
			var world := _compose_with_twist(own, torso_channels, bone, t)
			_append_rotation(keys, bone, time, MotionDrivers.rotation_delta(_rest_basis(ctx, bone), world))
		if ctx.has("upper_body_layout"):
			_articulate_upper_body(ctx, keys, time, t)
		_solve_arms(ctx, keys, time, t)
	if not run and not bool(ctx.get("lateral_step", false)) \
			and clamp_shortfall > 0.01 * leg_length:
		return {"keys": {}, "meta": {"reach_error":
			"Walk leg target shortened by %.3f m after reach planning; reduce stride/speed or inspect rig roles" % clamp_shortfall}}
	if run and clamp_shortfall > 0.01 * leg_length:
		return {"keys": {}, "meta": {"reach_error":
			"Run leg target exceeds this rig's reach by %.3f m (%.1f%% of leg length) at %.3f m/s; lower speed, shorten duration with explicit speed, or adjust crouch/foot lift" % [
				clamp_shortfall, 100.0 * clamp_shortfall / maxf(leg_length, 0.001), ground_speed]}}
	if clamp_shortfall > 0.01 * leg_length:
		warnings.append("leg target shortened by %.3f m (%.1f%% of leg length); reduce stride/speed or lower the pelvis" % [
			clamp_shortfall, 100.0 * clamp_shortfall / maxf(leg_length, 0.001)])

	# Extraction removes the designated track from the pose. It must never be
	# the hips track: removing pelvis bob/sway invalidates the two-bone solve.
	# The handler writes this reserved channel onto the character root instead.
	if rooted and not is_zero_approx(travel):
		var root_position: Array = []
		for index in times.size():
			var progress := _strafe_root_progress(float(index) / float(steps)) \
				if rooted_strafe else float(index) / float(steps)
			root_position.append({"time": float(times[index]),
				"delta": travel_axis * (travel * progress)})
		keys["__root_motion__"] = {"position": root_position, "loop_close": false}
	return {
		"keys": keys,
		"markers": _strafe_markers(length, str(ctx.get("lead_side", "l")))
			if rooted_strafe else _gait_markers(length, stance),
		"meta": {
			"speed": ground_speed,
			"stride_used": stride_degrees,
			"cadence": 120.0 / length,
			"clamped": clamped,
			"clamp_shortfall_m": clamp_shortfall,
			"foot_lift_base_used_m": lift_base,
			"reach_pelvis_drop_m": reach_drop,
			"lateral_capped": lateral_capped,
			"lateral_speed_cap": lateral_speed_cap if bool(ctx.get("lateral_step", false)) else 0.0,
			"warnings": warnings,
		},
	}


## Plan a periodic pelvis path before solving either leg. For every authored
## foot target, find the least extra downward translation that keeps the hip
## within the measured two-bone reach. A circular Lipschitz envelope spreads
## each required dip into neighbouring samples without ever lifting a sample
## above its reach limit. The shared path is then used by the pelvis track and
## both IK solves, so the solver cannot silently move only one foot target.
static func _walk_pelvis_plan(
	ctx: Dictionary, times: Array, pelvis_rotation: Array, bob_channel: Dictionary,
	sway_channel: Dictionary, crouch: float, span: float, stance: float,
	length: float, rooted: bool,
) -> Dictionary:
	var steps := times.size() - 1
	if steps < 2:
		return {"feasible": false}
	var up: Vector3 = ctx.up
	var lateral: Vector3 = ctx.lateral
	var hips_origin: Vector3 = ctx.get("hips_origin", Vector3.ZERO)
	var step_axis: Vector3 = ctx.get("step_axis", ctx.forward)
	var speed := span / (stance * length)
	var lift := float((ctx.config as Dictionary).get("foot_lift", 0.05)) * clampf(speed, 0.6, 1.8)
	var leg_length := measured_leg(ctx)
	var max_extra_drop := 0.16 * leg_length
	var base_offsets: Array = []
	var required: Array = []
	for index in steps:
		var t := float(index) / float(steps)
		var world := MotionDrivers.compose_rotation(pelvis_rotation, t)
		var base: Vector3 = up * (MotionDrivers.channel_value(bob_channel, t) - crouch) \
			+ lateral * MotionDrivers.channel_value(sway_channel, t)
		base_offsets.append(base)
		var needed := 0.0
		for side in ["l", "r"]:
			var leg: Dictionary = ctx.legs[side]
			var side_offset := 0.0 if side == "l" else 0.5
			var phase := fposmod(t + side_offset, 1.0)
			var foot := _foot_trajectory(phase, stance, span, speed, length, rooted, side_offset)
			var target: Vector3 = leg.ankle + step_axis * float(foot.forward) \
				+ up * (lift * float(foot.height))
			var hip: Vector3 = hips_origin + base + Basis(world) * (leg.hip - hips_origin)
			var difference := hip - target
			var vertical := difference.dot(up)
			var planar := difference - up * vertical
			var reach := float(leg.upper) + float(leg.lower) - 0.005 * leg_length
			var vertical_room_sq := reach * reach - planar.length_squared()
			if vertical_room_sq <= 0.0:
				return {"feasible": false}
			var vertical_room := sqrt(vertical_room_sq)
			if vertical < -vertical_room:
				return {"feasible": false}
			needed = maxf(needed, vertical - vertical_room)
		if needed > max_extra_drop:
			return {"feasible": false}
		required.append(maxf(needed, 0.0))
	var offsets: Array = []
	var max_drop := 0.0
	var sample_dt := length / float(steps)
	var drop_rate := maxf(0.5 * leg_length, 0.001)
	var radius := mini(steps / 2, ceili(max_extra_drop / (drop_rate * sample_dt)))
	for index in steps:
		var drop: float = required[index]
		for distance in range(1, radius + 1):
			var taper := drop_rate * sample_dt * float(distance)
			drop = maxf(drop, float(required[posmod(index - distance, steps)]) - taper)
			drop = maxf(drop, float(required[posmod(index + distance, steps)]) - taper)
		max_drop = maxf(max_drop, drop)
		offsets.append((base_offsets[index] as Vector3) - up * drop)
	offsets.append(offsets[0])
	return {"feasible": true, "offsets": offsets, "max_drop": max_drop}


static func _solve_leg(
	ctx: Dictionary, keys: Dictionary, side: String, t: float, time: float,
	offset: Vector3, pelvis_world: Quaternion, hips_animated: Basis, hips_origin: Vector3,
	stance: float, span: float, ground_speed: float, rooted: bool, length: float,
) -> Dictionary:
	var leg: Dictionary = ctx.legs[side]
	var up: Vector3 = ctx.up
	var step_axis: Vector3 = ctx.get("step_axis", ctx.forward)
	var knee_hint: Vector3 = ctx.get("knee_hint", ctx.forward)
	var side_offset := 0.0 if side == "l" else 0.5
	var p := fposmod(t + side_offset, 1.0)
	var rooted_strafe := bool(ctx.get("lateral_step", false)) and rooted
	var foot := _strafe_foot_trajectory(t, side == str(ctx.get("lead_side", "l")),
		ground_speed * length) if rooted_strafe else _foot_trajectory(
		p, stance, span, ground_speed, length, rooted, side_offset)
	var lift := float(ctx.get("foot_lift_scaled", (ctx.config as Dictionary).get("foot_lift", 0.05)))
	var ankle_target: Vector3 = (
		leg.ankle + step_axis * float(foot.forward)
		+ up * (lift * float(foot.height))
	)
	# Solve in character-local space. The root track is extracted separately,
	# then applied to the character by playback; it must not alter pelvis pose.
	# A target outside the leg span is reported through clamp_shortfall_m.
	var hip_pos: Vector3 = hips_origin + offset + Basis(pelvis_world) * (leg.hip - hips_origin)
	var solved := MotionDrivers.solve_leg(hip_pos, ankle_target, float(leg.upper),
		float(leg.lower), _rest_bend(ctx, leg, knee_hint))
	var knee: Vector3 = solved.knee
	# The shin aims at the REACHABLE ankle, so a target the leg cannot reach
	# shortens the step honestly instead of leaving the foot in the air.
	var effective: Vector3 = solved.effective_ankle
	var hips_rest := _rest_basis(ctx, ctx.get("hips", ""))
	var thigh_rest := _rest_basis(ctx, leg.thigh)
	var shin_rest := _rest_basis(ctx, leg.shin)
	var thigh_solve := MotionDrivers.aim_delta(hips_animated, hips_rest, thigh_rest,
		(knee - hip_pos).normalized(), (leg.knee as Vector3) - (leg.hip as Vector3))
	var shin_solve := MotionDrivers.aim_delta(thigh_solve.global, thigh_rest, shin_rest,
		(effective - knee).normalized(), (leg.ankle as Vector3) - (leg.knee as Vector3))
	_append_rotation(keys, leg.thigh, time, thigh_solve.delta)
	_append_rotation(keys, leg.shin, time, shin_solve.delta)
	var foot_bone := str(leg.get("foot", ""))
	if foot_bone.is_empty():
		return solved
	# Foot roll: keep the sole flat while planted, pitch it through heel strike
	# and toe-off, and hold the toe on the ground while the foot rolls over it.
	var foot_rest := _rest_basis(ctx, foot_bone)
	var pitch_axis := _foot_pitch_axis(ctx, leg, knee_hint)
	var roll := float((ctx.config as Dictionary).get("toe_roll", 1.0))
	var pitch := 0.0 if rooted_strafe else _foot_pitch_curve(p, stance, 8.0 * roll, 18.0 * roll)
	var foot_target := Basis(Quaternion(pitch_axis, deg_to_rad(pitch))) * foot_rest
	var delta := MotionDrivers.hold_global_delta(shin_solve.global, shin_rest, foot_rest, foot_target)
	var weight := clampf(1.0 - 2.0 * float(foot.height), 0.0, 1.0) \
		if rooted_strafe else _foot_plant_weight(p, stance)
	_append_rotation(keys, foot_bone, time, Quaternion.IDENTITY.slerp(delta, weight))
	var toe_bone := str(leg.get("toe", ""))
	if toe_bone.is_empty():
		return solved
	var toe_rest := _rest_basis(ctx, toe_bone)
	var toe_hold := MotionDrivers.hold_global_delta(foot_target, foot_rest, toe_rest, toe_rest)
	var toe_weight := weight if pitch < -1.0 and not rooted_strafe else 0.0
	_append_rotation(keys, toe_bone, time, Quaternion.IDENTITY.slerp(toe_hold, toe_weight))
	return solved


static func _solve_arms(ctx: Dictionary, keys: Dictionary, time: float, t: float) -> void:
	var config: Dictionary = ctx.config
	var arm_swing := float(config.arm_swing)
	var elbow := float(config.elbow)
	var elbow_swing := float(config.get("elbow_swing", 0.6 * arm_swing))
	var lag := float(config.lag)
	var phase := cos(TAU * (t - lag))
	var elbow_phase := cos(TAU * (t - lag - float(config.get("elbow_lag", 0.0))))
	var wrist_phase := sin(TAU * (t - lag - float(config.get("wrist_lag", 0.0))))
	var coordinated := bool(ctx.get("arm_hand_follow_through", ctx.get("measured_arms", false)))
	for side in ["l", "r"]:
		var sign := -1.0 if side == "l" else 1.0
		# `_solve_arm_chain`'s hinge is positive-forward by construction, so the
		# side sign alone phases the swing: left arm back at t=0, forward at t=0.5
		# (same side leg forward). The elbow straightens at the back and bends as
		# the arm comes forward.
		var swing_degrees := sign * arm_swing * phase
		var forward_weight := (1.0 + sign * elbow_phase) * 0.5
		var bend_degrees := elbow + elbow_swing * forward_weight
		var variation := float(config.get("arm_variation", 0.0))
		var seed_value := int(config.get("variation_seed", 0)) + (101 if side == "r" else 0)
		if variation > 0.0:
			bend_degrees += 0.6 * variation * MotionDrivers.periodic_noise(t, seed_value, 2)
		# Bounded seeded curves are baked into the clip, not sampled every frame.
		var wrist := sign * float(config.get("wrist_swing", 0.0)) * wrist_phase
		var twist := sign * float(config.get("forearm_twist", 0.0)) * sin(TAU * (t - lag - 0.04))
		var sway := sign * float(config.get("wrist_sway", 0.0)) * cos(TAU * (t - lag - float(config.get("wrist_lag", 0.0))))
		if variation > 0.0:
			wrist += variation * MotionDrivers.periodic_noise(t, seed_value + 23, 2)
			twist += 0.6 * variation * MotionDrivers.periodic_noise(t, seed_value + 47, 2)
			sway += 0.4 * variation * MotionDrivers.periodic_noise(t, seed_value + 71, 2)
		_solve_arm_chain(ctx, keys, side, time, swing_degrees, bend_degrees, "", wrist, coordinated, twist, sway)
		if ctx.has("hand_layout"):
			_relax_fingers(ctx, keys, side, time, t)


## One arm from the shoulder down: lower it by the rig's `arm_down`, swing it
## about a sagittal hinge (so the hand travels forward/back, never sideways),
## then flex the elbow about that same world hinge using the animated shoulder
## basis. Conjugating the bend by the rest frame - as this used to - turned the
## hinge with the lowered arm and curled the forearm across the body.
static func _solve_arm_chain(
	ctx: Dictionary, keys: Dictionary, side: String, time: float,
	swing_degrees: float, bend_degrees: float, transition: String = "",
	wrist_degrees: float = 0.0, coordinate_parents: bool = false,
	forearm_twist: float = 0.0, wrist_sway: float = 0.0,
) -> void:
	var roles: Dictionary = ctx.roles
	var forward: Vector3 = ctx.forward
	var arm := str(roles.get("arm_" + side, ""))
	if arm.is_empty():
		return
	var g_arm := _rest_basis(ctx, arm)
	var down_delta: Quaternion = (ctx.get("arm_down", {}) as Dictionary).get(side, Quaternion.IDENTITY)
	var down_world := (g_arm * Basis(down_delta) * g_arm.inverse()).get_rotation_quaternion()
	var rest_direction := g_arm * Vector3.UP
	if bool(ctx.get("measured_arms", false)):
		rest_direction = (ctx.get("arm_directions", {}) as Dictionary).get(side, rest_direction)
	var hang_dir := (Basis(down_world) * rest_direction).normalized()
	var hinge := hang_dir.cross(forward)
	if hinge.length_squared() < 0.000001:
		hinge = ctx.lateral
	hinge = hinge.normalized()
	if hinge.cross(hang_dir).dot(forward) < 0.0:
		hinge = -hinge
	var twist := 0.0
	var config: Dictionary = ctx.get("config", {})
	if config.has("arm_twist"):
		twist = float(config.arm_twist)
	var arm_world := (
		Quaternion(hinge, deg_to_rad(swing_degrees))
		* Quaternion(hang_dir, deg_to_rad(twist))
		* down_world
	)
	_append_rotation(keys, arm, time, MotionDrivers.rotation_delta(g_arm, arm_world), transition)
	# A small clavicle swing makes the shoulder follow the arm instead of the
	# whole swing happening at the socket.
	var shoulder := str(roles.get("shoulder_" + side, ""))
	if not shoulder.is_empty() and not is_zero_approx(swing_degrees):
		_append_rotation(keys, shoulder, time, MotionDrivers.rotation_delta(
			_rest_basis(ctx, shoulder), Quaternion(hinge, deg_to_rad(swing_degrees * 0.25))), transition)
	var forearm := str(roles.get("forearm_" + side, ""))
	if forearm.is_empty():
		return
	if not rest_ancestor(ctx, forearm, arm):
		return # An unconnected optional joint remains at rest.
	var arm_animated := Basis(arm_world) * g_arm
	if coordinate_parents:
		# Include the incoming torso and clavicle animation. Flex about the hinge
		# carried by that parent frame, rather than an assumed unanimated parent.
		var parent := str((ctx.rest[arm] as Dictionary).get("parent", ""))
		var parent_delta := _animated_basis(ctx, keys, parent, time) * _rest_basis(ctx, parent).inverse()
		hinge = (parent_delta * hinge).normalized()
		arm_animated = _animated_basis(ctx, keys, arm, time)
	_append_rotation(keys, forearm, time, MotionDrivers.world_delta(
		arm_animated, g_arm, _rest_basis(ctx, forearm), Quaternion(hinge, deg_to_rad(bend_degrees))), transition)
	var hand := str(roles.get("hand_" + side, ""))
	if coordinate_parents and not hand.is_empty():
		var fore_basis := _animated_basis(ctx, keys, forearm, time)
		var direction: Vector3 = (ctx.rest[hand].origin as Vector3) - (ctx.rest[forearm].origin as Vector3)
		var fore_axis := (fore_basis * _rest_basis(ctx, forearm).inverse() * direction).normalized()
		var axial := Quaternion(fore_axis, deg_to_rad(forearm_twist))
		if not is_zero_approx(forearm_twist):
			_layer_rotation(ctx, keys, forearm, time, axial)
			hinge = Basis(axial) * hinge
		var sway_axis := fore_axis.cross(hinge).normalized()
		_append_rotation(keys, hand, time, MotionDrivers.world_delta(
			_animated_basis(ctx, keys, forearm, time), _rest_basis(ctx, forearm),
			_rest_basis(ctx, hand), Quaternion(hinge, deg_to_rad(wrist_degrees)) * Quaternion(sway_axis, deg_to_rad(wrist_sway))), transition)


static func rest_ancestor(ctx: Dictionary, bone: String, ancestor: String) -> bool:
	var seen: Array = []
	while not bone.is_empty() and ctx.rest.has(bone) and not seen.has(bone):
		if bone == ancestor: return true
		seen.append(bone)
		bone = str(ctx.rest[bone].get("parent", ""))
	return false


## Recognized chains plus a non-coplanar thumb base disambiguate palm direction.
## Never assume a finger bone's local Y, or infer curl sign from left/right.
static func hand_layout(skeleton: Skeleton3D, ctx: Dictionary) -> Dictionary:
	var out := {}
	var extra_roles := {}
	for side in ["l", "r"]:
		var hand := str(ctx.roles["hand_" + side])
		var hand_index := skeleton.find_bone(hand)
		var roots := {}
		for kind in ["index", "middle", "ring", "pinky", "thumb"]:
			var candidates: Array = []
			for child in skeleton.get_bone_children(hand_index):
				if skeleton.get_bone_name(child).to_lower().contains(kind): candidates.append(child)
			if candidates.size() != 1:
				return {"error": "hand_relax unavailable: needs one recognized %s finger root on hand %s" % [kind, side]}
			roots[kind] = candidates[0]
		var origin := skeleton.get_bone_global_rest(hand_index).origin
		var direction := skeleton.get_bone_global_rest(roots.middle).origin - origin
		var across := skeleton.get_bone_global_rest(roots.index).origin - skeleton.get_bone_global_rest(roots.pinky).origin
		var normal := direction.cross(across)
		if normal.length() < 0.01 * direction.length() * across.length():
			return {"error": "hand_relax unavailable: degenerate palm geometry on hand " + side}
		normal = normal.normalized()
		var thumb := skeleton.get_bone_global_rest(roots.thumb).origin - origin
		var bias := thumb.dot(normal)
		if absf(bias) < 0.02 * direction.length():
			return {"error": "hand_relax unavailable: ambiguous palm side on hand " + side}
		normal *= signf(bias)
		var fingers := {}
		for kind in ["index", "middle", "ring", "pinky"]:
			var joints: Array = []
			var index: int = roots[kind]
			while index >= 0:
				var children := skeleton.get_bone_children(index)
				if children.is_empty(): break # terminal/tip has no measured distal segment
				if children.size() != 1 or not skeleton.get_bone_name(children[0]).to_lower().contains(kind):
					return {"error": "hand_relax unavailable: branching/unrecognized finger chain " + kind}
				var child: int = children[0]
				var segment := skeleton.get_bone_global_rest(child).origin - skeleton.get_bone_global_rest(index).origin
				if segment.length() < 0.0001 or segment.normalized().cross(normal).length() < 0.1:
					return {"error": "hand_relax unavailable: unusable finger segment " + kind}
				var name := skeleton.get_bone_name(index)
				joints.append({"bone": name, "direction": segment})
				extra_roles[name] = name
				index = child
			if joints.size() < 2:
				return {"error": "hand_relax unavailable: needs at least two measured joints per finger"}
			fingers[kind] = joints
		out[side] = {"hand": hand, "normal": normal, "fingers": fingers}
	ctx.rest.merge(_rest_map_of(skeleton, extra_roles, []))
	return out


static func _relax_fingers(ctx: Dictionary, keys: Dictionary, side: String, time: float, t: float) -> void:
	var layout: Dictionary = ctx.hand_layout[side]
	var hand := str(layout.hand)
	var hand_delta := _animated_basis(ctx, keys, hand, time) * _rest_basis(ctx, hand).inverse()
	var normal: Vector3 = hand_delta * (layout.normal as Vector3)
	var config: Dictionary = ctx.config
	var seed_value := int(config.get("variation_seed", 0)) + (101 if side == "r" else 0)
	var strengths := {"index": 0.75, "middle": 0.9, "ring": 1.0, "pinky": 1.1}
	for kind: String in layout.fingers:
		var joints: Array = layout.fingers[kind]
		var fraction := 0.93 + 0.07 * sin(TAU * (t - float(config.get("lag", 0.0)) - 0.1))
		var amount := float(config.hand_relax) * float(strengths[kind]) * fraction
		if float(config.get("arm_variation", 0.0)) > 0.0:
			amount += 0.35 * float(config.arm_variation) * MotionDrivers.periodic_noise(t, seed_value + 97, 2)
		amount = maxf(0.0, amount)
		for joint: Dictionary in joints:
			var bone := str(joint.bone)
			var parent := str(ctx.rest[bone].parent)
			var incoming := _animated_basis(ctx, keys, parent, time) * _rest_basis(ctx, parent).inverse()
			var direction: Vector3 = incoming * (joint.direction as Vector3)
			var hinge := direction.normalized().cross(normal.normalized()).normalized()
			_layer_rotation(ctx, keys, bone, time, Quaternion(hinge, deg_to_rad(amount / joints.size())))


## Current sampled parent basis, including non-role intermediary bones at rest.
## This evaluates the current generation sample, not engine playback or a bake.
static func _animated_basis(ctx: Dictionary, keys: Dictionary, bone: String, time: float) -> Basis:
	if bone.is_empty() or not ctx.rest.has(bone): return Basis.IDENTITY
	var entry: Dictionary = ctx.rest[bone]
	var parent := str(entry.get("parent", ""))
	var delta := Quaternion.IDENTITY
	var rotations: Array = (keys.get(bone, {}) as Dictionary).get("rotation", [])
	if not rotations.is_empty() and is_equal_approx(float(rotations[-1].time), time):
		delta = rotations[-1].delta
	return _animated_basis(ctx, keys, parent, time) * _rest_basis(ctx, parent).inverse() * _rest_basis(ctx, bone) * Basis(delta)


## Lower the measured arm-to-elbow direction toward rig down. Imported bones
## need not point along local Y, and the skeleton need not be world-Y-up.
## Automatic lowering leaves twelve degrees of outward clearance in a T pose.
static func arm_lower_delta(rest_basis: Basis, rest_direction: Vector3, up: Vector3, degrees: float = -1.0) -> Quaternion:
	if rest_direction.length_squared() < 0.000001: return Quaternion.IDENTITY
	var direction := rest_direction.normalized()
	var target := -up.normalized()
	var full := Quaternion(direction, target)
	var limit := rad_to_deg(direction.angle_to(target))
	var amount := maxf(0.0, limit - 12.0) if degrees < 0.0 else minf(degrees, limit)
	if limit < 0.000001: return Quaternion.IDENTITY
	return MotionDrivers.rotation_delta(rest_basis, Quaternion.IDENTITY.slerp(full, amount / limit))


## Relative forward/height motion of one ankle over a cycle. `p` is the foot's
## local phase (0 = contact) and `phase_offset` which half-cycle the foot leads
## by (0 left, 0.5 right). In-place cycles slide the planted foot backwards in
## clip space, which is what cancels the body's motion when the game moves the
## character. That is the CORRECT authoring for root motion too, and it used not
## to be.
##
## It used to be the other way round: with root motion the stance target was held
## Rooted clips store T(t) on a character-owned track for extraction. A local
## foot target is its desired world target minus T(t); that keeps stance fixed
## even while the character travels. During swing, the world target remains
## fixed until the foot lifts, then reaches its next contact before lowering.
## A rooted side step moves the leading foot outward before the trailing foot
## recovers. World foot displacement and extracted root displacement are
## authored separately; their difference is the bone solver's local target.
static func _strafe_root_progress(t: float) -> float:
	return MotionDrivers.smoothstep(clampf((t - 0.12) / 0.76, 0.0, 1.0))


static func _strafe_foot_trajectory(t: float, leading: bool, travel: float) -> Dictionary:
	var start := 0.06 if leading else 0.55
	var end := 0.45 if leading else 0.94
	var swing := clampf((t - start) / (end - start), 0.0, 1.0)
	var travel_phase := clampf((swing - 0.12) / 0.76, 0.0, 1.0)
	var world_progress := MotionDrivers.smoothstep(travel_phase)
	var height := 0.0
	if t > start and t < end:
		const APEX := 0.45
		height = MotionDrivers.smoothstep(swing / APEX) if swing < APEX else \
			1.0 - MotionDrivers.smoothstep((swing - APEX) / (1.0 - APEX))
	return {"forward": travel * (world_progress - _strafe_root_progress(t)),
		"height": height}


## Shift over the trailing support leg before lead toe-off, then over the
## newly planted leading leg before the trailing recovery swing.
static func _strafe_support_shift(t: float, sway: float) -> float:
	if t < 0.16:
		return -sway * MotionDrivers.smoothstep(t / 0.16)
	if t < 0.46:
		return -sway
	if t < 0.68:
		return lerpf(-sway, sway, MotionDrivers.smoothstep((t - 0.46) / 0.22))
	if t < 0.84:
		return sway
	return sway * (1.0 - MotionDrivers.smoothstep(clampf((t - 0.84) / 0.16, 0.0, 1.0)))


static func _foot_trajectory(p: float, stance: float, span: float, ground_speed: float, length: float, rooted: bool, phase_offset: float = 0.0) -> Dictionary:
	var local_phase := fposmod(p, 1.0)
	var travel := ground_speed * length
	if local_phase < stance:
		if rooted:
			return {"forward": 0.5 * span - travel * local_phase,
				"height": 0.0}
		return {"forward": span * (0.5 - local_phase / stance), "height": 0.0}
	var swing := (local_phase - stance) / maxf(1.0 - stance, 0.001)
	var from := -0.5 * span
	var to := 0.5 * span
	# The lift is a hump, not a plateau. It used to be 1.0 for the WHOLE swing, so
	# the foot teleported up at toe-off and dropped back at heel strike on a flat
	# step. This is exactly 0 at both contacts (where the foot is on the ground)
	# and peaks just before mid-swing, with zero slope at the contacts and at the
	# apex so neither end of the arc pops.
	const LIFT_APEX := 0.45
	var height := 0.0
	if swing < LIFT_APEX:
		height = MotionDrivers.smoothstep(swing / LIFT_APEX)
	else:
		height = 1.0 - MotionDrivers.smoothstep((swing - LIFT_APEX) / (1.0 - LIFT_APEX))
	# Lift before translating and finish travel before lowering. Otherwise the
	# foot moves several centimetres while it is still within the contact band
	# at toe-off and heel strike, even with a mathematically flat stance phase.
	var travel_phase := clampf((swing - 0.12) / 0.76, 0.0, 1.0)
	if rooted:
		return {"forward": 0.5 * span - travel * local_phase
			+ travel * MotionDrivers.smoothstep(travel_phase), "height": height}
	return {"forward": lerpf(from, to, MotionDrivers.smoothstep(travel_phase)), "height": height}


## Builds the context a recipe needs from a skeleton and a role map, with no
## editor, no scene and no AnimationPlayer - every value derived from the rig's
## own rest geometry. The motion handler assembles the same context the same way
## (motion.gd `_build_context`), so this is not a second source of truth: it is
## the same three measurements with the editor plumbing left out.
##
## `scale_distances` applies the same rig-relative rewrite to the distance
## defaults that the handler does, so a caller that wants the handler's exact
## numbers gets them; tier-1 leaves it off on purpose to build a context out of
## raw rest geometry.
## `chain` is the spine chain the recipe will walk. The handler passes the one it
## already resolved from params (which honours an explicit `spine_chain`), because
## the rest map has to cover the chain in use - resolving it a second time here
## gave a different answer and moved a neck bone's rest pose. Callers with no
## params of their own (tier-1) leave it empty and it is resolved from the
## skeleton.
static func context_from_skeleton(skeleton: Skeleton3D, roles: Dictionary,
		length: float, samples: float, scale_distances: bool = false,
		reference_leg: float = 0.85, chain: Array = []) -> Dictionary:
	if chain.is_empty():
		chain = RigAnalysis.spine_chain(_parent_of(skeleton), roles)
	var rest := _rest_map_of(skeleton, roles, chain)
	var legs := leg_map_from_rest(roles, rest)
	if legs.size() < 2 or not rest.has(str(roles.get("hips", ""))):
		return {"error": "the role map does not resolve both legs and a hips bone"}
	var frame := RigAnalysis.rig_frame(skeleton, roles)
	var config: Dictionary = {}
	var ctx := {
		"length": length,
		"samples": samples,
		"roles": roles,
		"spine_chain": chain,
		"forward": frame.forward,
		"up": frame.up,
		"lateral": frame.lateral,
		"hips": str(roles.get("hips", "")),
		"hips_parent_basis": _hips_parent_basis(skeleton, str(roles.get("hips", ""))),
		"hips_origin": (rest[str(roles.get("hips", ""))] as Dictionary).origin,
		"legs": legs,
		"rest": rest,
		"arm_directions": _arm_directions(skeleton, roles),
		"arm_down": {},
		"root_motion": false,
	}
	if scale_distances:
		scale_distances_to_rig(config, ctx, [], reference_leg)
	return ctx


## The reference leg length the recipe defaults are written against: a
## human_dummy-scale character, roughly 0.85 m from hip to ankle. Defaults are
## expressed as a fraction of this and multiplied by the rig's OWN measured leg, so
## a child and a giant get a proportional bob, foot lift, crouch and jump instead
## of the same five centimetres.
const REFERENCE_LEG := 0.85
## The defaults that are distances rather than angles or ratios, and so are the
## ones that have to scale with the rig.
const DISTANCE_DEFAULTS := ["bob", "sway", "foot_lift", "jump_crouch", "jump_height", "crouch"]


## Re-expresses the distance defaults as fractions of the rig's measured leg, in
## place, and records the factor as `ctx.distance_scale` for the recipes that need
## it directly (the turn's bob lives in a phase table, and the knee-bend crouch is
## bought with degrees).
##
## `explicit` lists the keys the caller already set, so a value a user asked for
## keeps its meaning in metres while untouched defaults move. It is a list rather
## than a lookup of params and overrides because this has to be callable from a
## headless test that has no params dict.
static func scale_distances_to_rig(config: Dictionary, ctx: Dictionary,
		explicit: Array = [], reference_leg: float = REFERENCE_LEG) -> float:
	var leg := measured_leg(ctx)
	if leg <= 0.0001:
		return 1.0
	var factor := leg / reference_leg
	ctx["distance_scale"] = factor
	if is_equal_approx(factor, 1.0):
		return factor
	for key in DISTANCE_DEFAULTS:
		if explicit.has(key) or not config.has(key):
			continue
		config[key] = float(config[key]) * factor
	return factor


## Hip-to-ankle distance, averaged over the legs: the length biomechanics means by
## "leg length", and the one a Froude number wants. Shorter than the bone sum
## whenever the rest pose is bent, which is the usual case.
static func _hip_to_ankle(ctx: Dictionary) -> float:
	var legs: Dictionary = ctx.get("legs", {})
	var total := 0.0
	var count := 0
	for side in legs:
		var leg: Dictionary = legs[side]
		if not leg.has("ankle") or not leg.has("hip"):
			continue
		total += (leg.ankle as Vector3).distance_to(leg.hip as Vector3)
		count += 1
	return total / float(maxi(count, 1))


## The Froude number this config's own defaults imply at the reference leg, which
## is the target every other rig is then scaled to. Derived rather than declared
## per recipe, so a run keeps its run value and a stroll its stroll value and
## neither needs a constant of its own.
static func _reference_froude(stride_degrees: float, stance: float, length: float) -> float:
	var speed := 2.0 * REFERENCE_LEG * sin(deg_to_rad(stride_degrees)) / maxf(stance * length, 0.0001)
	return speed / sqrt(9.81 * maxf(REFERENCE_LEG, 0.0001))


## Parent index of every bone, for `RigAnalysis.spine_chain`.
static func _parent_of(skeleton: Skeleton3D) -> Dictionary:
	var parents := {}
	for index in skeleton.get_bone_count():
		parents[skeleton.get_bone_name(index)] = skeleton.get_bone_parent(index)
	return parents


static func _hips_parent_basis(skeleton: Skeleton3D, hips: String) -> Basis:
	var index := skeleton.find_bone(hips)
	if index < 0:
		return Basis.IDENTITY
	var parent := skeleton.get_bone_parent(index)
	return skeleton.get_bone_global_rest(parent).basis.orthonormalized() \
		if parent >= 0 else Basis.IDENTITY


## Global rest basis and origin for the union of the role bones and the spine
## chain, so a bone the detector found that no role names still has its own rest
## pose instead of an identity fallback.
static func _rest_map_of(skeleton: Skeleton3D, roles: Dictionary, chain: Array) -> Dictionary:
	var rest := {}
	var wanted: Array = []
	for role in roles:
		wanted.append(str(roles[role]))
	for bone in chain:
		wanted.append(str(bone))
	for bone in wanted:
		if bone.is_empty() or rest.has(bone):
			continue
		var index := skeleton.find_bone(bone)
		if index < 0:
			continue
		while index >= 0:
			var name := skeleton.get_bone_name(index)
			if rest.has(name): break
			var xform := skeleton.get_bone_global_rest(index)
			var parent := skeleton.get_bone_parent(index)
			rest[name] = {"global": xform.basis, "origin": xform.origin,
				"parent": skeleton.get_bone_name(parent) if parent >= 0 else ""}
			index = parent
	return rest


static func _arm_directions(skeleton: Skeleton3D, roles: Dictionary) -> Dictionary:
	var out := {}
	for side in ["l", "r"]:
		var arm := skeleton.find_bone(str(roles.get("arm_" + side, "")))
		var child := skeleton.find_bone(str(roles.get("forearm_" + side, "")))
		if arm < 0: continue
		if child < 0:
			for index in skeleton.get_bone_count():
				if skeleton.get_bone_parent(index) == arm:
					child = index
					break
		if child >= 0:
			out[side] = skeleton.get_bone_global_rest(child).origin - skeleton.get_bone_global_rest(arm).origin
	return out


## The per-side leg geometry a two-bone solve needs: the bones, the hip and ankle
## rest points, the knee (which is the shin's own rest origin, so the pole is the
## rig's measured bend rather than a guess) and the two bone lengths.
static func leg_map_from_rest(roles: Dictionary, rest: Dictionary) -> Dictionary:
	var legs := {}
	for side in ["l", "r"]:
		var thigh := str(roles.get("thigh_" + side, ""))
		var shin := str(roles.get("shin_" + side, ""))
		var foot := str(roles.get("foot_" + side, ""))
		if not rest.has(thigh) or not rest.has(shin):
			continue
		var ankle: Vector3 = (rest[foot] as Dictionary).origin if rest.has(foot) else (rest[shin] as Dictionary).origin
		var lower: float = (ankle - (rest[shin] as Dictionary).origin).length()
		if lower <= 0.0001:
			# A shin measured at zero means the foot and the knee are the same
			# point, which is a rig with no shin rather than a very short one.
			# The old fallback invented 35 cm here, which is longer than a whole
			# child's leg and made the child rig stride further than it could walk.
			lower = maxf((rest[shin] as Dictionary).origin.distance_to(rest[thigh].origin) * 0.5, 0.01)
		legs[side] = {
			"thigh": thigh,
			"shin": shin,
			"foot": foot,
			"toe": str(roles.get("toe_" + side, "")),
			"hip": (rest[thigh] as Dictionary).origin,
			"ankle": ankle,
			"knee": (rest[shin] as Dictionary).origin,
			"upper": ((rest[shin] as Dictionary).origin - (rest[thigh] as Dictionary).origin).length(),
			"lower": lower,
		}
	return legs


## Longest measured hip-to-ankle distance of the two legs, in metres.
static func measured_leg(ctx: Dictionary) -> float:
	var legs: Dictionary = ctx.get("legs", {})
	var longest := 0.0
	for side in legs:
		var leg: Dictionary = legs[side]
		longest = maxf(longest, float(leg.get("upper", 0.0)) + float(leg.get("lower", 0.0)))
	return longest


## 1 while the foot should stay flat on the ground, 0 while it can follow the
## shin. Blends across the contact and toe-off edges.
static func _foot_plant_weight(p: float, stance: float) -> float:
	var local_phase := fposmod(p, 1.0)
	if local_phase >= stance:
		var swing := (local_phase - stance) / maxf(1.0 - stance, 0.001)
		return 1.0 - MotionDrivers.smoothstep(minf(swing / 0.25, 1.0))
	return MotionDrivers.smoothstep(minf(local_phase / 0.08, 1.0))


## Horizontal axis through the ankle that the foot pitches about: derived from
## the toe direction so +pitch always lifts the toe.
static func _foot_pitch_axis(ctx: Dictionary, leg: Dictionary, knee_hint: Vector3) -> Vector3:
	var up: Vector3 = ctx.up
	var toe := str(leg.get("toe", ""))
	var foot := str(leg.get("foot", ""))
	var rest: Dictionary = ctx.get("rest", {})
	if not toe.is_empty() and not foot.is_empty() and rest.has(toe) and rest.has(foot):
		var toe_dir: Vector3 = (rest[toe].origin as Vector3) - (rest[foot].origin as Vector3)
		toe_dir = toe_dir - up * toe_dir.dot(up)
		if toe_dir.length_squared() > 0.000001:
			return toe_dir.normalized().cross(up).normalized()
	return knee_hint.cross(up).normalized()


## Foot pitch over the cycle: heel strike toe-up, flat stance, toe-off roll.
static func _foot_pitch_curve(p: float, stance: float, heel_up: float, toe_down: float) -> float:
	var local := fposmod(p, 1.0)
	if local >= stance:
		var swing := (local - stance) / maxf(1.0 - stance, 0.001)
		return lerpf(-toe_down, 0.0, minf(swing / 0.25, 1.0))
	if local < 0.08:
		return lerpf(heel_up, 0.0, local / 0.08)
	if local > stance * 0.75:
		return lerpf(0.0, -toe_down, (local - stance * 0.75) / maxf(stance * 0.25, 0.001))
	return 0.0


## Foot-phase cues for a gait cycle: contacts, toe-offs and passing frames. The
## names are stable so audio/code can hook them.
static func _gait_markers(length: float, stance: float) -> Array:
	var times := {
		"contact.L": 0.0,
		"toe_off.L": stance * length,
		"passing.L": (stance + 1.0) * 0.5 * length,
		"contact.R": 0.5 * length,
		"toe_off.R": fposmod((0.5 + stance) * length, maxf(length, 0.001)),
		# The same mid-swing point as the left foot, half a cycle later. The old
		# parenthesisation averaged the phase sum instead, landing the marker at
		# 0.06 of the clip - inside the right foot's stance, before its swing.
		"passing.R": fposmod((0.5 + (stance + 1.0) * 0.5) * length, maxf(length, 0.001)),
	}
	var out: Array = []
	for marker_name in times:
		out.append({"name": marker_name, "time": clampf(float(times[marker_name]), 0.0, length)})
	return out


static func _strafe_markers(length: float, leading: String) -> Array:
	var trailing := "r" if leading == "l" else "l"
	return [
		{"name": "toe_off.%s" % leading.to_upper(), "time": 0.06 * length},
		{"name": "contact.%s" % leading.to_upper(), "time": 0.45 * length},
		{"name": "toe_off.%s" % trailing.to_upper(), "time": 0.55 * length},
		{"name": "contact.%s" % trailing.to_upper(), "time": 0.94 * length},
	]


# --- strafe -----------------------------------------------------------------

## Sideways gait: the walk solver with the foot trajectory along the character's
## lateral axis while the knees keep bending forward.
static func strafe_keys(ctx: Dictionary, direction: String) -> Dictionary:
	var side_sign := 1.0 if direction == "left" else -1.0
	var strafe_ctx := ctx.duplicate()
	strafe_ctx["step_axis"] = (ctx.lateral as Vector3) * side_sign
	strafe_ctx["lateral_step"] = true
	strafe_ctx["lead_side"] = "l" if direction == "left" else "r"
	strafe_ctx["knee_hint"] = ctx.forward
	return gait_keys(strafe_ctx, false)


static func strafe_config(style: String, overrides: Dictionary = {}) -> Dictionary:
	return _resolve_config({
		"stride": 14.0,
		"knee_bend": 35.0,
		"arm_swing": 8.0,
		"bob": 0.035,
		"sway": 0.03,
		"hip_yaw": 2.0,
		"hip_roll": 4.0,
		"chest_yaw": 1.0,
		"lean": 2.0,
		"foot_lift": 0.04,
		"elbow": 12.0,
		"elbow_swing": 6.0,
		"lag": 0.05,
		"stance": 0.6,
		"crouch": 0.0,
	}, style, overrides)


# --- jump -------------------------------------------------------------------

static func jump_config(style: String, overrides: Dictionary = {}) -> Dictionary:
	return _resolve_config({
		"jump_height": 0.5,
		"jump_crouch": 0.24,
		"jump_distance": 0.0,
		"arm_swing": 65.0,
		"elbow": 12.0,
		"lean": 6.0,
	}, style, overrides)


## Resolve sparse story beats into the same temporal density as the final
## clip. IK must be solved at played times: interpolating two individually
## grounded leg poses can put the foot through the floor between them.
static func _dense_phases(phases: Array, length: float, rate: float) -> Array:
	var times: Array[float] = []
	for time in MotionDrivers.sample_times(length, rate):
		times.append(float(time) / length)
	for phase in phases:
		var at := float((phase as Dictionary).t)
		if not times.has(at):
			times.append(at)
	times.sort()
	var dense: Array = []
	for at in times:
		if not dense.is_empty() and absf(at - float((dense[dense.size() - 1] as Dictionary).t)) < 0.00001:
			continue
		var left: Dictionary = phases[0]
		var right: Dictionary = phases[phases.size() - 1]
		for index in phases.size() - 1:
			if at <= float((phases[index + 1] as Dictionary).t) + 0.000001:
				left = phases[index]
				right = phases[index + 1]
				break
		var span := float(right.t) - float(left.t)
		var weight := clampf((at - float(left.t)) / maxf(span, 0.000001), 0.0, 1.0)
		weight = MotionDrivers.smoothstep(weight)
		var sample := {"t": at}
		for key in left:
			if str(key) != "t":
				sample[key] = lerpf(float(left[key]), float(right.get(key, left[key])), weight)
		dense.append(sample)
	return dense


## A one-shot jump: anticipation crouch, launch, an air arc, landing absorb and
## recovery. Feet stay planted before takeoff and after landing; in the air the
## ankles follow the hips. Keys are sparse with `ease_in_out` transitions.
static func jump_keys(ctx: Dictionary) -> Dictionary:
	var config: Dictionary = ctx.config
	var length := maxf(float(ctx.length), 0.01)
	var height := maxf(float(config.get("jump_height", 0.5)), 0.0)
	var crouch := maxf(float(config.get("jump_crouch", 0.24)), 0.0)
	var distance := float(config.get("jump_distance", 0.0))
	var roles: Dictionary = ctx.roles
	var hips := str(ctx.get("hips", ""))
	var forward: Vector3 = ctx.forward
	var up: Vector3 = ctx.up
	var signs := _axis_signs(ctx)
	var lean := float(config.get("lean", 6.0)) * float(signs.lean)
	var hips_origin: Vector3 = ctx.get("hips_origin", Vector3.ZERO)
	var hips_rest := _rest_basis(ctx, hips)
	var keys := {}
	# The lean ramp over the torso: [spine, chest, head] used to take 0.5/0.4/0.0
	# of the lean, i.e. 0.9 total with the head left behind.
	var lean_chain := _twist_chain(ctx, roles)
	var lean_shares := _ramp_shares(lean_chain, str(roles.get("head", "")), 0.35, 0.5, 0.25)
	var phases := _dense_phases([
		{"t": 0.0, "y": 0.0, "air": 0.0, "lean": 0.0, "swing": 0.0, "bend": float(config.get("elbow", 12.0))},
		{"t": 0.2, "y": -crouch, "air": 0.0, "lean": 0.5, "swing": -0.9, "bend": float(config.get("elbow", 12.0)) + 15.0},
		{"t": 0.3, "y": -0.08 * crouch, "air": 0.0, "lean": 0.15, "swing": 0.45, "bend": float(config.get("elbow", 12.0)) + 8.0},
		{"t": 0.47, "y": height, "air": 1.0, "lean": -0.2, "swing": 1.0, "bend": float(config.get("elbow", 12.0)) + 20.0},
		{"t": 0.62, "y": 0.82 * height, "air": 1.0, "lean": 0.1, "swing": 0.55, "bend": float(config.get("elbow", 12.0)) + 10.0},
		{"t": 0.74, "y": 0.06 * height, "air": 0.0, "lean": 0.25, "swing": 0.1, "bend": float(config.get("elbow", 12.0)) + 6.0},
		{"t": 0.84, "y": -0.85 * crouch, "air": 0.0, "lean": 0.55, "swing": -0.5, "bend": float(config.get("elbow", 12.0)) + 18.0},
		{"t": 1.0, "y": 0.0, "air": 0.0, "lean": 0.0, "swing": 0.0, "bend": float(config.get("elbow", 12.0))},
	], length, float(ctx.samples))
	for phase in phases:
		var time := float(phase.t) * length
		# Finish horizontal travel in the air, before the landing contact.
		var travel_share := MotionDrivers.smoothstep(clampf(
			(float(phase.t) - 0.3) / 0.32, 0.0, 1.0))
		var travel := forward * (distance * travel_share)
		var rooted := bool(ctx.get("root_motion", false)) and not is_zero_approx(distance)
		var offset := up * float(phase.y) + (Vector3.ZERO if rooted else travel)
		if rooted:
			_append_position(keys, "__root_motion__", time, travel)
		var world := Quaternion(ctx.lateral, deg_to_rad(float(phase.lean) * lean))
		var hips_animated := Basis(world) * hips_rest
		if not hips.is_empty():
			_append_rotation(keys, hips, time, MotionDrivers.rotation_delta(hips_rest, world))
			_append_hips_position(ctx, keys, hips, time, offset)
		for side in ["l", "r"]:
			var leg: Dictionary = ctx.legs[side]
			var hip_pos: Vector3 = hips_origin + offset + Basis(world) * (leg.hip - hips_origin)
			var ankle_target: Vector3 = leg.ankle + (Vector3.ZERO if rooted else travel)
			var air_share := float(phase.air)
			ankle_target += up * (maxf(float(phase.y), 0.0) * 0.55 * air_share)
			var jump_solved := MotionDrivers.solve_leg(hip_pos, ankle_target,
				float(leg.upper), float(leg.lower), _rest_bend(ctx, leg, forward))
			var knee: Vector3 = jump_solved.knee
			var effective: Vector3 = jump_solved.effective_ankle
			var thigh_rest := _rest_basis(ctx, leg.thigh)
			var shin_rest := _rest_basis(ctx, leg.shin)
			var thigh_solve := MotionDrivers.aim_delta(hips_animated, hips_rest, thigh_rest,
				(knee - hip_pos).normalized(), (leg.knee as Vector3) - (leg.hip as Vector3))
			var shin_solve := MotionDrivers.aim_delta(thigh_solve.global, thigh_rest, shin_rest,
				(effective - knee).normalized(), (leg.ankle as Vector3) - (leg.knee as Vector3))
			var transition := "ease_in_out" if float(phase.t) < 0.7 else "ease_out"
			_append_rotation(keys, leg.thigh, time, thigh_solve.delta, transition)
			_append_rotation(keys, leg.shin, time, shin_solve.delta, transition)
			var foot_bone := str(leg.get("foot", ""))
			if not foot_bone.is_empty():
				var foot_rest := _rest_basis(ctx, foot_bone)
				var flat := MotionDrivers.hold_global_delta(shin_solve.global, shin_rest, foot_rest, foot_rest)
				_append_rotation(keys, foot_bone, time, Quaternion.IDENTITY.slerp(flat, 1.0 - air_share), transition)
		# The lean runs up the whole torso: the lowest bone takes most of it, the
		# head takes a little, and any extra spine bone joins in - previously only
		# the spine and chest existed, so a 6-bone spine bent in two places.
		var lean_degrees := float(phase.lean) * lean
		for slot in lean_chain:
			var bone := str(slot)
			if bone == hips or bone.is_empty():
				continue
			var share := float(lean_shares.get(bone, 0.0))
			if is_zero_approx(share):
				continue
			var bone_world := Quaternion(ctx.lateral, deg_to_rad(lean_degrees * share))
			_append_rotation(keys, bone, time,
				MotionDrivers.rotation_delta(_rest_basis(ctx, bone), bone_world), "ease_in_out")
		var arm_swing := float(phase.swing) * float(config.get("arm_swing", 65.0))
		_solve_arm_chain(ctx, keys, "l", time, -arm_swing, float(phase.bend), "ease_in_out")
		_solve_arm_chain(ctx, keys, "r", time, -arm_swing, float(phase.bend), "ease_in_out")
	var markers := [
		{"name": "takeoff", "time": 0.3 * length},
		{"name": "apex", "time": 0.47 * length},
		{"name": "land", "time": 0.8 * length},
	]
	if keys.has("__root_motion__"):
		(keys["__root_motion__"] as Dictionary)["loop_close"] = false
	_mark_one_shot(keys)
	return {
		"keys": keys,
		"markers": markers,
		"meta": {"height": height, "crouch": crouch, "distance": distance},
	}


## A one-shot recipe ends somewhere else than it started (a jump lands, a turn
## faces another way), so its tracks must not be loop-closed: with
## `loop_mode: linear` the closing pass overwrote the last key with the first and
## threw the endpoint away.
static func _mark_one_shot(keys: Dictionary) -> void:
	for bone_name in keys:
		(keys[bone_name] as Dictionary)["loop_close"] = false


# --- turn -------------------------------------------------------------------

static func turn_config(style: String, overrides: Dictionary = {}) -> Dictionary:
	return _resolve_config({
		"turn_angle": 90.0,
		"arm_swing": 12.0,
		"elbow": 12.0,
		"lean": 4.0,
		"foot_lift": 0.05,
		"steps": 1.0,
	}, style, overrides)


## An in-place pivot turn: anticipation, a body sweep with one foot lifting and
## re-planting, then a settle. One-shot; `angle` is signed by `direction`.
##
## `steps` splits a big turn into that many pivot steps (each with its own
## anticipation, opposite foot, and settle) so a 180-degree turn reads as two
## weight shifts instead of one spin. The clip only carries the body rotation,
## so the driver re-bases the root yaw between steps.
static func turn_keys(ctx: Dictionary) -> Dictionary:
	var config: Dictionary = ctx.config
	var length := maxf(float(ctx.length), 0.01)
	var roles: Dictionary = ctx.roles
	var hips := str(ctx.get("hips", ""))
	var up: Vector3 = ctx.up
	var signs := _axis_signs(ctx)
	var direction := str(ctx.get("direction", "left"))
	var direction_sign := 1.0 if direction == "left" else -1.0
	var angle := float(config.get("turn_angle", 90.0)) * direction_sign
	var steps := clampi(int(config.get("steps", 1.0)), 1, 8)
	var step_angle := angle / float(steps)
	var step_length := length / float(steps)
	var keys := {}
	var markers: Array = []
	var hips_origin: Vector3 = ctx.get("hips_origin", Vector3.ZERO)
	var hips_rest := _rest_basis(ctx, hips)
	var phases := _dense_phases([
		{"t": 0.0, "yaw": 0.0, "bob": 0.0, "arm": 0.0},
		{"t": 0.14, "yaw": -0.06 * step_angle, "bob": -0.02, "arm": -0.25},
		{"t": 0.55, "yaw": 0.72 * step_angle, "bob": -0.035, "arm": 0.55},
		{"t": 0.8, "yaw": 1.045 * step_angle, "bob": -0.012, "arm": 0.2},
		{"t": 1.0, "yaw": step_angle, "bob": 0.0, "arm": 0.0},
	], step_length, maxf(float(ctx.samples), 120.0))
	# Lead distribution over the torso above the hips: the chest leads the sweep,
	# the head trails it, and any extra spine bone splits the difference.
	var lead_chain := _twist_chain(ctx, roles)
	var lead_shares := _lead_shares(lead_chain, str(roles.get("head", "")))
	var foot_yaws := {"l": 0.0, "r": 0.0}
	for step_index in steps:
		var start_yaw := float(step_index) * step_angle
		# The first step lifts the trailing foot; the next mirrors it.
		var step_side := "r" if (direction == "left") == (step_index % 2 == 0) else "l"
		for phase_index in phases.size():
			# Every step but the first starts where the previous one settled, so
			# only the first step keys the neutral start of its window.
			if step_index > 0 and phase_index == 0:
				continue
			var phase: Dictionary = phases[phase_index]
			var local := float(phase.t)
			var time := (float(step_index) + local) * step_length
			var yaw := start_yaw + float(phase.yaw)
			var world := Quaternion(up, deg_to_rad(yaw * float(signs.yaw)))
			var hips_animated := Basis(world) * hips_rest
			# The turn's phase bobs are metres, so they scale with the rig like every
			# other default distance.
			var offset := up * (float(phase.bob) * float(ctx.get("distance_scale", 1.0)))
			if not hips.is_empty():
				_append_rotation(keys, hips, time, MotionDrivers.rotation_delta(hips_rest, world))
				_append_hips_position(ctx, keys, hips, time, offset)
			for side in ["l", "r"]:
				var leg: Dictionary = ctx.legs[side]
				var lift := 0.0
				if side == step_side:
					# The trailing foot lifts through the middle of the step.
					var mid := absf(local - 0.5)
					lift = maxf(0.0, 1.0 - mid / 0.3) * float(config.get("foot_lift", 0.05))
				var hip_pos: Vector3 = hips_origin + offset + Basis(world) * (leg.hip - hips_origin)
				# Keep the support foot anchored while the pelvis turns. The lifted
				# foot travels to its new heading during swing, before it replants.
				var foot_yaw := float(foot_yaws[side])
				if side == step_side:
					var swing_share := MotionDrivers.smoothstep(clampf(
						(local - 0.2) / 0.55, 0.0, 1.0))
					foot_yaw = lerpf(foot_yaw, start_yaw + step_angle, swing_share)
				var foot_world := Quaternion(up, deg_to_rad(foot_yaw * float(signs.yaw)))
				var ankle_target: Vector3 = hips_origin + Basis(foot_world) * (leg.ankle - hips_origin) + up * lift
				var turn_solved := MotionDrivers.solve_leg(hip_pos, ankle_target,
					float(leg.upper), float(leg.lower), _rest_bend(ctx, leg, ctx.forward))
				var knee: Vector3 = turn_solved.knee
				var effective: Vector3 = turn_solved.effective_ankle
				var thigh_rest := _rest_basis(ctx, leg.thigh)
				var shin_rest := _rest_basis(ctx, leg.shin)
				var thigh_solve := MotionDrivers.aim_delta(hips_animated, hips_rest, thigh_rest,
					(knee - hip_pos).normalized(), (leg.knee as Vector3) - (leg.hip as Vector3))
				var shin_solve := MotionDrivers.aim_delta(thigh_solve.global, thigh_rest, shin_rest,
					(effective - knee).normalized(), (leg.ankle as Vector3) - (leg.knee as Vector3))
				_append_rotation(keys, leg.thigh, time, thigh_solve.delta, "ease_in_out")
				_append_rotation(keys, leg.shin, time, shin_solve.delta, "ease_in_out")
				var foot_bone := str(leg.get("foot", ""))
				if not foot_bone.is_empty():
					var foot_rest := _rest_basis(ctx, foot_bone)
					# The planted foot turns with the body; the stepping one follows.
					var foot_target := Basis(world) * foot_rest
					var flat := MotionDrivers.hold_global_delta(shin_solve.global, shin_rest, foot_rest, foot_target)
					_append_rotation(keys, foot_bone, time, Quaternion.IDENTITY.slerp(flat, 0.0 if lift > 0.001 else 1.0), "ease_in_out")
			# The torso above the hips carries a bounded lead: a fraction of *this
			# step's* angle, never of the running total, so a multi-step turn cannot
			# compound it into a corkscrew. Distributing it over the chain means a
			# 3-bone and a 6-bone spine both get a smooth lead instead of one
			# chest bone taking it all.
			var lead_fraction := 0.28 if local < 0.6 else 0.08
			for slot in lead_chain:
				var bone := str(slot)
				if bone == hips or bone.is_empty():
					continue
				var share := lead_fraction * float(lead_shares.get(bone, 0.0)) * absf(step_angle)
				var bone_yaw := (yaw + share) * float(signs.yaw)
				var bone_world := Quaternion(up, deg_to_rad(bone_yaw))
				_append_rotation(keys, bone, time,
					MotionDrivers.rotation_delta(_rest_basis(ctx, bone), bone_world), "ease_in_out")
			# Arms counterbalance the sweep so a T-pose rest does not stay spread.
			var arm_swing := float(config.get("arm_swing", 12.0)) * float(phase.arm)
			_solve_arm_chain(ctx, keys, "l", time, arm_swing, float(config.get("elbow", 12.0)) + 8.0, "ease_in_out")
			_solve_arm_chain(ctx, keys, "r", time, arm_swing, float(config.get("elbow", 12.0)) + 8.0, "ease_in_out")
		foot_yaws[step_side] = start_yaw + step_angle
		var suffix := "" if step_index == 0 else "_%d" % (step_index + 1)
		markers.append({"name": "anticipate" + suffix, "time": (float(step_index) + 0.14) * step_length})
		markers.append({"name": "step" + suffix, "time": (float(step_index) + 0.5) * step_length})
		markers.append({"name": "settle" + suffix, "time": (float(step_index) + 0.8) * step_length})
	_mark_one_shot(keys)
	return {
		"keys": keys,
		"markers": markers,
		"meta": {
			"angle": angle,
			"direction": direction,
			"steps": steps,
			"step_angle": step_angle,
		},
	}


# --- gait transitions -------------------------------------------------------

## Blend into (`walk_start`) or out of (`walk_stop`) a gait. The gait-facing end
## is sampled from `gait_keys` at `phase`, so the transition matches the cycle
## frame-for-frame and can be cross-faded or concatenated.
static func transition_keys(ctx: Dictionary, stopping: bool) -> Dictionary:
	var length := maxf(float(ctx.length), 0.01)
	var phase := clampf(float(ctx.get("phase", 0.0)), 0.0, 0.999)
	var gait := gait_keys(ctx, false)
	if (gait.keys as Dictionary).is_empty():
		return gait
	var gait_keys_dict: Dictionary = gait.keys
	var target_time := phase * float(ctx.length)
	var keys := {}
	var hips := str(ctx.get("hips", ""))
	var hips_origin: Vector3 = ctx.get("hips_origin", Vector3.ZERO)
	var hips_rest := _rest_basis(ctx, hips)
	var target_hips: Quaternion = _delta_at(
		(gait_keys_dict.get(hips, {}) as Dictionary).get("rotation", []), target_time)
	var target_offset_local: Vector3 = _vec_at(
		(gait_keys_dict.get(hips, {}) as Dictionary).get("position", []), target_time)
	var target_offset: Vector3 = (ctx.get("hips_parent_basis", Basis.IDENTITY) as Basis) * target_offset_local
	var target_world_basis := hips_rest * Basis(target_hips) * hips_rest.inverse()
	var target_world := target_world_basis.get_rotation_quaternion().normalized()
	# The imported X Bot and many artist rigs rest in a T pose. Begin and end
	# locomotion transitions with the same relaxed arm pose the gait solver uses.
	var resting_arms := {}
	for side in ["l", "r"]:
		_solve_arm_chain(ctx, resting_arms, side, 0.0, 0.0,
			float((ctx.config as Dictionary).get("elbow", 12.0)))
	var stance := clampf(float((ctx.config as Dictionary).get("stance", 0.6)), 0.2, 0.8)
	var speed := float((gait.meta as Dictionary).get("speed", 0.0))
	var span := speed * stance * length
	var rooted := bool(ctx.get("root_motion", false))
	var foot_targets := {}
	var support := "r"
	var rearward := INF
	for side in ["l", "r"]:
		var leg: Dictionary = ctx.legs[side]
		var p := fposmod(phase + (0.0 if side == "l" else 0.5), 1.0)
		var foot := _foot_trajectory(p, stance, span, speed, length, rooted,
			0.0 if side == "l" else 0.5)
		var forward_distance := float(foot.forward)
		foot_targets[side] = (leg.ankle as Vector3) \
			+ (ctx.forward as Vector3) * forward_distance \
			+ (ctx.up as Vector3) * float(foot.height) * float(ctx.get("foot_lift_scaled", 0.05))
		if float(foot.height) < 0.001 and forward_distance < rearward:
			rearward = forward_distance
			support = side
	var support_leg: Dictionary = ctx.legs[support]
	var root_end := Vector3.ZERO
	if rooted:
		root_end = (support_leg.ankle as Vector3) - (foot_targets[support] as Vector3)
	var times := MotionDrivers.sample_times(length, maxf(float(ctx.samples), 120.0))
	for time_value in times:
		var time := float(time_value)
		var t := clampf(time / length, 0.0, 1.0)
		var weight := MotionDrivers.smoothstep(t)
		var root_at: Vector3 = root_end * weight
		if stopping:
			# A stop must keep travelling forward while the swing foot lands and
			# takes the load. Time-reversing a start sends its root backward.
			weight = 1.0 - weight
			root_at = root_end * MotionDrivers.smoothstep(
				clampf((t - 0.35) / 0.55, 0.0, 1.0))
		var offset := target_offset * weight
		var world := Quaternion.IDENTITY.slerp(target_world, weight).normalized()
		var hips_animated := Basis(world) * hips_rest
		if not hips.is_empty():
			_append_rotation(keys, hips, time,
				target_hips if not stopping and t >= 0.99999
				else MotionDrivers.rotation_delta(hips_rest, world))
			_append_hips_position(ctx, keys, hips, time, offset)
		if rooted:
			_append_position(keys, "__root_motion__", time, root_at)
		for bone in gait_keys_dict:
			if bone == hips or bone == "__root_motion__":
				continue
			var is_leg := false
			for side in ["l", "r"]:
				var leg: Dictionary = ctx.legs[side]
				if bone in [str(leg.thigh), str(leg.shin), str(leg.get("foot", ""))]:
					is_leg = true
					break
			if is_leg:
				continue
			var source: Dictionary = gait_keys_dict[bone]
			if source.has("rotation"):
				var target_rotation: Quaternion = _delta_at(source.rotation, target_time)
				var resting_rotation := Quaternion.IDENTITY
				if resting_arms.has(bone):
					resting_rotation = _delta_at(
						(resting_arms[bone] as Dictionary).get("rotation", []), 0.0)
				_append_rotation(keys, str(bone), time,
					resting_rotation.slerp(target_rotation, weight).normalized())
			if source.has("position"):
				_append_position(keys, str(bone), time,
					_vec_at(source.position, target_time) * weight)
		for side in ["l", "r"]:
			var leg: Dictionary = ctx.legs[side]
			var hip_pos: Vector3 = hips_origin + offset + Basis(world) * (leg.hip - hips_origin)
			var world_ankle: Vector3 = leg.ankle
			if stopping:
				var initial_ankle: Vector3 = foot_targets[side]
				var final_ankle: Vector3 = (leg.ankle as Vector3) + root_end
				if side == support:
					# The old support stays fixed until the other foot has landed.
					var support_step := MotionDrivers.smoothstep(
						clampf((t - 0.5) / 0.28, 0.0, 1.0))
					world_ankle = initial_ankle.lerp(final_ankle, support_step)
					var support_lift := MotionDrivers.smoothstep(
						clampf((t - 0.40) / 0.10, 0.0, 1.0)) * (
						1.0 - MotionDrivers.smoothstep(clampf((t - 0.78) / 0.10, 0.0, 1.0)))
					world_ankle += (ctx.up as Vector3) * float(
						(ctx.config as Dictionary).get("foot_lift", 0.05)) * support_lift
				else:
					# The leading foot plants before root translation begins.
					var lead_step := MotionDrivers.smoothstep(
						clampf((t - 0.10) / 0.25, 0.0, 1.0))
					world_ankle = initial_ankle.lerp(final_ankle, lead_step)
					var lead_lift := MotionDrivers.smoothstep(
						clampf((t - 0.02) / 0.08, 0.0, 1.0)) * (
						1.0 - MotionDrivers.smoothstep(clampf((t - 0.29) / 0.07, 0.0, 1.0)))
					world_ankle += (ctx.up as Vector3) * float(
						(ctx.config as Dictionary).get("foot_lift", 0.05)) * lead_lift
			elif side != support:
				var step_share := MotionDrivers.smoothstep(clampf((t - 0.3) / 0.4, 0.0, 1.0))
				world_ankle = (leg.ankle as Vector3).lerp(
					(foot_targets[side] as Vector3) + root_end, step_share)
				var lift_in := MotionDrivers.smoothstep(clampf((t - 0.12) / 0.16, 0.0, 1.0))
				var lift_out := 1.0 - MotionDrivers.smoothstep(clampf((t - 0.72) / 0.16, 0.0, 1.0))
				world_ankle += (ctx.up as Vector3) * (
					float((ctx.config as Dictionary).get("foot_lift", 0.05)) * lift_in * lift_out)
			var ankle_target := world_ankle - root_at
			var solved := MotionDrivers.solve_leg(hip_pos, ankle_target,
				float(leg.upper), float(leg.lower), _rest_bend(ctx, leg, ctx.forward))
			var thigh_rest := _rest_basis(ctx, leg.thigh)
			var shin_rest := _rest_basis(ctx, leg.shin)
			var thigh_solve := MotionDrivers.aim_delta(hips_animated, hips_rest, thigh_rest,
				((solved.knee as Vector3) - hip_pos).normalized(), leg.knee - leg.hip)
			var shin_solve := MotionDrivers.aim_delta(thigh_solve.global, thigh_rest, shin_rest,
				((solved.effective_ankle as Vector3) - (solved.knee as Vector3)).normalized(),
				leg.ankle - leg.knee)
			_append_rotation(keys, str(leg.thigh), time, thigh_solve.delta)
			_append_rotation(keys, str(leg.shin), time, shin_solve.delta)
			var foot_bone := str(leg.get("foot", ""))
			if not foot_bone.is_empty():
				var foot_rest := _rest_basis(ctx, foot_bone)
				var target_foot := _delta_at(
					(gait_keys_dict.get(foot_bone, {}) as Dictionary).get("rotation", []), target_time)
				var flat := MotionDrivers.hold_global_delta(shin_solve.global, shin_rest,
					foot_rest, foot_rest)
				_append_rotation(keys, foot_bone, time, flat.slerp(target_foot, weight))
	# The gait-facing endpoint must be identical to the played gait pose,
	# including sparse samples at an arbitrary requested phase.
	for bone in gait_keys_dict:
		if bone == "__root_motion__" or not keys.has(bone):
			continue
		var source: Dictionary = gait_keys_dict[bone]
		if source.has("rotation") and (keys[bone] as Dictionary).has("rotation"):
			var rotation_index := 0 if stopping else -1
			((keys[bone] as Dictionary).rotation as Array)[rotation_index].delta = _delta_at(source.rotation, target_time)
		if source.has("position") and (keys[bone] as Dictionary).has("position"):
			var position_index := 0 if stopping else -1
			((keys[bone] as Dictionary).position as Array)[position_index].delta = _vec_at(source.position, target_time)
	if stopping:
		# The geometric solver may finish with a bent knee even when its ankle
		# target has reached rest. The neutral endpoint is the rig's actual rest
		# pose, which must join idle without a last-frame foot correction.
		for side in ["l", "r"]:
			var leg: Dictionary = ctx.legs[side]
			for bone in [str(leg.thigh), str(leg.shin), str(leg.get("foot", ""))]:
				if keys.has(bone) and (keys[bone] as Dictionary).has("rotation"):
					((keys[bone] as Dictionary).rotation as Array)[-1].delta = Quaternion.IDENTITY
	# A transition lands on (or starts from) a gait pose, so it is a one-shot
	# too: loop-closing it would overwrite the pose the next clip continues from.
	_mark_one_shot(keys)
	return {
		"keys": keys,
		"markers": [{"name": "settled", "time": length}],
		"meta": {"phase": phase},
	}


## Sample one delta channel at `time` through a real `Animation` track, so the
## transition curve the clip will actually play is the curve used here. The old
## nearest-key lookup returned the CLOSEST key instead of interpolating, so
## `walk_start` met the cycle on whichever key was luckier and popped whenever
## the requested phase fell between two sparse keys.
static func _sample_delta(keys: Array, time: float, rotation: bool) -> Variant:
	if keys.is_empty():
		return Quaternion.IDENTITY if rotation else Vector3.ZERO
	var anim := Animation.new()
	var track := anim.add_track(
		Animation.TYPE_ROTATION_3D if rotation else Animation.TYPE_POSITION_3D)
	for key in keys:
		var at := float(key.get("time", 0.0))
		var transition := ValueCodec.parse_transition(key.get("transition", 1.0))
		# The typed insert helpers take no transition, and the transition weight is
		# the whole point: it is what makes playback ease instead of run straight
		# from key to key, so the generic insert carries it.
		if rotation:
			anim.track_insert_key(track, at,
				(key.get("delta", Quaternion.IDENTITY) as Quaternion).normalized(), transition)
		else:
			anim.track_insert_key(track, at, key.get("delta", Vector3.ZERO), transition)
	anim.length = maxf(float(keys[keys.size() - 1].get("time", 0.0)), 0.001)
	return anim.rotation_track_interpolate(track, time) if rotation \
		else anim.position_track_interpolate(track, time)


static func _delta_at(rotation_keys: Array, time: float) -> Quaternion:
	return _sample_delta(rotation_keys, time, true) as Quaternion


static func _vec_at(position_keys: Array, time: float) -> Vector3:
	return _sample_delta(position_keys, time, false) as Vector3


# --- idle -------------------------------------------------------------------

## Per-bone lean shares for a torso chain. Every bone used to take the FULL
## lean, so a seven-bone spine folded seven times as much as a three-bone one and
## the same `lean` meant something different on every rig. The torso's shares now
## sum to 1.0 - so the requested lean IS the total fold, on any spine - while the
## head keeps its own `head_share` (it counter-leans rather than adding to the
## fold). A three-bone torso is unchanged, which is the shape the presets were
## tuned against.
static func _lean_shares(chain: Array, head: String, head_share: float) -> Dictionary:
	var out: Dictionary = {}
	var torso: Array = []
	for slot in chain:
		var bone := str(slot)
		if not bone.is_empty() and bone != head:
			torso.append(bone)
	var share := 1.0 / maxf(1.0, float(torso.size()))
	for bone in torso:
		out[bone] = share
	if not head.is_empty():
		out[head] = head_share
	return out


## The pole direction is the knee's bend ACROSS the rest hip-to-ankle axis.
## Hip-to-knee by itself is mostly vertical; projecting that nearly parallel
## vector against each changing ankle target makes the pole switch sides in
## mid-swing, sending the knee and foot through a discontinuity.
static func _rest_bend(ctx: Dictionary, leg: Dictionary, fallback: Vector3) -> Vector3:
	var hip: Vector3 = leg.get("hip", Vector3.ZERO)
	var knee: Vector3 = leg.get("knee", Vector3.ZERO)
	var ankle: Vector3 = leg.get("ankle", Vector3.ZERO)
	var axis := ankle - hip
	if axis.length_squared() < 0.000001:
		return fallback
	axis = axis.normalized()
	var bend := knee - hip
	bend -= axis * bend.dot(axis)
	if bend.length_squared() < 0.000001:
		bend = fallback - axis * fallback.dot(axis)
	return bend.normalized() if bend.length_squared() >= 0.000001 else fallback


static func idle_keys(ctx: Dictionary) -> Dictionary:
	var config: Dictionary = ctx.config
	var length := maxf(float(ctx.length), 0.001)
	var times := MotionDrivers.sample_times(length, float(ctx.samples))
	var steps := times.size() - 1
	var keys := {}
	var up: Vector3 = ctx.up
	var forward: Vector3 = ctx.forward
	var lateral: Vector3 = ctx.lateral
	var roles: Dictionary = ctx.roles
	var hips := str(ctx.get("hips", ""))
	var signs := _axis_signs(ctx)
	var scale := float(signs.lean)
	var look := float(config.look)
	var twist := float(config.twist)
	# Breathing is the under-layer; the visible motion is the look-around and
	# the torso twist. Every channel is integer-frequency, so the loop closes.
	# The twist is distributed over the chain instead of each bone taking its own
	# multiplier, so `twist` means the same total degrees on any rig.
	var twist_channels := _twist_channels(ctx, config, twist, up, [], _spread(config))
	var breath := [_channel(lateral, -float(config.amplitude) * scale, 1.0, 0.0, 0.0, "sine")]
	# A quarter of the twist rides along as a weight shift on the hips, which is
	# what made the old per-bone roll channels look like a ribcage rotating.
	var hips_shift := [_channel(lateral, 0.25 * twist * scale, 1.0, 0.25, 0.05, "sine")]
	var head_motion := [
		_channel(up, look, 1.0, 0.25, 0.02, "sine"),
		_channel(up, 0.3 * look, 2.0, 0.62, 0.02, "sine"),
		_channel(lateral, -0.35 * float(config.head_amplitude), 1.0, 0.0, 0.06, "sine"),
		_channel(forward, 0.12 * look, 1.0, 0.25, 0.05, "sine"),
	]
	# Seeded micro-motion, per chain bone: the torso breathes unevenly and the
	# head is never quite still.
	var noise_amount := float(config.noise)
	var noise_channels := {}
	if not is_zero_approx(noise_amount):
		var chain_bones := _twist_chain(ctx, roles)
		for slot in chain_bones:
			var bone := str(slot)
			var amount := noise_amount * scale * (0.5 if bone == str(roles.get("spine", "")) else 1.0)
			noise_channels[bone] = [
				_channel(up, amount, 1.0, 0.0, 0.0, "noise", 0.0, 21, 3),
				_channel(lateral, amount, 1.0, 0.35, 0.0, "noise", 0.0, 22, 3),
			]
		head_motion.append_array([
			_channel(up, 0.8 * noise_amount * scale, 1.0, 0.0, 0.0, "noise", 0.0, 23, 3),
			_channel(lateral, 0.6 * noise_amount * scale, 1.0, 0.5, 0.0, "noise", 0.0, 24, 3),
		])
	var lean := float(config.lean)
	var sway_channel := _channel(lateral, -float(config.sway), 1.0, 0.0, 0.0, "sine")
	var bob_channel := _channel(up, -0.5 * float(config.bob), 2.0, 0.0, 0.0, "cosine")
	var roll_channel := _channel(forward, float(config.shift) * float(signs.roll), 1.0, 0.0, 0.0, "sine")
	var chain := _twist_chain(ctx, roles)
	var chest := str(roles.get("chest", ""))
	var head := str(roles.get("head", ""))
	# The idle leans the opposite way to the walk, with the head holding its own
	# share; both are shares of the total, so the fold is spine-length independent.
	var lean_shares := _lean_shares(chain, head, 0.4)
	# The pelvis moving without the legs re-solving IS foot drift: a viewer sees
	# the character skate. `planted` (on by default) solves both legs against
	# their rest ankle targets every sample; `planted: false` keeps the old
	# pelvis-only clip for callers who key the feet themselves.
	var planted := bool(config.get("planted", true))
	var hips_origin: Vector3 = ctx.get("hips_origin", Vector3.ZERO)
	var hips_rest := _rest_basis(ctx, hips)

	for index in times.size():
		var t := float(index) / float(steps)
		var time := float(times[index])
		if not hips.is_empty():
			# duplicate(): append_array would otherwise grow hips_shift itself and
			# stack the twist channels once per sample.
			var hips_motion: Array = hips_shift.duplicate()
			hips_motion.append_array((twist_channels.get(hips, []) as Array))
			var world := (
				Quaternion(lateral, deg_to_rad(-lean * 0.35 * scale))
				* Quaternion(forward, deg_to_rad(MotionDrivers.channel_value(roll_channel, t)))
				* MotionDrivers.compose_rotation(hips_motion, t)
			)
			_append_rotation(keys, hips, time, MotionDrivers.rotation_delta(_rest_basis(ctx, hips), world))
			var hips_offset := (
				lateral * MotionDrivers.channel_value(sway_channel, t)
				+ up * MotionDrivers.channel_value(bob_channel, t)
			)
			_append_hips_position(ctx, keys, hips, time, hips_offset)
			if planted:
				var hips_animated := Basis(world) * hips_rest
				for side in ["l", "r"]:
					_solve_idle_leg(ctx, keys, str(side), time, hips_offset, world,
						hips_animated, hips_origin)
		# Every chain bone above the hips takes its share of the twist; the chest
		# keeps the breathing under-layer and the head keeps its look-around.
		for slot in chain:
			var bone := str(slot)
			if bone == hips or bone.is_empty():
				continue
			var own: Array = []
			if bone == chest:
				own = breath.duplicate()
				own.append_array((noise_channels.get(bone, []) as Array))
			elif bone == head:
				own = head_motion.duplicate()
			else:
				own = (noise_channels.get(bone, []) as Array).duplicate()
			var pose := _compose_with_twist(own, twist_channels, bone, t)
			# This bone's share of the total lean, so the fold does not grow with
			# the number of spine bones (the head keeps its own share).
			var lean_share := lean * scale * float(lean_shares.get(bone, 0.0))
			pose = pose * Quaternion(lateral, deg_to_rad(lean_share))
			_append_rotation(keys, bone, time, MotionDrivers.rotation_delta(_rest_basis(ctx, bone), pose))
		_solve_idle_arms(ctx, keys, time, t)
	return {"keys": keys, "markers": [], "meta": {}}


## One leg of a standing idle, solved so the ankle stays on its rest world
## point while the pelvis breathes, sways and twists. Without this the feet
## travel with the hips and the character skates in place.
static func _solve_idle_leg(
	ctx: Dictionary, keys: Dictionary, side: String, time: float,
	hips_offset: Vector3, pelvis_world: Quaternion, hips_animated: Basis,
	hips_origin: Vector3,
) -> void:
	var leg: Dictionary = ctx.legs[side]
	var knee_hint: Vector3 = ctx.get("knee_hint", ctx.forward)
	var hip_pos: Vector3 = hips_origin + hips_offset + Basis(pelvis_world) * (leg.hip - hips_origin)
	# The ankle target IS the rest ankle: a standing foot does not move, it only
	# stops following the pelvis.
	var ankle_target: Vector3 = leg.ankle
	var solved := MotionDrivers.solve_leg(hip_pos, ankle_target, float(leg.upper),
		float(leg.lower), _rest_bend(ctx, leg, knee_hint))
	var knee: Vector3 = solved.knee
	var thigh_rest := _rest_basis(ctx, leg.thigh)
	var shin_rest := _rest_basis(ctx, leg.shin)
	var hips_rest := _rest_basis(ctx, ctx.get("hips", ""))
	var thigh_solve := MotionDrivers.aim_delta(hips_animated, hips_rest, thigh_rest,
		(knee - hip_pos).normalized(), (leg.knee as Vector3) - (leg.hip as Vector3))
	var shin_solve := MotionDrivers.aim_delta(thigh_solve.global, thigh_rest, shin_rest,
		((solved.effective_ankle as Vector3) - knee).normalized(),
		(leg.ankle as Vector3) - (leg.knee as Vector3))
	_append_rotation(keys, leg.thigh, time, thigh_solve.delta)
	_append_rotation(keys, leg.shin, time, shin_solve.delta)
	var foot_bone := str(leg.get("foot", ""))
	if foot_bone.is_empty():
		return
	# A planted foot keeps its rest orientation in the world, so it stays flat on
	# the floor while the shin moves under it.
	var foot_rest := _rest_basis(ctx, foot_bone)
	_append_rotation(keys, foot_bone, time,
		MotionDrivers.hold_global_delta(shin_solve.global, shin_rest, foot_rest, foot_rest))


## Idle arms: the static arm-down offset (so T-pose rests hang naturally) plus a
## small swing that follows the weight shift, with a light elbow bend - all on
## the same sagittal hinge the gait uses.
static func _solve_idle_arms(ctx: Dictionary, keys: Dictionary, time: float, t: float) -> void:
	var config: Dictionary = ctx.config
	var arm_sway := float(config.arm_sway)
	var elbow := float(config.elbow)
	for side in ["l", "r"]:
		var sign := -1.0 if side == "l" else 1.0
		var sway := MotionDrivers.channel_value(
			_channel(ctx.lateral, sign * arm_sway, 1.0, 0.0, 0.1, "sine"), t)
		_solve_arm_chain(ctx, keys, side, time, sway, elbow)


# --- helpers ----------------------------------------------------------------

## Actual connected hips -> chest -> head ancestry. Rest offsets determine
## distribution, independently of bone-local axes and spine bone count.
static func upper_body_layout(ctx: Dictionary) -> Dictionary:
	var roles: Dictionary = ctx.get("roles", {})
	for role in ["hips", "chest", "head"]:
		if str(roles.get(role, "")).is_empty():
			return {"error": "Head/torso articulation requires hips, chest and head roles"}
	var hips := str(roles.hips)
	var chest := str(roles.chest)
	var head := str(roles.head)
	if hips == chest or chest == head or hips == head:
		return {"error": "Head/torso articulation requires distinct hips, chest and head joints"}
	var result := {}
	for segment in ["torso", "cervical"]:
		var bone := chest if segment == "torso" else head
		var stop := hips if segment == "torso" else chest
		var chain: Array = []
		while bone != stop and not bone.is_empty() and not chain.has(bone):
			if not ctx.rest.has(bone): break
			chain.push_front(bone)
			bone = str(ctx.rest[bone].get("parent", ""))
		if bone != stop or chain.is_empty():
			return {"error": "Head/torso articulation needs a connected hips -> chest -> head rest hierarchy"}
		var lengths: Array = []
		var total := 0.0
		for joint: String in chain:
			var parent := str(ctx.rest[joint].parent)
			var distance: float = (ctx.rest[joint].origin as Vector3).distance_to(ctx.rest[parent].origin as Vector3)
			lengths.append(distance)
			total += distance
		if total < 0.0001:
			return {"error": "Head/torso articulation needs nonzero torso and cervical rest lengths"}
		var shares := {}
		for i in chain.size(): shares[chain[i]] = float(lengths[i]) / total
		result[segment] = shares
	return result


## Layer a skeleton-space rotation over this sample's existing pose, converting
## through the already animated parent. Replace the sample, never duplicate it.
static func _layer_rotation(ctx: Dictionary, keys: Dictionary, bone: String,
		time: float, rotation: Quaternion) -> void:
	var parent := str(ctx.rest[bone].get("parent", ""))
	var incoming := _animated_basis(ctx, keys, parent, time) * _rest_basis(ctx, parent).inverse() * _rest_basis(ctx, bone)
	var delta := MotionDrivers.rotation_delta(incoming, rotation)
	var rotations: Array = keys.get(bone, {}).get("rotation", [])
	if not rotations.is_empty() and is_equal_approx(float(rotations[-1].time), time):
		rotations[-1].delta = (delta * (rotations[-1].delta as Quaternion)).normalized()
	else:
		_append_rotation(keys, bone, time, delta)


## Periodic authored flex and cervical articulation. Vertical head bob comes
## from the pelvis; local bone offsets stay unchanged (no stretched neck).
static func _articulate_upper_body(ctx: Dictionary, keys: Dictionary, time: float, t: float) -> void:
	var config: Dictionary = ctx.config
	var layout: Dictionary = ctx.upper_body_layout
	var up: Vector3 = ctx.up
	var lateral: Vector3 = ctx.lateral
	var forward: Vector3 = ctx.forward
	var signs := _axis_signs(ctx)
	var flex := float(config.get("torso_flex", 0.0)) * cos(TAU * 2.0 * t)
	var roll := -float(config.get("torso_roll", 0.0)) * float(signs.roll) * sin(TAU * t)
	for bone: String in layout.torso:
		var share := float(layout.torso[bone])
		_layer_rotation(ctx, keys, bone, time,
			Quaternion(lateral, deg_to_rad(flex * share)) * Quaternion(forward, deg_to_rad(roll * share)))
	var chest := str(ctx.roles.chest)
	var chest_up := (_animated_basis(ctx, keys, chest, time) * _rest_basis(ctx, chest).inverse() * up).normalized()
	# Partial swing correction preserves incoming yaw while moderating pitch/roll.
	var stabilize := Quaternion.IDENTITY.slerp(Quaternion(chest_up, up), float(config.get("head_stabilize", 0.0)))
	var delayed := t - float(config.get("head_lag", 0.0))
	var nod := -float(config.get("head_nod", 0.0)) * cos(TAU * 2.0 * delayed)
	var head_roll := float(config.get("head_roll", 0.0)) * sin(TAU * delayed)
	var cervical := Quaternion(lateral, deg_to_rad(nod)) * Quaternion(forward, deg_to_rad(head_roll)) * stabilize
	for bone: String in layout.cervical:
		_layer_rotation(ctx, keys, bone, time, Quaternion.IDENTITY.slerp(cervical, float(layout.cervical[bone])))

## The torso chain a recipe should twist: the context's detected chain, or the
## scalar roles as a fallback so hand-built and 2D contexts still move something.
static func _twist_chain(ctx: Dictionary, roles: Dictionary) -> Array:
	var chain: Array = ctx.get("spine_chain", [])
	if not chain.is_empty():
		return chain
	var out: Array = []
	for role in ["hips", "spine", "chest", "head"]:
		var name := str(roles.get(role, ""))
		if not name.is_empty() and not out.has(name):
			out.append(name)
	return out


## Per-bone twist channels over the chain: one sine plus a second harmonic per
## bone, with the degree values coming from the shared distributor so a recipe
## parameter means the same *total* twist on any rig.
##
## `total_degrees` may be negative (counter-rotation); `weights` and `spread` let
## a recipe choose the shape - the gait uses a hips-leads profile, the idle the
## default. Returns `{bone_name: [channel, ...]}`.
static func _twist_channels(
	ctx: Dictionary, config: Dictionary, total_degrees: float, axis: Vector3,
	weights: Array = [], spread := 1.0, lag_span := 0.06, clamp_degrees := 0.0,
) -> Dictionary:
	var out: Dictionary = {}
	var chain := _twist_chain(ctx, ctx.get("roles", {}))
	if chain.is_empty() or is_zero_approx(total_degrees):
		return out
	var degrees: Array = SpineTwist.amplitudes(
		chain.size(), total_degrees, weights, spread, clamp_degrees)
	var lags: Array = SpineTwist.lags(chain.size(), 0.0, lag_span)
	for index in chain.size():
		var amount := float(degrees[index])
		if is_zero_approx(amount):
			continue
		out[str(chain[index])] = [
			_channel(axis, amount, 1.0, 0.25, float(lags[index]), "sine"),
			_channel(axis, amount * 0.3, 2.0, 0.62, float(lags[index]), "sine"),
		]
	return out


## How far up the chain a twist travels: 0 keeps it on the hips, 1 uses the full
## profile. Overridable per call as `twist_spread`.
static func _spread(config: Dictionary) -> float:
	return clampf(float(config.get("twist_spread", 1.0)), 0.0, 1.0)


## Per-bone lead fractions for a turn sweep: the lead ramps up the torso and the
## head trails it, so the sweep is shared instead of landing on one chest bone.
## Values are multipliers of a step's angle (1.0 = a full step's worth of lead).
static func _lead_shares(chain: Array, head: String) -> Dictionary:
	return _ramp_shares(chain, head, 0.35, 1.0, -0.2)


## Ramps a value from `first` at the lowest bone to `last` at the highest, with a
## separate value for the head. Every value is a multiplier the recipe applies to
## its own amplitude, so the total stays comparable to the old per-bone constants.
static func _ramp_shares(chain: Array, head: String, first: float, last: float, head_value: float) -> Dictionary:
	var out: Dictionary = {}
	var torso: Array = []
	for slot in chain:
		var bone := str(slot)
		if not bone.is_empty():
			torso.append(bone)
	if torso.size() == 1:
		out[str(torso[0])] = 1.0
		return out
	var span := maxf(1.0, float(torso.size() - 1))
	for index in torso.size():
		var bone := str(torso[index])
		if not head.is_empty() and bone == head:
			out[bone] = head_value
		else:
			out[bone] = lerpf(first, last, float(index) / span)
	return out


## Compose a recipe's own channels with any distributed twist for that bone.
static func _compose_with_twist(own: Array, twist: Dictionary, bone: String, t: float) -> Quaternion:
	var channels: Array = own.duplicate(true)
	channels.append_array((twist.get(bone, []) as Array))
	return MotionDrivers.compose_rotation(channels, t)


static func _rest_basis(ctx: Dictionary, bone: String) -> Basis:
	if bone.is_empty():
		return Basis.IDENTITY
	var rest: Dictionary = ctx.rest.get(bone, {})
	return rest.get("global", Basis.IDENTITY)


## Rotation channel. `amplitude`/`offset` are degrees.
static func _channel(
	axis: Vector3, amplitude: float, frequency: float, phase: float, lag: float,
	shape: String, offset: float = 0.0, seed_value: int = 0, harmonics: int = 4,
) -> Dictionary:
	return {
		"axis": axis, "amplitude": amplitude, "frequency": frequency, "phase": phase,
		"lag": lag, "shape": shape, "offset": offset, "seed": seed_value, "harmonics": harmonics,
	}


static func _append_rotation(
	keys: Dictionary, bone: String, time: float, delta: Quaternion, transition: String = "",
) -> void:
	if not keys.has(bone):
		keys[bone] = {"rotation": []}
	var key := {"time": time, "delta": delta.normalized(), "transition": "linear"}
	if not transition.is_empty():
		key["transition"] = transition
	((keys[bone] as Dictionary)["rotation"] as Array).append(key)


static func _append_position(keys: Dictionary, bone: String, time: float, delta: Vector3) -> void:
	if not keys.has(bone):
		keys[bone] = {}
	if not (keys[bone] as Dictionary).has("position"):
		(keys[bone] as Dictionary)["position"] = []
	((keys[bone] as Dictionary)["position"] as Array).append({"time": time, "delta": delta, "transition": "linear"})


## Pelvis offsets are solved in skeleton space, while a bone position track is
## stored in its parent's local space. This conversion is essential when the
## imported root rotates the rig to a Z-up or differently oriented rest pose.
static func _append_hips_position(ctx: Dictionary, keys: Dictionary,
		hips: String, time: float, skeleton_delta: Vector3) -> void:
	var parent_basis: Basis = ctx.get("hips_parent_basis", Basis.IDENTITY)
	_append_position(keys, hips, time, parent_basis.inverse() * skeleton_delta)


## Geometric sign conventions, so the same numbers read the same way on any rig:
## yaw + brings the left hip forward, roll + drops the right hip, lean + tips the
## torso forward, swing + swings a hanging limb forward.
static func _axis_signs(ctx: Dictionary) -> Dictionary:
	var up: Vector3 = ctx.up
	var forward: Vector3 = ctx.forward
	var lateral: Vector3 = ctx.lateral
	var hips_origin: Vector3 = ctx.get("hips_origin", Vector3.ZERO)
	var left_hip: Vector3 = ctx.legs.l.hip
	var right_hip: Vector3 = ctx.legs.r.hip
	return {
		"yaw": 1.0 if up.cross(left_hip - hips_origin).dot(forward) >= 0.0 else -1.0,
		"roll": 1.0 if forward.cross(right_hip - hips_origin).dot(-up) >= 0.0 else -1.0,
		"lean": 1.0 if lateral.cross(up).dot(forward) >= 0.0 else -1.0,
		"swing": 1.0 if lateral.cross(-up).dot(forward) >= 0.0 else -1.0,
	}
