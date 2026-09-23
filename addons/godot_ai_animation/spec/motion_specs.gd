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
		"stride": 24.0,
		"knee_bend": 30.0,
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
	}, style, overrides)


static func run_config(style: String, overrides: Dictionary = {}) -> Dictionary:
	return _resolve_config({
		"stride": 34.0,
		"knee_bend": 55.0,
		"arm_swing": 34.0,
		"bob": 0.08,
		"sway": 0.015,
		"hip_yaw": 8.0,
		"hip_roll": 2.5,
		"chest_yaw": 7.0,
		"lean": 9.0,
		"foot_lift": 0.12,
		"elbow": 65.0,
		"elbow_swing": 12.0,
		"lag": 0.08,
		"stance": 0.36,
		"crouch": 0.0,
	}, style, overrides)


static func idle_config(style: String, overrides: Dictionary = {}) -> Dictionary:
	return _resolve_config({
		"amplitude": 1.6,
		"head_amplitude": 0.8,
		"look": 18.0,
		"twist": 12.0,
		"bob": 0.006,
		"sway": 0.018,
		"shift": 1.4,
		"noise": 0.35,
		"lean": 1.5,
		"arm_sway": 1.4,
		"elbow": 14.0,
	}, style, overrides)


static func _resolve_config(base: Dictionary, style: String, overrides: Dictionary) -> Dictionary:
	var config := base.duplicate(true)
	var multipliers: Dictionary = _STYLE_MULTIPLIERS.get(style, {})
	for key in multipliers:
		var value := float(multipliers[key])
		if key == "crouch_add":
			config["crouch"] = float(config.get("crouch", 0.0)) + value
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
	var crouch := float(config.crouch) + 0.003 * float(config.knee_bend)
	var stance := clampf(float(config.stance), 0.2, 0.8)
	var leg: Dictionary = ctx.legs.l
	var leg_length := float(leg.upper) + float(leg.lower)
	var warnings: Array = []
	var stride_degrees := float(config.stride)
	var speed_target := float(ctx.get("speed", 0.0))
	if speed_target > 0.0:
		# Solve the stride from the requested ground speed:
		# span = 2 * leg_length * sin(stride), speed = span / (stance * duration).
		var max_stride := float(ctx.get("max_stride", 55.0))
		var sin_needed := (speed_target * stance * length) / maxf(2.0 * leg_length, 0.001)
		if sin_needed > sin(deg_to_rad(max_stride)):
			var min_duration := (2.0 * leg_length * sin(deg_to_rad(max_stride))) / maxf(speed_target * stance, 0.0001)
			warnings.append(
				"speed %s m/s needs a stride past the %d deg cap at duration %ss; use duration >= %ss or lower the speed"
				% [snappedf(speed_target, 0.01), int(max_stride), snappedf(length, 0.01), snappedf(min_duration, 0.01)])
			sin_needed = sin(deg_to_rad(max_stride))
		stride_degrees = rad_to_deg(asin(clampf(sin_needed, 0.0, 1.0)))
	var span := 2.0 * leg_length * sin(deg_to_rad(stride_degrees))
	var ground_speed := span / (stance * length)
	var rooted := bool(ctx.get("root_motion", false))
	var travel := ground_speed * length if rooted else 0.0
	var travel_axis: Vector3 = ctx.get("step_axis", forward)
	var lift := float(config.get("foot_lift", 0.05)) * clampf(ground_speed, 0.6, 1.8)
	ctx["foot_lift_scaled"] = lift
	var lag := float(config.lag)
	var hip_yaw := float(config.hip_yaw) * float(signs.yaw)
	var hip_roll := float(config.hip_roll) * float(signs.roll)
	var chest_yaw := -0.8 * hip_yaw
	var lean := float(config.lean) * float(signs.lean)

	var pelvis_rotation := [
		_channel(lateral, hip_yaw, 1.0, 0.0, 0.0, "cosine"),
		_channel(forward, hip_roll, 1.0, 0.0, 0.0, "sine"),
		_channel(lateral, 0.0, 1.0, 0.0, 0.0, "sine", 0.5 * lean),
	]
	var spine_rotation := [
		_channel(up, 0.4 * chest_yaw, 1.0, 0.0, 0.0, "cosine"),
		_channel(lateral, 0.0, 1.0, 0.0, 0.0, "sine", 0.5 * lean),
	]
	var chest_rotation := [
		_channel(up, 0.6 * chest_yaw, 1.0, 0.0, 0.0, "cosine"),
	]
	var head_rotation := [
		_channel(up, -0.5 * chest_yaw, 1.0, 0.0, lag, "cosine"),
		_channel(lateral, 0.0, 1.0, 0.0, 0.0, "sine", -0.35 * lean),
	]
	var bob_channel := _channel(up, -0.5 * float(config.bob), 2.0, 0.0, 0.0, "cosine")
	var sway_channel := _channel(lateral, -float(config.sway), 1.0, 0.0, 0.0, "sine")

	var spine := str(roles.get("spine", ""))
	var chest := str(roles.get("chest", ""))
	var head := str(roles.get("head", ""))

	for index in times.size():
		var t := float(index) / float(steps)
		var time := float(times[index])
		var pelvis_world := MotionDrivers.compose_rotation(pelvis_rotation, t)
		var hips_animated := Basis(pelvis_world) * _rest_basis(ctx, hips)
		var offset: Vector3 = (
			up * (MotionDrivers.channel_value(bob_channel, t) - crouch)
			+ lateral * MotionDrivers.channel_value(sway_channel, t)
			+ travel_axis * (travel * t)
		)
		if not hips.is_empty():
			_append_rotation(keys, hips, time, MotionDrivers.rotation_delta(_rest_basis(ctx, hips), pelvis_world))
			_append_position(keys, hips, time, offset)
		_solve_leg(ctx, keys, "l", t, time, offset, pelvis_world, hips_animated, hips_origin, stance, span, ground_speed, rooted, length)
		_solve_leg(ctx, keys, "r", t, time, offset, pelvis_world, hips_animated, hips_origin, stance, span, ground_speed, rooted, length)
		if not spine.is_empty() and spine != chest:
			var world := MotionDrivers.compose_rotation(spine_rotation, t)
			_append_rotation(keys, spine, time, MotionDrivers.rotation_delta(_rest_basis(ctx, spine), world))
		if not chest.is_empty():
			var world := MotionDrivers.compose_rotation(chest_rotation, t)
			_append_rotation(keys, chest, time, MotionDrivers.rotation_delta(_rest_basis(ctx, chest), world))
		if not head.is_empty():
			var world := MotionDrivers.compose_rotation(head_rotation, t)
			_append_rotation(keys, head, time, MotionDrivers.rotation_delta(_rest_basis(ctx, head), world))
		_solve_arms(ctx, keys, time, t)

	# A rooted cycle ends further forward than it started: the hips travel must
	# survive the loop-closing pass, so opt the hips position track out of it.
	if rooted and not is_zero_approx(travel) and keys.has(hips):
		(keys[hips] as Dictionary)["loop_close"] = false
	return {
		"keys": keys,
		"markers": _gait_markers(length, stance),
		"meta": {
			"speed": ground_speed,
			"stride_used": stride_degrees,
			"cadence": 120.0 / length,
			"warnings": warnings,
		},
	}


