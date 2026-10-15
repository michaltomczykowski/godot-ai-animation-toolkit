extends RefCounted
## Saved graph control only. No animation generation or target pose writes.
static func load_case(row: Dictionary, root: Node) -> Dictionary:
	if FileAccess.get_sha256(row.scene) != row.scene_sha256: return {"error":"Saved scene hash mismatch"}
	var packed := ResourceLoader.load(row.scene, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null: return {"error":"Missing saved scene"}
	var scene := packed.instantiate()
	for node in scene.find_children("*", "AnimationMixer", true, false):
		node.active = false
		if node is AnimationPlayer: node.stop()
	root.add_child(scene)
	var tree := scene.get_node_or_null(row.tree) as AnimationTree
	var player := scene.get_node_or_null(row.player) as AnimationPlayer
	var target := scene.get_node_or_null(row.target) as Node2D
	if tree == null or player == null or target == null or tree.tree_root == null:
		scene.free()
		return {"error":"Missing saved tree/player/target/root"}
	if tree.get_node_or_null(tree.anim_player) != player:
		scene.free()
		return {"error":"Saved AnimationTree player binding mismatch"}
	var baseline := target.transform
	var view := {"scene":scene,"tree":tree,"player":player,"target":target,"row":row,
		"root_resource":tree.tree_root,"clips":clip_digest(player),"baseline":baseline}
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	var error := command(view, "neutral")
	if not error.is_empty():
		scene.free()
		return {"error":error}
	tree.advance(0.0)
	return view

static func clip_digest(player: AnimationPlayer) -> String:
	var clips: Array = []
	for name in player.get_animation_list():
		var clip := player.get_animation(name)
		var tracks: Array = []
		for t in clip.get_track_count():
			var keys: Array = []
			for k in clip.track_get_key_count(t): keys.append([clip.track_get_key_time(t,k),clip.track_get_key_value(t,k)])
			tracks.append([clip.track_get_path(t),clip.track_get_type(t),clip.track_get_interpolation_type(t),keys])
		clips.append([name,clip.length,clip.loop_mode,tracks])
	return var_to_str(clips).sha256_text()

static func command(v: Dictionary, action: String) -> String:
	var tree: AnimationTree = v.tree
	var op := str(v.row.operation)
	var neutral := action == "neutral"
	if action == "faster" and op not in ["blend_space","locomotion"]: return ""
	match op:
		"state_machine":
			if not tree.tree_root is AnimationNodeStateMachine: return "Expected saved state machine"
			var playback := tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
			if playback == null: return "Missing saved playback controller"
			if neutral: playback.stop()
			else:
				playback.start("idle")
				playback.travel("walk")
		"blend_space", "locomotion":
			if not tree.tree_root is AnimationNodeBlendSpace1D: return "Expected saved 1D blend space"
			tree.set("parameters/blend_position", 0.0 if neutral else (2.0 if action == "faster" else 1.0))
		"blend_tree":
			if not tree.tree_root is AnimationNodeBlendTree or not tree.tree_root.has_node("Blend2"): return "Expected saved Blend2"
			tree.set("parameters/Blend2/blend_amount", 0.0 if neutral else 1.0)
		"one_shot_layer":
			if not tree.tree_root is AnimationNodeBlendTree or not tree.tree_root.has_node("OneShot"): return "Expected saved OneShot"
			tree.set("parameters/OneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT if neutral else AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		"additive_lean":
			if not tree.tree_root is AnimationNodeBlendTree or not tree.tree_root.has_node("Add2"): return "Expected saved Add2"
			tree.set("parameters/Add2/add_amount", 0.0 if neutral else 1.0)
		"wire":
			if not tree.tree_root is AnimationNodeAnimation or tree.tree_root.animation != &"idle": return "Wire proof requires preserved idle root"
		_: return "Unsupported graph operation"
	return ""

static func ownership(v: Dictionary) -> bool:
	var active := 0
	for node in v.scene.find_children("*", "AnimationMixer", true, false):
		if node.active: active += 1
		if node is AnimationPlayer and node.is_playing(): return false
	return active == 1 and v.tree.active and not v.player.active and v.tree.tree_root == v.root_resource

static func sample(v: Dictionary, time: float) -> Dictionary:
	var state := ""
	if v.tree.tree_root is AnimationNodeStateMachine:
		state = str((v.tree.get("parameters/playback") as AnimationNodeStateMachinePlayback).get_current_node())
	return {"time_s":time,"position":[v.target.position.x,v.target.position.y],"rotation_rad":v.target.rotation,
		"state":state,"ownership":ownership(v)}

static func neutral_error(v: Dictionary) -> float:
	return maxf(v.target.transform.origin.distance_to(v.baseline.origin), absf(v.target.rotation - v.baseline.get_rotation()))
