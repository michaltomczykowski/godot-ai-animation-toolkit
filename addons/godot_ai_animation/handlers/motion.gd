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
const GraphBuilders := preload("res://addons/godot_ai_animation/spec/graph_builders.gd")

const _CYCLE_KINDS := {
	"walk_cycle": "walk",
	"run_cycle": "run",
	"idle_cycle": "idle",
	"cycle": "walk",
	"jump": "jump",
	"turn_cycle": "turn",
	"strafe_cycle": "strafe",
	"walk_start": "walk_start",
	"walk_stop": "walk_stop",
}

const _GAIT_KEYS := ["stride", "knee_bend", "arm_swing", "arm_twist", "bob", "sway", "hip_yaw", "hip_roll", "chest_yaw", "lean", "foot_lift", "elbow", "elbow_swing", "lag", "stance", "crouch", "toe_roll", "twist_spread"]

## Overrides that are switches rather than numbers, so they are not coerced.
const _BOOLEAN_OVERRIDES := ["planted"]

const _OVERRIDE_KEYS := {
	"walk": _GAIT_KEYS,
	"run": _GAIT_KEYS,
	"strafe": _GAIT_KEYS,
	"walk_start": _GAIT_KEYS,
	"walk_stop": _GAIT_KEYS,
	"idle": ["amplitude", "head_amplitude", "look", "twist", "bob", "sway", "shift", "noise", "lean", "arm_sway", "elbow", "arm_twist", "twist_spread", "planted"],
	# Only keys a recipe actually reads are accepted. `jump` never applied
	# `foot_lift` and `turn` never applied `lean`/`toe_roll`, so they used to be
	# accepted, reported as success and change nothing; now they are refused.
	"jump": ["jump_height", "jump_crouch", "jump_distance", "arm_swing", "elbow", "lean"],
	"turn": ["turn_angle", "arm_swing", "elbow", "foot_lift", "steps"],
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
		"character_setup":
			return motion_character_setup(params)
		"jump":
			return _run_cycle(params, "jump")
		"turn_cycle":
			return _run_cycle(params, "turn")
		"strafe_cycle":
			return _run_cycle(params, "strafe")
		"walk_start":
			return _run_cycle(params, "walk_start")
		"walk_stop":
			return _run_cycle(params, "walk_stop")
		"secondary_motion":
			return motion_secondary(params)
	return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
		"Unknown op '%s'. Valid: %s" % [op, ", ".join(OpRegistry.op_names(OpRegistry.FAMILY_MOTION))])


# --- cycle ops --------------------------------------------------------------

func _run_cycle(params: Dictionary, kind: String) -> Dictionary:
	var prepared := _prepare_cycle(params, kind)
	if prepared.has("error"):
		return prepared
	# Root motion: wire the player's root_motion_track inside the same action so
	# the clip actually drives the character.
	var extra_props: Array = []
	var root_motion_track := ""
	if prepared.rooted and bool(params.get("set_root_motion", true)):
		var player_resolved := _resolve_player(str(params.get("player_path", "")))
		if not player_resolved.has("error"):
			var root_node := ValueCodec.player_root_node(player_resolved.player)
			if root_node != null:
				root_motion_track = "%s:%s" % [str(root_node.get_path_to(prepared.resolved.node)), str(prepared.ctx.hips)]
				extra_props.append({
					"object": player_resolved.player,
					"property": "root_motion_track",
					"value": NodePath(root_motion_track),
					"old": player_resolved.player.root_motion_track,
				})
	var committed := _commit_procedural_clip(params, prepared.resolved, prepared.anim_name,
		prepared.length, prepared.loop_mode, prepared.keys, prepared.markers, extra_props)
	if committed.has("error"):
		return committed
	committed.data["style"] = prepared.style
	committed.data["samples"] = prepared.rate
	committed.data["roles"] = prepared.ctx.roles
	committed.data["spine_chain"] = prepared.ctx.spine_chain
	committed.data["root_motion"] = bool(prepared.ctx.get("root_motion", false))
	committed.data["root_motion_track"] = root_motion_track
	committed.data["speed"] = float(prepared.meta.get("speed",
		_implied_speed(kind, prepared.config, prepared.ctx, prepared.length)))
	for key in prepared.meta:
		if key != "warnings":
			committed.data[key] = prepared.meta[key]
	if prepared.meta.has("warnings") and not (prepared.meta.get("warnings") as Array).is_empty():
		committed.data["warnings"] = prepared.meta.get("warnings")
	committed.data["markers"] = prepared.markers.size()
	return committed


