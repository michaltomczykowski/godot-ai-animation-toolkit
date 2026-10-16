@tool
extends McpTestSuite
const Capture := preload("res://tests/test_graph_route_history.gd")
const Grounding := preload("res://addons/godot_ai_animation/runtime/setup_grounding.gd")
const Motion := preload("res://addons/godot_ai_animation/handlers/motion.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const Codec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")
const Digest := preload("res://tests/golden_digest.gd")
const FIXTURES := ["res://models/human_dummy/HumanCharacterDummy_F.fbx", "res://models/x_bot/X Bot.fbx", "res://repair_synthetic_short.tscn", "res://repair_synthetic_zup_tall.tscn"]
var handler: Motion
var _logger: Capture.ErrorCapture
var _engine_scope_start := -1
func suite_name() -> String: return "setup_integration"
func suite_setup(ctx: Dictionary) -> void:
	Context.undo_redo = ctx.get("undo_redo")
	handler = Motion.new()
	_logger = Capture.ErrorCapture.new()
	OS.add_logger(_logger)
func setup() -> void: _engine_scope_start = -1
func teardown() -> void:
	if _engine_scope_start >= 0 and is_instance_valid(_logger):
		assert_eq(_logger.errors.size(), _engine_scope_start, "zero scoped setup/save-reopen engine errors: "+str(_logger.errors.slice(_engine_scope_start)))
	_engine_scope_start = -1
func suite_teardown() -> void:
	if is_instance_valid(_logger):
		OS.remove_logger(_logger)
		_logger = null
func _same(player: AnimationPlayer, actual: String, reference: String) -> void:
	assert_true(player.has_animation(actual) and player.has_animation(reference), "parity clips exist")
	if not player.has_animation(actual) or not player.has_animation(reference): return
	var result := Digest.compare(Digest.from_animation(player.get_animation(actual)), Digest.from_animation(player.get_animation(reference)))
	assert_eq(str(result.shape), "", actual + " structure")
	assert_eq(int(result.worst), 0, actual + " exact keys")
	var a := player.get_animation(actual)
	var b := player.get_animation(reference)
	assert_eq(a.get_marker_names(), b.get_marker_names(), actual + " markers")
	for marker in a.get_marker_names():
		assert_eq(a.get_marker_time(marker), b.get_marker_time(marker), actual + " marker time")
