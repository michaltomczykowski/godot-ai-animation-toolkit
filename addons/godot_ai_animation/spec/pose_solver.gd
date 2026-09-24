@tool
extends RefCounted

## Pure pose solving: forward kinematics over rest-relative pose deltas and an
## analytic two-bone solve that puts a chain's end effector on a world target.
##
## The toolkit's poses store rest-relative rotations: the animated global basis
## of a bone is `A * rest_global * Basis(delta)`, where `A` is the parent's
## accumulated `global_anim * rest_global.inverse()` (identity at rest). That is
## exactly the convention Godot's `Skeleton3D` uses, so a solved delta can be
## written straight into a pose and keyed by `pose_to_clip`.
##
## No live Skeleton3D here: callers pass rest transforms in, so tier-1 can test
## the math headlessly.

const _EPSILON := 0.000001


## Animated global transforms for `rest_globals` under `parent_delta` and
## per-bone rest-relative `deltas`. Returns one Transform3D per bone.
static func fk_chain(rest_globals: Array, parent_delta: Transform3D, deltas: Array) -> Array:
	var out: Array = []
	var accumulated := parent_delta
	for index in rest_globals.size():
		var rest: Transform3D = rest_globals[index]
		var delta: Quaternion = deltas[index] if index < deltas.size() else Quaternion.IDENTITY
		var global := accumulated * rest
		global.basis = (global.basis * Basis(delta)).orthonormalized()
		out.append(global)
		accumulated = global * rest.affine_inverse()
	return out


## Analytic two-bone solve for a three-bone chain (`root -> mid -> end`).
##
## The end bone's origin (the wrist/ankle) is placed on `target`; the mid
## (elbow/knee) bends into `pole_hint`'s half-plane when given, otherwise it
## keeps the base pose's bend direction. `target` is in the same space as the
## rest transforms (callers convert world targets first).
##
## Returns `{rotations, elbow, reach, clamped, target}` where `rotations` is the
## solved rest-relative delta per chain bone (the end bone keeps its base delta).
static func solve_chain(
	rest_globals: Array, parent_delta: Transform3D, base_deltas: Array,
	target: Vector3, pole_hint: Vector3 = Vector3.ZERO,
) -> Dictionary:
	if rest_globals.size() != 3:
		return {"error": "a solve chain needs exactly three bones (root, mid, end)"}
	if base_deltas.size() != 3:
		return {"error": "base_deltas must hold one quaternion per chain bone"}
	var posed := fk_chain(rest_globals, parent_delta, base_deltas)
	var shoulder: Vector3 = (posed[0] as Transform3D).origin
	var base_elbow: Vector3 = (posed[1] as Transform3D).origin
	var upper_length: float = \
		(rest_globals[1] as Transform3D).origin.distance_to((rest_globals[0] as Transform3D).origin)
	var lower_length: float = \
		(rest_globals[2] as Transform3D).origin.distance_to((rest_globals[1] as Transform3D).origin)
	if upper_length < _EPSILON or lower_length < _EPSILON:
		return {"error": "the chain has zero-length bones"}
	var to_target := target - shoulder
	var wanted := to_target.length()
	if wanted < _EPSILON:
		return {"error": "the target sits on the chain root"}
	var minimum := absf(upper_length - lower_length) + 0.0005
	var maximum := upper_length + lower_length - 0.0005
	var reach := clampf(wanted, minimum, maximum)
	var direction := to_target / wanted
	# Elbow position: law of cosines in the plane spanned by the target line and
	# the bend hint (explicit pole, else the base pose's own bend direction).
	var along := (upper_length * upper_length - lower_length * lower_length + reach * reach) / (2.0 * reach)
	var height := sqrt(maxf(upper_length * upper_length - along * along, 0.0))
	var bend_source := pole_hint
	if bend_source.length_squared() < _EPSILON:
		bend_source = base_elbow - shoulder
	var perpendicular := bend_source - direction * direction.dot(bend_source)
	if perpendicular.length_squared() < _EPSILON:
		perpendicular = direction.cross(Vector3.UP)
		if perpendicular.length_squared() < _EPSILON:
			perpendicular = direction.cross(Vector3.RIGHT)
	perpendicular = perpendicular.normalized()
	var elbow := shoulder + direction * along + perpendicular * height
	# Convert the desired bone directions back into rest-relative deltas.
	var root_desired := _basis_from_y((elbow - shoulder).normalized(), (posed[0] as Transform3D).basis)
	var rotations: Array = base_deltas.duplicate()
	rotations[0] = _local_delta(rest_globals[0], parent_delta, root_desired)
	var mid_parent := Transform3D(
		root_desired * (rest_globals[0] as Transform3D).basis.inverse(), Vector3.ZERO)
	var mid_basis := _basis_from_y((target - elbow).normalized(), (posed[1] as Transform3D).basis)
	rotations[1] = _local_delta(rest_globals[1], mid_parent, mid_basis)
	return {
		"rotations": rotations,
		"elbow": elbow,
		"reach": reach,
		"clamped": absf(reach - wanted) > 0.0001,
		"target": target,
	}


## Basis whose Y axis (Godot's bone direction) is `direction`, choosing the roll
## closest to `reference`.
static func _basis_from_y(direction: Vector3, reference: Basis) -> Basis:
	var y := direction.normalized()
	var x := reference.x - y * y.dot(reference.x)
	if x.length_squared() < _EPSILON:
		x = reference.z - y * y.dot(reference.z)
	if x.length_squared() < _EPSILON:
		x = y.cross(Vector3.UP)
		if x.length_squared() < _EPSILON:
			x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	x = y.cross(z).normalized()
	return Basis(x, y, z)


## Rest-relative delta that turns `rest` (under `parent_delta`) into `desired`.
static func _local_delta(rest: Transform3D, parent_delta: Transform3D, desired: Basis) -> Quaternion:
	var frame := (parent_delta * rest).basis.orthonormalized()
	return (frame.inverse() * desired).get_rotation_quaternion().normalized()