static func _solve_leg(
	ctx: Dictionary, keys: Dictionary, side: String, t: float, time: float,
	offset: Vector3, pelvis_world: Quaternion, hips_animated: Basis, hips_origin: Vector3,
	stance: float, span: float, ground_speed: float, rooted: bool, length: float,
) -> void:
	var leg: Dictionary = ctx.legs[side]
	var up: Vector3 = ctx.up
	var step_axis: Vector3 = ctx.get("step_axis", ctx.forward)
	var knee_hint: Vector3 = ctx.get("knee_hint", ctx.forward)
	var side_offset := 0.0 if side == "l" else 0.5
	var p := fposmod(t + side_offset, 1.0)
	var foot := _foot_trajectory(p, stance, span, ground_speed, length, rooted)
	var lift := float(ctx.get("foot_lift_scaled", (ctx.config as Dictionary).get("foot_lift", 0.05)))
	var ankle_target: Vector3 = (
		leg.ankle + step_axis * float(foot.forward)
		+ up * (lift * float(foot.height))
	)
	var hip_pos: Vector3 = hips_origin + offset + Basis(pelvis_world) * (leg.hip - hips_origin)
	var knee := MotionDrivers.knee_position(hip_pos, ankle_target, float(leg.upper), float(leg.lower), knee_hint)
	var hips_rest := _rest_basis(ctx, ctx.get("hips", ""))
	var thigh_rest := _rest_basis(ctx, leg.thigh)
	var shin_rest := _rest_basis(ctx, leg.shin)
	var thigh_solve := MotionDrivers.aim_delta(hips_animated, hips_rest, thigh_rest, (knee - hip_pos).normalized())
	var shin_solve := MotionDrivers.aim_delta(thigh_solve.global, thigh_rest, shin_rest, (ankle_target - knee).normalized())
	_append_rotation(keys, leg.thigh, time, thigh_solve.delta)
	_append_rotation(keys, leg.shin, time, shin_solve.delta)
	var foot_bone := str(leg.get("foot", ""))
	if foot_bone.is_empty():
		return
	# Foot roll: keep the sole flat while planted, pitch it through heel strike
	# and toe-off, and hold the toe on the ground while the foot rolls over it.
	var foot_rest := _rest_basis(ctx, foot_bone)
	var pitch_axis := _foot_pitch_axis(ctx, leg, knee_hint)
	var roll := float((ctx.config as Dictionary).get("toe_roll", 1.0))
	var pitch := _foot_pitch_curve(p, stance, 8.0 * roll, 18.0 * roll)
	var foot_target := Basis(Quaternion(pitch_axis, deg_to_rad(pitch))) * foot_rest
	var delta := MotionDrivers.hold_global_delta(shin_solve.global, shin_rest, foot_rest, foot_target)
	var weight := _foot_plant_weight(p, stance)
	_append_rotation(keys, foot_bone, time, Quaternion.IDENTITY.slerp(delta, weight))
	var toe_bone := str(leg.get("toe", ""))
	if toe_bone.is_empty():
		return
	var toe_rest := _rest_basis(ctx, toe_bone)
	var toe_hold := MotionDrivers.hold_global_delta(foot_target, foot_rest, toe_rest, toe_rest)
	var toe_weight := weight if pitch < -1.0 else 0.0
	_append_rotation(keys, toe_bone, time, Quaternion.IDENTITY.slerp(toe_hold, toe_weight))


