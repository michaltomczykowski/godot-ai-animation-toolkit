@tool
extends McpTestSuite

const ErrorCodes := preload("res://addons/godot_ai_animation/utils/error_codes.gd")
const ToolContext := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const ValueCodec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")
const ClipSpec := preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecBuilder := preload("res://addons/godot_ai_animation/spec/spec_builder.gd")
const OpRegistry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")

const InspectHandler := preload("res://addons/godot_ai_animation/handlers/inspect.gd")
const MotionHandler := preload("res://addons/godot_ai_animation/handlers/motion.gd")

const DUMMY := "res://models/human_dummy/HumanCharacterDummy_F.fbx"
const PROFILE_NAME := "inspect_suite_profile"
const PROFILE_PATH := "res://animation_toolkit/rig_profiles/inspect_suite_profile.json"

## Tests for the animation_inspect tool (describe/timeline/audit/compare/stats/
## dry_run/help).
##
## NOTE: GDScript tests must not call save_scene, scene_create, scene_open,
## quit_editor, or reload_plugin (see the core CLAUDE.md Known Issues).

var _handler: InspectHandler
var _undo_redo: EditorUndoRedoManager


func suite_name() -> String:
	return "animation_inspect"


func suite_setup(ctx: Dictionary) -> void:
	_undo_redo = ctx.get("undo_redo")
	ToolContext.undo_redo = _undo_redo
	_handler = InspectHandler.new()


func suite_teardown() -> void:
	if FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(PROFILE_PATH)


# --- helpers ---------------------------------------------------------------

func _add_player(player_name: String) -> String:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return ""
	var player := AnimationPlayer.new()
	player.name = player_name
	player.add_animation_library("", AnimationLibrary.new())
	scene_root.add_child(player)
	player.set_owner(scene_root)
	return "/" + scene_root.name + "/" + player_name


func _remove_node(path: String) -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return
	var node := ValueCodec.resolve_scene_path(path, scene_root)
	if node != null:
		node.get_parent().remove_child(node)
		node.queue_free()


func _add_sibling(node: Node, sibling_name: String) -> Node:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return null
	node.name = sibling_name
	scene_root.add_child(node)
	node.owner = scene_root
	return node


func _find_of_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_of_type(child, type_name)
		if found != null:
			return found
	return null


func _assign_owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_assign_owners(child, owner)


