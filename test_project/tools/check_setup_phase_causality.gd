extends "check_setup_tree_quality.gd"
var selected_mode:=-1
var worst:Dictionary={}
var phase_gap:=0.0
func _load(row:Dictionary)->Dictionary:
	var v:=super._load(row)
	if not v.has("error") and selected_mode>=0:v.base.sync_mode=selected_mode
	return v
func _declared(v:Dictionary,points:Array,side:String)->bool:
	if side=="l":
		var entries:Array=[]
		var fractions:Array=[]
		for point:Dictionary in points:
			if float(point.weight)<=0.000001:continue
			var clip:Animation=v.player.get_animation(point.clip)
			var phase:=float(v.tree.get(point.phase_path))
			entries.append({"clip":point.clip,"weight":point.weight,"phase":phase,"length":clip.length})
			if point.clip!="idle":fractions.append(fposmod(phase,clip.length)/clip.length)
		if fractions.size()==2:
			var gap:=absf(float(fractions[0])-float(fractions[1]));phase_gap=maxf(phase_gap,minf(gap,1.0-gap))
		var height:=minf(_point(v,"foot_l").dot(v.up)-v.ground,_point(v,"foot_r").dot(v.up)-v.ground)
		if worst.is_empty() or height<float(worst.height):
			worst={"height":height,"points":entries,"feet":{},"world_basis":v.rig.global_basis}
			for s in ["l","r"]:worst.feet[s]=v.rig.get_bone_global_pose(v.indices["foot_"+s]).origin
	return super._declared(v,points,side)
func _source_comparison(row:Dictionary,snapshot:Dictionary)->Dictionary:
	if snapshot.is_empty():return {}
	var weighted:={"l":Vector3.ZERO,"r":Vector3.ZERO}
	var sources:Array=[]
	for point:Dictionary in snapshot.points:
		var v:=super._load(row)
		if v.has("error"):return {"error":v.error}
		v.player.active=true
		v.player.play(point.clip)
		v.player.seek(float(point.phase),true)
		v.player.advance(0.0)
		var record:={"clip":point.clip,"phase":point.phase,"weight":point.weight,"foot_height_m":{}}
		for side in ["l","r"]:
			var position:Vector3=v.rig.get_bone_global_pose(v.indices["foot_"+side]).origin
			weighted[side]+=position*float(point.weight)
			record.foot_height_m[side]=_point(v,"foot_"+side).dot(v.up)-v.ground
		sources.append(record)
		_free(v)
	var errors:={}
	for side in ["l","r"]:errors[side]=(snapshot.world_basis*(snapshot.feet[side]-weighted[side])).length()
	return {"sources":sources,"mixed_FK_vs_weighted_source_endpoint_error_m":errors}
func _run()->void:
	var args:=OS.get_cmdline_user_args()
	var route:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var modes:={"original":-1}
	for name in ClassDB.class_get_integer_constant_list("AnimationNodeBlendSpace1D"):
		if str(name).begins_with("SYNC_MODE_"):modes[str(name)]=ClassDB.class_get_integer_constant("AnimationNodeBlendSpace1D",name)
	var results:Array=[]
	for label in modes:
		selected_mode=int(modes[label])
		for row:Dictionary in route.cases:
			for spec:Dictionary in _specs(row):
				worst={};phase_gap=0.0
				var checked:=_check(row,spec,60)
				checked.erase("trace")
				checked["sync_test"]=label
				checked["maximum_normalized_gait_phase_gap"]=phase_gap
				checked["worst_mixed_sample"]=worst.duplicate(true)
				checked["independent_native_source_comparison"]=_source_comparison(row,worst)
				results.append(checked)
	var report:={"modes":modes,"runs":results,"engine_errors":logger.errors,"route_sha256":FileAccess.get_sha256(args[0]),"script_sha256":FileAccess.get_sha256(get_script().resource_path)}
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(report))
	OS.remove_logger(logger)
	print("SETUP_CAUSALITY="+JSON.stringify({"runs":results.size(),"modes":modes,"engine_errors":logger.errors}))
	quit(0 if logger.errors.is_empty() else 1)
