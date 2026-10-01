extends SceneTree

## Play live Godot AI FX results after scene save/reopen, checking actual values.

func _initialize() -> void:
	_probe.call_deferred()


func _close(actual: Variant, expected: Variant) -> bool:
	if actual is Vector2 and expected is Vector2:
		return (actual as Vector2).distance_to(expected) < 0.05
	if actual is Vector3 and expected is Vector3:
		return (actual as Vector3).distance_to(expected) < 0.05
	if actual is Color and expected is Color:
		return (actual as Color).is_equal_approx(expected)
	if actual is float or actual is int:
		return absf(float(actual) - float(expected)) < 0.05
	return actual == expected


func _probe() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("FX_RUNTIME_FAIL: pass scene path and operation after --")
		quit(1)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		print("FX_RUNTIME_FAIL: scene did not load: " + args[0])
		quit(1)
		return
	var fixture := packed.instantiate()
	root.add_child(fixture)
	var op := args[1]
	var checks: Array = []
	var failures: Array = []
	if op.begins_with("sprite_frames"):
		var sprite := fixture.get_node("SheetSprite") as AnimatedSprite2D
		if sprite.sprite_frames == null:
			failures.append("missing SpriteFrames after reopen")
		else:
			var count := sprite.sprite_frames.get_frame_count(op)
			checks.append({"frames": count, "animation": op})
			if count != 4:
				failures.append("expected four SpriteFrames cells")
	else:
		var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
		var animation := player.get_animation(op)
		if animation == null:
			failures.append("missing clip after reopen")
		else:
			var base := player.get_node(player.root_node)
			for track_index in animation.get_track_count():
				var track_type := animation.track_get_type(track_index)
				var track_path := animation.track_get_path(track_index)
				var target := base.get_node_or_null(NodePath(track_path.get_concatenated_names()))
				if target == null:
					failures.append("missing target for %s" % str(track_path))
					continue
				if track_type == Animation.TYPE_VALUE:
					if track_path.get_subname_count() == 0:
						failures.append("value track has no property: %s" % str(track_path))
						continue
					var property_path := NodePath(":" + str(track_path.get_concatenated_subnames()))
					var key_index := mini(1, animation.track_get_key_count(track_index) - 1)
					var at := animation.track_get_key_time(track_index, key_index)
					var expected: Variant = animation.track_get_key_value(track_index, key_index)
					player.play(op)
					player.seek(at, true)
					player.advance(0.0)
					var actual: Variant = target.get_indexed(property_path)
					checks.append({"path": str(track_path), "at": at,
						"expected": str(expected), "actual": str(actual)})
					if not _close(actual, expected):
						failures.append("played value mismatch: %s" % str(track_path))
				elif track_type == Animation.TYPE_METHOD:
					player.callback_mode_method = AnimationMixer.ANIMATION_CALLBACK_MODE_METHOD_IMMEDIATE
					player.play(op)
					player.advance(0.5)
					checks.append({"method_target": str(track_path), "text": str(target.get("text"))})
					if op == "counter" and str(target.get("text")) == "0":
						failures.append("counter method track did not change text")
				elif track_type == Animation.TYPE_AUDIO:
					player.play(op)
					player.advance(0.25)
					checks.append({"audio_target": str(track_path), "playing": target.playing})
					if not target.playing:
						failures.append("audio track did not start playback")
				else:
					failures.append("unsupported track type %d" % track_type)
	print("FX_RUNTIME=" + JSON.stringify({"op": op, "scene": args[0],
		"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
