@tool
extends RefCounted

## Own only nodes allocated by one modifier call, until its scene history
## action takes ownership. Scope exit covers every dry/refusal return, including
## unavailable engine APIs. Caller-owned targets and modifiers never enter here.
var _nodes: Array = []

func track(node: Node) -> void:
	if node != null: _nodes.append(node)

func transfer_to_history() -> void:
	_nodes.clear()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for candidate in _nodes:
			# A child may have been freed with a previously tracked parent.
			if is_instance_valid(candidate): candidate.free()