func test_default_setup_dummy_five_styles() -> void: _matrix(FIXTURES[0])
func test_default_setup_private_xbot_five_styles() -> void: _matrix(FIXTURES[1])
func test_default_setup_short_five_styles() -> void: _matrix(FIXTURES[2])
func test_default_setup_zup_tall_five_styles() -> void: _matrix(FIXTURES[3])
func _matrix(fixture: String) -> void:
	_engine_scope_start = _logger.errors.size()
	var scene := EditorInterface.get_edited_scene_root()
	if not ResourceLoader.exists(fixture):
		skip("private/local fixture unavailable: " + fixture)
		return
	for style in ["responsive", "grounded", "relaxed", "heavy", "sneaky"]:
		var body := (load(fixture) as PackedScene).instantiate()
		body.name = "SetupParity"
		scene.add_child(body)
		_assign(body, scene)
		var player := _find(body, "AnimationPlayer") as AnimationPlayer
		var skeleton := _find(body, "Skeleton3D") as Skeleton3D
		assert_true(player != null and skeleton != null, "fixture rig")
		if player == null or skeleton == null:
			body.free()
			continue
		var args := {"op": "character_setup", "player_path": Codec.from_node(player, scene), "skeleton_path": Codec.from_node(skeleton, scene), "style": style, "include_jump": true, "include_turn": true, "angle": 180.0}
		var setup := handler.run(args, null)
		assert_true(setup.has("data"), "default setup " + fixture + " " + style + ": " + str(setup))
		if setup.has("data"):
			var grounder := Codec.resolve_scene_path(str(setup.data.grounding_path), scene) as Grounding
			assert_true(grounder != null and grounder.get_script() == Grounding, "serialized setup grounder")
			if grounder != null:
				assert_eq(grounder.get_parent(), skeleton, "grounder is under bound skeleton")
				assert_eq(grounder.owner, scene, "grounder is scene owned")
				assert_true(grounder.active, "grounder ready while Tree inactive")
				assert_eq(grounder.validate_configuration(), "", "saved relative binding/configuration")
				for field in Grounding.CONFIG_FIELDS:
					assert_false(grounder.get(field) is Object, "serialized config contains no object references")
				var packed := PackedScene.new()
				assert_eq(packed.pack(scene), OK, "pack actual setup helper/bundle")
				var clone := packed.instantiate()
				var saved := clone.get_node_or_null(scene.get_path_to(grounder)) as Grounding
				assert_true(saved != null, "packed setup retains grounder")
				if saved != null:
					for field in Grounding.CONFIG_FIELDS: assert_eq(saved.get(field), grounder.get(field), "serialized grounding "+field)
					assert_true(saved.active, "serialized helper active")
					assert_eq(saved.owner, clone, "serialized scene owner")
					assert_eq(saved.get_node_or_null(saved.player_path), clone.get_node(scene.get_path_to(player)), "serialized relative Player binding")
					assert_eq(saved.get_node_or_null(saved.tree_path), clone.get_node(scene.get_path_to(grounder.get_node(grounder.tree_path))), "serialized relative Tree binding")
				clone.free()
			assert_gt(float(setup.data.speed_values.run), float(setup.data.speed_values.walk), "solved blend order")
			assert_false(setup.data.turn_wired, "turn remains unwired")
			assert_false(setup.data.actor_yaw_extraction, "translation extraction only")
			assert_eq(float(setup.data.clips.turn_left.capture_duration), 1.4, "180 automatic staging")
			for pair in [["idle", "idle_cycle"], ["walk", "walk_cycle"], ["run", "run_cycle"], ["jump", "jump"], ["turn_left", "turn_cycle"]]:
				var reference := {"op": pair[1], "player_path": args.player_path, "skeleton_path": args.skeleton_path, "style": style, "animation_name": "reference_" + pair[0], "root_motion": pair[0] in ["walk", "run", "jump"]}
				if pair[0] == "jump": reference.duration = 1.2
				if pair[0] == "turn_left":
					reference.angle = 180.0
					reference.steps = 2
				assert_true(handler.run(reference, null).has("data"), "dedicated " + pair[0])
				_same(player, pair[0], reference.animation_name)
			# Invalid setup controls refuse before changing library/bindings/tree.
			var binding := player.root_motion_track
			var names := player.get_animation_list()
			var child_count := body.get_child_count()
			for invalid in [{"run_speed": "fast"}, {"run_duration": 0.0}, {"turn_duration": 0.2}, {"angle": 721.0}, {"run_speed": 0.001}]:
				var refused := args.duplicate(true)
				refused.merge(invalid, true)
				assert_true(handler.run(refused, null).has("error"), "setup refuses " + str(invalid))
				assert_eq(player.get_animation_list(), names, "refusal library unchanged")
				assert_eq(player.root_motion_track, binding, "refusal extraction unchanged")
				assert_eq(body.get_child_count(), child_count, "refusal tree unchanged")
			var explicit := args.duplicate(true)
			explicit.merge({"run_speed": setup.data.speed_values.run, "run_duration": setup.data.clips.run.capture_duration, "turn_duration": 1.8, "jump_duration": 1.6, "height": 0.1, "crouch": 0.08, "distance": 0.2}, true)
			var made := handler.run(explicit, null)
			assert_true(made.has("data"), "explicit setup values")
			if made.has("data"):
				assert_eq(Codec.resolve_scene_path(str(made.data.grounding_path), scene), grounder, "overwrite reuses owned grounder")
				assert_eq(float(made.data.clips.run.capture_duration), float(explicit.run_duration), "explicit run duration")
				assert_eq(float(made.data.clips.turn_left.capture_duration), 1.8, "explicit turn duration")
				assert_eq(float(made.data.clips.jump.capture_duration), 1.6, "explicit jump duration")
				var reference := {"op": "jump", "player_path": args.player_path, "skeleton_path": args.skeleton_path, "style": style, "animation_name": "explicit_reference_jump", "root_motion": true, "duration": 1.6, "height": 0.1, "crouch": 0.08, "distance": 0.2}
				assert_true(handler.run(reference, null).has("data"), "explicit jump reference")
				_same(player, "jump", "explicit_reference_jump")
		body.get_parent().remove_child(body)
		body.free()
