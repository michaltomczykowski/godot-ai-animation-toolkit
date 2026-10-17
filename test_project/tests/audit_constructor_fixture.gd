@tool
extends Node3D

static var constructor_count := 0
func _init() -> void: constructor_count += 1
