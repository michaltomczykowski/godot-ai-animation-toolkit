extends SceneTree
const Native := preload("res://tools/character_quality_native.gd")
var logger := Native.CaptureErrors.new()

func _initialize() -> void:
	OS.add_logger(logger)
	_run.call_deferred()

func _angle(a: Basis, b: Basis) -> float:
	var q := a.get_rotation_quaternion().inverse() * b.get_rotation_quaternion()
	return 2.0 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w))

func _mixer(v: Dictionary, mode: String) -> AnimationMixer:
	if mode == "player": return v.player
	v.player.active = false
	var tree := AnimationTree.new()
	v.scene.add_child(tree)
	tree.anim_player = tree.get_path_to(v.player)
	tree.root_node = tree.get_path_to(v.player.get_node(v.player.root_node))
	tree.root_motion_track = v.player.root_motion_track
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var node := AnimationNodeAnimation.new()
	node.animation = v.player.current_animation
	tree.tree_root = node
	tree.active = true
	tree.advance(0.0)
	return tree

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		quit(1)
		return
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var fresh: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var rows: Array = []
	var failed := false
	for row: Dictionary in fresh.cases:
		var previous: Dictionary = {}
		for item: Dictionary in old.cases:
			if item.id == row.id: previous = item
		assert(not previous.is_empty())
		for fps in [30, 60, 120]:
			for mode in ["player", "tree"]:
				var a := Native.load_case(previous, root)
				var b := Native.load_case(row, root)
				var authored: bool = a.clip.length == b.clip.length and a.clip.loop_mode == b.clip.loop_mode and a.clip.get_track_count() == b.clip.get_track_count()
				if authored:
					for track in a.clip.get_track_count():
						authored = authored and a.clip.track_get_path(track) == b.clip.track_get_path(track) and a.clip.track_get_type(track) == b.clip.track_get_type(track) and a.clip.track_get_key_count(track) == b.clip.track_get_key_count(track)
						if not authored: break
						for key in a.clip.track_get_key_count(track):
							authored = authored and a.clip.track_get_key_time(track, key) == b.clip.track_get_key_time(track, key) and a.clip.track_get_key_value(track, key) == b.clip.track_get_key_value(track, key) and a.clip.track_get_key_transition(track, key) == b.clip.track_get_key_transition(track, key)
				var am: AnimationMixer = _mixer(a, mode)
				var bm: AnimationMixer = _mixer(b, mode)
				var worst := Vector2.ZERO
				var root_error := 0.0
				for frame in ceili(a.clip.length * fps) + 1:
					if frame > 0:
						am.advance(1.0 / fps)
						bm.advance(1.0 / fps)
						a.body.position += a.body.quaternion * am.get_root_motion_position()
						b.body.position += b.body.quaternion * bm.get_root_motion_position()
					root_error = maxf(root_error, (a.body.global_position - a.initial_body).distance_to(b.body.global_position - b.initial_body))
					for i in a.rig.get_bone_count():
						var ap: Transform3D = a.rig.get_bone_global_pose(i)
						var bp: Transform3D = b.rig.get_bone_global_pose(i)
						worst.x = maxf(worst.x, ap.origin.distance_to(bp.origin))
						worst.y = maxf(worst.y, _angle(ap.basis, bp.basis))
				var passed: bool = authored and worst.x < 0.000001 and worst.y < 0.000001 and root_error < 0.000001
				rows.append({"id": row.id, "fps": fps, "mixer": mode, "authored_channels_exact": authored,
					"position_error_m": worst.x, "rotation_error_rad": worst.y, "root_error_m": root_error, "passed": passed})
				failed = failed or not passed
				a.scene.free()
				b.scene.free()
	var report := {"passed": not failed and rows.size() == 24 and logger.errors.is_empty(), "runs": rows,
		"engine_errors": logger.errors, "preview_source": old.source_head, "fresh_source": fresh.source_head}
	FileAccess.open(args[2], FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("TRANSITION_PREVIEW_PARITY=" + JSON.stringify({"passed": report.passed, "runs": rows.size(), "engine_errors": logger.errors}))
	quit(0 if report.passed else 1)
