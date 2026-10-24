extends RefCounted
## Admission for actual displayed geometry only; never moves a saved target.
const BODY := Rect2(24,100,1872,760)
static func startup() -> Dictionary:
	var settings := {"width":ProjectSettings.get_setting("display/window/size/viewport_width",0),"height":ProjectSettings.get_setting("display/window/size/viewport_height",0),"stretch":ProjectSettings.get_setting("display/window/stretch/mode","")}
	settings["passed"] = int(settings.width)==1920 and int(settings.height)==1080 and str(settings.stretch)=="viewport"
	return settings
static func projected(points: Array, behind: int, visible: bool, count: int) -> Dictionary:
	var out: Array=[]
	var finite := true
	var fits := visible and behind==0 and points.size()==count and count>0
	var minimum := Vector2(INF,INF)
	var maximum := Vector2(-INF,-INF)
	for point: Vector2 in points:
		out.append([point.x,point.y])
		finite = finite and point.is_finite()
		minimum = minimum.min(point);maximum=maximum.max(point)
		fits = fits and point.x>=BODY.position.x+1 and point.y>=BODY.position.y+1 and point.x<=BODY.end.x-1 and point.y<=BODY.end.y-1
	var extent := maximum-minimum
	return {"points":out,"point_count":count,"body_rect":[BODY.position.x,BODY.position.y,BODY.size.x,BODY.size.y],"bounds":[minimum.x,minimum.y,extent.x,extent.y],"behind_or_clipped_depth":behind,"visible":visible,"finite":finite,"fits":fits and finite and extent.x>=2 and extent.y>=2}
static func graph(marker: Polygon2D) -> Dictionary:
	var points: Array=[]
	var transform := marker.get_global_transform_with_canvas()
	for vertex in marker.polygon:points.append(transform*vertex)
	return projected(points,0,marker.is_visible_in_tree(),marker.polygon.size())
static func rig(skeleton: Skeleton3D, camera: Camera3D) -> Dictionary:
	var points: Array=[]
	var behind := 0
	for bone in skeleton.get_bone_count():
		var pose := skeleton.global_transform*skeleton.get_bone_global_pose(bone)
		var vertices: Array=[]
		for x in [-1,1]:
			for y in [-1,1]:
				for z in [-1,1]:vertices.append(pose*Vector3(x*0.06,y*0.06,z*0.06))
		vertices.append(pose.origin+pose.basis.x*0.25)
		for vertex: Vector3 in vertices:
			var depth := -(camera.global_transform.affine_inverse()*vertex).z
			if camera.is_position_behind(vertex) or depth<camera.near or depth>camera.far:behind+=1
			points.append(camera.unproject_position(vertex))
	var result := projected(points,behind,true,skeleton.get_bone_count()*9)
	result["bone_count"]=skeleton.get_bone_count()
	result["skin_scope"]="unskinned_joint_spheres_and_axis_rods_only"
	return result