func test_setup_forward_jump_in_place_refuses_atomically() -> void:
	var scene := EditorInterface.get_edited_scene_root()
	var body := (load(FIXTURES[2]) as PackedScene).instantiate()
	scene.add_child(body)
	_assign(body,scene)
	var player := _find(body,"AnimationPlayer") as AnimationPlayer
	var skeleton := _find(body,"Skeleton3D") as Skeleton3D
	var history := Context.undo_redo.get_history_undo_redo(Context.undo_redo.get_object_history_id(body))
	var version := history.get_version()
	var names := player.get_animation_list()
	var binding := player.root_motion_track
	var pose := skeleton.get_bone_pose_rotation(1)
	var children := body.get_child_count()
	var result := handler.run({"op":"character_setup","player_path":Codec.from_node(player,scene),"skeleton_path":Codec.from_node(skeleton,scene),"include_jump":true,"root_motion":false,"distance":0.5},null)
	assert_true(result.has("error") and result.error.code=="OPERATION_UNAVAILABLE","unsupported in-place setup forward jump typed refusal")
	assert_eq(history.get_version(),version,"refusal creates no history")
	assert_eq(player.get_animation_list(),names,"refusal preserves clips")
	assert_eq(player.root_motion_track,binding,"refusal preserves extraction")
	assert_eq(skeleton.get_bone_pose_rotation(1),pose,"refusal preserves pose")
	assert_eq(body.get_child_count(),children,"refusal creates no tree")
	body.get_parent().remove_child(body)
	body.free()
func test_public_setup_saved_clip_witness() -> void:
	# The public client writes setup and reference clips, then installs this
	# marker. This branch only inspects the actual public outputs.
	var scene := EditorInterface.get_edited_scene_root()
	var marker := scene.get_node_or_null("PublicSetupIntegration")
	if marker == null:
		skip("public setup witness is installed by the external public-route client")
		return
	var player := Codec.resolve_scene_path(str(marker.get_meta("player_path")), scene) as AnimationPlayer
	assert_true(player != null, "public player")
	if player == null: return
	for pair in marker.get_meta("clip_pairs", []): _same(player, str(pair[0]), str(pair[1]))
func _assign(node: Node, owner_node: Node) -> void:
	node.owner = owner_node
	# Retained scene instances own their inherited descendants. Re-owning those
	# descendants to the edited root would save new typed nodes over base nodes.
	if not node.scene_file_path.is_empty(): return
	for child in node.get_children(): _assign(child, owner_node)
func _find(node: Node, type: String) -> Node:
	if node.is_class(type): return node
	for child in node.get_children():
		var found := _find(child, type)
		if found != null: return found
	return null

