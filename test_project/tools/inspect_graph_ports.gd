extends SceneTree

func _initialize() -> void:
	for node in [AnimationNodeOneShot.new(), AnimationNodeBlend2.new(), AnimationNodeAdd2.new()]:
		var ports: Array = []
		for index in node.get_input_count():
			ports.append(str(node.get_input_name(index)))
		print("GRAPH_PORTS=", node.get_class(), " ", JSON.stringify(ports))
	quit()
