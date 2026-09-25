extends SceneTree

## Tier-1 headless checks for the animation_graph builders: state machines,
## blend spaces, blend trees, dumps and clip-reference validation. No editor, no
## undo manager. Run with:
##
##   godot --headless --path test_project --script res://tests/tier1_graph_builders.gd

const GraphBuilders := preload("res://addons/godot_ai_animation/spec/graph_builders.gd")

var _checks := 0
var _failures := 0


func _init() -> void:
	_check_state_machine()
	_check_state_machine_validation()
	_check_blend_space_1d()
	_check_blend_space_2d()
	_check_blend_tree()
	_check_blend_tree_validation()
	_check_wrap_one_shot()
	_check_dump()
	_check_animations_and_issues()
	if _failures == 0:
		print("TIER1 PASS (%d checks)" % _checks)
	else:
		print("TIER1 FAIL (%d/%d checks failed)" % [_failures, _checks])
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  FAIL: %s" % message)


func _expect_approx(actual: float, expected: float, message: String) -> void:
	_expect(absf(actual - expected) < 0.0001, "%s (expected %s, got %s)" % [message, expected, actual])


func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _expect_error(result: Dictionary, message: String) -> void:
	_expect(result.has("error"), message)


func _sm_spec() -> Dictionary:
	return {
		"states": [
			{"name": "idle", "animation": "idle"},
			{"name": "walk", "animation": "walk"},
			{"name": "run", "animation": "run"},
		],
		"transitions": [
			{"from": "idle", "to": "walk", "xfade": 0.2, "condition": "walking"},
			{"from": "walk", "to": "idle", "xfade": 0.2, "advance_expression": "!walking"},
			{"from": "walk", "to": "run", "xfade": 0.15, "condition": "running", "priority": 3},
		],
	}


func _check_state_machine() -> void:
	var built := GraphBuilders.state_machine(_sm_spec())
	_expect(not built.has("error"), "state_machine builds")
	var machine: AnimationNodeStateMachine = built.root
	_expect(machine is AnimationNodeStateMachine, "the root is a state machine")
	var authored := 0
	for state_name in machine.get_node_list():
		if str(state_name) != "Start" and str(state_name) != "End":
			authored += 1
	_expect(authored == 3, "three states are added (%d)" % authored)
	_expect(machine.get_node_list().has(StringName("Start")) and machine.get_node_list().has(StringName("End")),
		"Godot's implicit Start/End markers exist")
	_expect(machine.has_node(StringName("idle")), "state names are preserved")
	_expect(int(built.state_count) == 3 and int(built.transition_count) == 3, "counts are reported")
	var idle_node := machine.get_node(StringName("idle"))
	_expect(idle_node is AnimationNodeAnimation, "states hold animation nodes")
	_expect(str((idle_node as AnimationNodeAnimation).animation) == "idle", "the state's clip is set")
	_expect(machine.get_node_position(StringName("walk")).x > machine.get_node_position(StringName("idle")).x,
		"auto layout spreads the states out")
	_expect(machine.get_transition_count() == 3, "transitions are added")
	var first := machine.get_transition(0)
	_expect_approx(first.xfade_time, 0.2, "xfade is stored")
	_expect(first.advance_mode == AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO,
		"advance_mode defaults to auto")
	_expect(str(first.advance_condition) == "walking", "conditions are stored on the transition")
	var third := machine.get_transition(2)
	_expect(int(third.priority) == 3, "priority is stored")
	_expect_approx(third.xfade_time, 0.15, "per-transition xfade")
	_expect((built.conditions as Array).has("walking") and (built.conditions as Array).has("running"),
		"condition names are collected (%s)" % str(built.conditions))
	var explicit := GraphBuilders.state_machine({
		"states": [{"name": "a", "animation": "idle", "position": {"x": 40, "y": 80}}],
		"transitions": [],
		"state_machine_type": "nested",
		"allow_transition_to_self": true,
		"reset_ends": true,
	})
	_expect(not explicit.has("error"), "explicit state machine options build")
	_expect(explicit.root.get_state_machine_type() == AnimationNodeStateMachine.STATE_MACHINE_TYPE_NESTED,
		"state_machine_type is applied")
	_expect(explicit.root.is_allow_transition_to_self(), "allow_transition_to_self is applied")
	_expect(explicit.root.are_ends_reset(), "reset_ends is applied")
	_expect(explicit.root.get_node_position(StringName("a")).is_equal_approx(Vector2(40, 80)),
		"explicit positions are honoured")


