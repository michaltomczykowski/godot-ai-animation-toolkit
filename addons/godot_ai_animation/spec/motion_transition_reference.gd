@tool
extends RefCounted

## Preparation-only reference tracks. Generation uses engine interpolation and
## FK; acceptance measures separately saved scenes through actual mixers.
const ValueCodec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")

static func build(prepared: Dictionary) -> Dictionary:
	var anim := Animation.new()
	anim.length = float(prepared.length)
	var tracks := {}
	for bone in prepared.keys:
		if bone == "__root_motion__": continue
		var channels := {}
		for channel in ["rotation", "position"]:
			if not (prepared.keys[bone] as Dictionary).has(channel): continue
			var track := anim.add_track(Animation.TYPE_ROTATION_3D if channel == "rotation" else Animation.TYPE_POSITION_3D)
			for key: Dictionary in prepared.keys[bone][channel]:
				anim.track_insert_key(track, float(key.time), key.delta, ValueCodec.parse_transition(key.get("transition", 1.0)))
			channels[channel] = track
		tracks[bone] = channels
	return {"animation": anim, "tracks": tracks, "rest": prepared.ctx.rest, "length": float(prepared.length)}

static func sample(reference: Dictionary, time: float) -> Dictionary:
	var at := fposmod(time, float(reference.length))
	var anim: Animation = reference.animation
	var channels := {}
	for bone in reference.tracks:
		var values := {}
		for channel in reference.tracks[bone]:
			var track := int(reference.tracks[bone][channel])
			values[channel] = anim.rotation_track_interpolate(track, at) if channel == "rotation" else anim.position_track_interpolate(track, at)
		channels[bone] = values
	return channels

static func global_pose(rest: Dictionary, channels: Dictionary, bone: String, cache: Dictionary) -> Transform3D:
	if cache.has(bone): return cache[bone]
	if bone.is_empty(): return Transform3D.IDENTITY
	var entry: Dictionary = rest[bone]
	var parent := str(entry.parent)
	var parent_rest := Transform3D.IDENTITY
	if not parent.is_empty(): parent_rest = Transform3D(rest[parent].global, rest[parent].origin)
	var local := parent_rest.affine_inverse() * Transform3D(entry.global, entry.origin)
	var values: Dictionary = channels.get(bone, {})
	# Procedural commits write local rest rotation * delta, rest origin + delta,
	# retaining local rest scale. Reproduce that exact coordinate contract.
	var rotation := (local.basis.get_rotation_quaternion() * (values.get("rotation", Quaternion.IDENTITY) as Quaternion)).normalized()
	local.basis = Basis(rotation) * Basis.from_scale(local.basis.get_scale())
	local.origin += values.get("position", Vector3.ZERO) as Vector3
	var result := global_pose(rest, channels, parent, cache) * local
	cache[bone] = result
	return result

static func blend(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var bones := a.duplicate()
	bones.merge(b, true)
	var out := {}
	for bone in bones:
		var first: Dictionary = a.get(bone, {})
		var second: Dictionary = b.get(bone, {})
		var channels := {}
		if first.has("rotation") or second.has("rotation"):
			channels["rotation"] = (first.get("rotation", Quaternion.IDENTITY) as Quaternion).slerp(second.get("rotation", Quaternion.IDENTITY), weight).normalized()
		if first.has("position") or second.has("position"):
			channels["position"] = (first.get("position", Vector3.ZERO) as Vector3).lerp(second.get("position", Vector3.ZERO), weight)
		out[bone] = channels
	return out
