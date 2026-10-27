@tool
extends McpTestSuite
const Motion := preload("res://addons/godot_ai_animation/handlers/motion.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const Codec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")
var handler: Motion
func suite_name() -> String: return "motion_transform"
func suite_setup(ctx: Dictionary) -> void:
	Context.undo_redo = ctx.get("undo_redo")
	handler = Motion.new()
func test_rotated_nested_uniform_world_metrics_and_native_root() -> void:
	for fixture in ["res://repair_synthetic_short.tscn", "res://repair_synthetic_zup_tall.tscn"]:
		for scale_value in [0.5,2.0]:
			var view := _fixture(fixture, scale_value)
			var args: Dictionary = view.args
			var body: Node3D = view.body
			var skeleton: Skeleton3D = view.skeleton
			var player: AnimationPlayer = view.player
			var prepared := handler._prepare_cycle(args, "walk")
			assert_true(not prepared.has("error"), "scaled walk prepares")
			if prepared.has("error"):
				view.parent.free()
				continue
			var direction: Vector3 = (skeleton.global_basis * prepared.ctx.forward).normalized()
			var result := handler.run(args, null)
			assert_true(result.has("data"), "scaled explicit walk: " + str(result))
			if result.has("data"):
				assert_true(absf(float(result.data.speed)-0.18)<0.000001, "explicit world speed preserved")
				assert_true(absf(float(result.data.world_scale)-scale_value)<0.000001, "effective uniform scale reported")
				assert_eq(result.data.root_motion_space,"owner_parent","root displacement coordinate contract")
				var origin: Vector3 = body.position
				for fps in [30,60,120]:
					body.position = origin
					var initial: Vector3 = body.global_position
					player.stop()
					player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
					player.play("metric_walk")
					player.advance(0.0)
					for step in fps:
						player.advance(1.0/fps)
						body.position += player.get_root_motion_position()
					assert_true((body.global_position-initial).distance_to(direction*0.18)<0.00001,"native world speed/direction fps"+str(fps))
			player.stop()
			var jump := args.duplicate(true)
			jump.merge({"op":"jump","animation_name":"metric_jump","duration":1.6,"height":0.12,"crouch":0.05,"distance":0.2},true)
			jump.erase("speed")
			var made := handler.run(jump,null)
			assert_true(made.has("data"),"scaled explicit jump: "+str(made))
			if made.has("data"):
				assert_true(absf(float(made.data.height)-0.12)<0.000001 and absf(float(made.data.crouch)-0.05)<0.000001 and absf(float(made.data.distance)-0.2)<0.000001,"explicit jump world metric metadata")
				var clip := player.get_animation("metric_jump")
				var track := clip.find_track(player.root_motion_track,Animation.TYPE_POSITION_3D)
				var authored: Vector3 = clip.track_get_key_value(track,clip.track_get_key_count(track)-1)-clip.track_get_key_value(track,0)
				assert_true(absf((view.parent.global_basis*authored).length()-0.2)<0.00001,"authored jump world distance")
			view.parent.get_parent().remove_child(view.parent)
			view.parent.free()
func test_transition_schedule_declares_skeleton_coordinates() -> void:
	var view := _fixture("res://repair_synthetic_short.tscn",2.0)
	var args: Dictionary = view.args.duplicate(true)
	args.merge({"op":"walk_start","animation_name":"schedule_start","duration":0.8,"root_motion":true},true)
	var result := handler.run(args,null)
	assert_true(result.has("data"),"transformed transition builds: "+str(result))
	if result.has("data"):
		assert_eq(result.data.actor_translation_space,"skeleton_local","schedule space is truthful")
		assert_true(absf(float(result.data.actor_translation_world_scale)-2.0)<0.000001,"schedule declares effective world scale")
		var schedule: Array = result.data.actor_translation_keys
		var last: Array = schedule[-1].offset
		var schedule_world: Vector3 = view.skeleton.global_basis*Vector3(float(last[0]),float(last[1]),float(last[2]))
		var clip: Animation = view.player.get_animation("schedule_start")
		var track: int = clip.find_track(view.player.root_motion_track,Animation.TYPE_POSITION_3D)
		var authored: Vector3 = clip.track_get_key_value(track,clip.track_get_key_count(track)-1)-clip.track_get_key_value(track,0)
		assert_true((view.parent.global_basis*authored).distance_to(schedule_world)<0.00001,"skeleton schedule converts to the actual owner-parent root track")
	view.parent.get_parent().remove_child(view.parent)
	view.parent.free()
