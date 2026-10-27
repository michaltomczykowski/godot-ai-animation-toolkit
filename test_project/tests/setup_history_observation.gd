@tool
extends RefCounted
## Stored native observations only. No operation dispatch, generation or pose writes.
const Stored := preload("res://tests/inspect_read_snapshot.gd")
static var _errors: Dictionary = {}
const Trace := preload("res://tests/operation_history_trace.gd")
static func marker() -> Dictionary:
 var directory := OS.get_environment("TOOLKIT_OPERATION_TRACE_DIR")
 var path := directory.path_join("active-setup-history.json")
 var span_path := directory.path_join("active-public-test-run.json")
 if directory.is_empty() or not FileAccess.file_exists(path) or not FileAccess.file_exists(span_path): return {}
 var value = JSON.parse_string(FileAccess.get_file_as_string(path))
 var span = JSON.parse_string(FileAccess.get_file_as_string(span_path))
 if not value is Dictionary or not span is Dictionary: return {}
 if value.get("context_sha256") != span.get("context_sha256") or value.get("run_id") != span.get("run_id"): return {}
 if value.get("context_sha256") != FileAccess.get_sha256(OS.get_environment("TOOLKIT_OPERATION_CONTEXT")): return {}
 var root := EditorInterface.get_edited_scene_root()
 if root == null or root.scene_file_path != value.get("scene"): return {}
 if value.get("request",{}).get("op") != "character_setup": return {}
 return value
static func _error_begin(value: Dictionary, phase: String) -> Dictionary:
 if not _errors.is_empty():
  OS.remove_logger(_errors.logger)
  _errors.clear()
  return {"complete": false, "reason": "prior setup logger scope was not closed"}
 var logger := Stored.Errors.new()
 OS.add_logger(logger)
 _errors = {"token": value.token, "begin_phase": phase, "logger": logger}
 return {"complete": true, "token": value.token, "begin_phase": phase}
static func _error_end(value: Dictionary, phase: String) -> Dictionary:
 if _errors.is_empty() or _errors.token != value.token: return {"complete": false, "reason": "missing/mismatched setup logger scope"}
 var logger: Stored.Errors = _errors.logger
 var entries := logger.entries.duplicate(true)
 OS.remove_logger(logger)
 var result := {"complete": true, "token": value.token, "begin_phase": _errors.begin_phase, "end_phase": phase,
  "errors_before": 0, "errors_after": entries.size(), "errors": entries}
 _errors.clear()
 return result
static func observe(phase: String, undo: EditorUndoRedoManager) -> void:
 var value := marker()
 if value.is_empty(): return
 if phase == "cleanup":
  if not _errors.is_empty() and _errors.token == value.token:
   OS.remove_logger(_errors.logger)
   _errors.clear()
  return
 var root := EditorInterface.get_edited_scene_root()
 var player_path := str(value.request.player_path).trim_prefix("/"+str(root.name)+"/")
 var player := root.get_node_or_null(NodePath(player_path)) as AnimationPlayer
 var clips := {}
 if player != null:
  for name in player.get_animation_list():
   var clip := player.get_animation(name)
   var tracks: Array = []
   for index in clip.get_track_count():
    var target_path := clip.track_get_path(index)
    var base := player.get_node_or_null(player.root_node)
    var target: Node = base.get_node_or_null(NodePath(target_path.get_concatenated_names())) if base!=null else null
    var bone := -1
    if target is Skeleton3D and target_path.get_subname_count()==1: bone=target.find_bone(target_path.get_subname(0))
    var keys: Array = []
    for key in clip.track_get_key_count(index):
     keys.append({"time":clip.track_get_key_time(index,key),"transition":clip.track_get_key_transition(index,key),"value":clip.track_get_key_value(index,key),"value_type":type_string(typeof(clip.track_get_key_value(index,key)))})
    tracks.append({"path":str(target_path),"type":clip.track_get_type(index),"enabled":clip.track_is_enabled(index),"interpolation":clip.track_get_interpolation_type(index),"node_class":target.get_class() if target!=null else "","node_path":str(root.get_path_to(target)) if target!=null else "","property":str(target_path.get_concatenated_subnames()),"property_type":type_string(typeof(target.get_indexed(NodePath(target_path.get_concatenated_subnames())))) if target!=null and not target is Skeleton3D and not target_path.get_concatenated_subnames().is_empty() else "","bone_index":bone,"bone_name":target.get_bone_name(bone) if target is Skeleton3D and bone>=0 else "","keys":keys})
   clips[str(name)]={"length":clip.length,"loop_mode":clip.loop_mode,"tracks":tracks}
 var row := {"op":"character_setup","mode":"setup_checkpoint","phase":phase,"marker":value,"stored":Stored.snapshot(undo),"clips":clips,"player_path":player_path,"player_class":player.get_class() if player!=null else "","player_root":str(player.root_node) if player!=null else "","scene_sha256":FileAccess.get_sha256(root.scene_file_path)}
 if phase in ["before_refusal", "before"]: row["error_boundary"] = _error_begin(value, phase)
 if phase in ["after_refusal", "after_write"]: row["error_observation"] = _error_end(value, phase)
 Trace._emit(row,"animation_motion","test_animation_motion.gd","setup_history_v1")
