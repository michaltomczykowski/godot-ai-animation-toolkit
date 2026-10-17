extends RefCounted
## Independent saved-resource/engine equivalence, not motion-quality approval.
const EXTRACTION_FIELDS := ["root_motion", "root_motion_requested", "root_motion_track", "root_motion_space", "root_motion_terminal_hold", "root_rotation_extracted", "translation_owner", "heading_owner", "actor_translation_keys", "actor_translation_space", "actor_translation_world_scale", "actor_translation_owner", "world_scale", "distance", "speed"]

static func same_channels(a: Animation, b: Animation) -> bool:
	if a.length != b.length or a.loop_mode != b.loop_mode or a.step != b.step or a.get_track_count() != b.get_track_count(): return false
	if a.get_marker_names() != b.get_marker_names(): return false
	for marker in a.get_marker_names():
		if a.get_marker_time(marker) != b.get_marker_time(marker) or a.get_marker_color(marker) != b.get_marker_color(marker): return false
	for track in a.get_track_count():
		if a.track_get_path(track) != b.track_get_path(track) or a.track_get_type(track) != b.track_get_type(track): return false
		if a.track_get_interpolation_type(track) != b.track_get_interpolation_type(track) or a.track_get_interpolation_loop_wrap(track) != b.track_get_interpolation_loop_wrap(track): return false
		if a.track_is_enabled(track) != b.track_is_enabled(track) or a.track_get_key_count(track) != b.track_get_key_count(track): return false
		if a.track_get_type(track) == Animation.TYPE_VALUE and a.value_track_get_update_mode(track) != b.value_track_get_update_mode(track): return false
		for key in a.track_get_key_count(track):
			if a.track_get_key_time(track, key) != b.track_get_key_time(track, key) or a.track_get_key_value(track, key) != b.track_get_key_value(track, key) or a.track_get_key_transition(track, key) != b.track_get_key_transition(track, key): return false
	return true

static func same_extraction(a: AnimationPlayer, b: AnimationPlayer, metadata_a: Dictionary, metadata_b: Dictionary) -> bool:
	if a.root_motion_track != b.root_motion_track or a.root_motion_local != b.root_motion_local: return false
	for field in EXTRACTION_FIELDS:
		if metadata_a.get(field) != metadata_b.get(field): return false
	return true

static func mixer(view: Dictionary, mode: String) -> AnimationMixer:
	if mode == "player": return view.player
	view.player.active = false
	var tree := AnimationTree.new()
	view.scene.add_child(tree)
	tree.anim_player = tree.get_path_to(view.player)
	tree.root_node = tree.get_path_to(view.player.get_node(view.player.root_node))
	tree.root_motion_track = view.player.root_motion_track
	tree.root_motion_local = view.player.root_motion_local
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var node := AnimationNodeAnimation.new()
	node.animation = view.animation_name
	tree.tree_root = node
	tree.active = true
	tree.advance(0.0)
	return tree

static func played(a: Dictionary, b: Dictionary, fps: int, mode: String) -> Dictionary:
	var exact := same_channels(a.clip, b.clip)
	var extraction := same_extraction(a.player, b.player, a.get("metadata", {}), b.get("metadata", {}))
	var bones_match: bool = a.rig.get_bone_count() == b.rig.get_bone_count()
	if bones_match:
		for bone in a.rig.get_bone_count():
			bones_match = bones_match and a.rig.get_bone_name(bone) == b.rig.get_bone_name(bone)
	var am := mixer(a, mode)
	var bm := mixer(b, mode)
	var position_error := 0.0
	var rotation_error := 0.0
	var root_error := 0.0
	var finite := true
	for frame in ceili((maxf(a.clip.length,b.clip.length) + 0.3) * fps) + 1:
		if frame > 0:
			am.advance(1.0/fps)
			bm.advance(1.0/fps)
			# These motion aliases have translation-only carriers. Paired bake
			# rotation extraction has a separate consumer and is not tested here.
			a.body.position += am.get_root_motion_position()
			b.body.position += bm.get_root_motion_position()
		var ar: Vector3 = a.body.global_position - a.initial_body
		var br: Vector3 = b.body.global_position - b.initial_body
		root_error = maxf(root_error, ar.distance_to(br))
		if not bones_match: continue
		for bone in a.rig.get_bone_count():
			var ap: Transform3D = a.rig.global_transform * a.rig.get_bone_global_pose(bone)
			var bp: Transform3D = b.rig.global_transform * b.rig.get_bone_global_pose(bone)
			finite = finite and ap.is_finite() and bp.is_finite()
			position_error = maxf(position_error, (ap.origin-(a.initial_body as Vector3)).distance_to(bp.origin-(b.initial_body as Vector3)))
			var q := ap.basis.orthonormalized().get_rotation_quaternion().inverse()*bp.basis.orthonormalized().get_rotation_quaternion()
			rotation_error = maxf(rotation_error,2.0*atan2(Vector3(q.x,q.y,q.z).length(),absf(q.w)))
	return {"fps":fps,"mode":mode,"channels_interpolation_markers_exact":exact,"extraction_metadata_exact":extraction,
		"position_error_m":position_error,"rotation_error_rad":rotation_error,"root_error_m":root_error,
		"finite":finite,"passed":exact and extraction and bones_match and finite and position_error < 0.000001 and rotation_error < 0.00001 and root_error < 0.000001}