## Compute everything a cycle needs before committing: config, context, keys,
## markers and metadata. No scene mutation, so `character_setup` can build
## several cycles and commit them in one undo action.
##
## Returns `{resolved, ctx, config, keys, markers, meta, length, rate, loop_mode,
## style, anim_name, rooted}` or an error dict.
func _prepare_cycle(params: Dictionary, kind: String) -> Dictionary:
	if not _CYCLE_KINDS.values().has(kind):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid preset '%s'. Valid: walk, run, idle, jump, turn, strafe" % kind)
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
		"jump":
			config = MotionSpecs.jump_config(style, {})
		"turn":
			config = MotionSpecs.turn_config(style, {})
		"strafe":
			config = MotionSpecs.strafe_config(style, {})
	for key in overrides:
		config[str(key)] = overrides[key]
	for key in valid_keys:
		if params.has(key):
			# Most keys are numbers, but `planted` is a switch: float(true) is 1.0
			# and float("false") is 0.0, which quietly turns a caller's boolean into
			# a number the recipe then treats as truthiness.
			config[key] = bool(params[key]) if str(key) in _BOOLEAN_OVERRIDES \
				else float(params[key])
	# Friendly top-level params map onto the per-move config keys.
	if params.has("height"):
		config["jump_height"] = float(params["height"])
	if params.has("distance"):
		config["jump_distance"] = float(params["distance"])
	if params.has("crouch"):
		config["jump_crouch"] = float(params["crouch"])
	if params.has("angle"):
		config["turn_angle"] = float(params["angle"])
	var length := float(built.length)
	var rate := float(built.rate)
	var ctx: Dictionary = built.ctx
	ctx["config"] = config
	ctx["speed"] = maxf(float(params.get("speed", 0.0)), 0.0)
	var direction := str(params.get("direction", "left"))
	if direction != "left" and direction != "right":
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'direction' must be 'left' or 'right'")
	ctx["direction"] = direction
	ctx["phase"] = clampf(float(params.get("phase", 0.0)), 0.0, 0.999)
	if kind == "strafe":
		ctx["step_axis"] = (built.ctx.lateral as Vector3) * (1.0 if direction == "left" else -1.0)
		ctx["knee_hint"] = built.ctx.forward
	var result: Dictionary
	match kind:
		"idle":
			result = MotionSpecs.idle_keys(ctx)
		"jump":
			result = MotionSpecs.jump_keys(ctx)
		"turn":
			result = MotionSpecs.turn_keys(ctx)
		"strafe":
			result = MotionSpecs.strafe_keys(ctx, direction)
		"walk_start", "walk_stop":
			result = MotionSpecs.transition_keys(ctx, kind == "walk_stop")
		_:
			result = MotionSpecs.gait_keys(ctx, kind == "run")
	var keys: Dictionary = result.get("keys", {})
	if keys.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"No bones could be keyed - check the skeleton's bone roles")
	return {
		"resolved": built.resolved,
		"ctx": ctx,
		"config": config,
		"keys": keys,
		"markers": result.get("markers", []),
		"meta": result.get("meta", {}),
		"length": length,
		"rate": rate,
		"loop_mode": int(built.loop_mode),
		"style": style,
		"kind": kind,
		"anim_name": str(params.get("animation_name", kind)),
		"rooted": bool(built.ctx.get("root_motion", false)) and not str(built.ctx.get("hips", "")).is_empty(),
	}


