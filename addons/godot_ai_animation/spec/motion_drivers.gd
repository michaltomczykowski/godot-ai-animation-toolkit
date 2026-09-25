@tool
extends RefCounted

## Pure procedural-motion math for the `animation_motion` family. No Skeleton3D,
## no editor, no undo: curves, noise, rest-relative rotation conversion and the
## two-bone leg solve all take plain numbers/transforms so this layer is tier-1
## testable.
##
## Conventions:
## - Channels are dictionaries:
##     {"axis": Vector3, "amplitude": float, "frequency": float, "phase": float,
##      "shape": "sine"|"cosine"|"triangle"|"noise", "offset": float,
##      "lag": float, "seed": int, "harmonics": int}
##   `amplitude` is degrees for rotation channels and metres for position ones.
##   `frequency` is cycles per clip (integer for a seamless loop).
##   `lag` delays the curve by that many cycles (follow-through).
## - Channels on one bone compose in list order, world rotation first to last:
##     R(t) = R0(t) * R1(t) * ...
## - Rotations are given in the skeleton's space (battle-tested: convert to the
##   bone's local frame with `rotation_delta`, which conjugates by the bone's
##   global rest basis).

const _EPSILON := 0.000001


# --- sampling ---------------------------------------------------------------

## Number of sampled intervals for a clip. At least 2 so a curve has a shape.
static func sample_count(length: float, samples_per_second: float) -> int:
	return maxi(2, int(round(maxf(length, 0.001) * maxf(samples_per_second, 1.0))))


## Sample times from 0 to `length` inclusive: `sample_count + 1` keys. A loop
## closes exactly because the last sample re-evaluates the first phase.
static func sample_times(length: float, samples_per_second: float) -> PackedFloat32Array:
	var count := sample_count(length, samples_per_second)
	var out := PackedFloat32Array()
	for index in count + 1:
		out.append(length * float(index) / float(count))
	return out


# --- signals ----------------------------------------------------------------

## Value of one signal shape at `x` cycles (phase already folded in). Bounded to
## [-1, 1].
static func signal_value(shape: String, x: float, seed_value: int = 0, harmonics: int = 4) -> float:
	match shape:
		"cosine":
			return cos(TAU * x)
		"triangle":
			return 4.0 * absf(fposmod(x, 1.0) - 0.5) - 1.0
		"noise":
			return periodic_noise(x, seed_value, harmonics)
		_:
			return sin(TAU * x)


## Deterministic, perfectly periodic noise: a sum of integer harmonics with
## random phases. Same seed always gives the same curve, and x and x+1 are equal,
## so it can drive a seamless loop.
static func periodic_noise(x: float, seed_value: int, harmonics: int = 4) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var total := 0.0
	var norm := 0.0
	for harmonic in range(1, maxi(1, harmonics) + 1):
		var amplitude := 1.0 / float(harmonic)
		total += amplitude * sin(TAU * (float(harmonic) * x + rng.randf()))
		norm += amplitude
	return total / maxf(norm, _EPSILON)


## Evaluate a channel at normalized clip time `t` (0..1). Returns degrees for
## rotation channels and metres for position channels.
static func channel_value(channel: Dictionary, t: float) -> float:
	var amplitude := float(channel.get("amplitude", 0.0))
	var offset := float(channel.get("offset", 0.0))
	if is_zero_approx(amplitude):
		return offset
	var frequency := float(channel.get("frequency", 1.0))
	var phase := float(channel.get("phase", 0.0)) - float(channel.get("lag", 0.0))
	var shaped := signal_value(
		str(channel.get("shape", "sine")), frequency * t + phase,
		int(channel.get("seed", 0)), int(channel.get("harmonics", 4)))
	return offset + amplitude * shaped


## Per-sample values of one channel (length = sample_count + 1).
static func channel_samples(channel: Dictionary, length: float, samples_per_second: float) -> PackedFloat32Array:
	var times := sample_times(length, samples_per_second)
	var out := PackedFloat32Array()
	for time in times:
		out.append(channel_value(channel, time / maxf(length, _EPSILON)))
	return out