static func _solve_arms(ctx: Dictionary, keys: Dictionary, time: float, t: float) -> void:
	var config: Dictionary = ctx.config
	var arm_swing := float(config.arm_swing)
	var elbow := float(config.elbow)
	var elbow_swing := float(config.get("elbow_swing", 0.6 * arm_swing))
	var lag := float(config.lag)
	var phase := cos(TAU * (t - lag))
	for side in ["l", "r"]:
		var sign := -1.0 if side == "l" else 1.0
		# `_solve_arm_chain`'s hinge is positive-forward by construction, so the
		# side sign alone phases the swing: left arm back at t=0, forward at t=0.5
		# (same side leg forward). The elbow straightens at the back and bends as
		# the arm comes forward.
		var swing_degrees := sign * arm_swing * phase
		var forward_weight := (1.0 - phase) * 0.5 if side == "l" else (1.0 + phase) * 0.5
		var bend_degrees := elbow + elbow_swing * forward_weight
		_solve_arm_chain(ctx, keys, side, time, swing_degrees, bend_degrees)


## One arm from the shoulder down: lower it by the rig's `arm_down`, swing it
## about a sagittal hinge (so the hand travels forward/back, never sideways),
## then flex the elbow about that same world hinge using the animated shoulder
## basis. Conjugating the bend by the rest frame - as this used to - turned the
## hinge with the lowered arm and curled the forearm across the body.
static func _solve_arm_chain(
	ctx: Dictionary, keys: Dictionary, side: String, time: float,
	swing_degrees: float, bend_degrees: float, transition: String = "",
) -> void:
	var roles: Dictionary = ctx.roles
	var forward: Vector3 = ctx.forward
	var arm := str(roles.get("arm_" + side, ""))
	if arm.is_empty():
		return
	var g_arm := _rest_basis(ctx, arm)
	var down_delta: Quaternion = (ctx.get("arm_down", {}) as Dictionary).get(side, Quaternion.IDENTITY)
	var down_world := (g_arm * Basis(down_delta) * g_arm.inverse()).get_rotation_quaternion()
	var hang_dir := ((Basis(down_world) * g_arm) * Vector3.UP).normalized()
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
	var arm_animated := Basis(arm_world) * g_arm
	_append_rotation(keys, forearm, time, MotionDrivers.world_delta(
		arm_animated, g_arm, _rest_basis(ctx, forearm), Quaternion(hinge, deg_to_rad(bend_degrees))), transition)


