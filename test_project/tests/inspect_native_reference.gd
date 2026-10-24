@tool
extends RefCounted

# Independent native engine path: no toolkit handlers/spec/grading code.
const SCENE := "res://repair_motion_fixture.tscn"
const CLIP := "repair_probe_walk"
const BONES := ["B-hips", "B-thigh.L", "B-shin.L", "B-foot.L", "B-toe.L", "B-thigh.R", "B-shin.R", "B-foot.R", "B-toe.R"]
static func _vec(v: Vector3) -> Array: return [v.x, v.y, v.z]
static func _strip(node: Node) -> void:
 node.set_script(null)
 if node is AnimationTree: node.active = false
 for child in node.get_children(): _strip(child)
static func build(marker: Dictionary) -> Dictionary:
 if marker.stage != "valid" or marker.scene != SCENE or marker.request.op not in ["sample", "motion_audit"]: return {"not_applicable": true}
 var audit: bool = marker.request.op == "motion_audit"
 var count := 120 if audit else 8
 var source := ResourceLoader.load(SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
 if source == null: return {"failure": "saved reference scene not loaded"}
 var reference := source.instantiate()
 _strip(reference)
 var player := reference.get_node_or_null("WalkAnim") as AnimationPlayer
 var skeleton := reference.get_node_or_null("Dummy/Skeleton3D") as Skeleton3D
 var actor := reference.get_node_or_null("Dummy") as Node3D
 if player == null or skeleton == null or actor == null or skeleton.find_bone("B-spine") < 0:
  reference.free()
  return {"failure": "reference structure missing"}
 var clip := player.get_animation(CLIP)
 if clip == null or not is_equal_approx(clip.length, 1.0):
  reference.free()
  return {"failure": "reference clip must be the authored one-second walk"}
 var original_root_track := str(player.root_motion_track)
 player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
 player.speed_scale = 1.0
 if audit: player.root_motion_track = NodePath("")
 var viewport := SubViewport.new()
 viewport.own_world_3d = true
 viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
 EditorInterface.get_base_control().get_tree().root.add_child(viewport)
 viewport.add_child(reference)
 var rests := {}
 for bone in BONES:
  var index := skeleton.find_bone(bone)
  if index < 0:
   viewport.free()
   return {"failure": "reference bone missing: " + bone}
  rests[bone] = skeleton.global_transform * skeleton.get_bone_global_rest(index).origin
 var up := Vector3.UP
 var forward: Vector3 = rests["B-toe.L"] - rests["B-foot.L"]
 forward -= up * forward.dot(up)
 forward = forward.normalized()
 var lateral: Vector3 = rests["B-thigh.L"] - rests["B-thigh.R"]
 lateral -= up * lateral.dot(up)
 lateral -= forward * lateral.dot(forward)
 lateral = lateral.normalized()
 var legs := {}
 for side in ["L", "R"]:
  legs[side.to_lower()] = (rests["B-thigh." + side] as Vector3).distance_to(rests["B-shin." + side]) + (rests["B-shin." + side] as Vector3).distance_to(rests["B-foot." + side])
 var spine_axis: Vector3 = skeleton.global_transform.basis * skeleton.get_bone_global_rest(skeleton.find_bone("B-spine")).basis.y.normalized()
 var eligible := skeleton.global_transform.basis.is_equal_approx(Basis.IDENTITY) and actor.position.is_equal_approx(Vector3.ZERO) and absf(spine_axis.dot(up)) > cos(deg_to_rad(10.0)) and forward.length() > 0.9 and lateral.length() > 0.9
 var frames: Array = []
 for index in count:
  var at := float(index) / float(count - 1)
  player.stop()
  skeleton.reset_bone_poses()
  player.play(CLIP)
  player.seek(at, true, true)
  var points := {}
  for bone in BONES: points[bone] = _vec((skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone))).origin)
  frames.append({"at": at, "position": player.current_animation_position, "assigned": str(player.assigned_animation), "speed": player.speed_scale, "process": player.callback_mode_process, "points": points})
 var output := {"scene": SCENE, "scene_sha256": FileAccess.get_sha256(SCENE), "clip": CLIP, "samples": count, "frames": frames, "eligible": eligible, "kind": "fresh_saved_scene_native_Player", "root_track_before": original_root_track, "root_track_played": str(player.root_motion_track), "up": _vec(up), "forward": _vec(forward), "lateral": _vec(lateral), "legs": legs, "rest_feet": {"l": _vec(rests["B-foot.L"]), "r": _vec(rests["B-foot.R"])}}
 player.stop()
 viewport.free()
 return output