## The committed human dummy, added under the edited scene root.
func _rig(prefix: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return {"error": "no scene"}
	if not ResourceLoader.exists(DUMMY):
		return {"error": "the human dummy asset is missing"}
	var packed = load(DUMMY)
	var root: Node = packed.instantiate()
	root.name = prefix + "Dummy"
	scene_root.add_child(root)
	_assign_owners(root, scene_root)
	var skeleton := _find_of_type(root, "Skeleton3D") as Skeleton3D
	var player := _find_of_type(root, "AnimationPlayer") as AnimationPlayer
	if skeleton == null or player == null:
		_remove_node("/" + scene_root.name + "/" + str(root.name))
		return {"error": "the dummy has no skeleton/player"}
	return {
		"root_path": "/" + scene_root.name + "/" + str(root.name),
		"skeleton_path": "/" + scene_root.name + "/" + str(scene_root.get_path_to(skeleton)),
		"player_path": "/" + scene_root.name + "/" + str(scene_root.get_path_to(player)),
		"skeleton": skeleton,
		"player": player,
	}


func _teardown_rig(rig: Dictionary) -> void:
	if rig.has("root_path"):
		_remove_node(rig.root_path)


func _add_clip(player_path: String, clip_name: String, spec: Dictionary) -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	var player := ValueCodec.resolve_scene_path(player_path, scene_root) as AnimationPlayer
	if player == null:
		return
	player.get_animation_library("").add_animation(clip_name, SpecBuilder.to_animation(spec))


## Player + target + a two-track clip (position 3 keys, modulate:a 2 keys).
func _fixture(prefix: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return {"error": "no scene"}
	var target := _add_sibling(Node2D.new(), prefix + "Target")
	var player_path := _add_player("InspectPlayer" + prefix)
	if player_path.is_empty():
		return {"error": "no player"}
	var spec := ClipSpec.make(1.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, prefix + "Target:position", [
		{"time": 0.0, "value": Vector2(0, 0), "transition": 1.0},
		{"time": 0.5, "value": Vector2(10, 4), "transition": 1.0},
		{"time": 1.0, "value": Vector2(20, 0), "transition": 1.0},
	])
	ClipSpec.add_value_track(spec, prefix + "Target:modulate:a", [
		{"time": 0.0, "value": 0.0, "transition": 1.0},
		{"time": 1.0, "value": 1.0, "transition": 1.0},
	])
	_add_clip(player_path, "clip", spec)
	return {
		"player_path": player_path,
		"target": "/" + scene_root.name + "/" + prefix + "Target",
		"prefix": prefix,
		"spec": spec,
	}


func _teardown(fixture: Dictionary) -> void:
	if fixture.has("player_path"):
		_remove_node(fixture.player_path)
	if fixture.has("target"):
		_remove_node(fixture.target)


func _findings_for(result: Dictionary, code: String) -> Array:
	var out: Array = []
	if not result.has("data"):
		return out
	for finding in result.data.findings:
		if str(finding.code) == code:
			out.append(finding)
	return out


# --- rollup ----------------------------------------------------------------

func test_rollup_dispatches_and_rejects_unknown_op() -> void:
	var unknown := _handler.run({"op": "peek"}, null)
	assert_is_error(unknown, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(unknown.error.message, "describe")
	assert_contains(unknown.error.message, "audit")


# --- describe / timeline ---------------------------------------------------

func test_describe_summarises_clip_and_tracks() -> void:
	var fixture := _fixture("Describe")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "describe", "player_path": fixture.player_path, "animation_name": "clip",
	}, null)
	assert_has_key(result, "data")
	assert_eq(result.data.clip_count, 1)
	var clip: Dictionary = result.data.clips[0]
	assert_eq(clip.track_count, 2)
	assert_eq(clip.key_count, 5)
	assert_eq(str(clip.loop_mode), "none")
	assert_true(str(clip.summary).contains("2 tracks"), "summary should mention the tracks: %s" % str(clip.summary))
	assert_eq(str(clip.tracks[0].path), "DescribeTarget:position")
	assert_eq(str(clip.tracks[0].type), "value")
	assert_eq(clip.tracks[0].keys, 3)
	assert_true(clip.tracks[0].node_resolved, "the target node should resolve")
	var all_clips := _handler.run({"op": "describe", "player_path": fixture.player_path}, null)
	assert_eq(all_clips.data.clip_count, 1, "describe without animation_name lists every clip")
	_teardown(fixture)


func test_timeline_lists_keys_with_values() -> void:
	var fixture := _fixture("Timeline")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "timeline", "player_path": fixture.player_path, "animation_name": "clip",
	}, null)
	assert_has_key(result, "data")
	assert_eq(result.data.returned_keys, 5)
	assert_eq(result.data.truncated, false)
	var position: Dictionary = result.data.tracks[0]
	assert_eq(position.keys.size(), 3)
	assert_true(is_equal_approx(float(position.keys[0].time), 0.0), "first key at 0")
	var value: Dictionary = position.keys[1].value
	assert_true(is_equal_approx(float(value.x), 10.0) and is_equal_approx(float(value.y), 4.0),
		"serialized Vector2 value, got %s" % str(value))
	assert_true(is_equal_approx(float(position.keys[1].transition), 1.0), "transitions are reported")
	_teardown(fixture)


func test_timeline_track_filter_and_truncation() -> void:
	var fixture := _fixture("TimelineFilter")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var filtered := _handler.run({
		"op": "timeline", "player_path": fixture.player_path, "animation_name": "clip",
		"track_path": "TimelineFilterTarget:modulate:a",
	}, null)
	assert_has_key(filtered, "data")
	assert_eq(filtered.data.track_count, 1)
	assert_eq(str(filtered.data.tracks[0].path), "TimelineFilterTarget:modulate:a")
	var capped := _handler.run({
		"op": "timeline", "player_path": fixture.player_path, "animation_name": "clip", "max_keys": 2,
	}, null)
	assert_true(bool(capped.data.truncated), "max_keys should truncate")
	assert_eq(capped.data.returned_keys, 2)
	var missing := _handler.run({
		"op": "timeline", "player_path": fixture.player_path, "animation_name": "clip",
		"track_path": "Nope:position",
	}, null)
	assert_is_error(missing, ErrorCodes.VALUE_OUT_OF_RANGE)
	_teardown(fixture)