## Relative forward/height motion of one ankle over a cycle. `p` is the foot's
## local phase (0 = contact). In-place cycles slide the planted foot backwards;
## with root motion the foot stays put in skeleton space while the body travels.
static func _foot_trajectory(p: float, stance: float, span: float, ground_speed: float, length: float, rooted: bool) -> Dictionary:
	var local_phase := fposmod(p, 1.0)
	if local_phase < stance:
		if rooted:
			var contact_time := -local_phase * length
			return {"forward": 0.5 * span + ground_speed * contact_time, "height": 0.0}
		return {"forward": span * (0.5 - local_phase / stance), "height": 0.0}
	var swing := (local_phase - stance) / maxf(1.0 - stance, 0.001)
	var from := -0.5 * span
	var to := 0.5 * span
	if rooted:
		from = 0.5 * span - ground_speed * stance * length
		to = from + ground_speed * length
	return {"forward": lerpf(from, to, MotionDrivers.smoothstep(swing)), "height": 1.0}


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
		"passing.R": fposmod((0.5 + stance + 1.0) * 0.5 * length, maxf(length, 0.001)),
	}
	var out: Array = []
	for marker_name in times:
		out.append({"name": marker_name, "time": clampf(float(times[marker_name]), 0.0, length)})
	return out


# --- strafe -----------------------------------------------------------------

