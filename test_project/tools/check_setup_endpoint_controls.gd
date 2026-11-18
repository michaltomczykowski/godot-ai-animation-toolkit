extends "res://tools/check_setup_tree_quality.gd"
## Deliberate corruption of disposable native instances, never saved scenes.
func _load(row: Dictionary) -> Dictionary:
	var v := super._load(row)
	if v.has("error"): return v
	var mode := str(row.get("translation_control","positive"))
	if mode=="rotated_parent_positive" or mode=="post_consumer_parent_drift":
		var parent := Node3D.new()
		root.add_child(parent)
		if v.has("driver"): v.driver.reparent(parent,true)
		else: v.scene.reparent(parent,true)
		v.control_parent=parent
		if mode=="rotated_parent_positive":
			parent.transform=Transform3D(Basis(Vector3.UP,0.4),Vector3(2,1,3))
			v.up=(parent.basis*v.up).normalized()
			v.forward=(parent.basis*v.forward).normalized()
			v.ground=minf(_point(v,"foot_l",true).dot(v.up),_point(v,"foot_r",true).dot(v.up))
			v.initial_owner=v.owner.global_position
			v.initial_rotation=v.owner.global_basis.orthonormalized().get_rotation_quaternion()
		# Scratch placement is fixture preparation, before the physical clock.
		# Flush its native transform updates and discard the pre-placement capture.
		v.rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		v.control_preparation_signals=v.signals
		v.signals=0
		v.erase("captured")
	return v
func _free(v: Dictionary) -> void:
	var parent: Node3D = v.get("control_parent")
	super._free(v)
	if is_instance_valid(parent): parent.free()
func _prepare_translation_control(v: Dictionary, row: Dictionary) -> void:
	var offset: Vector3 = v.forward*0.0002
	match str(row.get("translation_control","positive")):
		"positive", "rotated_parent_positive": pass
		"post_consumer_owner_drift": v.owner.global_position+=offset
		"post_consumer_parent_drift":
			if v.owner.get_parent() is Node3D: v.owner.get_parent().global_position+=offset
			else: push_error("Parent drift control requires a Node3D parent")
		_: push_error("Unknown disposable translation corruption")
func _prepare_endpoint_control(v: Dictionary, row: Dictionary, reference: Dictionary) -> void:
	var offset: Vector3 = v.forward*0.0002
	match str(row.get("endpoint_control","positive")):
		"positive", "lost_displacement": pass
		"pelvis_residual":
			var bone := int(v.indices.hips)
			var parent := int(v.rig.get_bone_parent(bone))
			var parent_world: Basis = v.rig.global_basis*(v.captured[parent].basis if parent>=0 else Basis.IDENTITY)
			v.rig.set_bone_pose_position(bone,v.rig.get_bone_pose_position(bone)+parent_world.inverse()*offset)
			v.rig.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		"rig_drift": v.rig.global_position+=offset
		"ancestor_drift": v.scene.global_position+=offset
		"wrong_idle_clip":
			reference.player.play("walk",0.0)
			reference.player.advance(0.0)
		"wrong_idle_phase":
			reference.player.seek(fposmod(reference.player.current_animation_position+0.1,reference.player.get_animation("idle").length),true)
			reference.player.advance(0.0)
		_: push_error("Unknown disposable endpoint corruption")
