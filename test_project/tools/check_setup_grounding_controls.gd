extends "res://tools/check_setup_tree_quality.gd"
## Corrupt ONLY disposable in-memory instances after immutable scene validation.
## Run with a derived manifest whose rows declare grounding_control. Each play
## must fail the real checker (including exact gait endpoints), not merely differ.
class LateWriter extends SkeletonModifier3D:
	var bone := -1
	func _process_modification_with_delta(_dt: float) -> void:
		if bone>=0: get_skeleton().set_bone_pose_rotation(bone,Quaternion(Vector3.RIGHT,0.8))
func _load(row: Dictionary) -> Dictionary:
	var v := super._load(row)
	if v.has("error"): return v
	match str(row.get("grounding_control","positive")):
		"positive", "saved_same_rig_tree", "saved_unrelated_rig_tree", "saved_same_rig_autoplay", "internal_nonempty_simulator": pass
		"recover_residual":
			v.modifier.max_residual_m=1.0
			v.modifier.evaluation_residual_m=1.0
			v.modifier._fail("prior temporary configuration failure")
		"partial_influence": v.modifier.influence=0.5
		"disabled": v.modifier.active=false
		"missing":
			v.modifier.active=false
			v.rig.remove_child(v.modifier)
			v.orphan=v.modifier
		"wrong_path": v.modifier.tree_path=NodePath("../MissingSetupTree")
		"wrong_order":
			var late:=LateWriter.new()
			late.bone=int(v.indices.shin_l)
			v.rig.add_child(late)
		_:
			_free(v)
			return {"error":"Unknown declared grounding corruption"}
	return v
func _free(v: Dictionary) -> void:
	if v.has("orphan") and is_instance_valid(v.orphan): v.orphan.free()
	super._free(v)

func _prepare_admission_control(scene: Node, row: Dictionary, _rig: Skeleton3D, tree: AnimationTree, player: AnimationPlayer) -> void:
	var mode := str(row.get("grounding_control","positive"))
	if mode=="internal_nonempty_simulator":
		var simulator := PhysicalBoneSimulator3D.new()
		simulator.name="ForeignInternalSimulator"
		_rig.add_child(simulator,false,Node.INTERNAL_MODE_BACK)
		simulator.add_child(Node.new()) # Violates the exact empty-node exemption.
		simulator.active=true
		return
	if mode not in ["saved_same_rig_tree","saved_unrelated_rig_tree","saved_same_rig_autoplay"]: return
	var animation_root := player.get_node(player.root_node)
	if mode=="saved_same_rig_autoplay":
		player.autoplay="idle"
		player.active=true
		return
	var target: Node = animation_root
	var peer_player: AnimationPlayer = player
	if mode=="saved_unrelated_rig_tree":
		target=animation_root.duplicate()
		target.name="UnrelatedOwnershipRig"
		# The duplicate supplies the actual track-addressable rig and library,
		# but no copied graph/helper may become an additional writer.
		for node in target.find_children("*","AnimationMixer",true,false): node.active=false
		for node in target.find_children("*","SkeletonModifier3D",true,false): node.active=false
		if target is AnimationMixer: target.active=false
		scene.add_child(target)
		if animation_root==player or animation_root.is_ancestor_of(player):
			peer_player=target.get_node(animation_root.get_path_to(player)) as AnimationPlayer
		else:
			peer_player=player.duplicate() as AnimationPlayer
			target.add_child(peer_player)
		peer_player.active=false
		peer_player.autoplay=""
		peer_player.root_node=peer_player.get_path_to(target)
	var peer := AnimationTree.new()
	peer.name="SavedCompetingTree"
	scene.add_child(peer)
	peer.anim_player=peer.get_path_to(peer_player)
	peer.root_node=peer.get_path_to(target)
	peer.tree_root=tree.tree_root
	peer.root_motion_track=tree.root_motion_track
	peer.root_motion_local=tree.root_motion_local
	peer.active=true