# --- audit -----------------------------------------------------------------

func test_audit_flags_broken_path_and_loop_snap() -> void:
	var fixture := _fixture("Audit")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var spec := ClipSpec.make(1.0, Animation.LOOP_LINEAR)
	ClipSpec.add_value_track(spec, "Ghost:position", [
		{"time": 0.0, "value": Vector2(0, 0)},
		{"time": 1.0, "value": Vector2(5, 0)},
	])
	ClipSpec.add_value_track(spec, "AuditTarget:position", [
		{"time": 0.0, "value": Vector2(0, 0)},
		{"time": 1.0, "value": Vector2(9, 0)},
	])
	_add_clip(fixture.player_path, "broken", spec)
	var result := _handler.run({
		"op": "audit", "player_path": fixture.player_path, "include_info": false,
	}, null)
	assert_has_key(result, "data")
	assert_true(result.data.clips_scanned >= 2, "both clips should be scanned")
	var broken := _findings_for(result, "broken_path")
	assert_eq(broken.size(), 1, "one broken track path should be reported")
	assert_true(str(broken[0].fix).contains("retarget"), "broken paths suggest retarget")
	var snaps := _findings_for(result, "loop_snap")
	assert_true(snaps.size() >= 1, "a linear loop with different ends should be reported")
	assert_true(str(snaps[0].fix).contains("make_seamless"), "loop seams suggest make_seamless")
	assert_true(str(snaps[0].severity) == "warning", "loop_snap is a warning")
	assert_true(int(result.data.summary.error) >= 1, "broken paths count as errors")
	_teardown(fixture)


