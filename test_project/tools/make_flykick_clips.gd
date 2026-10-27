extends SceneTree

## Headless builder for the `demo_flykick` clips.
##
## The two gaits are the addon's own procedural motion (MotionSpecs.gait_keys)
## written out through the same ClipSpec path the `animation_motion` tool uses,
## so they are identical to the op output. The other four clips are authored
## value tracks. Everything is keyed from t=0 on purpose: scene-owned players
## autoplay on scene load, so a clip that needs to start later carries its own
## leading hold instead of relying on a play() call.
##
## Run: godot --headless --path test_project --script res://tools/make_flykick_clips.gd

const SCENE_PATH := "res://demo_flykick.tscn"
const LENGTH := 7.0

const ClipSpec = preload("res://addons/godot_ai_animation/spec/clip_spec.gd")
const SpecBuilder = preload("res://addons/godot_ai_animation/spec/spec_builder.gd")
const MotionSpecs = preload("res://addons/godot_ai_animation/spec/motion_specs.gd")
const RigAnalysis = preload("res://addons/godot_ai_animation/spec/rig_analysis.gd")
const BoneAnimation = preload("res://addons/godot_ai_animation/handlers/bone_animation.gd")
const SpecIO = preload("res://addons/godot_ai_animation/spec/spec_io.gd")
const SpecModifiers = preload("res://addons/godot_ai_animation/spec/spec_modifiers.gd")
const SequenceSpecs = preload("res://addons/godot_ai_animation/spec/sequence_specs.gd")

var _report: Array[String] = []
var _failed := false


func _initialize() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		_fail("could not load %s" % SCENE_PATH)
		return
	var root: Node = packed.instantiate()
	root.name = "Flykick"
	get_root().add_child(root)
	# Rebuilds also work after the prior pass has removed the competing players.
	for parent_path in ["Victim", "Kicker"]:
		var action_name := "VictimAnim" if parent_path == "Victim" else "KickAnim"
		var parent_node: Node = root.get_node(parent_path)
		if not parent_node.has_node(action_name):
			var action_player := AnimationPlayer.new()
			action_player.name = action_name
			parent_node.add_child(action_player)

	_gait(root, "Victim/WalkAnim", "Victim/Walker/Body/Skeleton3D", "walk_in", false, 2.0)
	_gait(root, "Kicker/RunAnim", "Kicker/Runner/Body/Skeleton3D", "run_in", true, 2.6)

	_door(root)
	_victim_fly(root)
	_kicker_kick(root)
	_compose_characters(root)

	if _failed:
		quit(1)
		return
	var out := PackedScene.new()
	var err := out.pack(root)
	if err != OK:
		_fail("pack failed: %d" % err)
		return
	err = ResourceSaver.save(out, SCENE_PATH)
	if err != OK:
		_fail("save failed: %d" % err)
		return

	print("CLIP_BUILD_OK")
	for line in _report:
		print("  " + line)
	quit(0)


# --- procedural gaits --------------------------------------------------------

