# Modifier allocation and dry-run checkpoint

## Scope

Godot 4.7.2, through Godot AI's public `animation_rig_modifiers` dispatcher.
`test_rig_modifier_allocation.gd` requires all five advertised operations;
`mcp_rig_modifier_allocation.py` requires the exact named cases and assertion
minimums, then runs independent saved-scene playback. The complete Windows/Linux
MCP CI route requires this gate after core reload.

| Operation | Covered allocation cases |
| --- | --- |
| `ik_setup` | Two-bone, CCDIK, FABRIK, Jacobian and spline; generated or supplied targets, poles and paths |
| `look_at_setup` | Generated/supplied target; invalid origin mode, bone, node/type and axis; external-origin wiring |
| `twist_setup` | New disperser; invalid weight/mode, damping, reference type and non-unit quaternion |
| `spring_setup` | No explicit collisions or supplied caller-owned collider/center; wrong/missing centers and colliders, malformed arrays, late engine-name collision refusal |
| `retarget_setup` | New modifier and existing-modifier reconfiguration; invalid flags/target; direct target skeleton layout |

There are 18 dry/commit comparisons and 74 refusal calls. Every nonwriting call
checks exact `Node.get_orphan_node_ids()`, complete edited-scene structure,
transforms, owners, bone state and stored modifier properties, caller-node
survival, scene/global history versions and captured engine errors. Dry paths
must equal the committed paths, including reparented retarget targets and spring
colliders. Each commit must create one scene action and no global action;
Undo/Redo must restore the exact scene and retain the modifier's identity.

## Reproduced failures and repair

The pre-repair public route leaked three nodes in generated two-bone IK dry
runs, two in other generated IK dry runs, and one with supplied targets.
Look-at dry/late-refusal calls leaked one or two nodes; twist dry/late-refusal
calls leaked one. A separately corrected direct-target fixture reproduced a
retarget dry-run leak. Spring dry runs freed their temporary node but predicted
the wrong modifier name on a collision and reported pre-move collider paths.
Look-at accepted a non-Node3D origin; spring accepted missing/invalid centers.

Each modifier call now owns its new nodes through a scoped allocation helper.
On dry/refusal return the helper frees its temporary nodes. After commit it
transfers them to the scene history action, before any post-commit wiring
check; rolling back a committed action must retain its history-owned nodes.
Caller-owned nodes are never tracked. Pure look-at/twist/center settings are
validated before node allocation. Names are chosen before path construction.
Spring center requirements use the parsed enum so case-insensitive `NODE`/`BONE`
requests receive the same typed validation as lowercase requests.
Look-at verifies the committed target and origin paths, including an origin
that is the modifier's parent Skeleton3D (`..`).

External look-at origins now use modifier-relative NodePaths and require a
Node3D, matching the [engine source](https://github.com/godotengine/godot/blob/4.7/scene/3d/look_at_modifier_3d.cpp)
and [origin contract](https://docs.godotengine.org/en/4.7/classes/class_lookatmodifier3d.html).
`check_rig_modifier_origin.gd` imports no toolkit code. It loads the saved scene,
checks both paths, and measures active/inactive plus 0/0.5/1 influence playback.
The modifier's signal observes the full solver result; an inert last modifier
observes the engine's subsequently blended pose inside `modification_processed`.
This follows [Skeleton3D's blend order](https://github.com/godotengine/godot/blob/4.7/scene/3d/skeleton_3d.cpp)
and [SkeletonModifier3D influence](https://docs.godotengine.org/en/4.7/classes/class_skeletonmodifier3d.html).

## Evidence and remaining work

Recovery directory:
`F:/GODOTAITESTING/toolkit_repair_snapshot_2026-09-30/modifier_allocation_20261007`.
Baseline logs are retained separately from repaired results. Final local and
hosted results are recorded in `FIX_ROADMAP.md` and the checkpoint metadata.

Local final source: fresh editor 300/300 across 21 suites, zero captured
engine/tool-route/discovery errors; fresh external modifier gate eight required
cases and four independently played origin states, no script errors in either
editor log. All fourteen headless suites pass. The complete 114-gate public route
passes before the final enum-validation follow-up; hosted Windows/Linux CI must
repeat it on the pushed exact source.

This checkpoint covers allocation and local history integrity. The full
local/locked/editable-instance modifier matrix, source/peer isolation,
independent playback of both saved history states for every modifier, ordered
stacks, stateful spring continuity and native shortcut matrix remain open.
The external-origin playback test does not approve visual animation quality.
Active graph/modifier bake restoration, motion/sequence history and broader
fixed-camera visual review remain separate roadmap gates. No release is made.
