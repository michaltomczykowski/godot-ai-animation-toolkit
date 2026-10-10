extends RefCounted
## Engine-only playback and measurements. Never synthesizes or applies a pose.
class CaptureErrors extends Logger:
	var errors: Array[String] = []
	func _log_error(_fn: String, _file: String, _line: int, code: String, rationale: String, _notify: bool, type: int, _backtraces: Array) -> void:
		if type != 1: errors.append(rationale if not rationale.is_empty() else code)

static func rest(rig: Skeleton3D, roles: Dictionary, role: String) -> Vector3:
	return (rig.global_transform * rig.get_bone_global_rest(rig.find_bone(str(roles[role])))).origin
static func point(view: Dictionary, role: String) -> Vector3:
	return (view.rig.global_transform * view.rig.get_bone_global_pose(view.indices[role])).origin
static func load_case(row: Dictionary, parent: Node) -> Dictionary:
	var scene := (ResourceLoader.load(row.scene, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	# Disable autoplay before entering the tree; one manually advanced player owns output.
	for mixer in scene.find_children("*", "AnimationMixer", true, false):
		mixer.active = false
		mixer.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for modifier in scene.find_children("*", "SkeletonModifier3D", true, false): modifier.active = false
	parent.add_child(scene)
	var rig := scene.get_node(row.skeleton) as Skeleton3D
	var player := scene.get_node(row.player) as AnimationPlayer
	var roles: Dictionary = row.roles
	var indices := {}
	for role in roles:
		indices[role] = rig.find_bone(roles[role])
		assert(indices[role] >= 0, "Reported bone role must resolve")
	var spine := rest(rig, roles, "head") - rest(rig, roles, "hips")
	# Fixtures have authored Y/Z-up conventions. Select the dominant axis from rest,
	# independently of the generator/audit's frame helper and of world Y.
	var up := Vector3.ZERO
	var component := spine.abs().max_axis_index()
	up[component] = signf(spine[component])
	var forward := rest(rig, roles, "toe_l") - rest(rig, roles, "foot_l")
	forward = (forward - up * forward.dot(up)).normalized()
	assert(forward.length_squared() > 0.9, "Distinct rest forward axis required")
	var right := forward.cross(up).normalized()
	var leg := 0.0
	for side in ["l", "r"]:
		leg += rest(rig, roles, "thigh_" + side).distance_to(rest(rig, roles, "shin_" + side)) + rest(rig, roles, "shin_" + side).distance_to(rest(rig, roles, "foot_" + side))
	leg *= 0.5
	var ground := minf(rest(rig, roles, "foot_l").dot(up), rest(rig, roles, "foot_r").dot(up))
	var animation_root := player.get_node(player.root_node)
	var actor_path := NodePath() if player.root_motion_track.is_empty() else NodePath(player.root_motion_track.get_concatenated_names())
	# An ordinary in-place clip has no extraction binding. Its caller owns the
	# scene actor; do not resolve an empty NodePath as a child node.
	var body := animation_root as Node3D if actor_path.is_empty() else animation_root.get_node_or_null(actor_path) as Node3D
	if body == null:
		scene.free()
		return {"error": "Native actor/root-motion path does not resolve to Node3D"}
	var clip := player.get_animation(row.params.animation_name)
	player.stop()
	player.speed_scale = 1.0
	player.playback_auto_capture = false
	player.active = true
	player.play(row.params.animation_name, 0.0, 1.0)
	player.advance(0.0)
	return {"scene": scene, "rig": rig, "player": player, "body": body,
		"clip": clip, "indices": indices, "roles": roles, "up": up,
		"forward": forward, "right": right, "leg": leg, "ground": ground,
		"initial_body": body.global_position, "time": 0.0}
static func advance(view: Dictionary, delta: float) -> void:
	view.player.advance(delta)
	# Exactly one consumer, in the root-motion node's local convention.
	view.body.position += view.body.quaternion * view.player.get_root_motion_position()
	view.time += delta
static func contact(view: Dictionary, side: String) -> bool:
	var suffix := side.to_upper()
	var start: float = view.clip.get_marker_time("contact." + suffix)
	var end: float = view.clip.get_marker_time("toe_off." + suffix)
	var span := fposmod(end - start, view.clip.length)
	return fposmod(view.time - start, view.clip.length) < span - 0.000001
static func flat(point_value: Vector3, up: Vector3) -> Vector3:
	return point_value - up * point_value.dot(up)
static func values(v: Vector3) -> Array: return [v.x, v.y, v.z]
