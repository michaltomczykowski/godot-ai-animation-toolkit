extends SceneTree

## Export a registry-driven audit inventory. Evidence is maintained separately
## so regeneration cannot turn a pending operation into a claimed pass.

const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const EVIDENCE := "res://../docs/operation-evidence.json"
const OUTPUT := "res://../docs/operation-audit.json"
const CHECKS := [
	"mcp_invocation", "valid_effect", "track_paths_types", "dry_run",
	"undo_redo", "save_reopen", "playback", "visual_review",
	"reported_errors",
]


func _init() -> void:
	var evidence := _read_evidence()
	var rows: Array = []
	for family_name in OpRegistry.family_names():
		var family: Dictionary = OpRegistry.family(family_name)
		for descriptor in OpRegistry.op_descriptors(family_name):
			var key := "%s.%s" % [family_name, str(descriptor.name)]
			var row := {
				"key": key,
				"family": family_name,
				"op": str(descriptor.name),
				"handler": str(family.get("handler", "")),
				"claimed_effect": str(descriptor.get("summary", "")),
				"example": descriptor.get("example", {}),
				"promoted": bool(family.get("promoted", true)),
				"requires_writable": bool(family.get("requires_writable", true)),
				"family_batch_undoable": bool(family.get("undoable", true)),
				"status": "unverified",
				"checks": {},
				"platforms": {"windows": "pending", "linux": "pending"},
				"evidence": [],
			}
			for check in CHECKS:
				row.checks[check] = "pending"
			if evidence.has(key):
				var note: Dictionary = evidence[key]
				for field in ["status", "evidence", "fixture"]:
					if note.has(field):
						row[field] = note[field]
				for platform in ["windows", "linux"]:
					if (note.get("platforms", {}) as Dictionary).has(platform):
						row.platforms[platform] = note.platforms[platform]
				for check in CHECKS:
					if (note.get("checks", {}) as Dictionary).has(check):
						row.checks[check] = note.checks[check]
			rows.append(row)
			if row.status == "verified":
				for check in CHECKS:
					if row.checks[check] != "pass":
						print("AUDIT_EXPORT_FAIL: %s claims verified with %s=%s" % [
							key, check, str(row.checks[check])])
						quit(1)
						return
				for platform in ["windows", "linux"]:
					if row.platforms[platform] != "pass":
						print("AUDIT_EXPORT_FAIL: %s claims verified with %s=%s" % [
							key, platform, str(row.platforms[platform])])
						quit(1)
						return
	var invalid: Array = []
	for key in evidence:
		var found := false
		for row in rows:
			if row.key == key:
				found = true
				break
		if not found:
			invalid.append(key)
	if not invalid.is_empty():
		print("AUDIT_EXPORT_FAIL: evidence names removed operations: %s" % ", ".join(invalid))
		quit(1)
		return
	var path := ProjectSettings.globalize_path(OUTPUT)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("AUDIT_EXPORT_FAIL: cannot open %s" % path)
		quit(1)
		return
	file.store_string(JSON.stringify({"schema_version": 1, "operations": rows}, "  ") + "\n")
	file.close()
	var verified := 0
	for row in rows:
		if row.status == "verified":
			verified += 1
	print("AUDIT_EXPORT_OK: %d operations, %d verified" % [rows.size(), verified])
	quit(0)


func _read_evidence() -> Dictionary:
	var path := ProjectSettings.globalize_path(EVIDENCE)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
