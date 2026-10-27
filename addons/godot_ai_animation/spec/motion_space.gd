@tool
extends RefCounted
## The solver uses skeleton rest coordinates. Public metric controls/results
## cross the uniform world-scale boundary; root position tracks use owner-parent
## coordinates, as does Godot extraction when there is no root rotation track.
const METRIC_CONFIG := ["bob", "sway", "foot_lift", "crouch", "jump_height", "jump_crouch", "jump_distance"]
const ALIASES := {"jump_height": "height", "jump_crouch": "crouch", "jump_distance": "distance"}
static func geometry(basis: Basis) -> Dictionary:
	if not basis.is_finite(): return {"error": "Motion geometry has a nonfinite effective transform"}
	var lengths := Vector3(basis.x.length(), basis.y.length(), basis.z.length())
	if minf(lengths.x, minf(lengths.y, lengths.z)) <= 0.0 or basis.determinant() <= 0.0:
		return {"error": "Motion authoring requires a nonsingular, nonreflected effective skeleton transform"}
	var scale_value := (lengths.x + lengths.y + lengths.z) / 3.0
	if maxf(absf(lengths.x-scale_value), maxf(absf(lengths.y-scale_value), absf(lengths.z-scale_value))) > scale_value * 0.00001:
		return {"error": "Motion authoring requires positive uniform effective skeleton scale; nonuniform transforms are unsupported"}
	var x := basis.x / lengths.x
	var y := basis.y / lengths.y
	var z := basis.z / lengths.z
	if maxf(absf(x.dot(y)), maxf(absf(x.dot(z)), absf(y.dot(z)))) > 0.00001:
		return {"error": "Motion authoring requires an effective skeleton transform without shear"}
	return {"world_scale": scale_value}
static func local_config(config: Dictionary, params: Dictionary, overrides: Dictionary, world_scale: float) -> void:
	if world_scale == 1.0: return
	for field in METRIC_CONFIG:
		if not config.has(field): continue
		if params.has(field) or overrides.has(field) or (ALIASES.has(field) and params.has(ALIASES[field])):
			config[field] = float(config[field]) / world_scale
static func world_metrics(meta: Dictionary, world_scale: float) -> Dictionary:
	if world_scale == 1.0: return meta
	var result := meta.duplicate(true)
	for field in result:
		if (str(field).ends_with("_m") or str(field) in ["speed", "height", "crouch", "distance", "lateral_speed_cap"]) and (result[field] is float or result[field] is int):
			result[field] = float(result[field]) * world_scale
	return result
static func root_basis(owner: Node3D, skeleton: Skeleton3D) -> Basis:
	var parent := owner.get_parent_node_3d()
	return (parent.global_basis.inverse() if parent != null and not owner.top_level else Basis.IDENTITY) * skeleton.global_basis

static func carries(owner: Node3D, skeleton: Skeleton3D) -> bool:
	var cursor: Node = skeleton
	while cursor != null and cursor != owner:
		if cursor is Node3D and cursor.top_level: return false
		cursor = cursor.get_parent()
	return cursor == owner
