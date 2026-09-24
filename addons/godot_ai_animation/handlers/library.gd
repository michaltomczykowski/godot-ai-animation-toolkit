@tool
extends "res://addons/godot_ai_animation/handlers/animation_tool_base.gd"

## Project library — the `animation_library` tool.
##
## Templates are named, reusable presets/fx calls stored in a project file
## (default `res://animation_toolkit/library.json`); clip specs are the JSON
## interchange format for whole clips (`spec_export` / `spec_import` /
## `spec_apply`). File writes are not undoable (like the core's `scene_save`);
## clip creation through `template_apply` / `spec_apply` is one undo action.

const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecIO := preload("res://addons/godot_ai_animation/spec/spec_io.gd")
const SpecJson := preload("res://addons/godot_ai_animation/spec/spec_json.gd")
const SpecBuilder := preload("res://addons/godot_ai_animation/spec/spec_builder.gd")
const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const GenerateHandler := preload("res://addons/godot_ai_animation/handlers/generate.gd")
const FxHandler := preload("res://addons/godot_ai_animation/handlers/fx.gd")
const MotionHandler := preload("res://addons/godot_ai_animation/handlers/motion.gd")
const RigHandler := preload("res://addons/godot_ai_animation/handlers/rig.gd")

const DEFAULT_LIBRARY := "res://animation_toolkit/library.json"
const LIBRARY_FORMAT := "godot-ai-animation-library"
const LIBRARY_VERSION := 1
const SPEC_DIR := "res://animation_toolkit/clips"
const _APPLIABLE_TOOLS := [
	OpRegistry.FAMILY_PRESETS, OpRegistry.FAMILY_FX, OpRegistry.FAMILY_MOTION, OpRegistry.FAMILY_RIG,
]


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
		"template_save":
			return library_template_save(params)
		"template_apply":
			return library_template_apply(params)
		"template_list":
			return library_template_list(params)
		"template_delete":
			return library_template_delete(params)
		"spec_export":
			return library_spec_export(params)
		"spec_import":
			return library_spec_import(params)
		"spec_apply":
			return library_spec_apply(params)
	return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
		"Unknown op '%s'. Valid: %s" % [op, ", ".join(OpRegistry.op_names(OpRegistry.FAMILY_LIBRARY))])


# ============================================================================
# Templates
# ============================================================================

## Save a presets/fx call as a named template in the project library.
func library_template_save(params: Dictionary) -> Dictionary:
	var name := str(params.get("name", ""))
	if name.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "template_save needs 'name'")
	var tool := str(params.get("tool", OpRegistry.FAMILY_PRESETS))
	if not _APPLIABLE_TOOLS.has(tool):
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Invalid tool '%s'. Valid: %s" % [tool, ", ".join(_APPLIABLE_TOOLS)])
	var target_op := str(params.get("forward_op", params.get("op_name", "")))
	if target_op.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"template_save needs 'forward_op': the %s op to store" % tool)
	if OpRegistry.find_op(tool, target_op).is_empty():
		return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE,
			"Unknown op '%s' for %s. Valid: %s" % [target_op, tool, ", ".join(OpRegistry.op_names(tool))])
	var stored := {}
	var known := _op_param_names(tool, target_op)
	for key in params:
		if key in ["op", "name", "tool", "forward_op", "op_name", "overwrite", "library_path", "description", "dry_run"]:
			continue
		if known.has(str(key)):
			stored[str(key)] = params[key]
	var path := str(params.get("library_path", DEFAULT_LIBRARY))
	var loaded := _load_library(path)
	if loaded.has("error"):
		return loaded
	var library: Dictionary = loaded.library
	var overwrite := bool(params.get("overwrite", false))
	if library.templates.has(name) and not overwrite:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Template '%s' already exists. Pass overwrite=true to replace it." % name)
	var existed: bool = (library.templates as Dictionary).has(name)
	library.templates[name] = {
		"tool": tool,
		"op": target_op,
		"params": stored,
		"description": str(params.get("description", "")),
	}
	var written := _save_library(path, library)
	if written.has("error"):
		return written
	return {"data": {
		"library_path": path,
		"template": name,
		"tool": tool,
		"op": target_op,
		"params": stored,
		"param_count": stored.size(),
		"template_count": (library.templates as Dictionary).size(),
		"overwritten": existed,
		"undoable": false,
		"note": "library files are not part of the undo stack",
	}}


