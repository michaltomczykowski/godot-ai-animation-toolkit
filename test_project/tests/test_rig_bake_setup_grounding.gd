@tool
extends McpTestSuite

## Real setup ownership and native modifier signal, never reconstructed FK.
const Registry := preload("res://addons/godot_ai/custom_tools/mcp_tool_registry.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const Codec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")
const Sampler := preload("res://addons/godot_ai_animation/utils/pose_bake_sampler.gd")
const Replay := preload("res://addons/godot_ai_animation/utils/bake_graph_replay.gd")
const RootMotion := preload("res://addons/godot_ai_animation/utils/bake_root_motion.gd")
const Digest := preload("res://tests/golden_digest.gd")
const Capture := preload("res://tests/test_graph_route_history.gd")
const FIXTURE := preload("res://repair_synthetic_short.tscn")
var undo: EditorUndoRedoManager
var dispatcher
var logger: Capture.ErrorCapture
class Foreign extends SkeletonModifier3D:
	func _process_modification_with_delta(_delta: float) -> void: pass

func suite_name() -> String: return "rig_bake_setup_grounding"
func suite_setup(ctx: Dictionary) -> void:
	undo = ctx.undo_redo
	Context.undo_redo = undo
	dispatcher = Registry.get_instance().get("_dispatcher")
	logger = Capture.ErrorCapture.new()
	OS.add_logger(logger)
func suite_teardown() -> void: OS.remove_logger(logger)
func _call(family: String, params: Dictionary) -> Dictionary:
	return dispatcher.call("_dispatch", {"request_id": "bake-setup-grounding", "command": "custom_tool:"+family, "params": params})