# --- rotation conversion ----------------------------------------------------

## Compose a list of world-space rotation channels at `t` into one quaternion.
static func compose_rotation(channels: Array, t: float) -> Quaternion:
	var rotation := Quaternion.IDENTITY
	for channel in channels:
		var degrees := channel_value(channel, t)
		if is_zero_approx(degrees):
			continue
		var axis: Vector3 = channel.get("axis", Vector3.RIGHT)
		if axis.length_squared() < _EPSILON:
			continue
		rotation = rotation * Quaternion(axis.normalized(), deg_to_rad(degrees))
	return rotation.normalized()


## A world-space rotation applied to a bone, converted to the bone-local delta
## that `Animation` rotation tracks store. `global_rest` is the bone's global
## rest basis; the identity world rotation keeps the bone at rest.
static func rotation_delta(global_rest: Basis, world_rotation: Quaternion) -> Quaternion:
	var rest := global_rest.orthonormalized()
	return (rest.inverse() * Basis(world_rotation) * rest).get_rotation_quaternion().normalized()


## Pose delta that points a bone along `desired_dir` (skeleton space, i.e. along
## its local +Y at rest) while its parent animates. Returns
## {"delta": Quaternion, "global": Basis} where `global` is the bone's resulting
## global basis, ready to chain into a child.
static func aim_delta(
	parent_animated: Basis, parent_global_rest: Basis, bone_global_rest: Basis, desired_dir: Vector3,
) -> Dictionary:
	var target := desired_dir.normalized()
	var rest_local_animated := parent_animated * parent_global_rest.orthonormalized().inverse() * bone_global_rest.orthonormalized()
	var rest_dir := (rest_local_animated * Vector3.UP).normalized()
	if rest_dir.length_squared() < _EPSILON or target.length_squared() < _EPSILON:
		return {"delta": Quaternion.IDENTITY, "global": rest_local_animated}
	var swing := Quaternion(rest_dir, target)
	var global_basis := Basis(swing) * rest_local_animated
	var delta := rest_local_animated.inverse() * global_basis
	return {"delta": delta.get_rotation_quaternion().normalized(), "global": global_basis}


## Pose delta for a rotation about a **world axis** applied to a bone whose
## parent is animated. Unlike `rotation_delta`, the conjugation uses the bone's
## *animated* rest basis, so a world hinge stays a world hinge - this is what
## keeps an elbow flexing forward after its shoulder has been lowered.
static func world_delta(
	parent_animated: Basis, parent_global_rest: Basis, bone_global_rest: Basis, world_rotation: Quaternion,
) -> Quaternion:
	var animated_rest := parent_animated * parent_global_rest.orthonormalized().inverse() * bone_global_rest.orthonormalized()
	return (animated_rest.inverse() * Basis(world_rotation) * animated_rest).get_rotation_quaternion().normalized()


## Pose delta that puts a bone at `target_global` orientation regardless of the
## parent's animation (used to keep a foot flat while the shin swings).
static func hold_global_delta(
	parent_animated: Basis, parent_global_rest: Basis, bone_global_rest: Basis, target_global: Basis,
) -> Quaternion:
	var rest_local_animated := parent_animated * parent_global_rest.orthonormalized().inverse() * bone_global_rest.orthonormalized()
	return (rest_local_animated.inverse() * target_global.orthonormalized()).get_rotation_quaternion().normalized()


# --- leg solve --------------------------------------------------------------