## Ground speed a gaits represent, in metres per second (0 for everything else).
static func _implied_speed(kind: String, config: Dictionary, ctx: Dictionary, length: float) -> float:
	if kind != "walk" and kind != "run" and kind != "strafe":
		return 0.0
	var leg: Dictionary = ctx.legs.l
	var span := 2.0 * (float(leg.upper) + float(leg.lower)) * sin(deg_to_rad(float(config.stride)))
	var stance := clampf(float(config.stance), 0.2, 0.8)
	return span / (stance * length)


# --- character setup --------------------------------------------------------

## One call, one undo: build idle + walk + run (optionally jump/turn), wire the
## locomotion AnimationTree and set the root-motion track. The clip speeds become
## the blend-space positions, so a game can feed `velocity.length()` straight
## into the returned `speed_parameter`.
func motion_character_setup(params: Dictionary) -> Dictionary:
	var context_error := _context_error()
	if not context_error.is_empty():
		return context_error
	var player_path := str(params.get("player_path", ""))
	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "character_setup needs 'player_path'")
	var resolved_player := _resolve_player(player_path)
	if resolved_player.has("error"):
		return resolved_player
	var player: AnimationPlayer = resolved_player.player
	var player_root := ValueCodec.player_root_node(player)
	if player_root == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "The AnimationPlayer has no resolvable root_node")
	var walk_speed := maxf(float(params.get("speed", 1.4)), 0.0)
	var run_speed := maxf(float(params.get("run_speed", 4.0)), 0.0)
	if walk_speed <= 0.0 or run_speed <= walk_speed:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"character_setup needs 0 < speed < run_speed (got speed=%.3f, run_speed=%.3f)" % [walk_speed, run_speed])
	var overwrite := bool(params.get("overwrite", true))
	var root_motion := bool(params.get("root_motion", true))
	var include_jump := bool(params.get("include_jump", false))
	var include_turn := bool(params.get("include_turn", false))
	var direction := str(params.get("direction", "left"))
	if direction != "left" and direction != "right":
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'direction' must be 'left' or 'right'")
	var plans: Array = [
		{"kind": "idle", "name": "idle", "args": {
			"duration": float(params.get("idle_duration", 3.0)),
			"loop_mode": "linear", "root_motion": false,
		}},
		{"kind": "walk", "name": "walk", "args": {
			"duration": float(params.get("duration", 1.0)), "speed": walk_speed,
			"loop_mode": "linear", "root_motion": root_motion,
		}},
		{"kind": "run", "name": "run", "args": {
			"duration": float(params.get("run_duration", 0.6)), "speed": run_speed,
			"loop_mode": "linear", "root_motion": root_motion,
		}},
	]
	if include_jump:
		plans.append({"kind": "jump", "name": "jump", "args": {
			"duration": float(params.get("jump_duration", 1.2)),
			"height": float(params.get("height", 0.5)),
			"crouch": float(params.get("crouch", 0.24)),
			"distance": float(params.get("distance", 0.0)),
			"loop_mode": "none", "root_motion": false,
		}})
	if include_turn:
		plans.append({"kind": "turn", "name": "turn_" + direction, "args": {
			"duration": float(params.get("turn_duration", 0.7)),
			"angle": float(params.get("angle", 90.0)),
			"direction": direction,
			"loop_mode": "none", "root_motion": false,
		}})
	var common := {
		"player_path": player_path,
		"skeleton_path": str(params.get("skeleton_path", "")),
		"roles": params.get("roles", {}),
		"profile": params.get("profile", null),
		"style": str(params.get("style", "default")),
		"samples": float(params.get("samples", 24.0)),
		"set_root_motion": false,
		"dry_run": _dry_run,
	}
	var prepared_list: Array = []
	for plan in plans:
		var forwarded: Dictionary = common.duplicate(true)
		for key in (plan.args as Dictionary):
			forwarded[key] = plan.args[key]
		var prepared := _prepare_cycle(forwarded, str(plan.kind))
		if prepared.has("error"):
			return prepared
		prepared["name"] = str(plan.name)
		prepared_list.append(prepared)
	var library: AnimationLibrary = resolved_player.library
	var created_library := false
	if library == null:
		library = AnimationLibrary.new()
		created_library = true
	var added := {}
	var removed := {}
	var clips := {}
	var clips_by_kind := {}
	for prepared in prepared_list:
		var clip_name := str(prepared.name)
		clips_by_kind[str(prepared.kind)] = clip_name
		var existing := _existing_animation(library, clip_name, overwrite)
		if existing.has("error"):
			return existing.error
		if existing.old_anim != null:
			removed[clip_name] = existing.old_anim
		var built := _build_procedural_animation({"player_path": player_path}, prepared.resolved,
			clip_name, prepared.length, prepared.loop_mode, prepared.keys, prepared.markers)
		if built.has("error"):
			return built
		added[clip_name] = built.anim
		var clip_warnings: Array = (prepared.meta.get("warnings", []) as Array).duplicate()
		var speed := 0.0
		if str(prepared.kind) == "walk" or str(prepared.kind) == "run" or str(prepared.kind) == "strafe":
			speed = float(prepared.meta.get("speed",
				_implied_speed(str(prepared.kind), prepared.config, prepared.ctx, prepared.length)))
		clips[clip_name] = {
			"kind": str(prepared.kind),
			"length": prepared.length,
			"loop_mode": ValueCodec.loop_mode_to_string(prepared.loop_mode),
			"track_count": (built.spec.tracks as Array).size(),
			"key_count": ClipSpec.total_key_count(built.spec),
			"marker_count": (prepared.markers as Array).size(),
			"speed": speed,
			"warnings": clip_warnings,
		}
	# The locomotion tree: a 1D blend space on speed (idle at 0, walk and run at
	# the speeds their clips actually have - the stride cap can make a requested
	# speed unreachable, and a blend point at a speed no clip has would ask the
	# mixer to invent one).
	var walk_solved := float((clips.get(str(clips_by_kind.walk), {}) as Dictionary).get("speed", walk_speed))
	var run_solved := float((clips.get(str(clips_by_kind.run), {}) as Dictionary).get("speed", run_speed))
	var speed_warnings: Array = []
	for pair in [[str(clips_by_kind.walk), walk_speed, walk_solved], [str(clips_by_kind.run), run_speed, run_solved]]:
		if absf(float(pair[1]) - float(pair[2])) > 0.01:
			speed_warnings.append("%s: requested %.2f m/s, the stride cap allows %.2f m/s - the blend point uses the solved speed"
				% [str(pair[0]), float(pair[1]), float(pair[2])])
	var built_space := GraphBuilders.blend_space({
		"dimensions": 1,
		"points": [
			{"animation": str(clips_by_kind.idle), "position": 0.0, "name": "idle"},
			{"animation": str(clips_by_kind.walk), "position": walk_solved, "name": "walk"},
			{"animation": str(clips_by_kind.run), "position": run_solved, "name": "run"},
		],
		"min": 0.0, "max": run_solved, "snap": 0.01, "sync": true,
	})
	if built_space.has("error"):
		return built_space
	var tree_root: AnimationNode = built_space.root
	var speed_parameter := "parameters/blend_position"
	var jump_request := ""
	if include_jump:
		var wrapped := GraphBuilders.wrap_one_shot(tree_root, "jump",
			float(params.get("jump_fadein", 0.1)), float(params.get("jump_fadeout", 0.2)))
		if wrapped.has("error"):
			return wrapped
		tree_root = wrapped.root
		speed_parameter = "parameters/Base/blend_position"
		jump_request = "parameters/OneShot/request"
	var scene_root := EditorInterface.get_edited_scene_root()
	var tree_path := str(params.get("tree_path", ""))
	var tree: AnimationTree = null
	var tree_parent: Node = null
	var created_tree := false
	if not tree_path.is_empty():
		var node := ValueCodec.resolve_scene_path(tree_path, scene_root)
		if node != null:
			if not node is AnimationTree:
				return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
					"Node at %s is not an AnimationTree (got %s)" % [tree_path, node.get_class()])
			tree = node
		else:
			var parent := ValueCodec.resolve_scene_path(tree_path.get_base_dir(), scene_root)
			if parent == null:
				return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND,
					"Cannot create an AnimationTree at %s: parent '%s' not found" % [tree_path, tree_path.get_base_dir()])
			tree = AnimationTree.new()
			tree.name = tree_path.get_file()
			tree_parent = parent
			created_tree = true
	else:
		for candidate in scene_root.find_children("*", "AnimationTree", true, false):
			var existing_tree := candidate as AnimationTree
			if existing_tree.get_node_or_null(existing_tree.anim_player) == player:
				tree = existing_tree
				break
		if tree == null:
			tree = AnimationTree.new()
			tree.name = "AnimationTree"
			tree_parent = player.get_parent() if player.get_parent() != null else scene_root
			created_tree = true
	var root_motion_track := ""
	if root_motion and not str(prepared_list[0].ctx.get("hips", "")).is_empty():
		root_motion_track = "%s:%s" % [str(player_root.get_path_to(prepared_list[0].resolved.node)), str(prepared_list[0].ctx.hips)]
	var want_active := bool(params.get("active", false))
	var old_root: AnimationRootNode = tree.tree_root if not created_tree else null
	var old_anim_player := tree.anim_player
	var old_active := tree.active
	var old_tree_root_motion := tree.root_motion_track
	var old_player_root_motion := player.root_motion_track
	var wanted_player := _tree_anim_player_path(tree, player, tree_parent, created_tree)
	if not _dry_run:
		_create_scene_pinned_action("MCP: Character setup")
		var undo := ToolContext.undo_redo
		_stage_animation_changes(undo, player, library, created_library, removed, added)
		if created_tree:
			undo.add_do_method(tree_parent, "add_child", tree, true)
			undo.add_undo_method(tree_parent, "remove_child", tree)
			undo.add_do_method(tree, "set_owner", scene_root)
			undo.add_do_reference(tree)
		undo.add_do_property(tree, "tree_root", tree_root)
		undo.add_undo_property(tree, "tree_root", old_root)
		if tree.anim_player != wanted_player:
			undo.add_do_property(tree, "anim_player", wanted_player)
			undo.add_undo_property(tree, "anim_player", old_anim_player)
		if tree.active != want_active:
			undo.add_do_property(tree, "active", want_active)
			undo.add_undo_property(tree, "active", old_active)
		if not root_motion_track.is_empty():
			undo.add_do_property(player, "root_motion_track", NodePath(root_motion_track))
			undo.add_undo_property(player, "root_motion_track", old_player_root_motion)
			undo.add_do_property(tree, "root_motion_track", NodePath(root_motion_track))
			undo.add_undo_property(tree, "root_motion_track", old_tree_root_motion)
		undo.commit_action()
	var tree_label := ""
	if created_tree:
		tree_label = "%s/%s" % [ValueCodec.from_node(tree_parent, scene_root), str(tree.name)]
	else:
		tree_label = ValueCodec.from_node(tree, scene_root)
	var parameter_paths: Array = []
	if not _dry_run and tree.get_parent() != null:
		for entry in tree.get_property_list():
			var property_name := str(entry.get("name", ""))
			if property_name.begins_with("parameters/"):
				parameter_paths.append(property_name)
		parameter_paths.sort()
		speed_parameter = _first_parameter(parameter_paths, "/blend_position", speed_parameter)
		if include_jump:
			jump_request = _first_parameter(parameter_paths, "/request", jump_request)
	var warnings: Array = []
	for clip_name in clips:
		for warning in (clips[clip_name].warnings as Array):
			warnings.append("%s: %s" % [clip_name, str(warning)])
	return {"data": {
		"player_path": player_path,
		"skeleton_path": str(prepared_list[0].resolved.path),
		"tree_path": tree_label,
		"tree_created": created_tree,
		"tree_active": want_active,
		"clips": clips,
		"root_motion": root_motion,
		"root_motion_track": root_motion_track,
		"speed_parameter": speed_parameter,
		"speed_values": {"idle": 0.0, "walk": walk_solved, "run": run_solved},
		"jump_request_parameter": jump_request,
		"parameters": parameter_paths,
		"apply_snippet": _apply_snippet(tree_label, speed_parameter, jump_request),
		"warnings": warnings + speed_warnings,
		"undoable": true,
		"note": "inactive tree by default; pass active=true (or enable the tree) when the scene is ready",
	}}