func _check_state_machine_validation() -> void:
	_expect_error(GraphBuilders.state_machine({"states": []}), "state machines need states")
	_expect_error(GraphBuilders.state_machine({
		"states": [{"name": "a", "animation": "idle"}],
		"transitions": [{"from": "a", "to": "ghost"}],
	}), "transitions must reference known states")
	_expect_error(GraphBuilders.state_machine({
		"states": [{"name": "a", "animation": "idle"}, {"name": "a", "animation": "walk"}],
	}), "duplicate state names are rejected")
	_expect_error(GraphBuilders.state_machine({
		"states": [{"name": "a", "animation": "idle"}],
		"transitions": [{"from": "a", "to": "a", "advance_mode": "sometimes"}],
	}), "invalid advance modes are rejected")
	_expect_error(GraphBuilders.state_machine({
		"states": [{"name": "a", "animation": "idle"}],
		"transitions": [{"from": "a", "to": "a", "switch_mode": "later"}],
	}), "invalid switch modes are rejected")
	_expect_error(GraphBuilders.state_machine({
		"states": [{"name": "a", "animation": "idle"}],
		"state_machine_type": "floating",
	}), "invalid state machine types are rejected")
	var no_clip := GraphBuilders.state_machine({"states": [{"name": "a"}]})
	_expect(not no_clip.has("error"), "a state without a clip still builds")
	_expect(str((no_clip.root.get_node(StringName("a")) as AnimationNodeAnimation).animation) == "",
		"an empty state keeps an empty clip")


func _check_blend_space_1d() -> void:
	var built := GraphBuilders.blend_space({
		"dimensions": 1,
		"points": [
			{"animation": "idle", "position": 0.0},
			{"animation": "walk", "position": 1.0},
			{"animation": "run", "position": 2.0},
		],
		"min": 0.0,
		"max": 2.0,
		"snap": 0.01,
	})
	_expect(not built.has("error"), "blend_space 1D builds")
	var space: AnimationNodeBlendSpace1D = built.root
	_expect(space is AnimationNodeBlendSpace1D, "the root is a 1D blend space")
	_expect(space.get_blend_point_count() == 3, "three points are added")
	_expect_approx(space.get_blend_point_position(1), 1.0, "point positions are stored")
	_expect_approx(space.get_max_space(), 2.0, "max space is applied")
	_expect_approx(space.get_snap(), 0.01, "snap is applied")
	var point := space.get_blend_point_node(2)
	_expect(point is AnimationNodeAnimation and str((point as AnimationNodeAnimation).animation) == "run",
		"points hold the animation nodes")
	_expect(int(built.point_count) == 3 and int(built.dimensions) == 1, "counts are reported")
	_expect_error(GraphBuilders.blend_space({"points": []}), "blend spaces need points")
	_expect_error(GraphBuilders.blend_space({
		"dimensions": 3,
		"points": [{"animation": "idle", "position": 0.0}],
	}), "dimensions must be 1 or 2")
	_expect_error(GraphBuilders.blend_space({"points": [{"position": 0.0}]}), "points need an animation")


func _check_blend_space_2d() -> void:
	var built := GraphBuilders.blend_space({
		"dimensions": 2,
		"points": [
			{"animation": "idle", "position": {"x": 0, "y": 0}},
			{"animation": "run", "position": {"x": 1, "y": 0}},
			{"animation": "jump", "position": {"x": 0, "y": 1}},
		],
		"min": {"x": -1, "y": -1},
		"max": {"x": 1, "y": 1},
	})
	_expect(not built.has("error"), "blend_space 2D builds")
	var space: AnimationNodeBlendSpace2D = built.root
	_expect(space is AnimationNodeBlendSpace2D, "the root is a 2D blend space")
	_expect(space.get_blend_point_count() == 3, "three 2D points are added")
	_expect(space.get_blend_point_position(2).is_equal_approx(Vector2(0, 1)), "2D positions are stored")
	_expect(space.get_max_space().is_equal_approx(Vector2(1, 1)), "2D max space is applied")