func test_setup_grounding_conflicts_and_dry_are_atomic() -> void:
	var scene := EditorInterface.get_edited_scene_root()
	var body := (load(FIXTURES[2]) as PackedScene).instantiate()
	scene.add_child(body)
	_assign(body,scene)
	var player := _find(body,"AnimationPlayer") as AnimationPlayer
	var rig := _find(body,"Skeleton3D") as Skeleton3D
	var args := {"op":"character_setup","player_path":Codec.from_node(player,scene),"skeleton_path":Codec.from_node(rig,scene)}
	var names := player.get_animation_list()
	var count := rig.get_child_count()
	var history := Context.undo_redo.get_history_undo_redo(Context.undo_redo.get_object_history_id(body))
	var version := history.get_version()
	var dry := args.duplicate(true);dry.dry_run=true
	assert_true(handler.run(dry,null).has("data"),"grounding dry configuration succeeds")
	assert_eq(rig.get_child_count(),count,"dry adds no helper")
	assert_eq(player.get_animation_list(),names,"dry writes no clips")
	assert_eq(history.get_version(),version,"dry creates no history")
	var foreign := SkeletonModifier3D.new();rig.add_child(foreign);foreign.active=true
	var refusal := handler.run(args,null)
	assert_true(refusal.has("error") and refusal.error.code=="OPERATION_UNAVAILABLE","foreign active modifier typed refusal")
	assert_eq(history.get_version(),version,"foreign conflict creates no history")
	assert_eq(player.get_animation_list(),names,"foreign conflict writes no clips")
	assert_true(foreign.active,"foreign writer is never silently disabled")
	foreign.free()
	var occupied := Node.new();occupied.name="SetupGrounding";rig.add_child(occupied)
	refusal=handler.run(args,null)
	assert_true(refusal.has("error") and refusal.error.code=="OPERATION_UNAVAILABLE","foreign name typed refusal")
	assert_eq(history.get_version(),version,"name conflict creates no history")
	assert_eq(player.get_animation_list(),names,"name conflict writes no clips")
	occupied.free()
	var tree_collision := Node.new();tree_collision.name="AnimationTree";player.get_parent().add_child(tree_collision)
	refusal=handler.run(args,null)
	assert_true(refusal.has("error") and refusal.error.code=="OPERATION_UNAVAILABLE","occupied Tree name typed refusal")
	assert_eq(history.get_version(),version,"Tree name conflict creates no history")
	assert_eq(player.get_animation_list(),names,"Tree name conflict writes no clips")
	assert_eq(rig.get_child_count(),count,"Tree name conflict leaves no grounder")
	tree_collision.free()
	var made := handler.run(args,null)
	assert_true(made.has("data"),"uncontested setup succeeds")
	if made.has("data"):
		version=history.get_version();names=player.get_animation_list()
		var duplicate := Grounding.new();rig.add_child(duplicate)
		refusal=handler.run(args,null)
		assert_true(refusal.has("error") and refusal.error.code=="OPERATION_UNAVAILABLE","duplicate owner typed refusal")
		assert_eq(history.get_version(),version,"duplicate creates no history")
		assert_eq(player.get_animation_list(),names,"duplicate writes no clips")
		duplicate.free()
	body.free()