## Sideways gait: the walk solver with the foot trajectory along the character's
## lateral axis while the knees keep bending forward.
static func strafe_keys(ctx: Dictionary, direction: String) -> Dictionary:
	var side_sign := 1.0 if direction == "left" else -1.0
	var strafe_ctx := ctx.duplicate()
	strafe_ctx["step_axis"] = (ctx.lateral as Vector3) * side_sign
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
		"foot_lift": 0.05,
	}, style, overrides)


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
	var phases := [
		{"t": 0.0, "y": 0.0, "air": false, "lean": 0.0, "swing": 0.0, "bend": float(config.get("elbow", 12.0))},
		{"t": 0.2, "y": -crouch, "air": false, "lean": 0.5, "swing": -0.9, "bend": float(config.get("elbow", 12.0)) + 15.0},
		{"t": 0.3, "y": -0.08 * crouch, "air": false, "lean": 0.15, "swing": 0.45, "bend": float(config.get("elbow", 12.0)) + 8.0},
		{"t": 0.47, "y": height, "air": true, "lean": -0.2, "swing": 1.0, "bend": float(config.get("elbow", 12.0)) + 20.0},
		{"t": 0.62, "y": 0.82 * height, "air": true, "lean": 0.1, "swing": 0.55, "bend": float(config.get("elbow", 12.0)) + 10.0},
		{"t": 0.74, "y": 0.06 * height, "air": false, "lean": 0.25, "swing": 0.1, "bend": float(config.get("elbow", 12.0)) + 6.0},
		{"t": 0.84, "y": -0.85 * crouch, "air": false, "lean": 0.55, "swing": -0.5, "bend": float(config.get("elbow", 12.0)) + 18.0},
		{"t": 1.0, "y": 0.0, "air": false, "lean": 0.0, "swing": 0.0, "bend": float(config.get("elbow", 12.0))},
	]
	for phase in phases:
		var time := float(phase.t) * length
		var travel := forward * (distance * float(phase.t))
		var offset := up * float(phase.y) + travel
		var world := Quaternion(ctx.lateral, deg_to_rad(float(phase.lean) * lean))
		var hips_animated := Basis(world) * hips_rest
		if not hips.is_empty():
			_append_rotation(keys, hips, time, MotionDrivers.rotation_delta(hips_rest, world))
			_append_position(keys, hips, time, offset)
		for side in ["l", "r"]:
			var leg: Dictionary = ctx.legs[side]
			var hip_pos: Vector3 = hips_origin + offset + Basis(world) * (leg.hip - hips_origin)
			var ankle_target: Vector3 = leg.ankle + travel
			if bool(phase.air):
				ankle_target += up * (float(phase.y) * 0.55)
			var knee := MotionDrivers.knee_position(hip_pos, ankle_target, float(leg.upper), float(leg.lower), forward)
			var thigh_rest := _rest_basis(ctx, leg.thigh)
			var shin_rest := _rest_basis(ctx, leg.shin)
			var thigh_solve := MotionDrivers.aim_delta(hips_animated, hips_rest, thigh_rest, (knee - hip_pos).normalized())
			var shin_solve := MotionDrivers.aim_delta(thigh_solve.global, thigh_rest, shin_rest, (ankle_target - knee).normalized())
			var transition := "ease_in_out" if float(phase.t) < 0.7 else "ease_out"
			_append_rotation(keys, leg.thigh, time, thigh_solve.delta, transition)
			_append_rotation(keys, leg.shin, time, shin_solve.delta, transition)
			var foot_bone := str(leg.get("foot", ""))
			if not foot_bone.is_empty():
				var foot_rest := _rest_basis(ctx, foot_bone)
				var flat := MotionDrivers.hold_global_delta(shin_solve.global, shin_rest, foot_rest, foot_rest)
				_append_rotation(keys, foot_bone, time, Quaternion.IDENTITY.slerp(flat, 0.0 if bool(phase.air) else 1.0), transition)
		var spine := str(roles.get("spine", ""))
		var chest := str(roles.get("chest", ""))
		if not spine.is_empty() and spine != chest:
			var spine_world := Quaternion(ctx.lateral, deg_to_rad(float(phase.lean) * lean * 0.5))
			_append_rotation(keys, spine, time, MotionDrivers.rotation_delta(_rest_basis(ctx, spine), spine_world), "ease_in_out")
		if not chest.is_empty():
			var chest_world := Quaternion(ctx.lateral, deg_to_rad(float(phase.lean) * lean * 0.4))
			_append_rotation(keys, chest, time, MotionDrivers.rotation_delta(_rest_basis(ctx, chest), chest_world), "ease_in_out")
		var arm_swing := float(phase.swing) * float(config.get("arm_swing", 65.0))
		_solve_arm_chain(ctx, keys, "l", time, -arm_swing, float(phase.bend), "ease_in_out")
		_solve_arm_chain(ctx, keys, "r", time, -arm_swing, float(phase.bend), "ease_in_out")
	var markers := [
		{"name": "takeoff", "time": 0.3 * length},
		{"name": "apex", "time": 0.47 * length},
		{"name": "land", "time": 0.8 * length},
	]
	return {
		"keys": keys,
		"markers": markers,
		"meta": {"height": height, "crouch": crouch, "distance": distance},
	}


# --- turn -------------------------------------------------------------------

static func turn_config(style: String, overrides: Dictionary = {}) -> Dictionary:
	return _resolve_config({
		"turn_angle": 90.0,
		"arm_swing": 12.0,
		"elbow": 12.0,
		"lean": 4.0,
		"foot_lift": 0.05,
	}, style, overrides)


