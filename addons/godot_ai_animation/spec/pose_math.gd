@tool
extends RefCounted

## Pure pose helpers for the `animation_rig` tool.
##
## A pose is a plain Dictionary so it round-trips through JSON and is tier-1
## testable:
##
##     {
##       "source": "res://.../Rig/Skeleton3D",          # informational
##       "rest_relative": true,
##       "bones": {
##         "B-thigh.L": {
##           "rotation": Quaternion,   # rest-relative local delta
##           "position": Vector3,      # rest-relative offset (skeleton space)
##           "scale": Vector3,         # absolute pose scale
##         },
##       },
##     }
##
## Rest-relative storage is what makes poses portable between rigs with the same
## bone names (and between the F/M human dummy variants) and gives mirroring a
## well-defined meaning: rotations mirror as (w, -x, y, z), positions as
## (-x, y, z), scale is untouched.

const SpecJson := preload("res://addons/godot_ai_animation/spec/spec_json.gd")
const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")

const _SIDE_SUFFIXES := {
	".L": ".R",
	".R": ".L",
	"_L": "_R",
	"_R": "_L",
	"-L": "-R",
	"-R": "-L",
}

const _SIDE_WORDS := {
	"left": "right",
	"right": "left",
	"Left": "Right",
	"Right": "Left",
}


# --- construction ----------------------------------------------------------

static func make_pose(source: String = "") -> Dictionary:
	return {"source": source, "rest_relative": true, "bones": {}}


static func set_bone(
	pose: Dictionary, bone: String, rotation: Quaternion,
	position: Vector3, scale: Vector3,
) -> void:
	pose.bones[bone] = {"rotation": rotation, "position": position, "scale": scale}


static func has_bone(pose: Dictionary, bone: String) -> bool:
	return (pose.get("bones", {}) as Dictionary).has(bone)


static func bone_count(pose: Dictionary) -> int:
	return (pose.get("bones", {}) as Dictionary).size()


static func bone_names(pose: Dictionary) -> Array:
	var names: Array = (pose.get("bones", {}) as Dictionary).keys()
	names.sort()
	return names


# --- rest <-> pose conversion ----------------------------------------------

## Rest-relative delta -> the absolute local pose values the skeleton API takes.
static func delta_to_pose(delta: Dictionary, rest_rotation: Quaternion, rest_position: Vector3) -> Dictionary:
	var rotation: Quaternion = rest_rotation * delta.get("rotation", Quaternion.IDENTITY)
	return {
		"rotation": rotation.normalized(),
		"position": rest_position + delta.get("position", Vector3.ZERO),
		"scale": delta.get("scale", Vector3.ONE),
	}


## Absolute local pose values -> rest-relative delta.
static func pose_to_delta(pose_rotation: Quaternion, pose_position: Vector3, pose_scale: Vector3, rest_rotation: Quaternion, rest_position: Vector3) -> Dictionary:
	return {
		"rotation": (rest_rotation.inverse() * pose_rotation).normalized(),
		"position": pose_position - rest_position,
		"scale": pose_scale,
	}


# --- mirroring -------------------------------------------------------------

## The mirrored bone name (".L" <-> ".R", "_L" <-> "_R", "Left" <-> "Right"),
## or "" when the name has no recognisable side.
static func mirror_name(bone: String) -> String:
	for suffix in _SIDE_SUFFIXES:
		if bone.ends_with(suffix):
			return bone.substr(0, bone.length() - suffix.length()) + _SIDE_SUFFIXES[suffix]
	for word in _SIDE_WORDS:
		var index := bone.find(word)
		if index >= 0:
			return bone.substr(0, index) + _SIDE_WORDS[word] + bone.substr(index + word.length())
	return ""


## Mirror a pose across the rig's X axis (L/R bones swap). A reflection flips
## handedness, so a mirrored rotation keeps its angle and mirrors its axis:
## q = (x, y, z, w) becomes (x, -y, -z, w). Positions negate X; scale is kept.
## Returns `{pose, unmapped}` where `unmapped` lists bones with no mirrored
## counterpart.
static func mirror_pose(pose: Dictionary) -> Dictionary:
	var out := make_pose(str(pose.get("source", "")))
	var unmapped: Array = []
	for bone in (pose.get("bones", {}) as Dictionary):
		var values: Dictionary = pose.bones[bone]
		var target := mirror_name(str(bone))
		if target.is_empty():
			unmapped.append(str(bone))
			target = str(bone)
		var rotation: Quaternion = values.get("rotation", Quaternion.IDENTITY)
		var position: Vector3 = values.get("position", Vector3.ZERO)
		var mirrored := Quaternion(rotation.x, -rotation.y, -rotation.z, rotation.w).normalized()
		set_bone(out, target, mirrored,
			Vector3(-position.x, position.y, position.z),
			values.get("scale", Vector3.ONE))
	return {"pose": out, "unmapped": unmapped}


# --- blending --------------------------------------------------------------