## Knee position for a two-bone leg: law of cosines in the plane spanned by the
## hip->ankle line and `forward`, so the ankle stays where it was asked to be.
## Two-bone leg solve. Returns the knee plus the **effective ankle** - the
## closest point the leg can actually reach - so both bones aim at one reachable
## target. The shin used to aim at the *requested* ankle even when the knee had
## been computed from a clamped distance, which left the foot floating in any
## pose deeper than the leg's reach.
##
## `pole_hint` is the leg's own measured rest bend (rest knee minus rest hip),
## which keeps the knee on the side the rig was built with. A cross product
## against UP used to pick the side, and that cross is zero exactly when the leg
## is straight up - the one pose where the guess mattered most.
##
## `clamped` and `shortfall` report a target the leg cannot reach instead of
## hiding the substitution.
static func solve_leg(
	hip: Vector3, ankle_target: Vector3, upper: float, lower: float, pole_hint: Vector3,
) -> Dictionary:
	var to_ankle := ankle_target - hip
	var wanted := to_ankle.length()
	var minimum := absf(upper - lower) + 0.001
	var maximum := upper + lower - 0.001
	var distance := clampf(wanted, minimum, maximum)
	var direction := (to_ankle / wanted) if wanted > _EPSILON else Vector3.FORWARD
	var effective := hip + direction * distance
	var along := (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(upper * upper - along * along, 0.0))
	var perpendicular := pole_hint - direction * direction.dot(pole_hint)
	if perpendicular.length_squared() < _EPSILON:
		perpendicular = Vector3.UP.cross(direction)
	if perpendicular.length_squared() < _EPSILON:
		perpendicular = Vector3.FORWARD.cross(direction)
	perpendicular = perpendicular.normalized()
	return {
		"knee": hip + direction * along + perpendicular * height,
		"effective_ankle": effective,
		"clamped": wanted > maximum + _EPSILON or wanted < minimum - _EPSILON,
		"shortfall": maxf(0.0, wanted - distance),
	}


## The knee position alone, for callers that do not need the reach report.
static func knee_position(hip: Vector3, ankle: Vector3, upper: float, lower: float, forward: Vector3) -> Vector3:
	return solve_leg(hip, ankle, upper, lower, forward)["knee"] as Vector3


# --- secondary motion -------------------------------------------------------

## Damped angular spring following a series of target world rotations - the
## offline bake of a spring-bone chain. Returns one state quaternion per target,
## starting from `initial`. `stiffness` is 1/s^2 and `damping` 1/s: 120/12 is
## snappy hair, 30/6 a heavy tail. Deterministic and frame-rate independent.
static func follow_spring(targets: Array, stiffness: float, damping: float, dt: float, initial: Quaternion) -> Array:
	var state := initial.normalized()
	var velocity := Vector3.ZERO
	var states: Array = []
	for target in targets:
		var to_target: Quaternion = state.inverse() * (target as Quaternion)
		if to_target.w < 0.0:
			to_target = -to_target
		var angle := to_target.get_angle()
		var error := Vector3.ZERO
		if angle > _EPSILON:
			error = Vector3(to_target.x, to_target.y, to_target.z).normalized() * angle
		velocity += (error * maxf(stiffness, 0.0) - velocity * maxf(damping, 0.0)) * dt
		var step := velocity.length() * dt
		if step > _EPSILON:
			state = (Quaternion(velocity.normalized(), step) * state).normalized()
		states.append(state)
	return states


# --- curve helpers ----------------------------------------------------------

static func smoothstep(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Smooth a value series in place (0 = untouched, 1 = heavily smoothed). Used to
## take the edge off noise; wraps when `wrapped` so loops stay seamless.
static func smooth_series(values: PackedFloat32Array, strength: float, wrap: bool) -> PackedFloat32Array:
	var s := clampf(strength, 0.0, 1.0)
	if s <= 0.0 or values.size() < 3:
		return values
	var out := PackedFloat32Array()
	out.resize(values.size())
	for index in values.size():
		var previous := index - 1
		var following := index + 1
		if wrap:
			previous = posmod(previous, values.size() - 1)
			following = posmod(following, values.size() - 1)
		else:
			previous = maxi(previous, 0)
			following = mini(following, values.size() - 1)
		out[index] = values[index] * (1.0 - s) + (values[previous] + values[following]) * 0.5 * s
	return out
