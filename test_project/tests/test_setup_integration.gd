@tool
extends McpTestSuite
const Motion := preload("res://addons/godot_ai_animation/handlers/motion.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const Codec := preload("res://addons/godot_ai_animation/utils/value_codec.gd")
const Digest := preload("res://tests/golden_digest.gd")
const FIXTURES := ["res://models/human_dummy/HumanCharacterDummy_F.fbx", "res://models/x_bot/X Bot.fbx", "res://repair_synthetic_short.tscn", "res://repair_synthetic_zup_tall.tscn"]
var handler: Motion
func suite_name() -> String: return "setup_integration"
func suite_setup(ctx: Dictionary) -> void:
	Context.undo_redo = ctx.get("undo_redo")
	handler = Motion.new()
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
				assert_eq(float(made.data.clips.run.capture_duration), float(explicit.run_duration), "explicit run duration")
				assert_eq(float(made.data.clips.turn_left.capture_duration), 1.8, "explicit turn duration")
				assert_eq(float(made.data.clips.jump.capture_duration), 1.6, "explicit jump duration")
				var reference := {"op": "jump", "player_path": args.player_path, "skeleton_path": args.skeleton_path, "style": style, "animation_name": "explicit_reference_jump", "root_motion": true, "duration": 1.6, "height": 0.1, "crouch": 0.08, "distance": 0.2}
				assert_true(handler.run(reference, null).has("data"), "explicit jump reference")
				_same(player, "jump", "explicit_reference_jump")
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
	for child in node.get_children(): _assign(child, owner_node)
func _find(node: Node, type: String) -> Node:
	if node.is_class(type): return node
	for child in node.get_children():
		var found := _find(child, type)
		if found != null: return found
	return null