func test_audit_flags_autoplay_conflict() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		skip("No scene root")
		return
	_add_sibling(Node2D.new(), "ConflictTarget")
	var first_path := _add_player("InspectConflictA")
	var second_path := _add_player("InspectConflictB")
	if first_path.is_empty() or second_path.is_empty():
		skip("Scene not ready")
		return
	var spec := ClipSpec.make(1.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(spec, "ConflictTarget:position", [
		{"time": 0.0, "value": Vector2(0, 0)},
		{"time": 1.0, "value": Vector2(5, 0)},
	])
	_add_clip(first_path, "move", spec)
	_add_clip(second_path, "move", spec)
	var first_player := ValueCodec.resolve_scene_path(first_path, scene_root) as AnimationPlayer
	var second_player := ValueCodec.resolve_scene_path(second_path, scene_root) as AnimationPlayer
	first_player.autoplay = "move"
	second_player.autoplay = "move"
	var result := _handler.run({"op": "audit", "severity": "warning"}, null)
	assert_has_key(result, "data")
	var conflicts := _findings_for(result, "autoplay_conflict")
	assert_true(conflicts.size() >= 1, "two players animating the same path should conflict")
	assert_true(str(conflicts[0].track_path) == "ConflictTarget:position",
		"the conflict should name the shared track, got %s" % str(conflicts[0].track_path))
	first_player.autoplay = ""
	second_player.autoplay = ""
	_remove_node(first_path)
	_remove_node(second_path)
	_remove_node("/" + scene_root.name + "/ConflictTarget")


func test_audit_severity_filter_and_info() -> void:
	var fixture := _fixture("AuditFilter")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var spec := ClipSpec.make(0.0, Animation.LOOP_NONE)
	_add_clip(fixture.player_path, "empty", spec)
	var errors_only := _handler.run({
		"op": "audit", "player_path": fixture.player_path, "severity": "error",
	}, null)
	assert_has_key(errors_only, "data")
	for finding in errors_only.data.findings:
		assert_true(str(finding.severity) == "error", "severity filter should keep errors only")
	assert_true(_findings_for(errors_only, "zero_length").size() == 1, "zero-length clips are errors")
	var without_info := _handler.run({
		"op": "audit", "player_path": fixture.player_path, "include_info": false,
	}, null)
	assert_eq(_findings_for(without_info, "unused_clip").size(), 0, "info findings are excluded")
	var bad := _handler.run({"op": "audit", "severity": "loud"}, null)
	assert_is_error(bad, ErrorCodes.VALUE_OUT_OF_RANGE)
	_teardown(fixture)


# --- compare / stats -------------------------------------------------------

func test_compare_identical_and_changed() -> void:
	var fixture := _fixture("Compare")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var changed := ClipSpec.make(1.0, Animation.LOOP_NONE)
	ClipSpec.add_value_track(changed, "CompareTarget:position", [
		{"time": 0.0, "value": Vector2(0, 0)},
		{"time": 0.5, "value": Vector2(10, 40)},
		{"time": 1.0, "value": Vector2(20, 0)},
	])
	ClipSpec.add_value_track(changed, "CompareTarget:modulate:a", [
		{"time": 0.0, "value": 0.0},
		{"time": 1.0, "value": 1.0},
	])
	_add_clip(fixture.player_path, "tweaked", changed)
	var same := _handler.run({
		"op": "compare", "player_path": fixture.player_path,
		"animation_name": "clip", "other_animation_name": "clip",
	}, null)
	assert_has_key(same, "data")
	assert_true(bool(same.data.identical), "a clip compared with itself is identical")
	var diff := _handler.run({
		"op": "compare", "player_path": fixture.player_path,
		"animation_name": "clip", "other_animation_name": "tweaked",
	}, null)
	assert_false(bool(diff.data.identical), "a changed key must show up as a difference")
	assert_eq((diff.data.changed_tracks as Array).size(), 1)
	var track: Dictionary = diff.data.changed_tracks[0]
	assert_eq(str(track.path), "CompareTarget:position")
	assert_eq(int(track.changed_keys), 1)
	assert_true(float(track.max_delta) > 30.0, "the y delta should be reported, got %s" % str(track.max_delta))
	var missing := _handler.run({
		"op": "compare", "player_path": fixture.player_path,
		"animation_name": "clip", "other_animation_name": "nope",
	}, null)
	assert_is_error(missing, ErrorCodes.INVALID_PARAMS)
	_teardown(fixture)


func test_stats_totals() -> void:
	var fixture := _fixture("Stats")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({"op": "stats", "player_path": fixture.player_path}, null)
	assert_has_key(result, "data")
	assert_eq(result.data.player_count, 1)
	var player: Dictionary = result.data.players[0]
	assert_eq(player.clip_count, 1)
	assert_eq(player.key_count, 5)
	assert_true(is_equal_approx(float(player.total_length), 1.0), "total length sums the clips")
	assert_eq(int(result.data.track_types.value), 2, "both tracks are value tracks")
	assert_eq(int(result.data.loop_modes.none), 1)
	assert_eq(str(player.longest), "clip")
	_teardown(fixture)


# --- dry_run / help --------------------------------------------------------

func test_dry_run_edit_does_not_commit() -> void:
	var fixture := _fixture("DryEdit")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "dry_run", "tool": "animation_edit", "forward_op": "retime",
		"player_path": fixture.player_path, "animation_name": "clip", "factor": 0.5,
	}, null)
	assert_has_key(result, "data")
	assert_true(bool(result.data.dry_run), "dry_run is reported")
	assert_true(is_equal_approx(float(result.data.length_after), 0.5), "the would-be length is reported")
	var scene_root := EditorInterface.get_edited_scene_root()
	var player := ValueCodec.resolve_scene_path(fixture.player_path, scene_root) as AnimationPlayer
	assert_true(is_equal_approx(player.get_animation("clip").length, 1.0),
		"dry_run must not change the clip")
	var missing := _handler.run({
		"op": "dry_run", "tool": "animation_edit", "player_path": fixture.player_path,
		"animation_name": "clip", "factor": 0.5,
	}, null)
	assert_is_error(missing, ErrorCodes.MISSING_REQUIRED_PARAM)
	_teardown(fixture)


