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

	_gait(root, "Victim/WalkAnim", "Victim/Walker/Body/Skeleton3D", "walk_in", false, 2.0)
	_gait(root, "Kicker/RunAnim", "Kicker/Runner/Body/Skeleton3D", "run_in", true, 2.6)

	_door(root)
	_victim_fly(root)
	_kicker_kick(root)

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
		[4.15, Vector3(0.0, 0.0, 0.1)],
		[4.75, Vector3(0.0, 0.55, -0.25)],
		[5.35, Vector3(0.0, 0.05, -0.6)],
		[5.85, Vector3(0.0, 0.0, -0.5)],
		[LENGTH, Vector3(0.0, 0.0, -0.5)],
	])
	_add_rotation(spec, ".", [
		[0.0, Vector3.ZERO],
		[2.85, Vector3.ZERO],
		[2.95, Vector3(0.0, 0.0, 0.1)],
		[3.08, Vector3.ZERO],
		[4.15, Vector3.ZERO],
		[4.75, Vector3(1.2, 0.0, -2.4)],
		[5.35, Vector3(1.6, 0.0, -4.2)],
		[5.85, Vector3(1.6, 0.0, -4.7)],
		[LENGTH, Vector3(1.6, 0.0, -4.7)],
	])
	_install(player, "fly", SpecBuilder.to_animation(spec))
	_report.append("fly: twitch 2.85s, launch 4.15s-5.85s")


## The run ends on its last stride, so the kick is a body lunge on the outer
## pivot - no bone track, which is also why it cannot fight the run's.
func _kicker_kick(root: Node) -> void:
	var player: AnimationPlayer = root.get_node("Kicker/KickAnim")
	var spec := ClipSpec.make(LENGTH, Animation.LOOP_NONE)
	_add_position(spec, ".", [
		[0.0, Vector3(1.35, 0.0, 0.62)],
		[2.7, Vector3(1.35, 0.0, 0.62)],
		[2.95, Vector3(0.78, 0.0, 0.34)],
		[3.3, Vector3(0.72, 0.0, 0.28)],
		[LENGTH, Vector3(0.72, 0.0, 0.28)],
	])
	_add_rotation(spec, ".", [
		[0.0, Vector3.ZERO],
		[2.7, Vector3.ZERO],
		[2.95, Vector3(0.0, -0.28, 0.0)],
		[3.3, Vector3(0.0, -0.16, 0.0)],
		[LENGTH, Vector3(0.0, -0.16, 0.0)],
	])
	_install(player, "kick", SpecBuilder.to_animation(spec))
	_report.append("kick: lunge 2.7s-3.3s")


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