## Mirror of BoneAnimation._build_procedural_animation: rest pose + delta per
## key, quaternions sign-aligned, loop closed when the clip loops.
func _gait(root: Node, player_path: String, skel_path: String, anim_name: String,
		run: bool, duration: float) -> void:
	var player: AnimationPlayer = root.get_node(player_path)
	var skeleton: Skeleton3D = root.get_node(skel_path)

	var bone_names: Array = []
	for index in skeleton.get_bone_count():
		bone_names.append(skeleton.get_bone_name(index))
	var detected: Dictionary = RigAnalysis.detect_roles(bone_names)
	var roles: Dictionary = detected.get("roles", {})

	var samples := 24.0
	var config: Dictionary = MotionSpecs.run_config("default", {}) if run \
		else MotionSpecs.walk_config("default", {})

	# The same context MotionHandler._build_context builds, field for field. The
	# arm_down targets matter: a T-pose rig needs them or the arms never leave
	# the bind pose and the walk reads as a mannequin sliding forward.
	var chain_result := BoneAnimation.resolve_spine_chain({}, skeleton, roles)
	if chain_result.has("error"):
		_fail("%s: %s" % [anim_name, chain_result.error])
		return
	var chain: Array = chain_result.get("chain", [])
	var measured: Dictionary = MotionSpecs.context_from_skeleton(
		skeleton, roles, duration, samples, false, MotionSpecs.REFERENCE_LEG, chain)
	if measured.has("error"):
		_fail("%s: %s" % [anim_name, measured.error])
		return
	var arm_amount := _default_arm_down(skeleton, roles)
	var arm_down := {}
	for side in ["l", "r"]:
		var arm := str(roles.get("arm_" + side, ""))
		arm_down[side] = BoneAnimation._aim_delta(skeleton, arm, Vector3.DOWN, arm_amount) \
			if not arm.is_empty() else Quaternion.IDENTITY
	var hips := str(roles.get("hips", ""))
	var ctx := {
		"length": duration,
		"samples": samples,
		"roles": roles,
		"spine_chain": chain,
		"forward": measured.forward,
		"up": measured.up,
		"lateral": measured.lateral,
		"hips": hips,
		"hips_origin": (measured.rest[hips] as Dictionary).origin,
		"legs": measured.legs,
		"rest": measured.rest,
		"arm_down": arm_down,
		"root_motion": false,
		"config": config,
	}
	MotionSpecs.scale_distances_to_rig(config, ctx, [], MotionSpecs.REFERENCE_LEG)
	ctx["direction"] = "left"
	ctx["phase"] = 0.0

	var result: Dictionary = MotionSpecs.gait_keys(ctx, run)
	var keys: Dictionary = result.get("keys", {})
	if keys.is_empty():
		_fail("%s: no bones keyed" % anim_name)
		return

	# The player's root_node is its parent, so a track to the skeleton or to the
	# translate pivot is a plain relative path.
	var root_node := player.get_node_or_null(player.root_node)
	if root_node == null:
		_fail("%s: player has no resolvable root_node" % anim_name)
		return
	var track_root := str(root_node.get_path_to(skeleton))
	var spec := ClipSpec.make(duration, Animation.LOOP_NONE)
	for marker in result.get("markers", []):
		ClipSpec.add_marker(spec, str(marker.get("name", "")), float(marker.get("time", 0.0)))

	var bones := 0
	for bone_name in keys:
		var index := skeleton.find_bone(str(bone_name))
		if index < 0:
			continue
		var entry: Dictionary = keys[bone_name]
		var rest_rotation := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
		if entry.has("rotation"):
			var rotation_keys: Array = []
			for key in entry.rotation:
				rotation_keys.append({
					"time": float(key.time),
					"value": (rest_rotation * (key.delta as Quaternion)).normalized(),
					"transition": "linear",
				})
			ClipSpec.align_quaternions(rotation_keys)
			ClipSpec.close_loop(rotation_keys, duration)
			ClipSpec.add_value_track(spec, "%s:%s" % [track_root, bone_name], rotation_keys,
				Animation.INTERPOLATION_LINEAR, Animation.TYPE_ROTATION_3D)
		if entry.has("position"):
			var position_keys: Array = []
			for key in entry.position:
				position_keys.append({
					"time": float(key.time),
					"value": skeleton.get_bone_rest(index).origin + (key.delta as Vector3),
					"transition": "linear",
				})
			ClipSpec.close_loop(position_keys, duration)
			ClipSpec.add_value_track(spec, "%s:%s" % [track_root, bone_name], position_keys,
				Animation.INTERPOLATION_LINEAR, Animation.TYPE_POSITION_3D)
		bones += 1

	# The in-place gait is carried by the pivot it stands on, at the speed the
	# gait itself implies, so the feet stay planted instead of sliding.
	if anim_name == "walk_in":
		_add_position(spec, "Walker", [
			[0.0, Vector3(0.0, 0.0, 1.08)], [duration, Vector3.ZERO],
		])
	elif anim_name == "run_in":
		_add_position(spec, "Runner", [
			[0.0, Vector3(0.0, 0.0, 1.9)], [duration, Vector3.ZERO],
		])

	for track in spec.get("tracks", []):
		if int(track.type) != Animation.TYPE_POSITION_3D:
			continue
		for key in track.keys:
			if not (key.get("value") is Vector3):
				_fail("%s: %s key at %.3f is %s, not Vector3" % [
					anim_name, track.path, float(key.time), type_string(typeof(key.value))])
				return

	_install(player, anim_name, SpecBuilder.to_animation(spec))
	_report.append("%s: %d bones, %d keys, %d markers, %.2fs" % [
		anim_name, bones, ClipSpec.total_key_count(spec), result.get("markers", []).size(), duration])


