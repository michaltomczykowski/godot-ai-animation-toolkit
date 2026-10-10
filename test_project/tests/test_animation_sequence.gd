@tool
extends McpTestSuite

const SequenceHandler := preload("res://addons/godot_ai_animation/handlers/sequence.gd")
const ToolContext := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const PoseMath := preload("res://addons/godot_ai_animation/spec/pose_math.gd")
const SequenceSpecs := preload("res://addons/godot_ai_animation/spec/sequence_specs.gd")
const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecModifiers := preload("res://addons/godot_ai_animation/spec/spec_modifiers.gd")

var _undo_redo: EditorUndoRedoManager


func suite_name() -> String:
	return "animation_sequence"


func suite_setup(ctx: Dictionary) -> void:
	_undo_redo = ctx.get("undo_redo")
	ToolContext.undo_redo = _undo_redo


func test_composed_root_motion_accumulates_across_segments() -> void:
	var sources := []
	for displacement in [0.3, 1.0]:
		var spec := ClipSpec.make(1.0)
		ClipSpec.add_value_track(spec, "Actor:position", [
			{"time": 0.0, "value": Vector3.ZERO, "transition": 1.0},
			{"time": 1.0, "value": Vector3(0, 0, displacement), "transition": 1.0},
		], Animation.INTERPOLATION_LINEAR, Animation.TYPE_POSITION_3D)
		sources.append(spec)
	var built := SequenceSpecs.compose([
		{"start": 0.0, "duration": 1.0, "source_start": 0.0,
			"source_end": 1.0, "spec": sources[0]},
		{"start": 1.0, "duration": 1.0, "source_start": 0.0,
			"source_end": 1.0, "spec": sources[1]},
	], 2.0, 60, "Actor:position")
	assert_false(built.has("error"), "rooted clips compose: %s" % str(built))
	if built.has("error"):
		return
	var root_track: Dictionary = built.spec.tracks[0]
	var seam: Vector3 = SpecModifiers.sample_track(root_track, 1.0)
	var ending: Vector3 = SpecModifiers.sample_track(root_track, 2.0)
	assert_true(seam.distance_to(Vector3(0, 0, 0.3)) < 0.0001,
		"the second clip begins at the first clip's root position")
	assert_true(ending.distance_to(Vector3(0, 0, 1.3)) < 0.0001,
		"root travel accumulates across both clips")
	var overlapped := SequenceSpecs.compose([
		{"start": 0.0, "duration": 1.0, "source_start": 0.0,
			"source_end": 1.0, "spec": sources[0]},
		{"start": 0.8, "duration": 1.0, "source_start": 0.0,
			"source_end": 1.0, "fade_in": 0.2, "spec": sources[1]},
	], 1.8, 60, "Actor:position")
	assert_false(overlapped.has("error"), "rooted clips overlap: %s" % str(overlapped))
	if overlapped.has("error"):
		return
	var overlap_track: Dictionary = overlapped.spec.tracks[0]
	var before: Vector3 = SpecModifiers.sample_track(overlap_track, 0.799)
	var at_start: Vector3 = SpecModifiers.sample_track(overlap_track, 0.8)
	var at_end: Vector3 = SpecModifiers.sample_track(overlap_track, 1.8)
	assert_true(before.distance_to(at_start) < 0.005,
		"root travel remains continuous at the blend start")
	assert_true(at_end.distance_to(Vector3(0, 0, 1.24)) < 0.0001,
		"overlap carries travel reached when the next segment begins")


