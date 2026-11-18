extends RefCounted
## Read-only observations from the existing native checker; no keys/poses generated.
static func value(v: Variant) -> Array:
	return [v.x,v.y,v.z,v.w] if v is Quaternion else [v.x,v.y,v.z]
static func metric(a: Variant, b: Variant) -> float:
	if a is Quaternion:
		var q: Quaternion = a.inverse()*b
		return 2.0*atan2(Vector3(q.x,q.y,q.z).length(),absf(q.w))
	return a.distance_to(b)
static func observe(row: Dictionary, field: String, a: Variant, b: Variant, time: float, path: String = "") -> void:
	var error := metric(a,b)
	if not row.has(field) or error >= float(row[field].error):
		row[field]={"actual":value(a),"reference":value(b),"error":error,"time":time,"path":path}
static func file(path: String) -> Dictionary:
	return {"path":path,"sha256":FileAccess.get_sha256(path),"bytes":FileAccess.get_file_as_bytes(path).size()}
static func tracks(player: AnimationPlayer, clip: Animation) -> Array:
	var rows: Array=[]
	var base := player.get_node(player.root_node)
	for i in clip.get_track_count():
		var path := clip.track_get_path(i)
		var target := base.get_node_or_null(NodePath(path.get_concatenated_names()))
		var times: Array=[]
		var finite := true
		var normalized := true
		for k in clip.track_get_key_count(i):
			times.append(clip.track_get_key_time(i,k))
			var v: Variant=clip.track_get_key_value(i,k)
			finite=finite and v.is_finite()
			normalized=normalized and (not v is Quaternion or v.is_normalized())
		rows.append({"path":str(path),"type":clip.track_get_type(i),"enabled":clip.track_is_enabled(i),"target_class":target.get_class() if target!=null else "","bone":str(path.get_subname(0)) if target is Skeleton3D and path.get_subname_count()==1 else "","bone_index":target.find_bone(str(path.get_subname(0))) if target is Skeleton3D and path.get_subname_count()==1 else -1,"subnames":path.get_subname_count(),"times":times,"finite_values":finite,"normalized":normalized})
	return rows