# --- authored clips ----------------------------------------------------------

## The victim is already at the door, so the beat is the swing itself.
func _door(root: Node) -> void:
	var player: AnimationPlayer = root.get_node("SetAnim")
	var spec := ClipSpec.make(LENGTH, Animation.LOOP_NONE)
	_add_rotation(spec, "Door", [
		[0.0, Vector3.ZERO],
		[0.45, Vector3.ZERO],
		[1.75, Vector3(0.0, -1.31, 0.0)],
		[LENGTH, Vector3(0.0, -1.31, 0.0)],
	])
	_install(player, "set", SpecBuilder.to_animation(spec))
	_report.append("set: door swing 0.45s-1.75s")


## Impact twitch on contact, a held beat, then the launch and the landing.
func _victim_fly(root: Node) -> void:
	var player: AnimationPlayer = root.get_node("Victim/VictimAnim")
	var spec := ClipSpec.make(LENGTH, Animation.LOOP_NONE)
	_add_position(spec, ".", [
		[0.0, Vector3(0.0, 0.0, 0.1)],
		[2.95, Vector3(0.0, 0.0, 0.1)],
		[3.08, Vector3(-0.12, 0.12, 0.02)],
		[3.25, Vector3(-0.35, 0.32, -0.08)],
		[3.8, Vector3(-0.75, 0.7, -0.45)],
		[4.35, Vector3(-1.9, 0.35, 0.55)],
		[4.7, Vector3(-2.1, 0.28, 0.7)],
		[LENGTH, Vector3(-2.1, 0.28, 0.7)],
	])
	_add_rotation(spec, ".", [
		[0.0, Vector3.ZERO],
		[2.95, Vector3.ZERO],
		[3.08, Vector3(0.1, 0.0, -0.2)],
		[3.25, Vector3(0.2, 0.0, -0.55)],
		[3.8, Vector3(0.7, 0.0, -1.2)],
		[4.35, Vector3(1.2, 0.0, -1.65)],
		[4.7, Vector3(1.25, 0.0, -1.65)],
		[LENGTH, Vector3(1.25, 0.0, -1.65)],
	])
	var skeleton: Skeleton3D = root.get_node("Victim/Walker/Body/Skeleton3D")
	var bone_root := "Walker/Body/Skeleton3D"
	_add_bone_rotation(spec, skeleton, bone_root, "B-chest", [
		[0.0, Vector3.ZERO], [2.95, Vector3.ZERO], [3.08, Vector3(0.35, 0, -0.2)],
		[3.25, Vector3(0.5, 0, -0.25)],
		[3.8, Vector3(-0.35, 0, 0.3)], [4.7, Vector3(0.2, 0, 0.2)],
		[LENGTH, Vector3(0.2, 0, 0.2)],
	])
	for side in ["L", "R"]:
		var sign := 1.0 if side == "L" else -1.0
		_add_bone_rotation(spec, skeleton, bone_root, "B-upperArm." + side, [
			[0.0, Vector3.ZERO], [2.95, Vector3.ZERO], [3.08, Vector3(0.2, 0, sign * 0.5)],
			[3.25, Vector3(0.0, 0.0, sign * 0.9)],
			[3.8, Vector3(0.5, 0.0, sign * 1.2)],
			[4.7, Vector3(0.1, 0.0, sign * 0.4)],
			[LENGTH, Vector3(0.1, 0.0, sign * 0.4)],
		])
		_add_bone_rotation(spec, skeleton, bone_root, "B-thigh." + side, [
			[0.0, Vector3.ZERO], [2.95, Vector3.ZERO], [3.08, Vector3(sign * 0.2, 0, 0)],
			[3.25, Vector3(sign * 0.35, 0, 0)],
			[3.8, Vector3(-sign * 0.65, 0, 0)],
			[4.7, Vector3(sign * 0.3, 0, 0)],
			[LENGTH, Vector3(sign * 0.3, 0, 0)],
		])
	_install(player, "fly", SpecBuilder.to_animation(spec))
	_report.append("fly: impact 3.0s, airborne reaction and fall")