func test_dry_run_presets_does_not_commit() -> void:
	var fixture := _fixture("DryPreset")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "dry_run", "tool": "animation_presets", "forward_op": "pulse",
		"player_path": fixture.player_path, "target_path": "DryPresetTarget", "duration": 0.8,
	}, null)
	assert_has_key(result, "data")
	assert_true(bool(result.data.dry_run), "dry_run is reported")
	assert_true(is_equal_approx(float(result.data.length), 0.8), "the would-be clip length is reported")
	var scene_root := EditorInterface.get_edited_scene_root()
	var player := ValueCodec.resolve_scene_path(fixture.player_path, scene_root) as AnimationPlayer
	assert_false(player.has_animation("pulse"), "dry_run must not create the clip")
	_teardown(fixture)


func test_help_lists_ops_and_params() -> void:
	var result := _handler.run({"op": "help", "tool": "animation_edit"}, null)
	assert_has_key(result, "data")
	assert_eq(result.data.tool_count, 1)
	var tool: Dictionary = result.data.tools[0]
	assert_eq((tool.ops as Array).size(), 19, "every edit op is listed")
	for descriptor in tool.ops:
		assert_true((descriptor.params as Array).has("dry_run"),
			"%s should advertise dry_run" % str(descriptor.name))
	var single := _handler.run({"op": "help", "tool": "animation_edit", "op_name": "retime"}, null)
	assert_has_key(single, "data")
	assert_eq((single.data.tools[0].ops as Array).size(), 1)
	var everything := _handler.run({"op": "help"}, null)
	assert_eq(everything.data.tool_count, OpRegistry.family_names().size(), "help lists every tool")
	var unknown := _handler.run({"op": "help", "tool": "animation_edit", "op_name": "wobble"}, null)
	assert_is_error(unknown, ErrorCodes.VALUE_OUT_OF_RANGE)
	assert_contains(unknown.error.message, "retime")


func test_missing_clip_reports_available_names() -> void:
	var fixture := _fixture("Missing")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "describe", "player_path": fixture.player_path, "animation_name": "nope",
	}, null)
	assert_is_error(result, ErrorCodes.INVALID_PARAMS)
	assert_contains(result.error.message, "Available")
	assert_contains(result.error.message, "clip")
	_teardown(fixture)


func test_motion_report_metrics_and_health() -> void:
	var fixture := _fixture("MR")
	if fixture.has("error"):
		skip(fixture.error)
		return
	var result := _handler.run({
		"op": "motion_report", "player_path": fixture.player_path, "animation_name": "clip",
	}, null)
	assert_true(result.has("data"), "motion_report: %s" % str(result))
	assert_eq(int(result.data.track_count), 2, "both value tracks are reported")
	assert_eq(int(result.data.tracks[0].keys), 3, "per-track key counts are reported")
	assert_true(float(result.data.tracks[0].keys_per_second) == 3.0, "key density is reported")
	# The fixture's position track is not sparse, but the 2-key modulate track is.
	assert_true(_findings_for(result, "sparse_keys").size() >= 1, "sparse tracks are flagged")
	var broken := ClipSpec.make(1.0, Animation.LOOP_LINEAR)
	ClipSpec.add_value_track(broken, "MRTarget:position", [
		{"time": 0.0, "value": Vector2(0, 0), "transition": 1.0},
		{"time": 0.5, "value": Vector2(1, 0), "transition": 1.0},
		{"time": 1.0, "value": Vector2(9, 0), "transition": 1.0},
	])
	_add_clip(fixture.player_path, "broken", broken)
	var poppy := _handler.run({
		"op": "motion_report", "player_path": fixture.player_path, "animation_name": "broken",
	}, null)
	assert_true(poppy.has("data"), "motion_report on the broken clip: %s" % str(poppy))
	assert_false(bool(poppy.data.healthy), "a popping loop is not healthy")
	assert_true(_findings_for(poppy, "loop_seam").size() >= 1, "the seam pop is flagged")
	_teardown(fixture)


# --- rig_profile / sample --------------------------------------------------