## An in-place pivot turn: anticipation, a body sweep with one foot lifting and
## re-planting, then a settle. One-shot; `angle` is signed by `direction`.
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
	var keys := {}
	var hips_origin: Vector3 = ctx.get("hips_origin", Vector3.ZERO)
	var hips_rest := _rest_basis(ctx, hips)
	var phases := [
		{"t": 0.0, "yaw": 0.0, "bob": 0.0, "arm": 0.0},
		{"t": 0.14, "yaw": -0.06 * angle, "bob": -0.02, "arm": -0.25},
		{"t": 0.55, "yaw": 0.72 * angle, "bob": -0.035, "arm": 0.55},
		{"t": 0.8, "yaw": 1.045 * angle, "bob": -0.012, "arm": 0.2},
		{"t": 1.0, "yaw": angle, "bob": 0.0, "arm": 0.0},
	]
	var step_side := "r" if direction == "left" else "l"
	for phase in phases:
		var time := float(phase.t) * length
		var world := Quaternion(up, deg_to_rad(float(phase.yaw) * float(signs.yaw)))
		var hips_animated := Basis(world) * hips_rest
		var offset := up * float(phase.bob)
		if not hips.is_empty():
			_append_rotation(keys, hips, time, MotionDrivers.rotation_delta(hips_rest, world))
			_append_position(keys, hips, time, offset)
		for side in ["l", "r"]:
			var leg: Dictionary = ctx.legs[side]
			var lift := 0.0
			if side == step_side:
				# The trailing foot lifts through the middle of the turn.
				var mid := absf(float(phase.t) - 0.5)
				lift = maxf(0.0, 1.0 - mid / 0.3) * float(config.get("foot_lift", 0.05))
			var hip_pos: Vector3 = hips_origin + offset + Basis(world) * (leg.hip - hips_origin)
			var ankle_target: Vector3 = hips_origin + Basis(world) * (leg.ankle - hips_origin) + up * lift
			var knee := MotionDrivers.knee_position(hip_pos, ankle_target, float(leg.upper), float(leg.lower), ctx.forward)
			var thigh_rest := _rest_basis(ctx, leg.thigh)
			var shin_rest := _rest_basis(ctx, leg.shin)
			var thigh_solve := MotionDrivers.aim_delta(hips_animated, hips_rest, thigh_rest, (knee - hip_pos).normalized())
			var shin_solve := MotionDrivers.aim_delta(thigh_solve.global, thigh_rest, shin_rest, (ankle_target - knee).normalized())
			_append_rotation(keys, leg.thigh, time, thigh_solve.delta, "ease_in_out")
			_append_rotation(keys, leg.shin, time, shin_solve.delta, "ease_in_out")
			var foot_bone := str(leg.get("foot", ""))
			if not foot_bone.is_empty():
				var foot_rest := _rest_basis(ctx, foot_bone)
				# The planted foot turns with the body; the stepping one follows.
				var foot_target := Basis(world) * foot_rest
				var flat := MotionDrivers.hold_global_delta(shin_solve.global, shin_rest, foot_rest, foot_target)
				_append_rotation(keys, foot_bone, time, Quaternion.IDENTITY.slerp(flat, 0.0 if lift > 0.001 else 1.0), "ease_in_out")
		var chest := str(roles.get("chest", ""))
		if not chest.is_empty():
			# The chest and head lead the turn, then settle back.
			var lead := 0.28 if float(phase.t) < 0.6 else 0.08
			var chest_world := Quaternion(up, deg_to_rad(float(phase.yaw) * float(signs.yaw) * (1.0 + lead)))
			_append_rotation(keys, chest, time, MotionDrivers.rotation_delta(_rest_basis(ctx, chest), chest_world), "ease_in_out")
		var head := str(roles.get("head", ""))
		if not head.is_empty():
			var head_world := Quaternion(up, deg_to_rad(float(phase.yaw) * float(signs.yaw) * 0.25))
			_append_rotation(keys, head, time, MotionDrivers.rotation_delta(_rest_basis(ctx, head), head_world), "ease_in_out")
		# Arms counterbalance the sweep so a T-pose rest does not stay spread.
		var arm_swing := float(config.get("arm_swing", 12.0)) * float(phase.arm)
		_solve_arm_chain(ctx, keys, "l", time, arm_swing, float(config.get("elbow", 12.0)) + 8.0, "ease_in_out")
		_solve_arm_chain(ctx, keys, "r", time, arm_swing, float(config.get("elbow", 12.0)) + 8.0, "ease_in_out")
	var markers := [
		{"name": "anticipate", "time": 0.14 * length},
		{"name": "step", "time": 0.5 * length},
		{"name": "settle", "time": 0.8 * length},
	]
	return {
		"keys": keys,
		"markers": markers,
		"meta": {"angle": angle, "direction": direction},
	}