## The run ends on its last stride, so the kick is a body lunge on the outer
## pivot - no bone track, which is also why it cannot fight the run's.
func _kicker_kick(root: Node) -> void:
	var player: AnimationPlayer = root.get_node("Kicker/KickAnim")
	var spec := ClipSpec.make(LENGTH, Animation.LOOP_NONE)
	_add_position(spec, ".", [
		[0.0, Vector3(1.35, 0.0, 0.62)],
		[2.7, Vector3(1.35, 0.0, 0.62)],
		[2.95, Vector3(0.85, 0.35, 0.34)],
		[3.3, Vector3(0.50, 0.5, 0.16)],
		[3.85, Vector3(0.45, 0.12, 0.05)],
		[4.3, Vector3(0.45, 0.0, 0.05)],
		[LENGTH, Vector3(0.45, 0.0, 0.05)],
	])
	_add_rotation(spec, ".", [
		[0.0, Vector3.ZERO],
		[2.7, Vector3(0.0, 0.25, 0.0)],
		[2.95, Vector3(0.0, 1.0, -0.15)],
		[3.3, Vector3(0.0, 1.1, -0.25)],
		[3.85, Vector3(0.0, 0.45, 0.0)],
		[4.3, Vector3.ZERO],
		[LENGTH, Vector3.ZERO],
	])
	var skeleton: Skeleton3D = root.get_node("Kicker/Runner/Body/Skeleton3D")
	var bone_root := "Runner/Body/Skeleton3D"
	_add_bone_rotation(spec, skeleton, bone_root, "B-thigh.R", [
		[0.0, Vector3.ZERO], [2.7, Vector3.ZERO],
		[2.95, Vector3(0.6, 0, 0)], [3.3, Vector3(0.85, 0, 0)],
		[3.85, Vector3(-0.25, 0, 0)], [4.3, Vector3.ZERO], [LENGTH, Vector3.ZERO],
	])
	_add_bone_rotation(spec, skeleton, bone_root, "B-shin.R", [
		[0.0, Vector3.ZERO], [2.7, Vector3.ZERO],
		[2.95, Vector3(0.2, 0, 0)], [3.3, Vector3(0.3, 0, 0)],
		[3.85, Vector3(0.1, 0, 0)], [4.3, Vector3.ZERO], [LENGTH, Vector3.ZERO],
	])
	_add_bone_rotation(spec, skeleton, bone_root, "B-thigh.L", [
		[0.0, Vector3.ZERO], [2.7, Vector3.ZERO],
		[2.95, Vector3(-1.15, 0, -0.1)], [3.3, Vector3(-1.3, 0, -0.2)],
		[3.85, Vector3(0.4, 0, 0)], [4.3, Vector3.ZERO], [LENGTH, Vector3.ZERO],
	])
	_add_bone_rotation(spec, skeleton, bone_root, "B-shin.L", [
		[0.0, Vector3.ZERO], [2.7, Vector3.ZERO],
		[2.95, Vector3(0.3, 0, 0)], [3.3, Vector3(-0.05, 0, 0)],
		[3.85, Vector3(0.7, 0, 0)], [4.3, Vector3.ZERO], [LENGTH, Vector3.ZERO],
	])
	_add_bone_rotation(spec, skeleton, bone_root, "B-chest", [
		[0.0, Vector3.ZERO], [2.7, Vector3.ZERO],
		[2.95, Vector3(0.3, 0, 0)], [3.3, Vector3(0.45, 0, 0)],
		[3.85, Vector3(-0.15, 0, 0)], [4.3, Vector3.ZERO], [LENGTH, Vector3.ZERO],
	])
	for side in ["L", "R"]:
		var sign := 1.0 if side == "L" else -1.0
		_add_bone_rotation(spec, skeleton, bone_root, "B-upperArm." + side, [
			[0.0, Vector3.ZERO], [2.7, Vector3.ZERO],
			[2.95, Vector3(0.4, 0, sign * 0.5)],
			[3.3, Vector3(0.65, 0, sign * 0.7)],
			[3.85, Vector3(0.1, 0, sign * 0.25)],
			[4.3, Vector3.ZERO], [LENGTH, Vector3.ZERO],
		])
	_install(player, "kick", SpecBuilder.to_animation(spec))
	_report.append("kick: airborne leg extension 2.7s-3.3s")


