extends RefCounted
## Read-only attestation of existing saved public inputs, never generation/poses.
static func begin(row: Dictionary) -> Dictionary:
 return {"schema": "motion_physical_input_v1", "id": row.get("id", ""), "scene": row.get("scene", ""),
  "expected_scene_sha256": row.get("scene_sha256", ""), "scene_before_sha256": FileAccess.get_sha256(str(row.get("scene", ""))),
  "request": row.get("params", {}).duplicate(true), "fixture_sha256": row.get("fixture_sha256", ""), "roles": row.get("roles", {}).duplicate(true)}
static func loaded(value: Dictionary, row: Dictionary, view: Dictionary) -> void:
 var bones: Array = []
 for index in view.rig.get_bone_count():
  bones.append({"name": view.rig.get_bone_name(index), "parent": view.rig.get_bone_parent(index), "rest": view.rig.get_bone_rest(index)})
 var hash := HashingContext.new()
 hash.start(HashingContext.HASH_SHA256)
 hash.update(var_to_bytes(bones))
 value["rest_sha256"] = hash.finish().hex_encode()
 value["bone_count"] = bones.size()
 value["player"] = str(view.scene.get_path_to(view.player))
 value["skeleton"] = str(view.scene.get_path_to(view.rig))
 value["player_class"] = view.player.get_class()
 value["skeleton_class"] = view.rig.get_class()
 value["animation_name"] = str(row.params.animation_name)
 value["clip_present"] = view.player.has_animation(row.params.animation_name) and view.player.get_animation(row.params.animation_name) == view.clip
static func finish(value: Dictionary) -> Dictionary:
 value["scene_after_sha256"] = FileAccess.get_sha256(str(value.scene))
 value["complete"] = not str(value.expected_scene_sha256).is_empty() and value.scene_before_sha256 == value.expected_scene_sha256 and value.scene_after_sha256 == value.expected_scene_sha256 and value.get("bone_count", 0)>0 and value.get("clip_present", false)
 return value
static func select(rows: Array, id: String) -> Array:
 if id.is_empty(): return rows
 var selected: Array = []
 for row in rows:
  if str(row.get("id", "")) == id: selected.append(row)
 return selected
static func selector(args: PackedStringArray) -> String:
 var found := ""
 for arg in args:
  if arg.begins_with("case_id="):
   if not found.is_empty() or arg != "case_id=dummy": return "INVALID"
   found = "dummy"
 return found
