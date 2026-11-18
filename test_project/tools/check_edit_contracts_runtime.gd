extends SceneTree

const HistoryPlayback := preload("res://tools/check_edit_history_runtime.gd")
var failures: Array = []

func _initialize() -> void: _probe.call_deferred()

func _probe() -> void:
	var logger := HistoryPlayback.Capture.new()
	OS.add_logger(logger)
	var count := 0
	for state in ["undo", "redo"]:
		var path := "user://edit_contracts_%s.tscn" % state
		if not ResourceLoader.exists(path):
			failures.append(state + " missing scene")
			continue
		var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var scene := packed.instantiate()
		root.add_child(scene)
		var player := scene.get_node("EditContracts/AnimationPlayer") as AnimationPlayer
		var target := scene.get_node("EditContracts/Target") as Node3D
		player.play("pose")
		player.seek(0.5 if state == "undo" else 1.0, true)
		player.advance(0)
		if target.position.distance_to(Vector3(1, 0, 0)) > 0.0001: failures.append(state + " position or disabled track")
		if target.scale.distance_to(Vector3(1.5, 1.5, 1.5)) > 0.0001: failures.append(state + " scale")
		if target.quaternion.angle_to(Quaternion(Vector3.UP, PI / 4)) > 0.0001: failures.append(state + " rotation")
		if target.visible: failures.append(state + " discrete bool")
		var clip := player.get_animation("pose")
		if clip.track_get_interpolation_loop_wrap(3): failures.append(state + " value wrap metadata")
		if clip.track_is_enabled(4): failures.append(state + " disabled metadata")
		if clip.value_track_get_update_mode(3) != Animation.UPDATE_DISCRETE: failures.append(state + " update metadata")
		if absf(clip.get_marker_time("impact") - (0.25 if state == "undo" else 0.5)) > 0.0001: failures.append(state + " marker time")
		scene.free()
		count += 1
	OS.remove_logger(logger)
	print("EDIT_CONTRACTS_RUNTIME=" + JSON.stringify({"saved_states": count, "failures": failures, "engine_errors": logger.errors}))
	quit(0 if count == 2 and failures.is_empty() and logger.errors.is_empty() else 1)