func test_unsupported_transform_refuses_before_scene_history_changes() -> void:
	var view := _fixture("res://repair_synthetic_short.tscn",1.0)
	var parent: Node3D = view.parent
	var player: AnimationPlayer = view.player
	var initial_binding := player.root_motion_track
	var initial_names := player.get_animation_list()
	var skeleton: Skeleton3D = view.skeleton
	var initial_pose := skeleton.get_bone_pose_rotation(1)
	var child_count: int = view.body.get_child_count()
	var history := Context.undo_redo.get_history_undo_redo(Context.undo_redo.get_object_history_id(view.body))
	var version := history.get_version()
	for invalid in [Basis.from_scale(Vector3(1,2,1)),Basis.from_scale(Vector3(-1,1,1)),Basis(Vector3(1,0,0),Vector3(0.2,1,0),Vector3(0,0,1))]:
		parent.basis=invalid
		for op in ["walk_cycle","character_setup"]:
			var args: Dictionary = view.args.duplicate(true)
			args.op=op
			var result := handler.run(args,null)
			assert_true(result.has("error") and result.error.code=="OPERATION_UNAVAILABLE","unsupported effective transform typed refusal")
			assert_eq(player.get_animation_list(),initial_names,"refusal library unchanged")
			assert_eq(player.root_motion_track,initial_binding,"refusal binding unchanged")
			assert_eq(skeleton.get_bone_pose_rotation(1),initial_pose,"refusal pose unchanged")
			assert_eq(view.body.get_child_count(),child_count,"refusal tree unchanged")
			assert_eq(history.get_version(),version,"refusal history unchanged")
	parent.basis=Basis.IDENTITY
	skeleton.top_level=true
	var detached := handler.run(view.args,null)
	assert_true(detached.has("error") and detached.error.code=="OPERATION_UNAVAILABLE","detached spatial inheritance refuses")
	assert_eq(player.get_animation_list(),initial_names,"detached refusal library unchanged")
	assert_eq(history.get_version(),version,"detached refusal history unchanged")
	parent.get_parent().remove_child(parent)
	parent.free()
func _fixture(path: String, scale_value: float) -> Dictionary:
	var scene := EditorInterface.get_edited_scene_root()
	var parent := Node3D.new()
	parent.name="TransformFixture"
	parent.position=Vector3(4,2,-3)
	parent.basis=Basis(Vector3(1,2,3).normalized(),0.4).scaled(Vector3.ONE*scale_value)
	scene.add_child(parent)
	parent.owner=scene
	var body := (load(path) as PackedScene).instantiate() as Node3D
	parent.add_child(body)
	body.position=Vector3(2,0,1)
	body.rotation=Vector3(0.1,0.37,0.2)
	body.get_node("Dummy").rotation=Vector3(0.15,-0.25,0.1)
	_assign(body,scene)
	var skeleton := body.get_node("Dummy/Skeleton3D") as Skeleton3D
	var player := body.get_node("AnimationPlayer") as AnimationPlayer
	return {"parent":parent,"body":body,"skeleton":skeleton,"player":player,"args":{"op":"walk_cycle","player_path":Codec.from_node(player,scene),"skeleton_path":Codec.from_node(skeleton,scene),"animation_name":"metric_walk","duration":1.0,"speed":0.18,"root_motion":true}}
func _assign(node: Node, scene: Node) -> void:
	node.owner=scene
	for child in node.get_children(): _assign(child,scene)
