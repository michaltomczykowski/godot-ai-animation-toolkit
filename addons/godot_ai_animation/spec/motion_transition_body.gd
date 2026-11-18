@tool
extends RefCounted

## A transition-local inertial response. Reference windows and actor travel
## remain exact; the caller re-solves planted legs after this body layer.
const Reference := preload("res://addons/godot_ai_animation/spec/motion_transition_reference.gd")
const Specs := preload("res://addons/godot_ai_animation/spec/motion_specs.gd")

static func prepare(ctx: Dictionary, gait: Dictionary, middle: float) -> Dictionary:
	var layout := Specs.upper_body_layout(ctx)
	var omitted: Array = []
	if layout.has("error"):
		omitted.append({"feature": "transition_torso_head", "reason": layout.error})
		layout = {}
	var scale: float = {"responsive": 1.0, "grounded": 0.85, "relaxed": 0.9,
		"heavy": 1.15, "sneaky": 0.65}.get(str(gait.style), 1.0)
	# Dimensionless acceleration: bounded even for explicit short transitions.
	var leg := Specs.measured_leg(ctx)
	var strength := clampf(float(gait.meta.speed) / maxf(middle, 0.001) / 2.0, 0.35, 1.2) * scale
	var applied: Array = ["transition_pelvis_response"]
	if not layout.is_empty(): applied.append("transition_torso_head")
	for side in ["l", "r"]:
		var arm := str(ctx.roles.get("arm_" + side, ""))
		if not arm.is_empty() and Specs.rest_ancestor(ctx, arm, str(ctx.hips)):
			applied.append("transition_arm_follow_through_" + side)
		else:
			omitted.append({"feature": "transition_arm_follow_through_" + side,
				"reason": "No connected upper arm role"})
	return {"layout": layout, "leg": leg, "strength": strength,
		"applied": applied, "omitted": omitted}

static func _pulse(u: float, delay: float = 0.0) -> float:
	var t := clampf((u - delay) / (1.0 - delay), 0.0, 1.0)
	# Cubic ends have zero slope and acceleration; no endpoint kick.
	return 64.0 * pow(t * (1.0 - t), 3.0)

static func _rotate(rest: Dictionary, channels: Dictionary, bone: String, rotation: Quaternion) -> void:
	if bone.is_empty() or not rest.has(bone): return
	var parent := str(rest[bone].parent)
	var parent_rest := Transform3D.IDENTITY
	if not parent.is_empty(): parent_rest = Transform3D(rest[parent].global, rest[parent].origin)
	var local := parent_rest.affine_inverse() * Transform3D(rest[bone].global, rest[bone].origin)
	var incoming := Reference.global_pose(rest, channels, parent, {}).basis.orthonormalized() * Basis(local.basis.get_rotation_quaternion())
	var delta := (incoming.inverse() * Basis(rotation) * incoming).get_rotation_quaternion()
	var values: Dictionary = channels.get(bone, {})
	values["rotation"] = (delta * (values.get("rotation", Quaternion.IDENTITY) as Quaternion)).normalized()
	channels[bone] = values

static func apply(ctx: Dictionary, rest: Dictionary, channels: Dictionary, reaction: Dictionary,
		u: float, stopping: bool, support: String) -> void:
	if u <= 0.0 or u >= 1.0: return
	var pulse := _pulse(u)
	var delayed := _pulse(u, 0.12)
	var settle := pulse * sin(TAU * u)
	var strength := float(reaction.strength)
	var direction := -1.0 if stopping else 1.0
	var up: Vector3 = ctx.up
	var forward: Vector3 = ctx.forward
	var lateral: Vector3 = ctx.lateral
	var signs := Specs._axis_signs(ctx)
	var hips := str(ctx.hips)
	var support_offset: Vector3 = ctx.legs[support].hip - ctx.hips_origin
	var support_sign := 1.0 if support_offset.dot(lateral) >= 0.0 else -1.0
	# Weight moves onto the old support, then over the newly planted foot.
	var transfer := pulse * cos(PI * u) * support_sign
	var offset := (forward * (0.022 * direction * pulse + 0.008 * settle)
		+ lateral * 0.018 * transfer - up * 0.012 * delayed) * float(reaction.leg) * strength
	var parent := str(rest[hips].parent)
	var parent_basis := Reference.global_pose(rest, channels, parent, {}).basis
	channels[hips]["position"] = (channels[hips].get("position", Vector3.ZERO) as Vector3) + parent_basis.inverse() * offset
	_rotate(rest, channels, hips,
		Quaternion(lateral, deg_to_rad(float(signs.lean) * direction * 3.0 * pulse * strength))
		* Quaternion(forward, deg_to_rad(float(signs.roll) * 1.5 * transfer * strength)))
	var layout: Dictionary = reaction.layout
	# The chest follows the accelerating pelvis, then settles slightly later.
	for bone: String in layout.get("torso", {}):
		var share := float(layout.torso[bone])
		_rotate(rest, channels, bone,
			Quaternion(lateral, deg_to_rad(float(signs.lean) * (direction * 5.0 * delayed + 1.8 * settle) * share * strength))
			* Quaternion(forward, deg_to_rad(-float(signs.roll) * 0.8 * transfer * share * strength)))
	for bone: String in layout.get("cervical", {}):
		var share := float(layout.cervical[bone])
		_rotate(rest, channels, bone, Quaternion(lateral,
			deg_to_rad(-float(signs.lean) * (direction * 4.0 * delayed + 1.0 * settle) * share * strength)))
	# Hanging limbs lag the body; flex and wrist response arrive later still.
	for side in ["l", "r"]:
		if not (reaction.applied as Array).has("transition_arm_follow_through_" + side): continue
		var arm := str(ctx.roles["arm_" + side])
		var arm_sign := 1.0 if side == "l" else -1.0
		var swing := (-direction * 5.0 * delayed + 3.0 * arm_sign * transfer) * strength
		var shoulder := str(ctx.roles.get("shoulder_" + side, ""))
		if not shoulder.is_empty() and Specs.rest_ancestor(ctx, arm, shoulder):
			_rotate(rest, channels, shoulder, Quaternion(lateral, deg_to_rad(float(signs.swing) * swing * 0.25)))
		_rotate(rest, channels, arm, Quaternion(lateral, deg_to_rad(float(signs.swing) * swing)))
		var forearm := str(ctx.roles.get("forearm_" + side, ""))
		if forearm.is_empty() or not Specs.rest_ancestor(ctx, forearm, arm): continue
		_rotate(rest, channels, forearm, Quaternion(lateral,
			deg_to_rad(float(signs.swing) * 3.0 * _pulse(u, 0.2) * strength)))
		var hand := str(ctx.roles.get("hand_" + side, ""))
		if hand.is_empty() or not Specs.rest_ancestor(ctx, hand, forearm): continue
		_rotate(rest, channels, hand, Quaternion(lateral,
			deg_to_rad(-float(signs.swing) * direction * 2.5 * _pulse(u, 0.28) * strength)))