## Blend two poses. Bones missing from one side keep the other side's value, so
## a partial pose blends without snapping the rest of the rig.
static func blend_pose(a: Dictionary, b: Dictionary, factor: float) -> Dictionary:
	var out := make_pose(str(a.get("source", b.get("source", ""))))
	var only_a: Array = []
	var only_b: Array = []
	var names := {}
	for bone in (a.get("bones", {}) as Dictionary):
		names[bone] = true
	for bone in (b.get("bones", {}) as Dictionary):
		names[bone] = true
	for bone in names:
		var has_a := has_bone(a, bone)
		var has_b := has_bone(b, bone)
		if has_a and not has_b:
			only_a.append(str(bone))
			var values_a: Dictionary = a.bones[bone]
			set_bone(out, str(bone), values_a.get("rotation", Quaternion.IDENTITY),
				values_a.get("position", Vector3.ZERO), values_a.get("scale", Vector3.ONE))
			continue
		if has_b and not has_a:
			only_b.append(str(bone))
			var values_b: Dictionary = b.bones[bone]
			set_bone(out, str(bone), values_b.get("rotation", Quaternion.IDENTITY),
				values_b.get("position", Vector3.ZERO), values_b.get("scale", Vector3.ONE))
			continue
		var va: Dictionary = a.bones[bone]
		var vb: Dictionary = b.bones[bone]
		var qa: Quaternion = va.get("rotation", Quaternion.IDENTITY)
		var qb: Quaternion = vb.get("rotation", Quaternion.IDENTITY)
		var pa: Vector3 = va.get("position", Vector3.ZERO)
		var pb: Vector3 = vb.get("position", Vector3.ZERO)
		var sa: Vector3 = va.get("scale", Vector3.ONE)
		var sb: Vector3 = vb.get("scale", Vector3.ONE)
		set_bone(out, str(bone), qa.slerp(qb, factor), pa.lerp(pb, factor), sa.lerp(sb, factor))
	return {"pose": out, "only_a": only_a, "only_b": only_b}


## Blend many poses with weights (used by recipe generators).
static func blend_many(poses: Array, weights: Array) -> Dictionary:
	if poses.is_empty():
		return make_pose()
	var out: Dictionary = poses[0].duplicate(true)
	var total := float(weights[0]) if not weights.is_empty() else 1.0
	for index in range(1, poses.size()):
		var weight := float(weights[index]) if index < weights.size() else 1.0
		total += weight
		out = blend_pose(out, poses[index], weight / maxf(total, 0.000001)).pose
	return out


# --- subsets ---------------------------------------------------------------

## Keep only the listed bones (returns `{pose, missing}`).
static func subset(pose: Dictionary, bones: Array) -> Dictionary:
	var out := make_pose(str(pose.get("source", "")))
	var missing: Array = []
	for bone in bones:
		if not has_bone(pose, bone):
			missing.append(str(bone))
			continue
		var values: Dictionary = pose.bones[bone]
		set_bone(out, str(bone), values.get("rotation", Quaternion.IDENTITY),
			values.get("position", Vector3.ZERO), values.get("scale", Vector3.ONE))
	return {"pose": out, "missing": missing}


# --- JSON ------------------------------------------------------------------

static func to_json(pose: Dictionary) -> Dictionary:
	var out := {
		"format": "godot-ai-animation-pose",
		"version": 1,
		"source": str(pose.get("source", "")),
		"rest_relative": bool(pose.get("rest_relative", true)),
		"bones": {},
	}
	for bone in (pose.get("bones", {}) as Dictionary):
		var values: Dictionary = pose.bones[bone]
		out.bones[bone] = {
			"rotation": SpecJson.encode_value(values.get("rotation", Quaternion.IDENTITY)).ok,
			"position": SpecJson.encode_value(values.get("position", Vector3.ZERO)).ok,
			"scale": SpecJson.encode_value(values.get("scale", Vector3.ONE)).ok,
		}
	return out


static func from_json(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "A pose must be a JSON object")
	var dict: Dictionary = raw
	if not dict.has("bones"):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "The pose has no 'bones' section")
	var out := make_pose(str(dict.get("source", "")))
	out["rest_relative"] = bool(dict.get("rest_relative", true))
	for bone in (dict.bones as Dictionary):
		var values: Dictionary = dict.bones[bone]
		var rotation := SpecJson.decode_value(values.get("rotation", {"kind": "quaternion", "w": 1.0}))
		var position := SpecJson.decode_value(values.get("position", {"kind": "vector3"}))
		var scale := SpecJson.decode_value(values.get("scale", {"kind": "vector3", "x": 1.0, "y": 1.0, "z": 1.0}))
		if rotation.has("error") or position.has("error") or scale.has("error"):
			return ErrorCodes.make(ErrorCodes.WRONG_TYPE, "Pose bone '%s' has malformed values" % str(bone))
		set_bone(out, str(bone), rotation.ok, position.ok, scale.ok)
	if (out.bones as Dictionary).is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "The pose has no bones")
	return {"pose": out, "bone_count": bone_count(out)}


static func summarize(pose: Dictionary) -> Dictionary:
	return {
		"source": str(pose.get("source", "")),
		"rest_relative": bool(pose.get("rest_relative", true)),
		"bone_count": bone_count(pose),
		"bones": bone_names(pose),
	}
