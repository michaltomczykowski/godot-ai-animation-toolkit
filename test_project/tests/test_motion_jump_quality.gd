@tool
extends McpTestSuite
## Native whole-bone velocity regression. No golden recording or pose writes.
const Motion := preload("res://addons/godot_ai_animation/handlers/motion.gd")
const Context := preload("res://addons/godot_ai_animation/utils/tool_context.gd")
const ASSETS := ["res://models/human_dummy/HumanCharacterDummy_F.fbx", "res://repair_synthetic_short.tscn", "res://repair_synthetic_zup_tall.tscn"]
const STYLES := ["responsive","grounded","relaxed","heavy","sneaky"]
const FPS := 120
const MAX_LEGS_PER_SECOND := 10.0
var handler

func suite_name() -> String: return "animation_motion_jump_quality"
func suite_setup(ctx: Dictionary) -> void:
	Context.undo_redo = ctx.get("undo_redo")
	handler = Motion.new()

func test_default_jump_whole_bone_velocity_in_native_player_and_tree() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	assert_true(scene_root != null, "An edited test scene is required")
	if scene_root == null: return
	var runs := 0
	for asset: String in ASSETS:
		assert_true(ResourceLoader.exists(asset), "Required public fixture exists: " + asset)
		if not ResourceLoader.exists(asset): return
		for style: String in STYLES:
			for extracted in [false,true]:
				for mode: String in ["player","tree"]:
					var instance := (load(asset) as PackedScene).instantiate()
					instance.name = "JumpVelocityFixture"
					for mixer in instance.find_children("*","AnimationMixer",true,false):
						mixer.active = false
						mixer.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
					for modifier in instance.find_children("*","SkeletonModifier3D",true,false): modifier.active = false
					scene_root.add_child(instance)
					_owners(instance,scene_root)
					var rig := _find(instance,"Skeleton3D") as Skeleton3D
					var player := _find(instance,"AnimationPlayer") as AnimationPlayer
					var label := "%s/%s/%s/%s" % [asset.get_file(),style,"extracted" if extracted else "skeletal",mode]
					assert_true(rig != null and player != null,label+": skeleton/player exist")
					if rig == null or player == null:
						instance.free()
						continue
					# Height, timing, density and body controls remain defaults. Forward
					# distance alone exercises the two distinct translation owners.
					var params := {"op":"jump","animation_name":"ci_jump_velocity","distance":0.5,"root_motion":extracted,
						"player_path":"/"+scene_root.name+"/"+str(scene_root.get_path_to(player)),
						"skeleton_path":"/"+scene_root.name+"/"+str(scene_root.get_path_to(rig))}
					if style != "responsive": params.style = style
					var result: Dictionary = handler.run(params,null)
					assert_true(result.has("data"),label+": default jump builds: "+str(result.get("error",{})))
					if result.has("data"):
						var measured := measure(rig,player,"ci_jump_velocity",result.data.roles,mode)
						assert_true(measured.finite,label+": all native transforms remain finite")
						assert_true(measured.leg_length_m > 0.0,label+": measured world leg length")
						assert_true(measured.max_bone_speed_legs_per_s <= MAX_LEGS_PER_SECOND,label+": whole-bone speed %.6f > %.1f L/s; %s" % [measured.max_bone_speed_legs_per_s,MAX_LEGS_PER_SECOND,str(measured.worst)])
						assert_true(measured.motion_legs > 0.05,label+": jump is not inert")
						runs += 1
					instance.free()
	assert_eq(runs,ASSETS.size()*STYLES.size()*2*2,"All public rigs/styles/owners/mixers actually played")

static func measure(rig: Skeleton3D, player: AnimationPlayer, name: String, roles: Dictionary, mode: String) -> Dictionary:
	var leg := 0.0
	for side in ["l","r"]:
		var hip := (rig.global_transform*rig.get_bone_global_rest(rig.find_bone(roles["thigh_"+side]))).origin
		var knee := (rig.global_transform*rig.get_bone_global_rest(rig.find_bone(roles["shin_"+side]))).origin
		var foot := (rig.global_transform*rig.get_bone_global_rest(rig.find_bone(roles["foot_"+side]))).origin
		leg += hip.distance_to(knee)+knee.distance_to(foot)
	leg *= 0.5
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.active = true
	player.play(name,0.0,1.0)
	player.advance(0.0)
	var mixer: AnimationMixer = player
	var tree: AnimationTree
	if mode == "tree":
		player.active = false
		tree = AnimationTree.new()
		player.get_parent().add_child(tree)
		tree.anim_player = tree.get_path_to(player)
		tree.root_node = tree.get_path_to(player.get_node(player.root_node))
		tree.root_motion_track = player.root_motion_track
		tree.root_motion_local = player.root_motion_local
		tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var node := AnimationNodeAnimation.new()
		node.animation = name
		tree.tree_root = node
		tree.active = true
		tree.advance(0.0)
		mixer = tree
	var root_node := player.get_node(player.root_node)
	var owner := root_node.get_node_or_null(NodePath(player.root_motion_track.get_concatenated_names())) as Node3D if not player.root_motion_track.is_empty() else root_node as Node3D
	var previous: Array[Vector3] = []
	for i in rig.get_bone_count(): previous.append((rig.global_transform*rig.get_bone_global_pose(i)).origin)
	var initial := previous.duplicate()
	var finite := true
	var speed := 0.0
	var motion := 0.0
	var worst := {}
	for frame in range(1,ceili((player.get_animation(name).length+0.25)*FPS)+1):
		mixer.advance(1.0/FPS)
		# Position-only carrier deltas already use the owner's parent frame.
		if owner != null: owner.position += mixer.get_root_motion_position()
		for i in rig.get_bone_count():
			var pose := rig.global_transform*rig.get_bone_global_pose(i)
			finite = finite and pose.is_finite()
			var step := pose.origin.distance_to(previous[i])
			var normalized := step*FPS/maxf(leg,0.000001)
			if normalized > speed:
				speed = normalized
				worst = {"bone":rig.get_bone_name(i),"time":float(frame)/FPS,"step_m":step}
			motion = maxf(motion,pose.origin.distance_to(initial[i])/maxf(leg,0.000001))
			previous[i] = pose.origin
	if tree != null: tree.free()
	player.stop()
	player.active = false
	return {"finite":finite,"leg_length_m":leg,"max_bone_speed_legs_per_s":speed,"motion_legs":motion,"worst":worst}

static func _find(node: Node, type: String) -> Node:
	if node.is_class(type): return node
	for child in node.get_children():
		var found := _find(child,type)
		if found != null: return found
	return null
static func _owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_owners(child,owner)
