extends "res://tools/check_setup_tree_quality.gd"
## Deliberate corruption of disposable native instances, never saved scenes.
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
