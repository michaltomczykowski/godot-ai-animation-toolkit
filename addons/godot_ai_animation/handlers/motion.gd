@tool
extends "res://addons/godot_ai_animation/handlers/bone_animation.gd"

## Procedural character motion — the `animation_motion` tool.
##
## Cycles are generated from analytic curves (`spec/motion_drivers.gd`,
## `spec/motion_specs.gd`) and sampled densely, with the legs solved by a
## two-bone IK so planted feet stay planted. Bones are rotated in their rest
## frames, so the same numbers read the same way on any humanoid rig; `style`
## and `overrides` trade a small schema for deep tuning.

const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const MotionSpecs := preload("res://addons/godot_ai_animation/spec/motion_specs.gd")
const MotionDrivers := preload("res://addons/godot_ai_animation/spec/motion_drivers.gd")
const SpecIO := preload("res://addons/godot_ai_animation/spec/spec_io.gd")
const SpecModifiers := preload("res://addons/godot_ai_animation/spec/spec_modifiers.gd")

const _CYCLE_KINDS := {
	"walk_cycle": "walk",
	"run_cycle": "run",
	"idle_cycle": "idle",
	"cycle": "walk",
}

const _OVERRIDE_KEYS := {
	"walk": ["stride", "knee_bend", "arm_swing", "bob", "sway", "hip_yaw", "hip_roll", "chest_yaw", "lean", "foot_lift", "elbow", "lag", "stance", "crouch"],
	"run": ["stride", "knee_bend", "arm_swing", "bob", "sway", "hip_yaw", "hip_roll", "chest_yaw", "lean", "foot_lift", "elbow", "lag", "stance", "crouch"],
	"idle": ["amplitude", "head_amplitude", "bob", "sway", "shift", "noise", "lean", "arm_sway", "elbow"],
}


## Rollup entry registered with the Godot AI tool registry.
func run(params: Dictionary, _ctx) -> Dictionary:
	_dry_run = bool(params.get("dry_run", false))
	var result := _dispatch(params)
	if _dry_run and result.has("data"):
		result.data["dry_run"] = true
		result.data["undoable"] = false
	return result


func _dispatch(params: Dictionary) -> Dictionary:
	var op: String = params.get("op", "")
	match op:
		"walk_cycle":
			return _run_cycle(params, "walk")
		"run_cycle":
			return _run_cycle(params, "run")
		"idle_cycle":
			return _run_cycle(params, "idle")
		"cycle":
			return _run_cycle(params, str(params.get("preset", "walk")))
		"secondary_motion":
			return motion_secondary(params)
	return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
		"Unknown op '%s'. Valid: %s" % [op, ", ".join(OpRegistry.op_names(OpRegistry.FAMILY_MOTION))])


# --- cycle ops --------------------------------------------------------------

func _run_cycle(params: Dictionary, kind: String) -> Dictionary:
	if not _CYCLE_KINDS.values().has(kind):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid preset '%s'. Valid: walk, run, idle" % kind)
	var style := str(params.get("style", "default"))
	if style != "default" and not MotionSpecs._STYLE_MULTIPLIERS.has(style):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid style '%s'. Valid: %s" % [style, ", ".join(MotionSpecs._STYLE_MULTIPLIERS.keys())])
	var overrides = params.get("overrides", {})
	if not (overrides is Dictionary):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "'overrides' must be an object")
	var valid_keys: Array = _OVERRIDE_KEYS[kind]
	for key in overrides:
		if not valid_keys.has(str(key)):
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"Unknown %s override '%s'. Valid: %s" % [kind, str(key), ", ".join(valid_keys)])
	var built := _build_context(params, kind)
	if built.has("error"):
		return built
	var config: Dictionary = MotionSpecs.walk_config(style, {})
	match kind:
		"run":
			config = MotionSpecs.run_config(style, {})
		"idle":
			config = MotionSpecs.idle_config(style, {})
	for key in overrides:
		config[str(key)] = overrides[key]
	for key in valid_keys:
		if params.has(key):
			config[key] = float(params[key])
	var length := float(built.length)
	var rate := float(built.rate)
	var ctx: Dictionary = built.ctx
	ctx["config"] = config
	var keys: Dictionary = MotionSpecs.idle_keys(ctx) if kind == "idle" else MotionSpecs.gait_keys(ctx, kind == "run")
	if keys.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"No bones could be keyed - check the skeleton's bone roles")
	var anim_name := str(params.get("animation_name", kind))
	var committed := _commit_procedural_clip(params, built.resolved, anim_name, length, int(built.loop_mode), keys)
	if committed.has("error"):
		return committed
	committed.data["style"] = style
	committed.data["samples"] = rate
	committed.data["roles"] = built.ctx.roles
	committed.data["root_motion"] = bool(built.ctx.get("root_motion", false))
	committed.data["speed"] = _implied_speed(kind, config, built.ctx, length)
	if bool(built.ctx.get("root_motion", false)) and not str(built.ctx.get("hips", "")).is_empty():
		var player_resolved := _resolve_player(str(params.get("player_path", "")))
		if not player_resolved.has("error"):
			var root_node := ValueCodec.player_root_node(player_resolved.player)
			if root_node != null:
				committed.data["root_motion_track"] = "%s:%s" % [
					str(root_node.get_path_to(built.skeleton)), str(built.ctx.hips)]
	return committed