# --- gait transitions -------------------------------------------------------

## Blend into (`walk_start`) or out of (`walk_stop`) a gait. The gait-facing end
## is sampled from `gait_keys` at `phase`, so the transition matches the cycle
## frame-for-frame and can be cross-faded or concatenated.
static func transition_keys(ctx: Dictionary, stopping: bool) -> Dictionary:
	var length := maxf(float(ctx.length), 0.01)
	var phase := clampf(float(ctx.get("phase", 0.0)), 0.0, 0.999)
	var gait := gait_keys(ctx, false)
	var gait_keys_dict: Dictionary = gait.keys
	var target_time := phase * float(ctx.length)
	var keys := {}
	for bone in gait_keys_dict:
		var source: Dictionary = gait_keys_dict[bone]
		var entry := {}
		if source.has("rotation"):
			var target_rotation: Quaternion = _nearest_delta(source.rotation, target_time)
			var rotation_keys: Array = []
			if stopping:
				rotation_keys.append({"time": 0.0, "delta": target_rotation, "transition": "ease_in_out"})
				rotation_keys.append({"time": length, "delta": Quaternion.IDENTITY, "transition": "ease_in_out"})
			else:
				rotation_keys.append({"time": 0.0, "delta": Quaternion.IDENTITY, "transition": "ease_out"})
				rotation_keys.append({"time": length * 0.3, "delta": target_rotation.slerp(Quaternion.IDENTITY, 0.35).normalized(), "transition": "ease_in"})
				rotation_keys.append({"time": length, "delta": target_rotation, "transition": "ease_in_out"})
			entry["rotation"] = rotation_keys
		if source.has("position"):
			var target_position: Vector3 = _nearest_vec(source.position, target_time)
			var position_keys: Array = []
			if stopping:
				position_keys.append({"time": 0.0, "delta": target_position, "transition": "ease_in_out"})
				position_keys.append({"time": length, "delta": Vector3.ZERO, "transition": "ease_in_out"})
			else:
				position_keys.append({"time": 0.0, "delta": Vector3.ZERO, "transition": "ease_out"})
				position_keys.append({"time": length, "delta": target_position, "transition": "ease_in_out"})
			entry["position"] = position_keys
		if not entry.is_empty():
			keys[bone] = entry
	return {
		"keys": keys,
		"markers": [{"name": "settled", "time": length}],
		"meta": {"phase": phase},
	}


static func _nearest_delta(rotation_keys: Array, time: float) -> Quaternion:
	var best := Quaternion.IDENTITY
	var best_distance := INF
	for key in rotation_keys:
		var distance := absf(float(key.get("time", 0.0)) - time)
		if distance < best_distance:
			best_distance = distance
			best = key.get("delta", Quaternion.IDENTITY)
	return best


static func _nearest_vec(position_keys: Array, time: float) -> Vector3:
	var best := Vector3.ZERO
	var best_distance := INF
	for key in position_keys:
		var distance := absf(float(key.get("time", 0.0)) - time)
		if distance < best_distance:
			best_distance = distance
			best = key.get("delta", Vector3.ZERO)
	return best


