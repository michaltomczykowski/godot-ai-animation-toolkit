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
	# The torso counter-rotation: the hips lead, the spine and chest follow the
	# other way, the head stabilises. Expressed as chain weights so it holds on
	# any spine, and `chest_yaw` (previously shadowed by a local of the same name
	# and therefore dead) now scales the counter for rigs that want more or less.
	var counter := absf(float(config.get("chest_yaw", -0.8))) * 0.8
	var lean := float(config.lean) * float(signs.lean)

	var pelvis_rotation := [
		_channel(lateral, hip_yaw, 1.0, 0.0, 0.0, "cosine"),
		_channel(forward, hip_roll, 1.0, 0.0, 0.0, "sine"),
		_channel(lateral, 0.0, 1.0, 0.0, 0.0, "sine", 0.5 * lean),
	]
	# hips lead forward, everything above counter-rotates: [hips, spine, chest,
	# head] as [-counter on the torso, half back on the head to stabilise].
	var torso_weights := [0.0, -counter, -counter, counter * 0.5]
	var torso_channels := _twist_channels(
		ctx, config, hip_yaw, up, torso_weights, _spread(config), lag)
	var spine_lean := [_channel(lateral, 0.0, 1.0, 0.0, 0.0, "sine", 0.5 * lean)]
	var head_lean := [_channel(lateral, 0.0, 1.0, 0.0, 0.0, "sine", -0.35 * lean)]
	var bob_channel := _channel(up, -0.5 * float(config.bob), 2.0, 0.0, 0.0, "cosine")
	var sway_channel := _channel(lateral, -float(config.sway), 1.0, 0.0, 0.0, "sine")

	var chain := _twist_chain(ctx, roles)
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
		# The hips carry no twist share (the pelvis channels already lead), so
		# every chain bone above them is keyed from the distributed torso channels.
		for slot in chain:
			var bone := str(slot)
			if bone == hips or bone.is_empty():
				continue
			var own: Array = head_lean if bone == head else spine_lean
			var world := _compose_with_twist(own, torso_channels, bone, t)
			_append_rotation(keys, bone, time, MotionDrivers.rotation_delta(_rest_basis(ctx, bone), world))
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
	var foot := _foot_trajectory(p, stance, span, ground_speed, length, rooted, side_offset)
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
## local phase (0 = contact) and `phase_offset` which half-cycle the foot leads
## by (0 left, 0.5 right). In-place cycles slide the planted foot backwards in
## clip space, which is what cancels the body's motion when the game moves the
## character; with root motion the body travels *inside* the clip, so each stance
## holds a fixed world point and the swing covers the stride to the next one.
static func _foot_trajectory(p: float, stance: float, span: float, ground_speed: float, length: float, rooted: bool, phase_offset: float = 0.0) -> Dictionary:
	var local_phase := fposmod(p, 1.0)
	if local_phase < stance:
		if rooted:
			# The leg rotations are aimed at this target with the hips already
			# travelled, so the foot lands *on* it: holding the target still during
			# the stance is what plants the foot in the world. The trailing foot
			# holds the point half a stride behind, so the two never share one.
			return {
				"forward": 0.5 * span + phase_offset * ground_speed * length,
				"height": 0.0,
			}
		return {"forward": span * (0.5 - local_phase / stance), "height": 0.0}
	var swing := (local_phase - stance) / maxf(1.0 - stance, 0.001)
	var from := -0.5 * span
	var to := 0.5 * span
	if rooted:
		# The swing closes the gap to this stance's point, which is one stride
		# ahead of the one it just left.
		var travel := ground_speed * length
		from = 0.5 * span + (phase_offset - 1.0) * travel
		to = 0.5 * span + phase_offset * travel
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
	return {"forward": lerpf(from, to, MotionDrivers.smoothstep(swing)), "height": height}


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
	# The lean ramp over the torso: [spine, chest, head] used to take 0.5/0.4/0.0
	# of the lean, i.e. 0.9 total with the head left behind.
	var lean_chain := _twist_chain(ctx, roles)
	var lean_shares := _ramp_shares(lean_chain, str(roles.get("head", "")), 0.35, 0.5, 0.25)
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
	var phases := [
		{"t": 0.0, "yaw": 0.0, "bob": 0.0, "arm": 0.0},
		{"t": 0.14, "yaw": -0.06 * step_angle, "bob": -0.02, "arm": -0.25},
		{"t": 0.55, "yaw": 0.72 * step_angle, "bob": -0.035, "arm": 0.55},
		{"t": 0.8, "yaw": 1.045 * step_angle, "bob": -0.012, "arm": 0.2},
		{"t": 1.0, "yaw": step_angle, "bob": 0.0, "arm": 0.0},
	]
	# Lead distribution over the torso above the hips: the chest leads the sweep,
	# the head trails it, and any extra spine bone splits the difference.
	var lead_chain := _twist_chain(ctx, roles)
	var lead_shares := _lead_shares(lead_chain, str(roles.get("head", "")))
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
			var offset := up * float(phase.bob)
			if not hips.is_empty():
				_append_rotation(keys, hips, time, MotionDrivers.rotation_delta(hips_rest, world))
				_append_position(keys, hips, time, offset)
			for side in ["l", "r"]:
				var leg: Dictionary = ctx.legs[side]
				var lift := 0.0
				if side == step_side:
					# The trailing foot lifts through the middle of the step.
					var mid := absf(local - 0.5)
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
	var gait_keys_dict: Dictionary = gait.keys
	var target_time := phase * float(ctx.length)
	var keys := {}
	for bone in gait_keys_dict:
		var source: Dictionary = gait_keys_dict[bone]
		var entry := {}
		if source.has("rotation"):
			var target_rotation: Quaternion = _delta_at(source.rotation, target_time)
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
			var target_position: Vector3 = _vec_at(source.position, target_time)
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
			_append_position(keys, hips, time, hips_offset)
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
			var lean_share := lean * 0.4 * scale if bone == head else -lean * 0.5 * scale
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
	var knee := MotionDrivers.knee_position(hip_pos, ankle_target, float(leg.upper), float(leg.lower), knee_hint)
	var thigh_rest := _rest_basis(ctx, leg.thigh)
	var shin_rest := _rest_basis(ctx, leg.shin)
	var hips_rest := _rest_basis(ctx, ctx.get("hips", ""))
	var thigh_solve := MotionDrivers.aim_delta(hips_animated, hips_rest, thigh_rest, (knee - hip_pos).normalized())
	var shin_solve := MotionDrivers.aim_delta(thigh_solve.global, thigh_rest, shin_rest, (ankle_target - knee).normalized())
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
