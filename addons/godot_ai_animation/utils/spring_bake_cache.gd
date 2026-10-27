@tool
extends RefCounted
## Godot4.7.2 ed1daf0bf defers global->joint cache propagation. Private
## synchronous bake copies cannot await that queue or mutate author nodes.
## Mirror _update_joints using public setters, retaining the authored mode.
## Call only inside a synchronous private evaluation, after mixer updates.
static func prime(spring:SpringBoneSimulator3D,initialize:bool=false)->String:
	for setting in spring.get_setting_count():
		var count:=spring.get_joint_count(setting)
		if count<1:return "spring joint chain is unavailable"
		if spring.is_config_individual(setting):
			for joint in count:
				for field in ["radius","stiffness","drag","gravity"]:
					if not is_finite(float(spring.call("get_joint_"+field,setting,joint))):return "nonfinite individual spring "+field
				if not spring.get_joint_gravity_direction(setting,joint).is_finite():return "nonfinite individual spring gravity direction"
				if initialize:spring.set_joint_rotation_axis(setting,joint,spring.get_joint_rotation_axis(setting,joint))
			continue
		var values:Array=[]
		var direction:=spring.get_gravity_direction(setting)
		var axis:=spring.get_rotation_axis(setting)
		var axis_vector:=spring.get_rotation_axis_vector(setting)
		if not direction.is_finite() or direction.is_zero_approx():return "invalid spring gravity direction"
		if axis==SkeletonModifier3D.ROTATION_AXIS_CUSTOM and (not axis_vector.is_finite() or axis_vector.is_zero_approx()):return "invalid spring custom rotation axis"
		for joint in count:
			# Engine uses float unit/offset, even with GDScript double scalars.
			var offset:=0.0
			if count>1:
				var unit:float=PackedFloat32Array([1.0/float(count-1)])[0]
				offset=PackedFloat32Array([float(joint)*unit])[0]
			var fields:={}
			for field in ["radius","stiffness","drag","gravity"]:
				var value:float=spring.call("get_"+field,setting)
				var curve:Curve=spring.call("get_"+field+"_damping_curve",setting)
				if curve!=null:
					if count==1:return "single-joint spring damping curve has undefined native normalized offset"
					value*=curve.sample_baked(offset)
				value=PackedFloat32Array([value])[0]
				if not is_finite(value):return "nonfinite spring cache "+field
				fields[field]=value
			values.append(fields)
		# Setters reject global mode. Restore it before sampling so animation
		# can still write global settings. No queue flush occurs in this path.
		spring.set_individual_config(setting,true)
		for joint in count:
			for field in values[joint]:spring.call("set_joint_"+field,setting,joint,values[joint][field])
			spring.set_joint_gravity_direction(setting,joint,direction)
			# reset() defers marking simulation_dirty; this public setter marks
			# it immediately, even for unchanged ALL. Initialize once at open,
			# never each sample: that would discard the Verlet momentum.
			if initialize or spring.get_joint_rotation_axis(setting,joint)!=axis:spring.set_joint_rotation_axis(setting,joint,axis)
			if axis==SkeletonModifier3D.ROTATION_AXIS_CUSTOM and spring.get_joint_rotation_axis_vector(setting,joint)!=axis_vector:spring.set_joint_rotation_axis_vector(setting,joint,axis_vector)
		spring.set_individual_config(setting,false)
	return ""
