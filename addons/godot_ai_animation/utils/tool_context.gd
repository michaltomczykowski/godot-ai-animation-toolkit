@tool
extends RefCounted

## Shared context the addon's EditorPlugin fills in and the lazily loaded tool
## handler reads. Kept out of plugin.gd so handlers never preload the
## EditorPlugin itself (and so tests can inject a manager directly).

static var undo_redo: EditorUndoRedoManager = null