func _compose_characters(root: Node) -> void:
	var pairs := [
		{"player": "Victim/WalkAnim", "gait": "walk_in",
			"action_player": "Victim/VictimAnim", "action": "fly",
			"output": "victim_action", "start": 2.0, "fade": 0.2,
			"contacts": [{"name": "impact", "time": 1.0},
				{"name": "landing", "time": 2.7}]},
		{"player": "Kicker/RunAnim", "gait": "run_in",
			"action_player": "Kicker/KickAnim", "action": "kick",
			"output": "kicker_action", "start": 2.5, "fade": 0.2,
			"contacts": [{"name": "kick_impact", "time": 0.55},
				{"name": "landing", "time": 1.8}]},
	]
	for entry in pairs:
		var player: AnimationPlayer = root.get_node(entry.player)
		var action_player: AnimationPlayer = root.get_node(entry.action_player)
		var gait: Animation = player.get_animation(entry.gait)
		var action: Animation = action_player.get_animation(entry.action)
		var start := float(entry.start)
		var gait_spec: Dictionary = SpecIO.from_animation(gait)
		var action_spec: Dictionary = SpecIO.from_animation(action)
		# A sparse action starts from the last played gait pose. Otherwise its
		# rest keys pull the character into the imported rig's T pose before impact.
		var action_ready := 2.95 if str(entry.output) == "victim_action" else 2.7
		_seed_action_from_gait(gait_spec, action_spec, start, action_ready,
			str(entry.output) == "kicker_action")
		var composed := SequenceSpecs.compose([
			{"start": 0.0, "duration": gait.length, "source_start": 0.0,
				"source_end": gait.length, "fade_in": 0.0,
				"spec": gait_spec},
			{"start": start, "duration": LENGTH - start, "source_start": start,
				"source_end": LENGTH, "fade_in": float(entry.fade),
				"spec": action_spec, "contacts": entry.contacts},
		], LENGTH, 30)
		if composed.has("error"):
			_fail("%s: %s" % [entry.output, str(composed.error)])
			return
		_install(player, str(entry.output), SpecBuilder.to_animation(composed.spec))
		# Only one player now writes each character. The old action player was a
		# workaround that let gait and action freeze or fight over the same bones.
		action_player.get_parent().remove_child(action_player)
		action_player.free()
		_report.append("%s: %d tracks, %d samples, one AnimationPlayer" % [
			entry.output, (composed.spec.tracks as Array).size(), int(composed.sample_count)])