## Path from the (possibly detached) tree to the player.
func _tree_anim_player_path(tree: AnimationTree, player: AnimationPlayer, tree_parent: Node, created: bool) -> NodePath:
	if not created and tree.get_parent() != null:
		return tree.get_path_to(player)
	if tree_parent == null:
		return NodePath()
	var relative := str(tree_parent.get_path_to(player))
	if relative.is_empty():
		return NodePath("..")
	return NodePath("../" + relative)


static func _first_parameter(paths: Array, suffix: String, fallback: String) -> String:
	for path in paths:
		if str(path).ends_with(suffix):
			return str(path)
	return fallback


static func _apply_snippet(tree_label: String, speed_parameter: String, jump_request: String) -> String:
	var lines: Array = [
		"@onready var tree: AnimationTree = get_node(\"%s\")" % tree_label,
		"",
		"# each physics frame:",
		"tree.set(\"%s\", velocity.length())" % speed_parameter,
	]
	if not jump_request.is_empty():
		lines.append("")
		lines.append("if Input.is_action_just_pressed(\"jump\"):")
		lines.append("\ttree.set(\"%s\", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)" % jump_request)
	return "\n".join(lines)


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


# --- rig context ------------------------------------------------------------

func _build_context(params: Dictionary, kind: String) -> Dictionary:
	var resolved := _resolve_skeleton(params)
	if resolved.has("error"):
		return resolved
	if resolved.kind != "3d":
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "%s needs a Skeleton3D (bone roles are matched by name)" % kind)
	var skeleton: Skeleton3D = resolved.node
	var roles: Dictionary = _resolve_roles(params, skeleton)
	if roles.has("_error"):
		return roles["_error"]
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
	if not is_finite(length) or length <= 0.0:
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "duration must be a finite number > 0")
	# Every numeric recipe parameter reaches the clip as a key value, so a NaN or
	# infinity from a bad call would be written straight into the animation.
	for key in params:
		var value: Variant = params[key]
		if value is float and not is_finite(value):
			return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
				"'%s' must be a finite number (got %s)" % [str(key), str(value)])
		if value is Array or value is Dictionary:
			var bad := _first_non_finite(value, str(key))
			if not bad.is_empty():
				return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, bad)
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
	var chain := _spine_chain(params, skeleton, roles)
	if chain.has("error"):
		return chain
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
			"spine_chain": chain.chain,
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