func test_rig_profile_reports_roles_and_capabilities() -> void:
	var rig := _rig("Profile")
	if rig.has("error"):
		skip(rig.error)
		return
	var result := _handler.run({"op": "rig_profile", "skeleton_path": rig.skeleton_path}, null)
	assert_true(result.has("data"), "rig_profile: %s" % str(result))
	assert_eq(str(result.data.roles.hips), "B-hips", "hips is detected")
	assert_true(not str(result.data.roles.get("thigh_l", "")).is_empty(), "the left thigh is detected")
	assert_true(not str(result.data.roles.get("foot_r", "")).is_empty(), "the right foot is detected")
	assert_true(bool(result.data.capabilities.walk_cycle), "the dummy can walk")
	assert_true(bool(result.data.capabilities.idle_cycle), "the dummy can idle")
	assert_true((result.data.missing.locomotion as Array).is_empty(), "no locomotion role is missing")
	assert_true(float(result.data.limbs.leg_length) > 0.5, "leg length is measured")
	assert_true((result.data.suggested_ops as Array).size() > 0, "next ops are suggested")
	assert_true(["T", "A", "arms_down"].has(str(result.data.pose.pose)),
		"the rest pose is classified (%s)" % str(result.data.pose.pose))
	_teardown_rig(rig)


func test_rig_profile_saves_and_is_reused_by_motion() -> void:
	var rig := _rig("ProfileSave")
	if rig.has("error"):
		skip(rig.error)
		return
	var saved := _handler.run({
		"op": "rig_profile", "skeleton_path": rig.skeleton_path,
		"save": true, "name": PROFILE_NAME, "overwrite": true,
	}, null)
	assert_true(saved.has("data"), "rig_profile save: %s" % str(saved))
	assert_eq(str(saved.data.saved), PROFILE_PATH, "the profile file is written")
	assert_true(FileAccess.file_exists(PROFILE_PATH), "the profile exists on disk")
	var loaded := _handler.run({
		"op": "rig_profile", "skeleton_path": rig.skeleton_path, "profile": PROFILE_NAME,
	}, null)
	assert_true(loaded.has("data"), "rig_profile with a profile: %s" % str(loaded))
	assert_true(not (loaded.data.profile_roles as Dictionary).is_empty(), "the profile roles load")
	var motion := MotionHandler.new()
	var walked := motion.run({
		"op": "walk_cycle", "player_path": rig.player_path, "skeleton_path": rig.skeleton_path,
		"profile": PROFILE_NAME, "duration": 1.0, "loop_mode": "linear", "animation_name": "profiled_walk",
	}, null)
	assert_true(walked.has("data"), "walk_cycle with a profile: %s" % str(walked))
	assert_true(not str(walked.data.roles.get("thigh_l", "")).is_empty(), "profile roles reach the motion op")
	var bogus := motion.run({
		"op": "walk_cycle", "player_path": rig.player_path, "skeleton_path": rig.skeleton_path,
		"profile": "no_such_profile", "duration": 1.0, "animation_name": "nope_walk",
	}, null)
	assert_is_error(bogus, ErrorCodes.INVALID_PARAMS)
	assert_contains(bogus.error.message, "not found")
	_teardown_rig(rig)


func test_sample_returns_positions_feet_and_restores_pose() -> void:
	var rig := _rig("Sample")
	if rig.has("error"):
		skip(rig.error)
		return
	var motion := MotionHandler.new()
	var walked := motion.run({
		"op": "walk_cycle", "player_path": rig.player_path, "skeleton_path": rig.skeleton_path,
		"duration": 1.0, "loop_mode": "linear", "animation_name": "walk",
	}, null)
	if not walked.has("data"):
		skip("walk_cycle failed: %s" % str(walked))
		_teardown_rig(rig)
		return
	var skeleton: Skeleton3D = rig.skeleton
	var thigh := skeleton.find_bone("B-thigh.L")
	var before := skeleton.get_bone_pose_rotation(thigh)
	var result := _handler.run({
		"op": "sample", "player_path": rig.player_path, "animation_name": "walk",
		"skeleton_path": rig.skeleton_path, "samples": 12, "include_rotation": true,
	}, null)
	assert_true(result.has("data"), "sample: %s" % str(result))
	assert_eq(int(result.data.sample_count), 12, "every requested sample is returned")
	var bones: Dictionary = result.data.bones
	assert_true(bones.has("B-foot.L"), "the role bones are probed by default")
	assert_eq((bones["B-foot.L"].positions as Array).size(), 12, "one position per sample")
	assert_eq((bones["B-foot.L"].euler_degrees as Array).size(), 12, "rotations come with include_rotation")
	var feet: Dictionary = result.data.feet
	assert_true(feet.has("l") and feet.has("r"), "both feet are analysed")
	assert_eq((feet.l.heights as Array).size(), 12, "foot heights are sampled")
	assert_true(float(feet.l.min_height) < 0.5, "the planted foot reaches the ground")
	assert_true((feet.l.contacts as Array).size() >= 1, "the walk has a contact window")
	assert_true(skeleton.get_bone_pose_rotation(thigh).is_equal_approx(before), "the pose is restored")
	var explicit := _handler.run({
		"op": "sample", "player_path": rig.player_path, "animation_name": "walk",
		"skeleton_path": rig.skeleton_path, "bones": ["B-hips", "B-nope"], "times": [0.0, 0.5],
	}, null)
	assert_true(explicit.has("data"), "sample with explicit times: %s" % str(explicit))
	assert_eq(str((explicit.data.missing_bones as Array)[0]), "B-nope", "unknown bones are reported")
	assert_eq((explicit.data.bones["B-hips"].positions as Array).size(), 2, "explicit times are honoured")
	_teardown_rig(rig)