## Apply a saved template (with optional overrides) through its original tool.
func library_template_apply(params: Dictionary) -> Dictionary:
	var name := str(params.get("name", ""))
	if name.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "template_apply needs 'name'")
	var path := str(params.get("library_path", DEFAULT_LIBRARY))
	var loaded := _load_library(path)
	if loaded.has("error"):
		return loaded
	var library: Dictionary = loaded.library
	if not library.templates.has(name):
		var names: Array = (library.templates as Dictionary).keys()
		names.sort()
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Template '%s' not found in %s. Templates: %s"
			% [name, path, ", ".join(names) if not names.is_empty() else "(none)"])
	var template: Dictionary = library.templates[name]
	var forwarded: Dictionary = (template.params as Dictionary).duplicate(true)
	for key in params:
		if key in ["op", "name", "library_path", "description", "forward_op", "op_name"]:
			continue
		forwarded[str(key)] = params[key]
	forwarded["op"] = str(template.op)
	if bool(params.get("dry_run", false)):
		forwarded["dry_run"] = true
	var result := _run_tool(str(template.tool), forwarded)
	if result.has("data"):
		result.data["template"] = name
		result.data["library_path"] = path
		result.data["applied_tool"] = str(template.tool)
		result.data["applied_op"] = str(template.op)
	return result


## List the saved templates.
func library_template_list(params: Dictionary) -> Dictionary:
	var path := str(params.get("library_path", DEFAULT_LIBRARY))
	var loaded := _load_library(path, true)
	if loaded.has("error"):
		return loaded
	var library: Dictionary = loaded.library
	var entries: Array = []
	for name in library.templates:
		var template: Dictionary = library.templates[name]
		entries.append({
			"name": str(name),
			"tool": str(template.get("tool", "")),
			"op": str(template.get("op", "")),
			"description": str(template.get("description", "")),
			"params": template.get("params", {}),
			"param_count": (template.get("params", {}) as Dictionary).size(),
		})
	entries.sort_custom(func(a, b): return str(a.name) < str(b.name))
	return {"data": {
		"library_path": path,
		"exists": bool(loaded.get("exists", false)),
		"template_count": entries.size(),
		"templates": entries,
	}}


## Remove a template.
func library_template_delete(params: Dictionary) -> Dictionary:
	var name := str(params.get("name", ""))
	if name.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "template_delete needs 'name'")
	var path := str(params.get("library_path", DEFAULT_LIBRARY))
	var loaded := _load_library(path)
	if loaded.has("error"):
		return loaded
	var library: Dictionary = loaded.library
	if not library.templates.has(name):
		var names: Array = (library.templates as Dictionary).keys()
		names.sort()
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Template '%s' not found in %s. Templates: %s"
			% [name, path, ", ".join(names) if not names.is_empty() else "(none)"])
	var removed: Dictionary = library.templates[name]
	library.templates.erase(name)
	var written := _save_library(path, library)
	if written.has("error"):
		return written
	return {"data": {
		"library_path": path,
		"template": name,
		"removed_tool": str(removed.get("tool", "")),
		"removed_op": str(removed.get("op", "")),
		"template_count": (library.templates as Dictionary).size(),
		"undoable": false,
	}}


# ============================================================================
# Clip specs
# ============================================================================

## Write a clip from an AnimationPlayer to a JSON spec file.
func library_spec_export(params: Dictionary) -> Dictionary:
	var player_path := str(params.get("player_path", ""))
	var anim_name := str(params.get("animation_name", ""))
	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "spec_export needs 'player_path'")
	if anim_name.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "spec_export needs 'animation_name'")
	var resolved := _resolve_player(player_path)
	if resolved.has("error"):
		return resolved
	var player: AnimationPlayer = resolved.player
	var library: AnimationLibrary = resolved.library
	if library == null or not library.has_animation(anim_name):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Animation '%s' not found on %s" % [anim_name, player_path])
	var anim: Animation = library.get_animation(anim_name)
	var unsupported := SpecIO.unsupported_tracks(anim)
	if not unsupported.is_empty():
		return ErrorCodes.make(ErrorCodes.WRONG_TYPE,
			"Animation '%s' has tracks this toolkit cannot export: %s"
			% [anim_name, SpecIO.describe_unsupported(anim)])
	var spec := SpecIO.from_animation(anim)
	var path := str(params.get("path", ""))
	if path.is_empty():
		path = "%s/%s.json" % [SPEC_DIR, anim_name]
	var written := _write_json(path, SpecJson.to_json(spec), bool(params.get("overwrite", true)))
	if written.has("error"):
		return written
	return {"data": {
		"path": path,
		"player_path": player_path,
		"animation_name": anim_name,
		"undoable": false,
		"note": "spec files are not part of the undo stack",
	}}


