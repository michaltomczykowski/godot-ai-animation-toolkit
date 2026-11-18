extends SceneTree
## Rebuild the original, primitive-mesh showcase performer.

const OUT := "res://showcase_2_0/robot.tscn"
const PORCELAIN := Color("#dce9df")
const GRAPHITE := Color("#253638")
const MINT := Color("#9af1cb")
const GOLD := Color("#f7cb74")

var performer: Node3D
var skeleton: Skeleton3D
var materials := {}


func _initialize() -> void:
	_build.call_deferred()


func _build() -> void:
	performer = Node3D.new()
	performer.name = "Kite"
	root.add_child(performer)
	var robot := Node3D.new()
	_add(performer, robot, "Robot")
	skeleton = Skeleton3D.new()
	_add(robot, skeleton, "Skeleton3D")
	_add(performer, AnimationPlayer.new(), "AnimationPlayer")

	_bone("root", "", Vector3.ZERO)
	_bone("hips", "root", Vector3(0, 0.98, 0))
	_bone("spine", "hips", Vector3(0, 0.16, 0))
	_bone("chest", "spine", Vector3(0, 0.21, 0))
	_bone("neck", "chest", Vector3(0, 0.16, 0))
	_bone("head", "neck", Vector3(0, 0.13, 0))
	for side in ["L", "R"]:
		var sign_x := 1.0 if side == "L" else -1.0
		var suffix: String = "." + side
		_bone("thigh" + suffix, "hips", Vector3(0.124 * sign_x, -0.026, 0))
		_bone("shin" + suffix, "thigh" + suffix, Vector3(0, -0.43, 0.055))
		_bone("foot" + suffix, "shin" + suffix, Vector3(0, -0.43, -0.058))
		_bone("toe" + suffix, "foot" + suffix, Vector3(0, -0.05, 0.145))
		_bone("shoulder" + suffix, "chest", Vector3(0.195 * sign_x, 0.12, 0))
		_bone("upperArm" + suffix, "shoulder" + suffix, Vector3(0.105 * sign_x, -0.045, 0))
		_bone("forearm" + suffix, "upperArm" + suffix, Vector3(0.078 * sign_x, -0.246, 0.018))
		_bone("hand" + suffix, "forearm" + suffix, Vector3(0.035 * sign_x, -0.227, 0.045))
	_bone("aerial", "chest", Vector3(0, 0.17, -0.15))
	_bone("aerial_tip", "aerial", Vector3(0, 0.13, -0.1))
	_bone("aerial_end", "aerial_tip", Vector3(0, 0.10, -0.06))

	_shell("hips", "HipShell", Vector3(0, 0.02, 0), Vector3(0.33, 0.17, 0.25), GRAPHITE)
	_shell("spine", "SpineCoupler", Vector3(0, 0.06, 0), Vector3(0.225, 0.24, 0.19), GRAPHITE)
	_shell("chest", "TorsoShell", Vector3(0, 0.016, 0), Vector3(0.435, 0.30, 0.28), PORCELAIN)
	_box("chest", "StatusPanel", Vector3(0, 0.03, 0.129), Vector3(0.20, 0.083, 0.035), GRAPHITE)
	for column in 3:
		_box("chest", "StatusLight%d" % column, Vector3(0.045 * (column - 1), 0.03, 0.151), Vector3(0.024, 0.025, 0.012), MINT)
	_shell("head", "Helmet", Vector3(0, 0.03, 0), Vector3(0.31, 0.26, 0.26), PORCELAIN)
	_shell("head", "Visor", Vector3(0, 0.04, 0.101), Vector3(0.258, 0.128, 0.126), GRAPHITE)
	for sign_x in [-1.0, 1.0]:
		_box("head", "VisorLight%d" % int(sign_x), Vector3(sign_x * 0.057, 0.047, 0.163), Vector3(0.035, 0.025, 0.008), MINT)
	for side in ["L", "R"]:
		var suffix: String = "." + side
		_shell("shoulder" + suffix, "Shoulder", Vector3.ZERO, Vector3(0.14, 0.14, 0.14), GOLD)
		_segment("upperArm" + suffix, "forearm" + suffix, "UpperArm", 0.124, PORCELAIN)
		_segment("forearm" + suffix, "hand" + suffix, "Forearm", 0.111, GRAPHITE)
		_shell("hand" + suffix, "Glove", Vector3(0, -0.034, 0.007), Vector3(0.105, 0.155, 0.096), PORCELAIN)
		_segment("thigh" + suffix, "shin" + suffix, "Thigh", 0.167, PORCELAIN)
		_shell("shin" + suffix, "Knee", Vector3(0, 0, 0.015), Vector3(0.157, 0.156, 0.156), GOLD)
		_segment("shin" + suffix, "foot" + suffix, "Shin", 0.132, GRAPHITE)
		_shell("foot" + suffix, "Boot", Vector3(0, -0.012, 0.059), Vector3(0.151, 0.112, 0.271), PORCELAIN)
	_segment("aerial", "aerial_tip", "AerialStem", 0.039, GRAPHITE)
	_segment("aerial_tip", "aerial_end", "AerialEnd", 0.028, GOLD)
	_shell("aerial_end", "Receiver", Vector3.ZERO, Vector3(0.064, 0.064, 0.064), MINT)

	var packed := PackedScene.new()
	var result := packed.pack(performer)
	if result == OK:
		result = ResourceSaver.save(packed, OUT)
	if result != OK:
		push_error("Could not save Kite: %s" % error_string(result))
	quit(0 if result == OK else 1)


func _add(parent: Node, child: Node, label: String) -> void:
	child.name = label
	parent.add_child(child)
	child.owner = performer


func _bone(label: String, parent: String, offset: Vector3) -> void:
	var index := skeleton.get_bone_count()
	skeleton.add_bone(label)
	skeleton.set_bone_parent(index, skeleton.find_bone(parent) if not parent.is_empty() else -1)
	skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, offset))
	skeleton.set_bone_pose_position(index, offset)


func _mount(bone: String) -> BoneAttachment3D:
	var key := "Mount_" + bone.replace(".", "_")
	var existing := skeleton.get_node_or_null(NodePath(key)) as BoneAttachment3D
	if existing != null:
		return existing
	var attachment := BoneAttachment3D.new()
	_add(skeleton, attachment, key)
	attachment.bone_name = bone
	return attachment


func _mesh(bone: String, label: String, mesh: PrimitiveMesh, color: Color) -> MeshInstance3D:
	if not materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.55
		if color == MINT:
			material.emission_enabled = true
			material.emission = MINT
			material.emission_energy_multiplier = 0.25
		materials[color] = material
	mesh.material = materials[color]
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	_add(_mount(bone), instance, label)
	return instance


func _shell(bone: String, label: String, center: Vector3, dimensions: Vector3, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 24
	mesh.rings = 10
	mesh.radius = 0.5
	mesh.height = 1
	var instance := _mesh(bone, label, mesh, color)
	instance.position = center
	instance.scale = dimensions


func _box(bone: String, label: String, center: Vector3, dimensions: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	_mesh(bone, label, mesh, color).position = center


func _segment(bone: String, tip: String, label: String, diameter: float, color: Color) -> void:
	var end := skeleton.get_bone_rest(skeleton.find_bone(tip)).origin
	var mesh := CapsuleMesh.new()
	mesh.radial_segments = 16
	mesh.rings = 6
	mesh.radius = diameter * 0.5
	mesh.height = end.length() * 0.91
	var instance := _mesh(bone, label, mesh, color)
	instance.position = end * 0.5
	instance.quaternion = Quaternion(Vector3.UP, end.normalized())