func _seed_action_from_gait(gait: Dictionary, action: Dictionary, start: float,
		ready: float, settle_arms: bool) -> void:
	var gait_tracks := {}
	for track in gait.get("tracks", []):
		gait_tracks["%d|%s" % [int(track.type), str(track.path)]] = track
	for track in action.get("tracks", []):
		if not str(track.path).contains("Skeleton3D:"):
			continue
		var label := "%d|%s" % [int(track.type), str(track.path)]
		if not gait_tracks.has(label):
			continue
		var inherited = SpecModifiers.sample_track(gait_tracks[label], gait.length)
		var keys: Array = [
			{"time": start, "value": inherited, "transition": 1.0},
			{"time": ready, "value": inherited, "transition": 1.0},
		]
		for key in track.keys:
			if float(key.time) > ready + 0.0001:
				var kept: Dictionary = key.duplicate(true)
				if settle_arms and str(track.path).contains("B-upperArm"):
					kept.value = inherited
				keys.append(kept)
		track.keys = keys


func _add_bone_rotation(spec: Dictionary, skeleton: Skeleton3D, track_root: String,
		bone: String, rows: Array) -> void:
	var index := skeleton.find_bone(bone)
	if index < 0:
		_fail("missing pose bone %s" % bone)
		return
	var rest := skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
	var keys: Array = []
	for row in rows:
		var delta := Quaternion(Basis.from_euler(row[1]))
		keys.append({"time": float(row[0]), "value": (rest * delta).normalized(),
			"transition": 1.0})
	ClipSpec.align_quaternions(keys)
	ClipSpec.add_value_track(spec, "%s:%s" % [track_root, bone], keys,
		Animation.INTERPOLATION_LINEAR, Animation.TYPE_ROTATION_3D)


# --- track helpers -----------------------------------------------------------

func _add_position(spec: Dictionary, node_path: String, rows: Array) -> void:
	var keys: Array = []
	for row in rows:
		keys.append({"time": float(row[0]), "value": row[1], "transition": "ease_in_out"})
	ClipSpec.add_value_track(spec, "%s:position" % node_path, keys,
		Animation.INTERPOLATION_CUBIC, Animation.TYPE_POSITION_3D)


func _add_rotation(spec: Dictionary, node_path: String, rows: Array) -> void:
	var keys: Array = []
	for row in rows:
		keys.append({
			"time": float(row[0]),
			"value": Quaternion(Basis.from_euler(row[1])),
			"transition": "ease_in_out",
		})
	ClipSpec.align_quaternions(keys)
	ClipSpec.add_value_track(spec, "%s:rotation" % node_path, keys,
		Animation.INTERPOLATION_CUBIC, Animation.TYPE_ROTATION_3D)


func _install(player: AnimationPlayer, anim_name: String, anim: Animation) -> void:
	var library: AnimationLibrary
	if player.has_animation_library(""):
		library = player.get_animation_library("")
	else:
		library = AnimationLibrary.new()
		player.add_animation_library("", library)
	if library.has_animation(anim_name):
		library.remove_animation(anim_name)
	library.add_animation(anim_name, anim)
	player.autoplay = anim_name


## MotionHandler._default_arm_down: a rig whose arms rest near-vertical is
## already aiming down, anything else needs the full pull toward the floor.
func _default_arm_down(skeleton: Skeleton3D, roles: Dictionary) -> float:
	for side in ["l", "r"]:
		var arm := str(roles.get("arm_" + side, ""))
		if arm.is_empty():
			continue
		var index := skeleton.find_bone(arm)
		if index < 0:
			continue
		var rest_dir := (skeleton.get_bone_global_rest(index).basis * Vector3.UP).normalized()
		if absf(rest_dir.dot(Vector3.UP)) < 0.5:
			return 78.0
	return 0.0


func _fail(message: String) -> void:
	_failed = true
	printerr("CLIP_BUILD_FAIL: %s" % message)