## `preview` validates like the other probes, then refuses politely when it
## cannot render: headless servers have no rasteriser, and the render itself is
## deferred to editor frames, so a direct call (tests, dry_run) has no transport
## to push the reply through.
func test_preview_validates_then_reports_why_it_cannot_render() -> void:
	var rig := _rig("Preview")
	if rig.has("error"):
		skip(rig.error)
		return
	var motion := MotionHandler.new()
	var walked := motion.run({
		"op": "walk_cycle", "player_path": rig.player_path, "skeleton_path": rig.skeleton_path,
		"duration": 1.0, "loop_mode": "linear", "animation_name": "walk",
	}, null)
	if not walked.has("data"):
		skip("walk_cycle failed: %s" % str(walked))
		_teardown_rig(rig)
		return
	var skeleton: Skeleton3D = rig.skeleton
	var before := skeleton.get_bone_pose_rotation(skeleton.find_bone("B-thigh.L"))
	var bad_times := _handler.run({
		"op": "preview", "player_path": rig.player_path, "animation_name": "walk",
		"skeleton_path": rig.skeleton_path, "times": [],
	}, null)
	assert_is_error(bad_times, ErrorCodes.INVALID_PARAMS)
	assert_contains(bad_times.error.message, "times")
	var ghost_clip := _handler.run({
		"op": "preview", "player_path": rig.player_path, "animation_name": "ghost",
	}, null)
	assert_is_error(ghost_clip, ErrorCodes.INVALID_PARAMS)
	var result := _handler.run({
		"op": "preview", "player_path": rig.player_path, "animation_name": "walk",
		"skeleton_path": rig.skeleton_path, "times": [0.0, 0.5],
	}, null)
	assert_is_error(result, ErrorCodes.INVALID_PARAMS)
	if DisplayServer.get_name() == "headless" or OS.has_feature("headless"):
		assert_contains(result.error.message, "rendering device")
	else:
		assert_contains(result.error.message, "Godot AI tool")
	assert_true(skeleton.get_bone_pose_rotation(skeleton.find_bone("B-thigh.L")).is_equal_approx(before),
		"preview leaves the edited scene's pose alone")
	_teardown_rig(rig)


func test_registry_matches_inspect_schema() -> void:
	var info := OpRegistry.family(OpRegistry.FAMILY_INSPECT)
	assert_false(info.is_empty(), "the inspect family is registered")
	assert_false(bool(info.requires_writable), "inspect does not require a writable project")
	assert_false(bool(info.undoable), "inspect never touches the undo stack")
	var op_enum: Array = info.schema.properties.op.enum
	assert_eq(op_enum.size(), 11, "the inspect schema lists every op")
	for descriptor in info.ops:
		assert_true(op_enum.has(descriptor.name), "%s is in the schema enum" % descriptor.name)
		for param in descriptor.params:
			assert_true(info.schema.properties.has(param), "%s declares param %s" % [descriptor.name, param])
	assert_true(str(info.description).length() <= OpRegistry.MAX_DESCRIPTION_CHARS,
		"the inspect description fits the custom-tool cap")
