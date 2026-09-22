@tool
extends RefCounted

## Local error-code vocabulary for the animation toolkit addon.
##
## Mirrors the subset of the Godot AI core codes this addon emits so clients
## see the same codes as built-in tools (the server maps the strings). Keeping
## a local copy means the addon never preloads core scripts for error plumbing.

const INVALID_PARAMS := "INVALID_PARAMS"
const EDITOR_NOT_READY := "EDITOR_NOT_READY"
const NODE_NOT_FOUND := "NODE_NOT_FOUND"
const PROPERTY_NOT_ON_CLASS := "PROPERTY_NOT_ON_CLASS"
const WRONG_TYPE := "WRONG_TYPE"
const VALUE_OUT_OF_RANGE := "VALUE_OUT_OF_RANGE"
const MISSING_REQUIRED_PARAM := "MISSING_REQUIRED_PARAM"


static func make(code: String, message: String) -> Dictionary:
	return {"status": "error", "error": {"code": code, "message": message}}