func test_compose_playback_contact_dry_run_and_undo() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		skip("No edited scene")
		return
	var holder := Node3D.new()
	holder.name = "SequenceFixture"
	root.add_child(holder)
	holder.owner = root
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	holder.add_child(skeleton)
	skeleton.owner = root
	skeleton.add_bone("Root")
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	holder.add_child(player)
	player.owner = root
	var library := AnimationLibrary.new()
	player.add_animation_library("", library)
	for source in ["approach", "kick"]:
		var clip := Animation.new()
		clip.length = 1.0
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath("Skeleton3D:Root"))
		clip.track_insert_key(track, 0.0, Quaternion.IDENTITY)
		clip.track_insert_key(track, 1.0,
			Quaternion(Vector3.RIGHT, 0.8 if source == "kick" else 0.2))
		library.add_animation(source, clip)
	var player_path := "/%s/SequenceFixture/AnimationPlayer" % root.name
	var skeleton_path := "/%s/SequenceFixture/Skeleton3D" % root.name
	var params := {
		"op": "compose", "player_path": player_path,
		"skeleton_path": skeleton_path, "animation_name": "action", "duration": 1.8,
		"segments": [
			{"start": 0.0, "duration": 1.0, "source_animation": "approach"},
			{"start": 0.8, "duration": 1.0, "source_animation": "kick",
				"fade_in": 0.2, "contacts": [{"name": "impact", "time": 0.3}]},
		],
	}
	var handler := SequenceHandler.new()
	var preview_params: Dictionary = params.duplicate(true)
	preview_params["dry_run"] = true
	var preview := handler.run(preview_params, null)
	assert_true(preview.has("data"), "dry run composes: %s" % str(preview))
	assert_false(player.has_animation("action"), "dry run does not commit")
	var result := handler.run(params, null)
	assert_true(result.has("data"), "compose commits: %s" % str(result))
	assert_true(player.has_animation("action"), "output clip exists")
	if player.has_animation("action"):
		var action := player.get_animation("action")
		assert_true(action.get_track_count() == 1, "one character-owned rotation track")
		assert_true(action.has_marker(&"contact_impact"), "impact marker survives composition")
		assert_true(absf(action.get_marker_time(&"contact_impact") - 1.1) < 0.001,
			"impact marker lands on the scheduled timeline")
		var before_overlap := action.rotation_track_interpolate(0, 0.799)
		var overlap_start := action.rotation_track_interpolate(0, 0.8)
		var after_overlap := action.rotation_track_interpolate(0, 0.801)
		assert_true(before_overlap.angle_to(overlap_start) < 0.02
			and overlap_start.angle_to(after_overlap) < 0.02,
			"overlap does not jump at its first boundary")
		var before_fade_end := action.rotation_track_interpolate(0, 0.999)
		var fade_end := action.rotation_track_interpolate(0, 1.0)
		var after_fade_end := action.rotation_track_interpolate(0, 1.001)
		assert_true(before_fade_end.angle_to(fade_end) < 0.02
			and fade_end.angle_to(after_fade_end) < 0.02,
			"overlap does not jump at its final boundary")
		player.playback_default_blend_time = 0.0
		player.play("action")
		player.seek(1.5, true)
		player.advance(0.0)
		var played := skeleton.get_bone_pose_rotation(0)
		assert_true(played.get_angle() > 0.3, "the kick pose actually plays")
		player.stop()
	assert_true(editor_undo(_undo_redo), "one undo reverts the composition")
	assert_false(player.has_animation("action"), "undo removes the output clip")
	var pose := PoseMath.make_pose()
	PoseMath.set_bone(pose, "Root", Quaternion(Vector3.RIGHT, 0.6),
		Vector3.ZERO, Vector3.ONE)
	var pose_params := {
		"op": "compose", "player_path": player_path, "skeleton_path": skeleton_path,
		"animation_name": "pose_action", "duration": 0.5, "dry_run": true,
		"segments": [{"start": 0.0, "duration": 0.5, "pose": PoseMath.to_json(pose)}],
	}
	var posed := handler.run(pose_params, null)
	assert_true(posed.has("data"), "inline saved-pose format composes: %s" % str(posed))
	var outside_params: Dictionary = params.duplicate(true)
	outside_params["animation_name"] = "outside_source"
	outside_params["segments"][1]["source_end"] = 2.0
	var outside := handler.run(outside_params, null)
	assert_true(outside.has("error"), "source range outside the clip is rejected")
	if outside.has("error"):
		assert_true(str(outside.error.code) == "VALUE_OUT_OF_RANGE",
			"source range has a typed error")
	assert_false(player.has_animation("outside_source"), "invalid source range did not commit")
	var late_start_params: Dictionary = params.duplicate(true)
	late_start_params["animation_name"] = "late_start"
	late_start_params["segments"][0]["start"] = 0.2
	var late_start := handler.run(late_start_params, null)
	assert_true(late_start.has("error"), "a sequence cannot begin with an implicit pre-roll pose")
	assert_false(player.has_animation("late_start"), "rejected late start did not commit")
	var budget_params: Dictionary = params.duplicate(true)
	budget_params["animation_name"] = "over_budget"
	budget_params["duration"] = 10.0
	budget_params["samples"] = 120
	budget_params["segments"] = [
		{"start": 0.0, "duration": 10.0, "source_animation": "approach"},
	]
	var budget := handler.run(budget_params, null)
	assert_true(budget.has("error"), "the actual output sample count is bounded")
	if budget.has("error"):
		assert_true(str(budget.error.code) == "VALUE_OUT_OF_RANGE",
			"the output key budget has a typed error")
	assert_false(player.has_animation("over_budget"), "key budget rejection did not commit")
	var gap_params: Dictionary = params.duplicate(true)
	gap_params["animation_name"] = "gap_action"
	gap_params["segments"][0]["duration"] = 0.4
	gap_params["segments"][0]["source_end"] = 0.4
	gap_params["dry_run"] = false
	var gap_result := handler.run(gap_params, null)
	assert_true(gap_result.has("data"), "timeline gap composes")
	if player.has_animation("gap_action"):
		var gap := player.get_animation("gap_action")
		var held_start := gap.rotation_track_interpolate(0, 0.4)
		var held_middle := gap.rotation_track_interpolate(0, 0.6)
		var held_end := gap.rotation_track_interpolate(0, 0.8)
		assert_true(held_start.angle_to(held_middle) < 0.001
			and held_middle.angle_to(held_end) < 0.001,
			"a timeline gap holds the last authored pose")
	holder.get_parent().remove_child(holder)
	holder.queue_free()
