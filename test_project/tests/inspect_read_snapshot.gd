@tool
extends RefCounted

# No toolkit sampling, grading or snapshot implementation is used here.
static var active: Dictionary = {}
class Errors extends Logger:
 var entries: Array = []
 func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, type: int, _backtraces: Array) -> void:
  if type != 1: entries.append({"function": function, "file": file, "line": line, "code": code, "message": rationale, "type": type})

static func bytes_hash(value: Variant) -> String:
 var hash := HashingContext.new()
 hash.start(HashingContext.HASH_SHA256)
 hash.update(var_to_bytes(value))
 return hash.finish().hex_encode()

static func marker(test: String) -> Dictionary:
 var directory := OS.get_environment("TOOLKIT_OPERATION_TRACE_DIR")
 var path := directory.path_join("active-inspect-read.json")
 var span_path := directory.path_join("active-public-test-run.json")
 if directory.is_empty() or not FileAccess.file_exists(path) or not FileAccess.file_exists(span_path): return {}
 var value = JSON.parse_string(FileAccess.get_file_as_string(path))
 var span = JSON.parse_string(FileAccess.get_file_as_string(span_path))
 if not value is Dictionary or not span is Dictionary: return {}
 if span.get("request") != {"suite": "inspect_read_witness", "test_name": test, "verbose": true}: return {}
 if not value.get("request") is Dictionary or value.get("stage") not in ["valid", "refusal"]: return {}
 var edited := EditorInterface.get_edited_scene_root()
 if edited == null or edited.scene_file_path != value.get("scene"): return {}
 var op := str(value.request.get("op", ""))
 if value.get("operation") != "animation_inspect." + op: return {}
 if value.get("scene") == "res://repair_edit_fixture.tscn":
  if op not in ["describe", "timeline", "audit", "compare", "stats", "motion_report", "dry_run", "help"]: return {}
 elif value.get("scene") == "res://repair_motion_fixture.tscn":
  if op not in ["rig_profile", "sample", "motion_audit"]: return {}
 else: return {}
 if value.get("context_sha256") != span.get("context_sha256") or value.get("run_id") != span.get("run_id"): return {}
 var context := OS.get_environment("TOOLKIT_OPERATION_CONTEXT")
 if value.get("context_sha256") != FileAccess.get_sha256(context): return {}
 return value

static func _file(path: String, files: Dictionary) -> void:
 var source := path.get_slice("::", 0)
 if source.begins_with("res://") and not files.has(source) and FileAccess.file_exists(source): files[source] = FileAccess.get_sha256(source)

static func _canonical(value: Variant, resources: Dictionary, files: Dictionary, unsupported: Array) -> Variant:
 if value == null or value is bool or value is int or value is String: return value
 if value is StringName or value is NodePath: return {"type": type_string(typeof(value)), "value": str(value)}
 if value is Node: return {"node": str(value.get_path()), "id": value.get_instance_id()}
 if value is Resource:
  var id := str(value.get_instance_id())
  if resources.has(id): return {"resource_id": id}
  var record := {"class": value.get_class(), "path": value.resource_path, "properties": {}}
  resources[id] = record
  _file(value.resource_path, files)
  if value is Script: return {"resource_id": id}
  for property in value.get_property_list():
   if int(property.usage) & PROPERTY_USAGE_STORAGE:
    record.properties[str(property.name)] = _canonical(value.get(property.name), resources, files, unsupported)
  return {"resource_id": id}
 if value is Dictionary:
  var entries: Array = []
  for key in value:
   entries.append([_canonical(key, resources, files, unsupported), _canonical(value[key], resources, files, unsupported)])
  return {"dictionary": entries}
 if value is Array:
  var items: Array = []
  for item in value: items.append(_canonical(item, resources, files, unsupported))
  return {"array": items}
 var type := typeof(value)
 if type in [TYPE_FLOAT, TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_RECT2, TYPE_RECT2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_TRANSFORM2D, TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_PLANE, TYPE_QUATERNION, TYPE_AABB, TYPE_BASIS, TYPE_TRANSFORM3D, TYPE_PROJECTION, TYPE_COLOR, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY]:
  return {"type": type_string(type), "bytes_sha256": bytes_hash(value)}
 unsupported.append(type_string(type))
 return {"unsupported": type_string(type)}