## Read a JSON spec file (or inline spec) and report what it contains.
func library_spec_import(params: Dictionary) -> Dictionary:
	var loaded := _resolve_spec(params)
	if loaded.has("error"):
		return loaded
	var spec: Dictionary = loaded.spec
	var summary := SpecJson.summarize(spec)
	var issues := _spec_issues(spec)
	return {"data": {
		"path": str(loaded.get("path", "")),
		"length": float(summary.length),
		"loop_mode": ValueCodec.loop_mode_to_string(int(summary.loop_mode)),
		"track_count": int(summary.track_count),
		"key_count": int(summary.key_count),
		"track_types": summary.track_types,
		"paths": summary.paths,
		"issues": issues,
	}}


## Build a clip from a JSON spec file (or an inline spec), optionally remapping
## every track onto `target_path`.
func library_spec_apply(params: Dictionary) -> Dictionary:
	var player_path := str(params.get("player_path", ""))
	if player_path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM, "spec_apply needs 'player_path'")
	var context_error := _context_error()
	if not context_error.is_empty():
		return context_error
	var resolved := _resolve_player(player_path)
	if resolved.has("error"):
		return resolved
	var player: AnimationPlayer = resolved.player
	var library: AnimationLibrary = resolved.library
	var created_library := false
	if library == null:
		library = AnimationLibrary.new()
		created_library = true
	var loaded := _resolve_spec(params)
	if loaded.has("error"):
		return loaded
	var spec: Dictionary = loaded.spec
	var target_path := str(params.get("target_path", ""))
	var resolved_target := ""
	if not target_path.is_empty():
		var target_result := _resolve_spec_target(player, target_path)
		if target_result.has("error"):
			return target_result
		resolved_target = str(target_result.track_path_root)
		spec = SpecJson.remap_node(spec, resolved_target)
	var anim_name := str(params.get("animation_name", ""))
	if anim_name.is_empty():
		var from_path := str(loaded.get("path", ""))
		anim_name = from_path.get_file().get_basename() if not from_path.is_empty() else "clip"
	var valid := SpecBuilder.validate(spec)
	if valid.has("error"):
		return valid
	var overwrite := bool(params.get("overwrite", false))
	var existing := _existing_animation(library, anim_name, overwrite)
	if existing.has("error"):
		return existing.error
	var anim := SpecBuilder.to_animation(spec)
	_commit_animation_add("MCP: Apply clip spec %s" % anim_name, player, library,
		created_library, anim_name, anim, existing.old_anim)
	var summary := SpecJson.summarize(spec)
	return {"data": {
		"player_path": player_path,
		"animation_name": anim_name,
		"source_path": str(loaded.get("path", "")),
		"target_path": resolved_target if not resolved_target.is_empty() else target_path,
		"length": float(summary.length),
		"loop_mode": ValueCodec.loop_mode_to_string(int(summary.loop_mode)),
		"track_count": int(summary.track_count),
		"key_count": int(summary.key_count),
		"paths": summary.paths,
		"issues": _spec_issues(spec, player),
		"library_created": created_library,
		"overwritten": existing.old_anim != null,
		"undoable": true,
	}}


# ============================================================================
# Helpers
# ============================================================================

## Resolve a remap target the way the presets do: scene-absolute paths become
## root_node-relative track paths, relative paths are used as-is.
func _resolve_spec_target(player: AnimationPlayer, target_path: String) -> Dictionary:
	var root_node := ValueCodec.player_root_node(player)
	if root_node == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"AnimationPlayer at %s has no resolvable root_node (is the scene open?)" % str(player.get_path()))
	if not target_path.begins_with("/"):
		if root_node.get_node_or_null(target_path) == null:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"Target node not found at '%s' (relative to the player's root_node '%s')"
				% [target_path, str(root_node.name)])
		return {"track_path_root": target_path}
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return ErrorCodes.make(ErrorCodes.EDITOR_NOT_READY, "No edited scene open")
	var target := ValueCodec.resolve_scene_path(target_path, scene_root)
	if target == null:
		return ErrorCodes.make(ErrorCodes.NODE_NOT_FOUND, ValueCodec.format_node_error(target_path, scene_root))
	return {"track_path_root": str(root_node.get_path_to(target))}