## Ground speed the cycle represents, in metres per second (0 for idle).
static func _implied_speed(kind: String, config: Dictionary, ctx: Dictionary, length: float) -> float:
	if kind == "idle":
		return 0.0
	var leg: Dictionary = ctx.legs.l
	var span := 2.0 * (float(leg.upper) + float(leg.lower)) * sin(deg_to_rad(float(config.stride)))
	var stance := clampf(float(config.stance), 0.2, 0.8)
	return span / (stance * length)


# --- secondary motion -------------------------------------------------------

## Bake offline spring bones into an existing clip: each named bone (hair, tail,
## antenna, cloth strip root) lags behind its animated parent with a damped
## angular spring, keyed as ordinary rotation tracks. Jiggle bones must not
## already have a rotation track in the clip - that keeps the pass additive-free
## and deterministic.
func motion_secondary(params: Dictionary) -> Dictionary:
	var player_path := str(params.get("player_path", ""))
	var anim_name := str(params.get("animation_name", ""))
	if player_path.is_empty() or anim_name.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"secondary_motion needs 'player_path' and 'animation_name'")
	var resolved_player := _resolve_player(player_path)
	if resolved_player.has("error"):
		return resolved_player
	var player: AnimationPlayer = resolved_player.player
	var library: AnimationLibrary = resolved_player.library
	if library == null or not library.has_animation(anim_name):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Animation '%s' not found on %s" % [anim_name, player_path])
	var anim := library.get_animation(anim_name)
	var unsupported := SpecIO.unsupported_tracks(anim)
	if not unsupported.is_empty():
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"Animation '%s' has tracks this toolkit cannot edit: %s"
			% [anim_name, SpecIO.describe_unsupported(anim)])
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "secondary_motion needs a Skeleton3D")
	var skeleton: Skeleton3D = resolved.node
	var bones: Array = params.get("bones", [])
	if bones.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"secondary_motion needs 'bones': [\"B-hair01\", ...]")
	var root_node := ValueCodec.player_root_node(player)
	if root_node == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "The AnimationPlayer has no resolvable root_node")
	var track_root := str(root_node.get_path_to(skeleton))
	if track_root.is_empty() or track_root == ".":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "The skeleton must live under the player's root_node")
	var spec := SpecIO.from_animation(anim)
	var length := float(spec.length)
	if length <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "The clip is empty (length 0)")
	var infos := {}
	for bone in bones:
		var bone_name := str(bone)
		var index := skeleton.find_bone(bone_name)
		if index < 0:
			return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND, "'%s' is not a bone of this skeleton" % bone_name)
		var parent_index := skeleton.get_bone_parent(index)
		if parent_index < 0:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "'%s' is a root bone: nothing drives it" % bone_name)
		if ClipSpec.find_track_index(spec, "%s:%s" % [track_root, bone_name], Animation.TYPE_ROTATION_3D) >= 0:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"'%s' already has a rotation track in '%s' - jiggle bones must be unkeyed" % [bone_name, anim_name])
		infos[bone_name] = {
			"index": index,
			"parent_index": parent_index,
			"parent_rest": skeleton.get_bone_global_rest(parent_index).basis,
			"bone_rest": skeleton.get_bone_global_rest(index).basis,
		}
	var fps := clampf(float(params.get("samples", 30.0)), 4.0, 120.0)
	var steps := maxi(2, int(round(length * fps)))
	var dt := length / float(steps)
	var snapshot := _pose_snapshot(skeleton)
	var parent_globals := {}
	for bone_name in infos:
		parent_globals[bone_name] = []
	var targets := {}
	for bone_name in infos:
		targets[bone_name] = []
	for step in steps + 1:
		var time := length * float(step) / float(steps)
		_apply_spec_at(skeleton, spec, time)
		for bone_name in infos:
			var info: Dictionary = infos[bone_name]
			var parent_basis := skeleton.get_bone_global_pose(int(info.parent_index)).basis
			parent_globals[bone_name].append(parent_basis)
			targets[bone_name].append(
				(parent_basis * (info.parent_rest as Basis).inverse() * (info.bone_rest as Basis)).get_rotation_quaternion())
	_pose_restore(skeleton, snapshot)
	var stiffness := float(params.get("stiffness", 120.0))
	var damping := float(params.get("damping", 12.0))
	if stiffness < 0.0 or damping < 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'stiffness' and 'damping' must be >= 0")
	var substeps := 2
	var sim_dt := dt / float(substeps)
	for bone_name in infos:
		var expanded: Array = []
		for target in targets[bone_name]:
			for _sub in substeps:
				expanded.append(target)
		var states := MotionDrivers.follow_spring(
			expanded, stiffness, damping, sim_dt, (targets[bone_name][0] as Quaternion))
		var keys: Array = []
		for step in steps + 1:
			var time := length * float(step) / float(steps)
			var state: Quaternion = states[mini(step * substeps, states.size() - 1)]
			var parent_global: Basis = parent_globals[bone_name][step]
			keys.append({
				"time": time,
				"value": (parent_global.inverse() * Basis(state)).get_rotation_quaternion().normalized(),
				"transition": "linear",
			})
		ClipSpec.align_quaternions(keys)
		if int(spec.loop_mode) != Animation.LOOP_NONE:
			ClipSpec.close_loop(keys, length)
		ClipSpec.add_value_track(spec, "%s:%s" % [track_root, bone_name], keys,
			Animation.INTERPOLATION_LINEAR, Animation.TYPE_ROTATION_3D)
	var valid := SpecBuilder.validate(spec)
	if valid.has("error"):
		return valid
	var built := SpecBuilder.to_animation(spec)
	_commit_animation_changes("MCP: Secondary motion %s" % anim_name, player, library, false,
		{anim_name: anim}, {anim_name: built})
	return {"data": {
		"player_path": player_path,
		"skeleton_path": resolved.path,
		"animation_name": anim_name,
		"bones": bones,
		"stiffness": stiffness,
		"damping": damping,
		"samples": fps,
		"track_count": (spec.tracks as Array).size(),
		"key_count": ClipSpec.total_key_count(spec),
		"undoable": true,
	}}


