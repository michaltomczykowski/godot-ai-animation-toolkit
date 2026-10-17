@tool
extends RefCounted

## Root travel has one owner. Integrate native extraction on the private owner
## before world-dependent modifiers, then encode that trajectory independently
## of the selected skeleton's final bone poses.
const Errors := preload("res://addons/godot_ai_animation/utils/error_codes.gd")
var mode := "preserve"
var source_local := false
var owner: Node3D
var initial: Transform3D
var rotation: Quaternion
var scale_accumulator := Vector3.ONE
var motion_track: NodePath

func configure(mixer: AnimationMixer, player: AnimationPlayer, target: Node3D, animation: String, requested_mode: String) -> Dictionary:
	mode = requested_mode
	source_local = mixer.root_motion_local
	motion_track = mixer.root_motion_track
	var root := mixer.get_node_or_null(mixer.root_node)
	if root == null: return _error("source mixer root is unresolved")
	var track_node := root.get_node_or_null(NodePath(motion_track.get_concatenated_names()))
	if not track_node is Node3D: return _error("root-motion track has no Node3D target")
	if track_node is Skeleton3D:
		if motion_track.get_subname_count() != 1 or track_node.find_bone(motion_track.get_subname(0)) < 0:
			return _error("root-motion track must name an existing bone")
	var found := false
	for name in player.get_animation_list():
		if not animation.is_empty() and str(name) != animation: continue
		var clip := player.get_animation(name)
		for i in clip.get_track_count():
			if not clip.track_is_enabled(i): continue
			var path := clip.track_get_path(i)
			var type := clip.track_get_type(i)
			if path == motion_track and type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]: found = true
			if target != null:
				var destination := root.get_node_or_null(NodePath(path.get_concatenated_names()))
				if destination == target and path != motion_track and (type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D] or type == Animation.TYPE_VALUE and path.get_concatenated_subnames() in ["transform", "position", "rotation", "rotation_degrees", "quaternion", "basis", "scale"]):
					return _error("animation also writes the movement owner: " + str(path))
	if not found: return _error("root-motion track does not match an enabled native transform track")
	if mode != "pose_only":
		if target == null: return _error("preserve/apply extraction requires root_motion_target_path")
		if not _representable(target.transform) or not _representable(target.global_transform): return _error("movement owner has nonfinite, mirrored or sheared transforms")
	return {"ok": true}

func begin(copy: Node3D) -> void:
	owner = copy
	if owner == null: return
	initial = owner.transform
	rotation = owner.quaternion
	scale_accumulator = Vector3.ONE

static func capture(mixer: AnimationMixer) -> Dictionary:
	return {"position": mixer.get_root_motion_position(), "rotation": mixer.get_root_motion_rotation(),
		"scale": mixer.get_root_motion_scale(), "accumulator": mixer.get_root_motion_rotation_accumulator()}

func consume(delta: Dictionary, time: float) -> Dictionary:
	if mode == "pose_only": return {"ok": true}
	if owner == null: return _error("private movement owner is missing at t=%.6f" % time)
	for key in delta:
		if not delta[key].is_finite(): return _error("nonfinite extraction '%s' at t=%.6f" % [key, time])
	rotation = (rotation * (delta.rotation as Quaternion)).normalized()
	# This is Godot's documented local/non-local extraction convention, in the
	# owner's parent frame. Its parent transform supplies world conversion.
	var frame: Quaternion = rotation if source_local else (delta.accumulator as Quaternion).inverse() * rotation
	var position := owner.position + frame * (delta.position as Vector3)
	scale_accumulator += delta.scale
	var scale := initial.basis.get_scale() * scale_accumulator
	owner.transform = Transform3D(Basis(rotation).scaled_local(scale), position)
	if not _representable(owner.transform) or not _representable(owner.global_transform): return _error("unrepresentable movement at t=%.6f" % time)
	return {"ok": true}

func sample() -> Dictionary:
	if owner == null or mode == "pose_only": return {}
	var value := owner.transform
	if mode == "preserve":
		var inverse := initial.basis.get_rotation_quaternion().inverse()
		return {"position": inverse * (value.origin - initial.origin),
			"rotation": (inverse * value.basis.get_rotation_quaternion()).normalized(),
			"scale": value.basis.get_scale() / initial.basis.get_scale()}
	return {"position": value.origin, "rotation": value.basis.get_rotation_quaternion(), "scale": value.basis.get_scale()}

static func _representable(value: Transform3D) -> bool:
	if not value.is_finite() or value.basis.determinant() <= 0: return false
	var basis := value.basis
	if minf(basis.x.length(), minf(basis.y.length(), basis.z.length())) < 0.000001: return false
	return absf(basis.x.normalized().dot(basis.y.normalized())) < 0.0001 and absf(basis.x.normalized().dot(basis.z.normalized())) < 0.0001 and absf(basis.y.normalized().dot(basis.z.normalized())) < 0.0001

func _error(message: String) -> Dictionary:
	return Errors.make(Errors.OPERATION_UNAVAILABLE, "Root-motion bake: " + message)
