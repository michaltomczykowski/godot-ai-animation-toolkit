extends SceneTree

## Play a saved MCP-composed sequence with the engine's AnimationPlayer.

func _initialize() -> void:
	_probe.call_deferred()


func _probe() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("SEQUENCE_RUNTIME_FAIL: pass a scene path after --")
		quit(1)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		print("SEQUENCE_RUNTIME_FAIL: cannot load %s" % args[0])
		quit(1)
		return
	var fixture := packed.instantiate()
	root.add_child(fixture)
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var skeleton := fixture.get_node("Skeleton3D") as Skeleton3D
	var clip := player.get_animation("audit_action")
	player.play("audit_action")
	player.advance(0.4)
	var early := skeleton.get_bone_pose_rotation(0).get_angle()
	player.advance(1.1)
	var late := skeleton.get_bone_pose_rotation(0).get_angle()
	var saved_pose_angle := -1.0
	if player.has_animation("audit_saved_pose"):
		player.play("audit_saved_pose")
		player.advance(0.25)
		saved_pose_angle = skeleton.get_bone_pose_rotation(0).get_angle()
	var result := {
		"scene": args[0], "early_angle": early, "late_angle": late,
		"saved_pose_angle": saved_pose_angle,
		"length": clip.length, "tracks": clip.get_track_count(),
		"keys": clip.track_get_key_count(0),
		"contact_impact": clip.has_marker(&"contact_impact"),
		"impact_time": clip.get_marker_time(&"contact_impact") if clip.has_marker(&"contact_impact") else -1.0,
	}
	print("SEQUENCE_RUNTIME=" + JSON.stringify(result))
	quit(0 if late > early + 0.25 and result.contact_impact
		and (saved_pose_angle < 0.0 or absf(saved_pose_angle - 0.6) < 0.02)
		and absf(float(result.impact_time) - 1.1) < 0.001 else 1)
