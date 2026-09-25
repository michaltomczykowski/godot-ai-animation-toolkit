@tool
extends RefCounted

## Value and plumbing helpers ported from the core animation handler so this
## addon is self-contained (no core handler internals): transition names,
## loop-mode labels, serialization, scene-path resolution, and value coercion
## against a resolved property.

const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")

## Every file this toolkit writes lives under here. A write path arrives as a
## caller's string, and "res://" or a project file is one typo (or one confused
## agent) away, so the writers are confined to this subtree.
const WRITE_ROOT := "res://animation_toolkit/"

## Named transition vocabulary shared with the core animation tooling
## (docs/animation-recipes.md): linear/ease_in/ease_out/ease_in_out.
const _NAMED_TRANSITIONS := {
	"linear": 1.0,
	"ease_in": 2.0,
	"ease_out": 0.5,
	"ease_in_out": -2.0,
}

const _COLOR_SENTINEL := Color(-1.0, -1.0, -1.0, -1.0)


static func parse_transition(v: Variant) -> float:
	if v is float or v is int:
		return float(v)
	if v is String:
		var key: String = (v as String).to_lower()
		if _NAMED_TRANSITIONS.has(key):
			return float(_NAMED_TRANSITIONS[key])
	return 1.0


static func loop_mode_to_string(mode: int) -> String:
	match mode:
		Animation.LOOP_LINEAR:
			return "linear"
		Animation.LOOP_PINGPONG:
			return "pingpong"
		_:
			return "none"


## Check a path this toolkit is about to write. Returns "" when it is allowed,
## otherwise a message naming the rule that refused it.
##
## Two rules, both about the path arriving as a caller's string:
## - it must be inside `WRITE_ROOT` (so `res://`, `user://` and an absolute path
##   are all refused, as is `res://animation_toolkit/../scenes/Main.tscn` once
##   simplified);
## - its file name must be a plain name - no separators, no `..`, no leading dot
##   and none of the characters Godot refuses in a node name.
static func check_write_path(path: String) -> String:
	var trimmed := path.strip_edges()
	if trimmed.is_empty():
		return "'path' must not be empty"
	if not trimmed.begins_with("res://"):
		return "Writes are confined to %s (got '%s', an absolute or user:// path)" % [WRITE_ROOT, trimmed]
	var simplified := trimmed.simplify_path()
	if not simplified.begins_with(WRITE_ROOT):
		return "Writes are confined to %s (got '%s')" % [WRITE_ROOT, trimmed]
	var file_name := simplified.get_file()
	if file_name.is_empty() or file_name == ".":
		return "'%s' does not name a file" % simplified
	for bad in ["/", "\\", ":", ".."]:
		if file_name.contains(str(bad)):
			return "The file name '%s' must be a plain name" % file_name
	if file_name.begins_with("."):
		return "The file name '%s' must not start with a dot" % file_name
	for bad in [".", "@", "\"", "%", "$", "&", "'", "*", ":", ";"]:
		if file_name.contains(str(bad)) and str(bad) != ".":
			return "The file name '%s' contains '%s', which is not allowed" % [file_name, str(bad)]
	return ""


## Join a caller-supplied directory and file name under `WRITE_ROOT`, refusing
## anything that would escape it. `directory` may be "" (use the default) or a
## path inside the root; `file_name` must be a plain file name.
static func toolkit_write_path(directory: String, file_name: String) -> Dictionary:
	if file_name.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "A file name is required")
	var problem := check_write_path("%s%s" % [WRITE_ROOT, file_name])
	if not problem.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, problem)
	var base := directory.strip_edges()
	if base.is_empty():
		return {"ok": true, "path": "%s%s" % [WRITE_ROOT, file_name]}
	if not base.begins_with(WRITE_ROOT):
		base = WRITE_ROOT + base.trim_prefix("/")
	var problem_dir := check_write_path("%sx" % base)
	if not problem_dir.is_empty():
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Directory: %s" % problem_dir)
	return {"ok": true, "path": "%s/%s" % [base, file_name]}

## The node animation track paths are stored relative to: the player's explicit
## `root_node` when set and resolvable, else its parent.
static func player_root_node(player: AnimationPlayer) -> Node:
	if not player.is_inside_tree():
		return null
	var root_path := player.root_node
	if root_path != NodePath():
		var node := player.get_node_or_null(root_path)
		if node != null:
			return node
	return player.get_parent()


static func serialize(value: Variant) -> Variant:
	if value == null:
		return null
	if value is Color:
		return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}
	if value is Vector2:
		return {"x": value.x, "y": value.y}
	if value is Vector3:
		return {"x": value.x, "y": value.y, "z": value.z}
	return value


## Resolve a scene path against the edited scene root. Mirrors the core
## McpScenePath vocabulary: "/" and "/<SceneRoot>" are the root,
## "/root/<SceneRoot>/..." is an alias, anything else is a node path under the
## root.
static func resolve_scene_path(path: String, scene_root: Node) -> Node:
	if scene_root == null:
		return null
	if path == "/":
		return scene_root
	var alias_prefix := "/root/" + scene_root.name
	if path == alias_prefix or path.begins_with(alias_prefix + "/"):
		return resolve_scene_path(path.substr(5), scene_root)
	var root_prefix := "/" + scene_root.name
	if path == root_prefix:
		return scene_root
	if path.begins_with(root_prefix + "/"):
		return scene_root.get_node_or_null(path.substr(root_prefix.length() + 1))
	return scene_root.get_node_or_null(path)