## Apply a clip spec to the skeleton at `time` (rest + sampled key values), so
## the spring pass can read animated parent poses without an AnimationPlayer.
func _apply_spec_at(skeleton: Skeleton3D, spec: Dictionary, time: float) -> void:
	skeleton.reset_bone_poses()
	for track in spec.get("tracks", []):
		var type := int(track.get("type", -1))
		if type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_POSITION_3D and type != Animation.TYPE_SCALE_3D:
			continue
		var index := skeleton.find_bone(ClipSpec.property_of(str(track.get("path", ""))))
		if index < 0:
			continue
		var value = SpecModifiers.sample_track(track, time)
		if value == null:
			continue
		match type:
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(index, value)
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(index, value)
			Animation.TYPE_SCALE_3D:
				skeleton.set_bone_pose_scale(index, value)


# --- rig context ------------------------------------------------------------

func _build_context(params: Dictionary, kind: String) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "%s needs a Skeleton3D (bone roles are matched by name)" % kind)
	var skeleton: Skeleton3D = resolved.node
	var roles: Dictionary = _resolve_roles(params, skeleton)
	var required: Array = ["hips", "thigh_l", "thigh_r", "shin_l", "shin_r"]
	if kind != "idle":
		required.append_array(["foot_l", "foot_r"])
	var missing: Array = []
	for role in required:
		if not roles.has(role):
			missing.append(role)
	if not missing.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Cannot find bones for: %s. Pass 'roles' to name them explicitly (e.g. {\"thigh_l\": \"B-thigh.L\"})." % ", ".join(missing))
	var length := float(params.get("duration", 1.0))
	if length <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "duration must be > 0")
	var loop_result := _loop_mode(params)
	if loop_result.has("error"):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, loop_result.error)
	var rate := clampf(float(params.get("samples", 24.0)), 4.0, 120.0)
	var rest := _rest_map(skeleton, roles)
	var legs := _leg_map(skeleton, roles, rest)
	var hips := str(roles.get("hips", ""))
	if legs.size() < 2 or not rest.has(hips):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Could not resolve the leg chain. Check 'roles' (hips, thigh/shin/foot per side) and that the bones exist on this skeleton.")
	var thigh_l := str(roles.thigh_l)
	var thigh_r := str(roles.thigh_r)
	var forward: Vector3 = _forward_dir(skeleton, roles)
	var up := Vector3.UP
	var lateral: Vector3 = rest[thigh_l].origin - rest[thigh_r].origin
	lateral.y = 0.0
	if lateral.length_squared() < 0.000001:
		lateral = forward.cross(up)
	lateral = lateral.normalized()
	var arm_down := {}
	var arm_amount := float(params.get("arm_down", -1.0))
	if arm_amount < 0.0:
		arm_amount = _default_arm_down(skeleton, roles)
	for side in ["l", "r"]:
		var arm := str(roles.get("arm_" + side, ""))
		arm_down[side] = _aim_delta(skeleton, arm, Vector3.DOWN, arm_amount) if not arm.is_empty() else Quaternion.IDENTITY
	return {
		"resolved": resolved,
		"skeleton": skeleton,
		"length": length,
		"rate": rate,
		"loop_mode": int(loop_result.ok),
		"ctx": {
			"length": length,
			"samples": rate,
			"roles": roles,
			"forward": forward,
			"up": up,
			"lateral": lateral,
			"hips": hips,
			"hips_origin": rest[hips].origin if not hips.is_empty() else Vector3.ZERO,
			"legs": legs,
			"rest": rest,
			"arm_down": arm_down,
			"root_motion": bool(params.get("root_motion", false)),
		},
	}