func _check_blend_tree() -> void:
	var built := GraphBuilders.blend_tree({
		"type": "blend2",
		"inputs": [
			{"type": "animation", "animation": "walk"},
			{"type": "animation", "animation": "run"},
		],
	})
	_expect(not built.has("error"), "blend_tree builds")
	var tree: AnimationNodeBlendTree = built.root
	_expect(tree is AnimationNodeBlendTree, "the root is a blend tree")
	_expect(tree.has_node(StringName("Blend2")), "the combiner is named after its type")
	_expect(int(built.node_count) == 3, "three nodes are created (%d)" % int(built.node_count))
	_expect(int(built.animation_count) == 2, "two animation nodes are counted")
	var combiner := tree.get_node(StringName("Blend2"))
	_expect(combiner.get_input_count() == 2, "a blend2 node has two inputs")
	var nested := GraphBuilders.blend_tree({
		"type": "one_shot",
		"fadein": 0.15,
		"fadeout": 0.3,
		"mix_mode": "add",
		"inputs": [{"type": "blend2", "inputs": [
			{"type": "animation", "animation": "walk"},
			{"type": "animation", "animation": "run"},
		]}],
	})
	_expect(not nested.has("error"), "nested blend trees build")
	_expect(nested.root.has_node(StringName("OneShot")), "the one-shot node exists")
	var shot: AnimationNodeOneShot = nested.root.get_node(StringName("OneShot"))
	_expect_approx(shot.fadein_time, 0.15, "fadein is applied")
	_expect_approx(shot.fadeout_time, 0.3, "fadeout is applied")
	_expect(shot.mix_mode == AnimationNodeOneShot.MIX_MODE_ADD, "mix_mode is applied")
	_expect(int(nested.node_count) == 4, "nested node count (%d)" % int(nested.node_count))
	var with_sm := GraphBuilders.blend_tree({
		"type": "blend2",
		"inputs": [
			{"type": "state_machine", "states": [{"name": "a", "animation": "idle"}]},
			{"type": "animation", "animation": "run"},
		],
	})
	_expect(not with_sm.has("error"), "state machines nest inside blend trees")
	_expect(with_sm.root.get_node(StringName("StateMachine")) is AnimationNodeStateMachine,
		"the nested state machine is added as a node")
	_check_output_wiring()