static func format_node_error(path: String, scene_root: Node) -> String:
	if scene_root == null:
		return "Node not found: %s. No edited scene is open." % path
	var root_name := str(scene_root.name)
	if path.begins_with("/root/"):
		var after_root := path.substr(6)
		var first_segment := after_root.split("/")[0]
		if first_segment != root_name and not first_segment.is_empty():
			return "Node not found: %s. Did you mean '/%s/%s'?" % [path, root_name, after_root]
	if not path.begins_with("/") and not path.is_empty():
		return "Node not found: %s (relative to the edited scene root '%s')." % [path, root_name]
	return "Node not found: %s (scene root '%s')." % [path, root_name]


## Scene-relative path of `node` for error hints: "/<SceneRoot>" or
## "/<SceneRoot>/<path>".
static func from_node(node: Node, scene_root: Node) -> String:
	if scene_root == null or node == null:
		return ""
	if node == scene_root:
		return "/" + scene_root.name
	if not scene_root.is_ancestor_of(node):
		return "/" + node.name
	return "/" + scene_root.name + "/" + str(scene_root.get_path_to(node))


## Coerce a JSON value to the type of `target`'s `property` (or of a
## "property:component" subpath) so the generalized pulse can breathe floats
## and jitter vectors without the core's full parser stack.
static func coerce_for_property(raw: Variant, target: Node, property: String) -> Dictionary:
	var parts := property.split(":")
	var base := parts[0]
	var sub := parts[1] if parts.size() > 1 else ""
	if not _has_property(target, base):
		return ErrorCodes.make(ErrorCodes.PROPERTY_NOT_ON_CLASS,
			"Target '%s' (class %s) has no '%s' property" % [target.name, target.get_class(), base])
	if not sub.is_empty():
		## Component subpaths (:x/:y/:z/:a/...) are scalar floats.
		return _coerce_float(raw, property)
	var current: Variant = target.get(base)
	match typeof(current):
		TYPE_FLOAT, TYPE_INT:
			return _coerce_float(raw, property)
		TYPE_VECTOR2:
			var v2 := _coerce_components(raw, 2)
			if v2.has("error"):
				return v2
			return {"ok": Vector2(v2.ok[0], v2.ok[1])}
		TYPE_VECTOR3:
			var v3 := _coerce_components(raw, 3)
			if v3.has("error"):
				return v3
			return {"ok": Vector3(v3.ok[0], v3.ok[1], v3.ok[2])}
		TYPE_COLOR:
			return _coerce_color(raw)
	return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
		"Unsupported '%s' type '%s'. Supported: float, Vector2, Vector3, Color"
		% [property, type_string(typeof(current))])


static func _has_property(target: Node, property: String) -> bool:
	for entry in target.get_property_list():
		if entry.name == property:
			return true
	return false


static func _coerce_float(raw: Variant, label: String) -> Dictionary:
	var number: float
	if raw is int or raw is float:
		number = float(raw)
	elif raw is String and (raw as String).is_valid_float():
		number = (raw as String).to_float()
	else:
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"'%s' value must be a number (got %s)" % [label, type_string(typeof(raw))])
	if not is_finite(number):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "'%s' value must be finite" % label)
	return {"ok": number}


static func _coerce_components(raw: Variant, count: int) -> Dictionary:
	var components: Array = []
	if raw is Array:
		var arr: Array = raw
		if arr.size() != count:
			return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
				"Expected %d components, got %d" % [count, arr.size()])
		components = arr
	elif raw is Dictionary:
		var keys := ["x", "y", "z"]
		var dict: Dictionary = raw
		for i in count:
			if not dict.has(keys[i]):
				return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
					"Missing component '%s'" % keys[i])
			components.append(dict[keys[i]])
	else:
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"Expected an array or {x,y[,z]} dict (got %s)" % type_string(typeof(raw)))
	var parsed: Array = []
	for component in components:
		var result := _coerce_float(component, "component")
		if result.has("error"):
			return result
		parsed.append(result.ok)
	return {"ok": parsed}


static func _coerce_color(raw: Variant) -> Dictionary:
	if raw is Color:
		return {"ok": raw}
	if raw is String:
		var parsed := Color.from_string(raw as String, _COLOR_SENTINEL)
		if parsed.is_equal_approx(_COLOR_SENTINEL):
			return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
				"Color string '%s' is not a valid hex or named color" % raw)
		return {"ok": parsed}
	if raw is Dictionary:
		var dict: Dictionary = raw
		for key in ["r", "g", "b"]:
			if not dict.has(key):
				return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
					"Color dict is missing '%s'" % key)
		var components := [dict.r, dict.g, dict.b, dict.get("a", 1.0)]
		var parsed: Array = []
		for component in components:
			var result := _coerce_float(component, "color")
			if result.has("error"):
				return result
			parsed.append(result.ok)
		return {"ok": Color(parsed[0], parsed[1], parsed[2], parsed[3])}
	return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
		"Expected a Color, hex/named string, or {r,g,b[,a]} dict (got %s)" % type_string(typeof(raw)))
