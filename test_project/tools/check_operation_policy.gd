extends SceneTree
const Registry := preload("res://addons/godot_ai_animation/registry/op_registry.gd")
const Generate := preload("res://addons/godot_ai_animation/handlers/generate.gd")
const FX := preload("res://addons/godot_ai_animation/handlers/fx.gd")
const Graph := preload("res://addons/godot_ai_animation/handlers/graph.gd")
const Inspect := preload("res://addons/godot_ai_animation/handlers/inspect.gd")
const Library := preload("res://addons/godot_ai_animation/handlers/library.gd")
const Rig := preload("res://addons/godot_ai_animation/handlers/rig.gd")
const Sequence := preload("res://addons/godot_ai_animation/handlers/sequence.gd")
const Edit := preload("res://addons/godot_ai_animation/handlers/edit.gd")

func _init() -> void:
	var count := 0
	for family_name in Registry.family_names():
		var family: Dictionary = Registry.family(family_name)
		var serialized := JSON.stringify(family.schema)
		assert(serialized.to_utf8_buffer().size() + serialized.count(":") + serialized.count(",") <= Registry.MAX_SCHEMA_BYTES)
		assert(str(family.description).length() <= Registry.MAX_DESCRIPTION_CHARS)
		var advertised: Array = family.schema.properties.op.enum
		for descriptor in family.ops:
			count += 1
			assert(descriptor.availability.status == "supported")
			assert(advertised.has(descriptor.name))
			assert(Registry.preflight(family_name, {"op": descriptor.name}).is_empty())
	assert(count == 103)
	var refusal := Registry.preflight(Registry.FAMILY_RIG_MODIFIERS, {"op": "ik_setup", "kind": "jacobian"})
	assert(refusal.error.code == "OPERATION_UNAVAILABLE")
	assert(not Registry.family(Registry.FAMILY_RIG_MODIFIERS).schema.properties.kind.enum.has("jacobian"))
	assert(Registry.preflight(Registry.FAMILY_RIG_MODIFIERS, {"op": "ik_setup", "kind": "invalid"}).is_empty())
	var edit := Edit.new()
	var spec := {"length": 1.0, "loop_mode": 0, "tracks": []}
	var result := edit._commit_edited({"anim_name": "unchanged", "spec": spec}, spec.duplicate(true), "unused", {})
	assert(result.data.changed == false and result.data.affected_count == 0)
	assert(result.data.undoable == false and result.data.overwritten == false)
	print("OPERATION_POLICY_PASS: 103 inventory, narrow typed guard, idempotent no-history result")
	quit(0)
