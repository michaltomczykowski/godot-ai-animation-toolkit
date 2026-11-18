@tool
extends RefCounted
## Read-only raw observations. No expected values or generated-key oracle.
class Capture extends Logger:
	var errors: Array[String] = []
	func _log_error(_fn: String,_file: String,_line: int,code: String,rationale: String,_notify: bool,type: int,_trace: Array) -> void:
		if type!=1: errors.append(rationale if not rationale.is_empty() else code)
static func describe(path: String, fixture: Node, player: AnimationPlayer, names: Array) -> Dictionary:
	var clips := {}
	var animation_root := player.get_node_or_null(player.root_node)
	for name: String in names:
		if not player.has_animation(name): continue
		var clip := player.get_animation(name)
		var tracks: Array = []
		for index in clip.get_track_count():
			var target_path := clip.track_get_path(index)
			var target: Node = animation_root.get_node_or_null(NodePath(target_path.get_concatenated_names())) if animation_root!=null else null
			var property := str(target_path.get_concatenated_subnames())
			var key_times: Array = []
			for key in clip.track_get_key_count(index): key_times.append(clip.track_get_key_time(index,key))
			tracks.append({"path":str(target_path),"type":clip.track_get_type(index),"enabled":clip.track_is_enabled(index),"node_resolved":target!=null,"node_class":target.get_class() if target!=null else "","property":property,"property_type":typeof(target.get_indexed(NodePath(property))) if target!=null and not property.is_empty() else TYPE_NIL,"key_count":clip.track_get_key_count(index),"key_times":key_times,"interpolation":clip.track_get_interpolation_type(index)})
		clips[name]={"length":clip.length,"loop_mode":clip.loop_mode,"tracks":tracks}
	return {"schema":"edit_native_intention_v1","scene_sha256":FileAccess.get_sha256(path),"fixture_sha256":FileAccess.get_sha256("res://repair_edit_fixture.tscn"),"fixture_class":fixture.get_class(),"player_path":str(fixture.get_path_to(player)),"player_class":player.get_class(),"root_node":str(player.root_node),"root_resolves_fixture":animation_root==fixture,"clock":"native_seek_advance_zero","clips":clips}