## A blend tree with an unconnected `output` node builds cleanly, reports no
## issue, and then evaluates to nothing - the graph is there and no pose ever
## plays. 4.7 cannot read a connection back, so the wiring is verified in the
## SERIALIZED resource: that is what the editor and the engine load.
func _check_output_wiring() -> void:
	var output := StringName("output")
	for label in ["flat", "nested"]:
		var spec := {
			"type": "blend2",
			"inputs": [
				{"type": "animation", "animation": "walk"},
				{"type": "animation", "animation": "run"},
			],
		}
		if label == "nested":
			spec = {"type": "one_shot", "inputs": [spec]}
		var built := GraphBuilders.blend_tree(spec)
		_expect(not built.has("error"), "%s blend_tree builds" % label)
		var tree: AnimationNodeBlendTree = built.root
		_expect(tree.has_node(output), "%s: the output node exists" % label)
		_expect(bool(built.get("output_wired", false)), "%s: the builder wired output" % label)
		var source := str(built.get("output_source", ""))
		_expect(not source.is_empty() and tree.has_node(StringName(source)),
			"%s: the reported output source is a real node (%s)" % [label, source])
		_expect(str(source) != str(output), "%s: output is not wired to itself" % label)
		var path := "user://tier1_blend_tree_%s.tres" % label
		var err := ResourceSaver.save(tree, path)
		_expect(err == OK, "%s: the tree serializes (%d)" % [label, err])
		if err != OK:
			continue
		var text := FileAccess.get_file_as_string(path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		# 4.7 serialises connections as one flat array of
		# [input_node, input_index, output_node, ...] triples.
		var wired_token := '&"output", 0, &"%s"' % source
		_expect(text.contains("node_connections"),
			"%s: the saved tree records connections" % label)
		_expect(text.contains(wired_token),
			"%s: output input 0 is wired to '%s' in the saved tree" % [label, source])
		_expect(text.contains(source),
			"%s: the saved tree names '%s' as the output source" % [label, source])


func _check_blend_tree_validation() -> void:
	var wrong_inputs := GraphBuilders.blend_tree({
		"type": "blend2",
		"inputs": [{"type": "animation", "animation": "walk"}],
	})
	_expect(wrong_inputs.has("error"), "blend2 needs exactly two inputs")
	_expect_error(GraphBuilders.blend_tree({"type": "wobble"}), "unknown node types are rejected")
	_expect_error(GraphBuilders.blend_tree({"type": "animation"}), "animation nodes need a clip")
	_expect_error(GraphBuilders.blend_tree({
		"type": "blend2",
		"inputs": [
			{"type": "animation", "animation": "walk", "name": "Same"},
			{"type": "animation", "animation": "run", "name": "Same"},
		],
	}), "duplicate node names are rejected")
	var bad_mix := GraphBuilders.blend_tree({
		"type": "one_shot",
		"mix_mode": "multiply",
		"inputs": [{"type": "animation", "animation": "jump"}],
	})
	_expect(bad_mix.has("error"), "invalid mix modes are rejected")


func _check_wrap_one_shot() -> void:
	var space := GraphBuilders.blend_space({
		"dimensions": 1,
		"points": [
			{"animation": "idle", "position": 0.0},
			{"animation": "walk", "position": 1.4},
			{"animation": "run", "position": 4.0},
		],
		"min": 0.0, "max": 4.0, "sync": true,
	})
	_expect(not space.has("error"), "the base blend space builds")
	var wrapped := GraphBuilders.wrap_one_shot(space.root, "jump", 0.1, 0.25)
	_expect(not wrapped.has("error"), "wrap_one_shot builds")
	var tree: AnimationNodeBlendTree = wrapped.root
	_expect(tree is AnimationNodeBlendTree, "the wrapped root is a blend tree")
	for node_name in ["Base", "OneShot", "Shot", "Blend2", "output"]:
		_expect(tree.has_node(StringName(node_name)), "'%s' node exists" % node_name)
	_expect(tree.get_node(StringName("Base")) is AnimationNodeBlendSpace1D,
		"the base root is preserved as the Base node")
	var shot: AnimationNodeOneShot = tree.get_node(StringName("OneShot"))
	_expect_approx(shot.fadein_time, 0.1, "fadein is applied")
	_expect_approx(shot.fadeout_time, 0.25, "fadeout is applied")
	_expect(shot.mix_mode == AnimationNodeOneShot.MIX_MODE_BLEND, "blend is the default mix mode")
	var clip: AnimationNodeAnimation = tree.get_node(StringName("Shot"))
	_expect_eq(str(clip.animation), "jump", "the one-shot clip is assigned")
	_expect((GraphBuilders.animations_in(tree) as Array).has("jump"),
		"the one-shot clip is discoverable")
	var add_shot := GraphBuilders.wrap_one_shot(space.root, "lean", 0.1, 0.2, "add")
	_expect(not add_shot.has("error"), "add mode builds")
	_expect((add_shot.root.get_node(StringName("OneShot")) as AnimationNodeOneShot).mix_mode \
		== AnimationNodeOneShot.MIX_MODE_ADD, "add mode is applied")
	_expect_error(GraphBuilders.wrap_one_shot(null, "jump"), "a base root is required")
	_expect_error(GraphBuilders.wrap_one_shot(space.root, ""), "an animation name is required")
	_expect_error(GraphBuilders.wrap_one_shot(space.root, "jump", 0.1, 0.2, "wobble"),
		"unknown mix modes are rejected")


func _check_dump() -> void:
	var built := GraphBuilders.state_machine(_sm_spec())
	var dump := GraphBuilders.graph_dump(built.root)
	_expect(str(dump.type) == "state_machine", "the dump names the root type")
	_expect(int(dump.state_count) == 3 and int(dump.transition_count) == 3, "the dump counts states/transitions")
	var walk_state: Dictionary = {}
	for state in dump.states:
		if str(state.name) == "walk":
			walk_state = state
	_expect(not walk_state.is_empty(), "the dump lists states")
	_expect(str(walk_state.node.animation) == "walk", "the dump includes each state's clip")
	var first: Dictionary = dump.transitions[0]
	_expect(str(first["from"]) == "idle" and str(first["to"]) == "walk", "the dump lists transition endpoints")
	_expect(str(first.condition) == "walking", "the dump includes conditions")
	_expect(str(first.advance_mode) == "auto", "the dump names advance modes")
	var third: Dictionary = dump.transitions[2]
	_expect(str(third.switch_mode) == "immediate", "the dump names switch modes")
	var tree_dump := GraphBuilders.graph_dump(GraphBuilders.blend_tree({
		"type": "blend2",
		"inputs": [
			{"type": "animation", "animation": "walk"},
			{"type": "animation", "animation": "run"},
		],
	}).root)
	_expect(str(tree_dump.type) == "blend_tree", "blend trees dump as blend_tree")
	_expect(int(tree_dump.node_count) == 3, "the blend tree dump lists every node")
	var space_dump := GraphBuilders.graph_dump(GraphBuilders.blend_space({
		"dimensions": 1,
		"points": [{"animation": "idle", "position": 0.0}, {"animation": "walk", "position": 1.0}],
	}).root)
	_expect(str(space_dump.type) == "blend_space_1d", "blend spaces dump as blend_space_1d")
	_expect(int(space_dump.point_count) == 2, "the dump lists blend points")
	_expect(str(space_dump.points[1].animation) == "walk", "the dump includes point clips")
	var single := GraphBuilders.graph_dump(GraphBuilders.blend_tree({
		"type": "animation", "animation": "idle",
	}).root.get_node(StringName("Animation")))
	_expect(str(single.type) == "animation" and str(single.animation) == "idle", "animation nodes dump their clip")
	_expect(GraphBuilders.graph_dump(null).is_empty(), "null dumps as an empty dictionary")


func _check_animations_and_issues() -> void:
	var built := GraphBuilders.blend_tree({
		"type": "blend2",
		"inputs": [
			{"type": "state_machine",
				"states": [
					{"name": "a", "animation": "idle"},
					{"name": "b", "animation": "walk"},
				],
				"transitions": [{"from": "a", "to": "b", "condition": "go"}],
			},
			{"type": "animation", "animation": "run"},
		],
	})
	var animations := GraphBuilders.animations_in(built.root)
	_expect(animations.size() == 3, "every referenced clip is collected (%s)" % str(animations))
	_expect(animations.has("idle") and animations.has("walk") and animations.has("run"), "clips are deduplicated")
	var issues := GraphBuilders.issues_for(built.root, ["idle", "walk"])
	_expect(issues.size() == 1, "exactly one missing clip is reported (%d)" % issues.size())
	_expect(str(issues[0].code) == "missing_clip", "the issue code is missing_clip")
	_expect(str(issues[0].message).contains("run"), "the issue names the missing clip")
	_expect(GraphBuilders.issues_for(built.root, []).is_empty(), "an empty clip list skips the missing-clip check")
	var empty := GraphBuilders.blend_tree({"type": "animation", "animation": "idle"})
	empty.root.remove_node(StringName("Animation"))
	var empty_node := AnimationNodeAnimation.new()
	empty.root.add_node(StringName("Empty"), empty_node, Vector2.ZERO)
	var empty_issues := GraphBuilders.issues_for(empty.root, ["idle"])
	_expect(empty_issues.size() == 1 and str(empty_issues[0].code) == "empty_animation",
		"animation nodes without a clip are flagged")
	var stranded := GraphBuilders.state_machine({
		"states": [{"name": "a", "animation": "idle"}, {"name": "b", "animation": "walk"}],
		"transitions": [],
	})
	var stranded_issues := GraphBuilders.issues_for(stranded.root, ["idle", "walk"])
	_expect(stranded_issues.size() == 1 and str(stranded_issues[0].code) == "no_transitions",
		"state machines that cannot move are flagged")