static func _tree(node: Node, root: Node, nodes: Dictionary, resources: Dictionary, files: Dictionary, unsupported: Array) -> void:
 var path := str(root.get_path_to(node))
 var record := {"id": node.get_instance_id(), "class": node.get_class(), "name": str(node.name), "properties": {}, "children": []}
 nodes[path] = record
 _file(node.scene_file_path, files)
 for property in node.get_property_list():
  if int(property.usage) & PROPERTY_USAGE_STORAGE:
   record.properties[str(property.name)] = _canonical(node.get(property.name), resources, files, unsupported)
 if node is Skeleton3D:
  var bones: Array = []
  for index in node.get_bone_count():
   bones.append({"name": node.get_bone_name(index), "parent": node.get_bone_parent(index), "rest": _canonical(node.get_bone_rest(index), resources, files, unsupported), "position": _canonical(node.get_bone_pose_position(index), resources, files, unsupported), "rotation": _canonical(node.get_bone_pose_rotation(index), resources, files, unsupported), "scale": _canonical(node.get_bone_pose_scale(index), resources, files, unsupported), "enabled": node.is_bone_enabled(index)})
  record["bones"] = bones
 if node is AnimationPlayer:
  var current := str(node.current_animation)
  var assigned := str(node.assigned_animation)
  record["playback"] = {"assigned": assigned, "current": current, "playing": node.is_playing(), "queue": _canonical(node.get_queue(), resources, files, unsupported), "speed": node.speed_scale, "playing_speed": node.get_playing_speed(), "position": node.current_animation_position if not current.is_empty() else null}
  if current.is_empty() and not assigned.is_empty(): unsupported.append("unreadable_stopped_or_paused_Player_position:" + path)
  var libraries := {}
  for name in node.get_animation_library_list(): libraries[str(name)] = _canonical(node.get_animation_library(name), resources, files, unsupported)
  record["libraries"] = libraries
  var clips := {}
  for name in node.get_animation_list(): clips[str(name)] = _canonical(node.get_animation(name), resources, files, unsupported)
  record["clips"] = clips
 for child in node.get_children():
  record.children.append(str(child.name))
  _tree(child, root, nodes, resources, files, unsupported)

static func _write_files(directory: String, files: Dictionary) -> void:
 var dir := DirAccess.open(directory)
 if dir == null: return
 for name in dir.get_files(): files[directory.path_join(name)] = FileAccess.get_sha256(directory.path_join(name))
 for name in dir.get_directories(): _write_files(directory.path_join(name), files)

static func snapshot(undo: EditorUndoRedoManager) -> Dictionary:
 var root := EditorInterface.get_edited_scene_root()
 var nodes := {}
 var resources := {}
 var files := {}
 var unsupported: Array = []
 if root == null: return {"unsupported": ["no_scene"]}
 _tree(root, root, nodes, resources, files, unsupported)
 _write_files("res://animation_toolkit", files)
 var history := undo.get_history_undo_redo(undo.get_object_history_id(root))
 var global_history := undo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)
 return {"scene": root.scene_file_path, "nodes": nodes, "resources": resources, "files": files, "unsupported": unsupported, "history": history.get_version(), "global_history": global_history.get_version()}

static func begin(value: Dictionary, undo: EditorUndoRedoManager) -> void:
 var errors := Errors.new()
 OS.add_logger(errors)
 active = {"marker": value.duplicate(true), "logger": errors, "begin_ticks": Time.get_ticks_usec()}
 active["before"] = snapshot(undo)

static func finish(value: Dictionary, undo: EditorUndoRedoManager) -> Dictionary:
 var before: Dictionary = active.get("before", {"unsupported": ["incomplete_begin"]})
 var logger: Errors = active.logger
 var after := snapshot(undo)
 var errors := logger.entries.duplicate(true)
 OS.remove_logger(logger)
 var row := {"op": str(value.request.op), "marker": value, "before": before, "after": after, "begin_marker": active.marker, "errors": errors, "errors_before": 0, "errors_after": errors.size(), "snapshot_schema": "stored_graph_v1"}
 active.clear()
 if str(value.stage) == "valid" and str(value.request.op) in ["sample", "motion_audit"]:
  var reference_logger := Errors.new()
  OS.add_logger(reference_logger)
  row["reference"] = preload("res://tests/inspect_native_reference.gd").build(value)
  row["after_reference"] = snapshot(undo)
  row["reference_errors"] = reference_logger.entries.duplicate(true)
  OS.remove_logger(reference_logger)
 return row
