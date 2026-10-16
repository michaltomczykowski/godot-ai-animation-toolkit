@tool
extends RefCounted

## Optional raw evidence only. The Python public wrapper owns the active span;
## this helper never invokes an operation or alters test assertion state.
static func emit_fx(row: Dictionary) -> void:
	_emit(row, "animation_fx", "test_fx_route_history.gd", "fx_history_v1")

static func emit_edit(row: Dictionary) -> void:
	_emit(row, "animation_edit", "test_edit_route_history.gd", "edit_history_v1")

static func emit_library_file(row: Dictionary) -> void:
	_emit(row, "animation_library", "test_library_contracts.gd", "library_file_v1")

static func emit_library_read(row: Dictionary) -> void:
	_emit(row, "animation_library", "test_library_contracts.gd", "library_read_refusal_v1")

static func emit_preset_library(row: Dictionary, family: String) -> void:
	_emit(row, family, "test_preset_library_history.gd", "preset_library_history_v1")

static func _emit(row: Dictionary, family: String, driver: String, validator: String) -> void:
	var context_path := OS.get_environment("TOOLKIT_OPERATION_CONTEXT")
	var trace_dir := OS.get_environment("TOOLKIT_OPERATION_TRACE_DIR")
	if context_path.is_empty() and trace_dir.is_empty(): return
	var active_path := trace_dir.path_join("active-public-test-run.json")
	if not FileAccess.file_exists(active_path):
		# Full editor suite runs outside the public collector remain ordinary tests.
		return
	var span: Variant = JSON.parse_string(FileAccess.get_file_as_string(active_path))
	if not span is Dictionary or span.get("context_sha256") != FileAccess.get_sha256(context_path):
		push_error("History evidence has a foreign public test span")
		return
	var stem := "%s-editor-%s-%s" % [span.run_id, OS.get_process_id(), Time.get_ticks_usec()]
	var event := {"schema_version": 1, "kind": "editor_history_assertions",
		"context_sha256": span.context_sha256, "run_id": span.run_id,
		"id": stem + ":1", "sequence": 1,
		"time_ns": int(Time.get_unix_time_from_system() * 1000000000.0),
		"driver": driver, "route": "public_test_run_inner_dispatch",
		"operation": family + "." + str(row.op), "validator": validator,
		"test_run_begin_id": span.begin_id, "row": _safe(row)}
	var file := FileAccess.open(trace_dir.path_join(stem + ".jsonl"), FileAccess.WRITE)
	if file == null:
		push_error("History evidence file could not be written")
		return
	file.store_line(JSON.stringify(event))
	file.close()

static func _safe(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key in value: out[str(key)] = _safe(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item in value: out.append(_safe(item))
		return out
	if value is Vector2: return {"type": "Vector2", "x": value.x, "y": value.y}
	if value is Vector3: return {"type": "Vector3", "x": value.x, "y": value.y, "z": value.z}
	if value is Color: return {"type": "Color", "r": value.r, "g": value.g, "b": value.b, "a": value.a}
	if value is Quaternion: return {"type": "Quaternion", "x": value.x, "y": value.y, "z": value.z, "w": value.w}
	if value is Basis: return {"type": "Basis", "x": _safe(value.x), "y": _safe(value.y), "z": _safe(value.z)}
	if value is Transform2D: return {"type": "Transform2D", "x": _safe(value.x), "y": _safe(value.y), "origin": _safe(value.origin)}
	if value is Transform3D: return {"type": "Transform3D", "basis": _safe(value.basis), "origin": _safe(value.origin)}
	if value is NodePath or value is StringName: return str(value)
	return value