func _own(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	for child in node.get_children(): _own(child, owner_node)
func _history() -> UndoRedo:
	return undo.get_history_undo_redo(undo.get_object_history_id(EditorInterface.get_edited_scene_root()))
func _fixture(label: String) -> Dictionary:
	var scene := EditorInterface.get_edited_scene_root()
	var body := FIXTURE.instantiate() as Node3D
	body.name = label
	scene.add_child(body)
	_own(body, scene)
	var skeleton := body.get_node("Dummy/Skeleton3D") as Skeleton3D
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var result := _call("animation_motion", {"op": "character_setup", "player_path": str(player.get_path()),
		"skeleton_path": str(skeleton.get_path()), "root_motion": true, "active": true,
		"include_jump": false, "include_turn": false})
	assert_has_key(result, "data", "real public character_setup "+str(result))
	if not result.has("data"):
		body.free()
		return {}
	var tree := Codec.resolve_scene_path(str(result.data.tree_path), scene) as AnimationTree
	var grounder := Codec.resolve_scene_path(str(result.data.get("grounding_path", "")), scene) as SkeletonModifier3D
	assert_true(tree != null and grounder != null, "actual setup owns Tree and grounding helper")
	if tree == null or grounder == null:
		body.free()
		return {}
	assert_eq(grounder.get_script().resource_path, Sampler.GROUNDING_PATH, "exact setup runtime helper")
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var speed := (float(result.data.speed_values.walk)+float(result.data.speed_values.run))*0.5
	tree.set(str(result.data.speed_parameter), speed)
	grounder.call("reset_grounding", "independent_native_take")
	return {"root": body, "skeleton": skeleton, "player": player, "tree": tree,
		"grounder": grounder, "speed": speed, "speed_parameter": str(result.data.speed_parameter)}
func _poses(skeleton: Skeleton3D) -> Array:
	var poses: Array = []
	for bone in skeleton.get_bone_count(): poses.append(skeleton.get_bone_pose(bone))
	return poses
func _tick(f: Dictionary, delta: float) -> Dictionary:
	f.tree.advance(delta)
	var fk := _poses(f.skeleton)
	assert_true(f.tree.get_root_motion_rotation().is_equal_approx(Quaternion.IDENTITY), "straight setup replay has no yaw extraction")
	# This fixture has identity parent/yaw; consume native translation only.
	# Bone poses come solely from the real Tree and real grounding modifier.
	f.root.position += f.tree.get_root_motion_position()
	var observed := {"poses": [], "count": 0}
	var signal_capture := func():
		observed.poses = _poses(f.skeleton)
		observed.count += 1
	f.grounder.modification_processed.connect(signal_capture)
	f.skeleton.advance(delta)
	f.skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
	f.grounder.modification_processed.disconnect(signal_capture)
	assert_eq(observed.count, 1, "one actual final grounding signal")
	assert_eq(f.grounder.get("status"), "grounded", "native solve succeeded "+str(f.grounder.call("diagnostics")))
	return {"poses": observed.poses, "fk": fk}
func _state(f: Dictionary) -> Dictionary:
	var result := {"pose": _poses(f.skeleton), "transform": f.root.transform, "tree_active": f.tree.active,
		"tree_root": f.tree.tree_root, "player_library": f.player.get_animation_library(""), "helper": {}, "parameters": {}}
	for field in ["status","last_error","evaluations","unreachable","resets","reset_reason","max_residual_m","evaluation_residual_m","max_correction_m","_view","_signature","_anchors","_phases","_was_enabled","_points"]:
		var value: Variant = f.grounder.get(field)
		result.helper[field] = value.duplicate(true) if value is Dictionary or value is Array else value
	for entry in f.tree.get_property_list():
		if str(entry.name).begins_with("parameters/"): result.parameters[str(entry.name)] = f.tree.get(entry.name)
	return result
func _params(f: Dictionary, fps: int) -> Dictionary:
	return {"op": "bake_pose_sequence", "player_path": str(f.player.get_path()), "skeleton_path": str(f.skeleton.get_path()),
		"source_tree_path": str(f.tree.get_path()), "animation_name": "grounded_bake", "duration": 0.3,
		"fps": fps, "positions": true, "scales": true, "root_motion_mode": "preserve",
		"root_motion_target_path": str(f.root.get_path()), "tree_parameters": {f.speed_parameter: f.speed}}
func _difference(a: Array, b: Array) -> float:
	var worst := 0.0
	for bone in mini(a.size(),b.size()):
		worst = maxf(worst,a[bone].origin.distance_to(b[bone].origin))
		worst = maxf(worst,a[bone].basis.get_rotation_quaternion().angle_to(b[bone].basis.get_rotation_quaternion()))
	return worst
func test_real_setup_final_signal_bake_and_live_continuation() -> void:
	for fps in [30,60]: _case(fps)
func _case(fps: int) -> void:
	var errors := logger.errors.size()
	var subject := _fixture("GroundedBakeSubject")
	var control := _fixture("GroundedBakeControl")
	var reference := _fixture("GroundedBakeReference")
	if subject.is_empty() or control.is_empty() or reference.is_empty():
		for f in [subject,control,reference]:
			if not f.is_empty(): f.root.free()
		return
	for frame in 8:
		_tick(subject,1.0/fps)
		_tick(control,1.0/fps)
	var before := _state(subject)
	assert_true(not before.helper._phases.is_empty(), "live source has warmed native phases")
	var version := _history().get_version()
	var orphans := Node.get_orphan_node_ids()
	var params := _params(subject,fps)
	var dry := _call("animation_rig",params.merged({"dry_run":true},true))
	assert_has_key(dry,"data","grounded dry bake "+str(dry))
	assert_eq(_state(subject),before,"dry preserves every live grounding cache/phase and pose")
	assert_eq(_history().get_version(),version,"dry creates no history")
	assert_eq(Node.get_orphan_node_ids(),orphans,"dry frees private evaluation")
	var made := _call("animation_rig",params)
	assert_has_key(made,"data","grounded Tree bake "+str(made))
	if made.has("data"):
		assert_eq(_state(subject),before,"write preserves live state")
		var output := Codec.resolve_scene_path(str(made.data.player_path),EditorInterface.get_edited_scene_root()) as AnimationPlayer
		var clip := output.get_animation("grounded_bake")
		var path: String = str(output.get_node(output.root_node).get_path_to(subject.skeleton))
		var track := clip.find_track(path+":"+str(subject.skeleton.get_bone_name(0)),Animation.TYPE_ROTATION_3D)
		assert_true(track>=0,"actual baked bone tracks")
		var previous := 0.0
		var correction := 0.0
		for sample in (clip.track_get_key_count(track) if track>=0 else 0):
			var time := clip.track_get_key_time(track,sample)
			var native := _tick(reference,time-previous)
			assert_eq(native.poses.size(),subject.skeleton.get_bone_count(),"all native final bones captured")
			correction = maxf(correction,_difference(native.fk,native.poses))
			for bone in native.poses.size():
				var bone_path := path+":"+str(subject.skeleton.get_bone_name(bone))
				var r := clip.find_track(bone_path,Animation.TYPE_ROTATION_3D)
				var p := clip.find_track(bone_path,Animation.TYPE_POSITION_3D)
				var s := clip.find_track(bone_path,Animation.TYPE_SCALE_3D)
				assert_true(r>=0 and p>=0 and s>=0,"complete baked final TRS")
				if mini(r,mini(p,s))<0: continue
				assert_true((clip.track_get_key_value(r,sample) as Quaternion).angle_to(native.poses[bone].basis.get_rotation_quaternion())<0.001,"native grounded rotation")
				assert_true((clip.track_get_key_value(p,sample) as Vector3).distance_to(native.poses[bone].origin)<0.00001,"native grounded position")
				assert_true((clip.track_get_key_value(s,sample) as Vector3).distance_to(native.poses[bone].basis.get_scale())<0.00001,"native grounded scale")
			previous = time
		assert_true(correction>0.00001,"oracle is nontrivial: native grounded result differs from raw Tree FK")
		var repeat := _call("animation_rig",params.merged({"output_player_path":made.data.player_path,"overwrite":true},true))
		assert_has_key(repeat,"data","repeat grounded replay")
		var repeated := output.get_animation("grounded_bake")
		var parity := Digest.compare(Digest.from_animation(clip),Digest.from_animation(repeated))
		assert_eq(str(parity.shape),"","repeat same key structure")
		assert_eq(int(parity.worst),0,"repeat fresh private caches give identical keys")
		assert_eq(_state(subject),before,"repeat preserves live state")
		assert_eq(_history().get_version(),version+2,"one action per write")
		assert_true(_history().undo(),"undo repeat")
		assert_true(output.get_animation("grounded_bake")==clip,"Undo restores original clip identity")
		assert_true(_history().undo(),"undo initial bake")
		assert_false(output.is_inside_tree(),"Undo removes isolated output")
		assert_true(_history().redo(),"Redo initial bake")
		assert_true(_history().redo(),"Redo repeat")
		assert_eq(_state(subject),before,"Undo/Redo preserves live grounding state")
		assert_true(_history().undo(),"cleanup repeat")
		assert_true(_history().undo(),"cleanup initial bake")
	for frame in 6:
		var continued := _tick(subject,1.0/fps)
		var expected := _tick(control,1.0/fps)
		assert_true(_difference(continued.poses,expected.poses)<0.001,"continued live grounding matches untouched native control")
	assert_eq(logger.errors.size(),errors,"no bake engine errors "+str(logger.errors.slice(errors)))
	for f in [subject,control,reference]: f.root.free()

func test_private_failure_and_wrong_or_foreign_binding_refuse_atomically() -> void:
	var errors := logger.errors.size()
	var f := _fixture("GroundedBakeFailures")
	if f.is_empty(): return
	_tick(f,0.01)
	var before := _state(f)
	var version := _history().get_version()
	var orphans := Node.get_orphan_node_ids()
	for fail_solve in [false,true]:
		var replay := Replay.new()
		assert_has_key(replay.configure(f.tree,_params(f,30),0.3),"ok")
		var motion := RootMotion.new()
		assert_has_key(motion.configure(f.tree,f.player,f.root,"","preserve"),"ok")
		var sampler := Sampler.new()
		var opened := sampler.open(EditorInterface.get_edited_scene_root(),f.skeleton,f.player,"",f.tree,replay,motion,f.root)
		assert_has_key(opened,"ok","private grounded evaluator opens")
		if not opened.has("ok"): continue
		assert_has_key(sampler.sample(0.0,0.0),"poses","first grounded capture")
		if fail_solve: sampler.grounders[sampler.skeleton].set("target_tolerance_m",0.0)
		else: sampler._test_fail_at=0.1
		var refused := sampler.sample(0.1,0.1)
		assert_eq(refused.get("error",{}).get("code"),"OPERATION_UNAVAILABLE","late/private solve failure is typed")
		sampler.close()
		assert_eq(_state(f),before,"private failure preserves live helper/Tree")
		assert_eq(Node.get_orphan_node_ids(),orphans,"failure frees private nodes")
		assert_eq(_history().get_version(),version,"failure creates no history")
	var bare := _params(f,30)
	bare.erase("source_tree_path")
	bare.erase("tree_parameters")
	bare.source_animation="walk"
	var wrong := _call("animation_rig",bare)
	assert_eq(wrong.get("error",{}).get("code"),"OPERATION_UNAVAILABLE","grounding refuses missing explicit Tree")
	var original_binding: NodePath = f.grounder.get("tree_path")
	f.grounder.set("tree_path",NodePath("/MissingGroundingTree"))
	var wrong_binding := _call("animation_rig",_params(f,30))
	assert_eq(wrong_binding.get("error",{}).get("code"),"OPERATION_UNAVAILABLE","grounding refuses a different or missing Tree binding")
	f.grounder.set("tree_path",original_binding)
	f.grounder.active=false
	var foreign := Foreign.new()
	f.skeleton.add_child(foreign)
	var rejected := _call("animation_rig",_params(f,30))
	assert_eq(rejected.get("error",{}).get("code"),"OPERATION_UNAVAILABLE","foreign scripted modifier remains unavailable")
	foreign.free()
	f.grounder.active=true
	assert_eq(_state(f),before,"refusals preserve live helper state")
	assert_eq(_history().get_version(),version,"refusals create no history")
	assert_eq(logger.errors.size(),errors,"typed refusals emit no engine errors "+str(logger.errors.slice(errors)))
	f.root.free()