## Resolve a spec from `spec` (inline dict) or `path` (JSON file).
func _resolve_spec(params: Dictionary) -> Dictionary:
	var inline = params.get("spec")
	if inline is Dictionary and not (inline as Dictionary).is_empty():
		var decoded := SpecJson.from_json(inline)
		if decoded.has("error"):
			return decoded
		return {"spec": decoded.spec, "path": ""}
	var path := str(params.get("path", ""))
	if path.is_empty():
		return ErrorCodes.make(ErrorCodes.MISSING_REQUIRED_PARAM,
			"Pass 'path' (a spec JSON file) or 'spec' (an inline clip spec)")
	if not FileAccess.file_exists(path):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "Spec file not found: %s" % path)
	var raw := _read_json(path)
	if raw.has("error"):
		return raw
	var decoded_file := SpecJson.from_json(raw.data)
	if decoded_file.has("error"):
		return ErrorCodes.make(decoded_file.error.code, "%s: %s" % [path, str(decoded_file.error.message)])
	return {"spec": decoded_file.spec, "path": path}


func _spec_issues(spec: Dictionary, player: AnimationPlayer = null) -> Array:
	var issues: Array = []
	if float(spec.get("length", 0.0)) <= 0.0011:
		issues.append({"severity": "warning", "code": "zero_length",
			"message": "the clip has no length and will not play"})
	for track in spec.get("tracks", []):
		var path := str(track.get("path", ""))
		if player != null:
			var root := ValueCodec.player_root_node(player)
			if root != null and root.get_node_or_null(NodePath(ClipSpec.node_path_of(path))) == null:
				issues.append({"severity": "warning", "code": "missing_node",
					"message": "track '%s' does not resolve on this player" % path})
	return issues


func _op_param_names(tool: String, op_name: String) -> Array:
	var descriptor := OpRegistry.find_op(tool, op_name)
	return descriptor.get("params", [])


func _run_tool(tool: String, forwarded: Dictionary) -> Dictionary:
	if tool == OpRegistry.FAMILY_PRESETS:
		return GenerateHandler.new().run(forwarded, null)
	if tool == OpRegistry.FAMILY_FX:
		return FxHandler.new().run(forwarded, null)
	if tool == OpRegistry.FAMILY_MOTION:
		return MotionHandler.new().run(forwarded, null)
	if tool == OpRegistry.FAMILY_RIG:
		return RigHandler.new().run(forwarded, null)
	return ErrorCodes.make(ErrorCodes.VALUE_OUT_OF_RANGE, "Cannot apply templates for tool '%s'" % tool)


# --- library file I/O ------------------------------------------------------

func _load_library(path: String, _allow_missing: bool = false) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"library": {"format": LIBRARY_FORMAT, "version": LIBRARY_VERSION, "templates": {}}, "exists": false}
	var raw := _read_json(path)
	if raw.has("error"):
		return raw
	var data: Dictionary = raw.data
	if str(data.get("format", LIBRARY_FORMAT)) != LIBRARY_FORMAT:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"%s is not a %s file" % [path, LIBRARY_FORMAT])
	var templates = data.get("templates", {})
	if not templates is Dictionary:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "%s has a malformed 'templates' section" % path)
	return {"library": {"format": LIBRARY_FORMAT, "version": LIBRARY_VERSION, "templates": templates}, "exists": true}


func _save_library(path: String, library: Dictionary) -> Dictionary:
	var data := {
		"format": LIBRARY_FORMAT,
		"version": LIBRARY_VERSION,
		"templates": library.templates,
	}
	return _write_json(path, data, true)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Cannot read %s (%s)" % [path, error_string(FileAccess.get_open_error())])
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "%s is not valid JSON" % path)
	if not parsed is Dictionary:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS, "%s must contain a JSON object" % path)
	return {"data": parsed}


func _write_json(path: String, data: Dictionary, overwrite: bool) -> Dictionary:
	if not overwrite and FileAccess.file_exists(path):
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"%s already exists. Pass overwrite=true to replace it." % path)
	var directory := path.get_base_dir()
	if not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		var made := DirAccess.make_dir_recursive_absolute(directory)
		if made != OK:
			return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
				"Cannot create %s (%s)" % [directory, error_string(made)])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ErrorCodes.make(ErrorCodes.INVALID_PARAMS,
			"Cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return {"ok": true}