func test_setup_custom_animation_root_and_remote_tree_history_serialization() -> void:
	_engine_scope_start = _logger.errors.size()
	var scene := EditorInterface.get_edited_scene_root()
	var body := (load(FIXTURES[2]) as PackedScene).instantiate()
	track(body)
	body.name="NestedRootSetup"
	# This regression deliberately reparents a Player; use a local disposable
	# tree instead of trying to reparent an inherited scene-instance node.
	body.scene_file_path=""
	scene.add_child(body);_assign(body,scene)
	var player := _find(body,"AnimationPlayer") as AnimationPlayer
	var rig := _find(body,"Skeleton3D") as Skeleton3D
	var drivers := Node.new();drivers.name="Drivers";body.add_child(drivers);drivers.owner=scene
	player.reparent(drivers);player.root_node=NodePath("../..")
	var hub := Node.new();track(hub);hub.name="RemoteSetupTree";scene.add_child(hub);hub.owner=scene
	var tree := AnimationTree.new();tree.name="CustomTree";tree.active=false;hub.add_child(tree);tree.owner=scene
	var prior_root := tree.root_node
	var prior_player := tree.anim_player
	var prior_names := player.get_animation_list()
	var args := {"op":"character_setup","player_path":Codec.from_node(player,scene),"skeleton_path":Codec.from_node(rig,scene),"tree_path":Codec.from_node(tree,scene)}
	var dry := args.duplicate(true);dry.dry_run=true
	assert_true(handler.run(dry,null).has("data"),"remote Tree custom animation root dry preflight")
	assert_eq(tree.root_node,prior_root,"dry preserves remote root_node")
	assert_eq(player.get_animation_list(),prior_names,"dry preserves remote clip library")
	var made := handler.run(args,null)
	assert_true(made.has("data"),"remote Tree with custom Player root builds: "+str(made))
	if made.has("data"):
		var grounder := Codec.resolve_scene_path(str(made.data.grounding_path),scene) as Grounding
		assert_eq(tree.get_node_or_null(tree.root_node),body,"Tree root_node resolves actual custom animation root")
		assert_eq(tree.get_node_or_null(tree.anim_player),player,"remote Tree binds nested Player")
		assert_eq(grounder.validate_configuration(),"","remote helper is usable")
		var grounder_path := scene.get_path_to(grounder)
		var wanted_root := tree.root_node
		assert_true(editor_undo(Context.undo_redo),"remote bundle single Undo")
		assert_eq(tree.root_node,prior_root,"Undo restores caller Tree root_node")
		assert_eq(tree.anim_player,prior_player,"Undo restores caller Player binding")
		assert_eq(player.get_animation_list(),prior_names,"Undo restores original clip set")
		assert_true(scene.get_node_or_null(grounder_path)==null,"Undo removes remote helper")
		assert_true(editor_redo(Context.undo_redo),"remote bundle single Redo")
		assert_eq(tree.root_node,wanted_root,"Redo restores exact remote root_node")
		grounder=scene.get_node(grounder_path) as Grounding
		assert_eq(grounder.validate_configuration(),"","Redo restores working helper paths")
		var packed := PackedScene.new();assert_eq(packed.pack(scene),OK,"pack remote saved bundle")
		var saved_path := "user://setup_remote_tree_history_"+str(Time.get_ticks_usec())+".tscn"
		assert_eq(ResourceSaver.save(packed,saved_path),OK,"save remote bundle to unique disposable scene")
		var saved_scene := ResourceLoader.load(saved_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var reopened := saved_scene.instantiate()
		track(reopened)
		var saved_tree := reopened.get_node(scene.get_path_to(tree)) as AnimationTree
		var saved_player := reopened.get_node(scene.get_path_to(player)) as AnimationPlayer
		var saved_grounder := reopened.get_node(grounder_path) as Grounding
		var saved_body := reopened.get_node(scene.get_path_to(body))
		assert_true(saved_body.get_node_or_null("AnimationPlayer")==null,"reopen does not resurrect inherited Player at its old slot")
		assert_eq(saved_body.find_children("*","AnimationPlayer",true,false).size(),1,"reopen contains exactly one intended nested Player")
		assert_eq(saved_tree.get_node_or_null(saved_tree.root_node),saved_player.get_node_or_null(saved_player.root_node),"saved/reinstantiated animation roots agree")
		assert_eq(saved_grounder.get_node_or_null(saved_grounder.tree_path),saved_tree,"saved remote helper Tree path")
		assert_eq(saved_grounder.get_node_or_null(saved_grounder.player_path),saved_player,"saved nested helper Player path")
		reopened.free()
	var second := (load(FIXTURES[2]) as PackedScene).instantiate()
	track(second)
	second.name="DetachedRemoteSetup";second.scene_file_path=""
	scene.add_child(second);_assign(second,scene)
	var second_player := _find(second,"AnimationPlayer") as AnimationPlayer
	var second_rig := _find(second,"Skeleton3D") as Skeleton3D
	var second_drivers := Node.new();second.add_child(second_drivers);second_drivers.owner=scene
	second_player.reparent(second_drivers);second_player.root_node=NodePath("../..")
	var new_args := {"op":"character_setup","player_path":Codec.from_node(second_player,scene),"skeleton_path":Codec.from_node(second_rig,scene),"tree_path":Codec.from_node(hub,scene)+"/FreshTree"}
	var new_dry := new_args.duplicate(true);new_dry.dry_run=true
	assert_true(handler.run(new_dry,null).has("data"),"detached remote Tree preflight resolves actual animation root")
	assert_true(hub.get_node_or_null("FreshTree")==null,"detached dry creates no Tree")
	var fresh := handler.run(new_args,null)
	assert_true(fresh.has("data"),"detached remote Tree commit succeeds: "+str(fresh))
	if fresh.has("data"):
		var fresh_tree := hub.get_node("FreshTree") as AnimationTree
		assert_eq(fresh_tree.get_node_or_null(fresh_tree.root_node),second,"new remote Tree has exact custom animation root")
		var fresh_grounder := Codec.resolve_scene_path(str(fresh.data.grounding_path),scene) as Grounding
		assert_eq(fresh_grounder.validate_configuration(),"","new remote helper paths usable")
	hub.free();body.free();second.free()

func test_setup_internal_modifier_writers_refuse_dry_write_and_runtime() -> void:
	var scene := EditorInterface.get_edited_scene_root()
	var body := (load(FIXTURES[2]) as PackedScene).instantiate()
	body.name="InternalWriterSetup";scene.add_child(body);_assign(body,scene)
	var player := _find(body,"AnimationPlayer") as AnimationPlayer
	var rig := _find(body,"Skeleton3D") as Skeleton3D
	var args := {"op":"character_setup","player_path":Codec.from_node(player,scene),"skeleton_path":Codec.from_node(rig,scene)}
	var simulator := PhysicalBoneSimulator3D.new()
	rig.add_child(simulator,false,Node.INTERNAL_MODE_BACK);simulator.active=true
	assert_true(Grounding.is_inert_internal_simulator(simulator),"exact inert internal empty simulator exemption")
	var dry := args.duplicate(true);dry.dry_run=true
	var history := Context.undo_redo.get_history_undo_redo(Context.undo_redo.get_object_history_id(body))
	var version := history.get_version()
	var names := player.get_animation_list()
	var binding := player.root_motion_track
	var pose := rig.get_bone_pose_rotation(1)
	var rest := rig.get_bone_rest(1)
	assert_true(handler.run(dry,null).has("data"),"inert internal simulator admits dry setup")
	assert_eq(history.get_version(),version,"inert dry remains mutation free")
	for mode in ["nonempty","simulating"]:
		var sentinel: Node = null
		if mode=="nonempty":
			sentinel=Node.new();simulator.add_child(sentinel)
		else:
			simulator.physical_bones_start_simulation()
			assert_true(simulator.is_simulating_physics(),"empty simulator running-state boundary is real")
		assert_false(Grounding.is_inert_internal_simulator(simulator),"potential writer is never exempt: "+mode)
		var children := rig.get_child_count(true)
		for request in [dry,args]:
			var refusal := handler.run(request,null)
			assert_true(refusal.has("error") and refusal.error.code=="OPERATION_UNAVAILABLE","internal "+mode+" typed dry/write refusal")
			assert_eq(history.get_version(),version,"internal refusal no Undo action")
			assert_eq(player.get_animation_list(),names,"internal refusal preserves library")
			assert_eq(player.root_motion_track,binding,"internal refusal preserves extraction")
			assert_eq(rig.get_bone_pose_rotation(1),pose,"internal refusal preserves bone pose")
			assert_eq(rig.get_bone_rest(1),rest,"internal refusal preserves rest")
			assert_eq(rig.get_child_count(true),children,"internal refusal adds no helper")
			assert_true(simulator.active,"internal writer never silently disabled")
		if sentinel!=null: sentinel.free()
		simulator.physical_bones_stop_simulation()
	var made := handler.run(args,null)
	assert_true(made.has("data"),"inert empty internal node permits actual setup")
	if made.has("data"):
		var grounder := Codec.resolve_scene_path(str(made.data.grounding_path),scene) as Grounding
		assert_eq(grounder.validate_configuration(),"","runtime admits exact inert internal node")
		var sentinel := Node.new();simulator.add_child(sentinel)
		assert_true(grounder.validate_configuration().contains("Foreign active bone modifier"),"runtime refuses internal nonempty potential writer")
		sentinel.free();simulator.physical_bones_start_simulation()
		assert_true(grounder.validate_configuration().contains("Foreign active bone modifier"),"runtime refuses internal running simulator")
		simulator.physical_bones_stop_simulation()
		assert_eq(grounder.validate_configuration(),"","runtime ownership recovers after explicit stop")
	body.free()
