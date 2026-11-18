@tool
extends McpTestSuite
const Graph := preload("res://tests/test_rig_bake_graph.gd")
const Saved := preload("res://tests/bake_saved_matrix.gd")
var helper := Graph.new()
func suite_name() -> String: return "rig_bake_storage"
func suite_setup(ctx: Dictionary) -> void: helper.suite_setup(ctx)
func suite_teardown() -> void: helper.suite_teardown()
func _case(layout: String, fps: int) -> void:
	var label := "storage_%s_%d" % [layout, fps]
	var f := helper._fixture("BakeStorage", "state")
	var scene := EditorInterface.get_edited_scene_root()
	var peer: Node
	var source_path := "user://bake_storage_source_%s.tscn" % label
	var source_bytes := PackedByteArray()
	if layout in ["locked", "editable"]:
		for child in f.root.get_children(): helper.helper._own(child, f.root)
		var packed := PackedScene.new()
		assert_eq(packed.pack(f.root), OK, label + " source pack")
		assert_eq(ResourceSaver.save(packed, source_path), OK, label + " source save")
		source_bytes = FileAccess.get_file_as_bytes(source_path)
		f.root.free()
		packed = ResourceLoader.load(source_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		f.root = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		scene.add_child(f.root)
		f.root.owner = scene
		f.player = f.root.get_node("AnimationPlayer")
		f.skeleton = f.root.get_node("Skeleton")
		f.tree = f.root.get_node("Tree")
		scene.set_editable_instance(f.root, layout == "editable")
		peer = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		peer.name = "BakeStoragePeer"
		scene.add_child(peer)
		peer.owner = scene
	var output: AnimationPlayer
	if layout in ["missing_library", "local_library", "overwrite"]:
		output = AnimationPlayer.new()
		output.name = "ExplicitBake"
		output.active = false
		output.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		f.root.add_child(output)
		output.owner = scene
		if layout != "missing_library":
			var library := AnimationLibrary.new()
			var old := Animation.new()
			old.length = 0.7
			var track := old.add_track(Animation.TYPE_ROTATION_3D)
			old.track_set_path(track, "Skeleton:arm")
			old.track_insert_key(track, 0, Quaternion(Vector3.UP, 0.9))
			library.add_animation("unrelated", old)
			if layout == "overwrite": library.add_animation("baked", old)
			output.add_animation_library("", library)
	helper._begin(f)
	f.tree.advance(0.04)
	f.tree.get("parameters/playback").travel("Action")
	f.tree.advance(0.02)
	f.tree.get("parameters/playback").travel("Idle")
	var params := helper.helper._params(f).merged({"source_tree_path": str(f.tree.get_path()), "duration": 0.205, "fps": fps, "tree_starts": f.starts, "tree_events": f.events, "overwrite": layout == "overwrite"}, true)
	params.erase("source_animation")
	if output != null: params.output_player_path = str(output.get_path())
	var state := helper._public(f.tree)
	var library: AnimationLibrary = f.player.get_animation_library("")
	var peer_library: AnimationLibrary = peer.get_node("AnimationPlayer").get_animation_library("") if peer != null else null
	var editable := scene.is_editable_instance(f.root) if peer != null else false
	var version := helper.helper._history().get_version()
	var errors := helper.helper._logger.errors.size()
	var saved := Saved.begin(f, params, label)
	saved.undo_existing = layout == "overwrite"
	var dry := helper._call(params.merged({"dry_run": true}, true))
	assert_has_key(dry, "data", label + " dry")
	assert_eq(helper.helper._history().get_version(), version, label + " dry history")
	var result := helper._call(params)
	assert_has_key(result, "data", label + " write " + str(result.get("error", {})))
	if result.has("data"):
		output = scene.get_node(NodePath(str(result.data.player_path).trim_prefix("/Main/")))
		assert_eq(result.data.player_path, dry.data.player_path, label + " predictable destination")
		assert_eq(helper._public(f.tree), state, label + " untouched source graph")
		assert_eq(f.player.get_animation_library(""), library, label + " source library identity")
		assert_eq(helper.helper._history().get_version(), version + 1, label + " one action")
		Saved.state(saved, output, "do")
		assert_true(helper.helper._history().undo(), label + " Undo")
		Saved.state(saved, output, "undo")
		assert_eq(helper._public(f.tree), state, label + " Undo graph exact")
		if peer != null: assert_eq(scene.is_editable_instance(f.root), editable, label + " original instance permission")
		assert_true(helper.helper._history().redo(), label + " Redo")
		Saved.state(saved, output, "redo")
		Saved.finish(saved)
		assert_true(helper.helper._history().undo(), label + " final Undo")
	if peer != null:
		assert_eq(peer.get_node("AnimationPlayer").get_animation_library(""), peer_library, label + " peer library identity")
		assert_eq(FileAccess.get_file_as_bytes(source_path), source_bytes, label + " source bytes immutable")
		assert_false(peer.has_node("AnimationBakeOutput"), label + " peer has no generated node")
		peer.free()
	assert_eq(helper.helper._logger.errors.size(), errors, label + " zero engine errors")
	f.root.free()
func test_graph_output_storage() -> void:
	for layout in ["locked", "editable", "missing_library", "local_library", "overwrite"]:
		for fps in [30, 60, 120]: _case(layout, fps)