## "overrides.lean must be a finite number (got nan)" for the first non-finite
## number inside a nested param, or "" when they are all finite.
static func _first_non_finite(value: Variant, path: String) -> String:
	if value is float and not is_finite(value):
		return "'%s' must be a finite number (got %s)" % [path, str(value)]
	if value is Array:
		for index in (value as Array).size():
			var found := _first_non_finite((value as Array)[index], "%s[%d]" % [path, index])
			if not found.is_empty():
				return found
		return ""
	if value is Dictionary:
		for key in (value as Dictionary).keys():
			var found := _first_non_finite((value as Dictionary)[key], "%s.%s" % [path, str(key)])
			if not found.is_empty():
				return found
	return ""


## The torso chain the twist distribution walks: an explicit `spine_chain` param
## when given (validated against the skeleton), otherwise detected from the bone
## parents. Returns `{"chain": [...]}` or an error, so a typo fails loudly
## instead of twisting a limb.
func _spine_chain(params: Dictionary, skeleton: Skeleton3D, roles: Dictionary) -> Dictionary:
	return resolve_spine_chain(params, skeleton, roles)


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
			return 78.0
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
			"toe": str(roles.get("toe_" + side, "")),
			"hip": rest[thigh].origin,
			"ankle": ankle,
			"upper": (rest[shin].origin - rest[thigh].origin).length(),
			"lower": lower,
		}
	return legs
