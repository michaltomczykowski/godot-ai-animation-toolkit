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
		"positive": pass
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