## Global rest basis/origin per role bone (skeleton space).
func _rest_map(skeleton: Skeleton3D, roles: Dictionary) -> Dictionary:
	var rest := {}
	for role in roles:
		var bone := str(roles[role])
		if rest.has(bone):
			continue
		var index := skeleton.find_bone(bone)
		if index < 0:
			continue
		var xform := skeleton.get_bone_global_rest(index)
		rest[bone] = {"global": xform.basis, "origin": xform.origin}
	return rest


## Arms on a T-pose rest are horizontal, so the swing axis would run along the
## arm and do nothing. Detect that and lower the arms by default; A-pose rigs
## keep their rest. An explicit `arm_down` always wins.
func _default_arm_down(skeleton: Skeleton3D, roles: Dictionary) -> float:
	for side in ["l", "r"]:
		var arm := str(roles.get("arm_" + side, ""))
		if arm.is_empty():
			continue
		var index := skeleton.find_bone(arm)
		if index < 0:
			continue
		var rest_dir := (skeleton.get_bone_global_rest(index).basis * Vector3.UP).normalized()
		if absf(rest_dir.dot(Vector3.UP)) < 0.5:
			return 70.0
	return 0.0


func _leg_map(skeleton: Skeleton3D, roles: Dictionary, rest: Dictionary) -> Dictionary:
	var legs := {}
	for side in ["l", "r"]:
		var thigh := str(roles.get("thigh_" + side, ""))
		var shin := str(roles.get("shin_" + side, ""))
		var foot := str(roles.get("foot_" + side, ""))
		if not rest.has(thigh) or not rest.has(shin):
			continue
		var ankle: Vector3 = rest[foot].origin if rest.has(foot) else rest[shin].origin
		var lower: float = (ankle - (rest[shin].origin as Vector3)).length()
		if lower <= 0.0001:
			lower = 0.35
		legs[side] = {
			"thigh": thigh,
			"shin": shin,
			"foot": foot,
			"hip": rest[thigh].origin,
			"ankle": ankle,
			"upper": (rest[shin].origin - rest[thigh].origin).length(),
			"lower": lower,
		}
	return legs