# --- idle -------------------------------------------------------------------

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
	var breath := [_channel(lateral, -float(config.amplitude) * scale, 1.0, 0.0, 0.0, "sine")]
	var spine_motion := [
		_channel(lateral, -0.6 * float(config.amplitude) * scale, 1.0, 0.0, 0.03, "sine"),
		_channel(up, 0.5 * twist, 1.0, 0.25, 0.05, "sine"),
		_channel(up, 0.15 * twist, 2.0, 0.62, 0.05, "sine"),
		_channel(lateral, 0.15 * twist, 1.0, 0.25, 0.08, "sine"),
	]
	var chest_motion := [
		_channel(up, twist, 1.0, 0.25, 0.0, "sine"),
		_channel(up, 0.3 * twist, 2.0, 0.62, 0.0, "sine"),
		_channel(lateral, 0.25 * twist, 1.0, 0.25, 0.05, "sine"),
	]
	var head_motion := [
		_channel(up, look, 1.0, 0.25, 0.02, "sine"),
		_channel(up, 0.3 * look, 2.0, 0.62, 0.02, "sine"),
		_channel(lateral, -0.35 * float(config.head_amplitude), 1.0, 0.0, 0.06, "sine"),
		_channel(forward, 0.12 * look, 1.0, 0.25, 0.05, "sine"),
	]
	var noise_amount := float(config.noise)
	if not is_zero_approx(noise_amount):
		spine_motion.append(_channel(up, noise_amount * scale, 1.0, 0.0, 0.0, "noise", 0.0, 21, 3))
		spine_motion.append(_channel(lateral, noise_amount * scale, 1.0, 0.35, 0.0, "noise", 0.0, 22, 3))
		head_motion.append(_channel(up, 0.8 * noise_amount * scale, 1.0, 0.0, 0.0, "noise", 0.0, 23, 3))
		head_motion.append(_channel(lateral, 0.6 * noise_amount * scale, 1.0, 0.5, 0.0, "noise", 0.0, 24, 3))
	var lean := float(config.lean)
	var sway_channel := _channel(lateral, -float(config.sway), 1.0, 0.0, 0.0, "sine")
	var bob_channel := _channel(up, -0.5 * float(config.bob), 2.0, 0.0, 0.0, "cosine")
	var roll_channel := _channel(forward, float(config.shift) * float(signs.roll), 1.0, 0.0, 0.0, "sine")
	var hips_yaw_channel := _channel(up, -0.2 * twist, 1.0, 0.25, 0.03, "sine")

	for index in times.size():
		var t := float(index) / float(steps)
		var time := float(times[index])
		if not hips.is_empty():
			var world := (
				Quaternion(lateral, deg_to_rad(-lean * 0.35 * scale))
				* Quaternion(forward, deg_to_rad(MotionDrivers.channel_value(roll_channel, t)))
				* Quaternion(up, deg_to_rad(MotionDrivers.channel_value(hips_yaw_channel, t)))
			)
			_append_rotation(keys, hips, time, MotionDrivers.rotation_delta(_rest_basis(ctx, hips), world))
			_append_position(keys, hips, time,
				lateral * MotionDrivers.channel_value(sway_channel, t)
				+ up * MotionDrivers.channel_value(bob_channel, t))
		var spine := str(roles.get("spine", ""))
		var chest := str(roles.get("chest", ""))
		var head := str(roles.get("head", ""))
		if not spine.is_empty() and spine != chest:
			var world := MotionDrivers.compose_rotation(spine_motion, t) * Quaternion(lateral, deg_to_rad(-lean * 0.5 * scale))
			_append_rotation(keys, spine, time, MotionDrivers.rotation_delta(_rest_basis(ctx, spine), world))
		if not chest.is_empty():
			var world := (
				MotionDrivers.compose_rotation(chest_motion, t)
				* MotionDrivers.compose_rotation(breath, t)
				* Quaternion(lateral, deg_to_rad(-lean * 0.5 * scale))
			)
			_append_rotation(keys, chest, time, MotionDrivers.rotation_delta(_rest_basis(ctx, chest), world))
		if not head.is_empty():
			var world := MotionDrivers.compose_rotation(head_motion, t) * Quaternion(lateral, deg_to_rad(lean * 0.4 * scale))
			_append_rotation(keys, head, time, MotionDrivers.rotation_delta(_rest_basis(ctx, head), world))
		_solve_idle_arms(ctx, keys, time, t)
	return {"keys": keys, "markers": [], "meta": {}}


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
		"swing": 1.0 if lateral.cross(Vector3.DOWN).dot(forward) >= 0.0 else -1.0,
	}
