extends SceneTree

## A saved preset must change its target when Godot's AnimationPlayer plays it.

const TARGETS := {
	"pulse": ["Target3D", "scale"],
	"bounce": ["Target2D", "scale"],
	"orbit": ["Target3D", "position"],
	"sweep": ["Target2D", "rotation"],
	"drift": ["Target3D", "position"],
	"spin": ["Target3D", "rotation"],
	"float": ["Target3D", "position"],
	"stagger": ["Target2D", "modulate"],
}
const SHOWCASE_PLAYERS := ["AnimBounce", "AnimOrbit", "AnimSweep",
	"AnimDrift", "AnimPulse", "AnimFloat", "AnimSpin"]


func _initialize() -> void:
	_probe.call_deferred()


func _distance(a: Variant, b: Variant) -> float:
	if a is Vector2 and b is Vector2:
		return (a as Vector2).distance_to(b)
	if a is Vector3 and b is Vector3:
		return (a as Vector3).distance_to(b)
	if a is Color and b is Color:
		return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)
	if a is Transform3D and b is Transform3D:
		return a.origin.distance_to(b.origin) + a.basis.get_rotation_quaternion().angle_to(
			b.basis.get_rotation_quaternion())
	if a is Quaternion and b is Quaternion:
		return a.angle_to(b)
	if a is float or a is int:
		return absf(float(a) - float(b))
	return 0.0


func _probe() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or (not TARGETS.has(args[1]) and args[1] != "showcase"):
		print("PRESET_SAVED_PLAYBACK_FAIL: scene and known operation required")
		quit(1)
		return
	var packed := load(args[0]) as PackedScene
	if packed == null:
		print("PRESET_SAVED_PLAYBACK_FAIL: saved scene cannot load")
		quit(1)
		return
	var fixture := packed.instantiate()
	root.add_child(fixture)
	var op := args[1]
	if op == "showcase":
		_probe_showcase(fixture)
		return
	var player := fixture.get_node("AnimationPlayer") as AnimationPlayer
	var clip_name := "audit_" + op
	var clip := player.get_animation(clip_name)
	if clip == null:
		print("PRESET_SAVED_PLAYBACK_FAIL: saved clip missing")
		quit(1)
		return
	var target: Node = fixture.get_node(TARGETS[op][0])
	var property_name: String = TARGETS[op][1]
	player.play(clip_name)
	player.seek(0.0, true)
	player.advance(0.0)
	var baseline: Variant = target.get(property_name)
	var maximum := 0.0
	for fraction in [0.25, 0.5, 0.75, 0.99]:
		player.seek(clip.length * fraction, true)
		player.advance(0.0)
		maximum = maxf(maximum, _distance(baseline, target.get(property_name)))
	print("PRESET_SAVED_PLAYBACK=" + JSON.stringify({"op": op,
		"scene": args[0], "property": property_name,
		"maximum_change": maximum}))
	quit(0 if maximum > 0.001 else 1)


func _probe_showcase(fixture: Node) -> void:
	var showcase := fixture.get_node("RepairShowcase")
	var rows: Array = []
	var failures: Array = []
	for player_name in SHOWCASE_PLAYERS:
		var player := showcase.get_node(player_name) as AnimationPlayer
		var clip_name: String = str(player_name).trim_prefix("Anim").to_lower()
		var clip := player.get_animation(clip_name)
		if clip == null or clip.get_track_count() == 0:
			failures.append("missing saved clip for " + player_name)
			continue
		var path := clip.track_get_path(0)
		var base := player.get_node(player.root_node)
		var target := base.get_node_or_null(NodePath(path.get_concatenated_names()))
		if target == null or path.get_subname_count() == 0:
			failures.append("unresolved track for " + player_name)
			continue
		var property_path := NodePath(":" + str(path.get_concatenated_subnames()))
		player.play(clip_name)
		player.seek(0.0, true)
		player.advance(0.0)
		var baseline: Variant = target.get_indexed(property_path)
		var maximum := 0.0
		for fraction in [0.25, 0.5, 0.75, 0.99]:
			player.seek(clip.length * fraction, true)
			player.advance(0.0)
			maximum = maxf(maximum, _distance(baseline, target.get_indexed(property_path)))
		rows.append({"player": player_name, "track": str(path),
			"maximum_change": maximum})
		if maximum <= 0.001:
			failures.append("saved clip stayed inert for " + player_name)
	print("PRESET_SHOWCASE_PLAYBACK=" + JSON.stringify({"rows": rows,
		"failures": failures}))
	quit(0 if failures.is_empty() and rows.size() == SHOWCASE_PLAYERS.size() else 1)
