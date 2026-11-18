extends SceneTree

## Export applicability-aware historical inventory. Candidate qualification lives
## in external receipts and is never inferred from a documentation regeneration.
const Registry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const CHECKS := ["mcp_invocation", "valid_effect", "track_paths_types", "dry_run", "undo_redo", "save_reopen", "playback", "visual_review", "reported_errors", "source_unchanged", "typed_errors", "file_effect"]

func _required(effect: String) -> Array:
	var checks: Array = ["mcp_invocation", "valid_effect", "reported_errors", "source_unchanged", "typed_errors"]
	if effect in ["scene_write", "scene_structure"]:
		checks.append_array(["dry_run", "undo_redo", "save_reopen", "playback", "visual_review"])
	if effect == "scene_write": checks.append("track_paths_types")
	if effect == "file_write": checks.append_array(["dry_run", "file_effect"])
	if effect == "render": checks.append_array(["file_effect", "visual_review"])
	return checks

func _init() -> void:
	var docs := ProjectSettings.globalize_path("res://../docs")
	var args := OS.get_cmdline_user_args()
	var docs_arg := args.find("--docs-root")
	if docs_arg >= 0 and docs_arg + 1 < args.size(): docs = args[docs_arg + 1]
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(docs.path_join("operation-evidence.json")))
	if not document is Dictionary or document.get("schema_version") != 2 or not document.get("operations") is Dictionary:
		_fail("Evidence must use schema_version 2 and operations mapping")
		return
	var evidence: Dictionary = document.operations
	var rows: Array = []
	var inventory_keys: Array = []
	for family_name in Registry.family_names():
		var family: Dictionary = Registry.family(family_name)
		for descriptor in family.ops:
			var key := "%s.%s" % [family_name, descriptor.name]
			inventory_keys.append(key)
			if not evidence.has(key):
				_fail("Missing evidence row " + key)
				return
			var note: Dictionary = evidence[key]
			var checks: Dictionary = note.get("checks", {})
			var records: Dictionary = note.get("evidence_records", {})
			var required := _required(str(descriptor.effect_kind))
			if note.get("effect_kind") != descriptor.effect_kind:
				_fail(key + " effect classification differs from registry")
				return
			var verified := true
			for name in CHECKS:
				var check: Dictionary = checks.get(name, {})
				if check.get("status", "") not in ["pass", "fail", "pending", "not_applicable"]:
					_fail(key + "." + name + " has invalid status")
					return
				if check.status == "not_applicable" and (required.has(name) or str(check.get("reason", "")).is_empty()):
					_fail(key + "." + name + " unjustified N/A")
					return
				var refs: Array = check.get("evidence_refs", [])
				if check.status == "pass" and refs.is_empty():
					_fail(key + "." + name + " pass without evidence")
					return
				for ref in refs:
					if not records.has(ref):
						_fail(key + " missing evidence " + str(ref))
						return
				if required.has(name) and check.status != "pass": verified = false
			var row := {"key": key, "family": family_name, "op": descriptor.name,
				"handler": family.handler, "claimed_effect": descriptor.summary,
				"example": descriptor.get("example", {}), "promoted": family.get("promoted", true),
				"requires_writable": family.get("requires_writable", true), "family_batch_undoable": family.get("undoable", true),
				"availability": descriptor.availability, "advertised": descriptor.availability.status == "supported",
				"effect_kind": note.effect_kind, "status": "verified" if verified else "partial",
				"qualification": "pending", "checks": checks, "evidence_records": records,
				"review_policy": note.get("review_policy", {}), "platforms": note.get("platforms", {}),
				"evidence": note.get("evidence", []), "historical_status": note.get("historical_status", "partial"),
				"historical_checks": note.get("historical_checks", {})}
			if note.has("fixture"): row["fixture"] = note.fixture
			rows.append(row)
	for key in evidence:
		if not inventory_keys.has(key):
			_fail("Evidence names removed operation " + key)
			return
	var file := FileAccess.open(docs.path_join("operation-audit.json"), FileAccess.WRITE)
	if file == null:
		_fail("Cannot open inventory output")
		return
	file.store_string(JSON.stringify({"schema_version": 2, "operations": rows}, "  ") + "\n")
	file.close()
	print("AUDIT_EXPORT_OK: %d rows; candidate qualification remains pending" % rows.size())
	quit(0)

func _fail(message: String) -> void:
	print("AUDIT_EXPORT_FAIL: " + message)
	quit(1)
