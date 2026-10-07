# Next checkpoint: modifier history and evaluation

## Fixtures and routes

Use the public Godot AI `animation_rig_modifiers` route for every write, dry run
and refusal. Preserve the allocation gate introduced in the previous checkpoint.
Start with a synthetic rig with authored rest/pose, nontrivial transforms and
metadata; then cover the bundled dummy. Use separate source and peer instances
from immutable packed scenes. Record source file bytes and original resource
identities before every operation.

| Modifier | Request variants | Layouts |
| --- | --- | --- |
| IK | All five kinds; generated/existing targets, mixed two-bone target/pole ownership, virtual end, authored spline | Local, locked and editable source instance |
| Look-at | Generated/existing targets; self, parent bone, external node and skeleton origins; rotated parent; limits | Local, locked and editable source instance |
| Twist | Even/weighted, rest/reference, extended end, influence | Local, locked and editable source instance |
| Spring | Automatic/list/excluded collisions; bone/node/world center; collision name clashes; nontrivial caller transforms | Local and supported editable layouts; explicit refusal for forbidden instanced colliders |
| Retarget | Create and existing reconfiguration; transform flags/global mode; bare target root and wrapped-target refusal | Local and editable source; locked source refusal; direct target instance where supported |

Avoid multiplying every parameter by every layout. Exercise shared ownership
rules across layouts; add targeted cases for operation-specific risks.

## History and persistence gates

For each supported write require one scene action and no global action. Save
the Do, Undo and Redo states. Assert complete scene structure, owners, transforms,
settings, caller-node identities, permissions and source/peer isolation.
For refusals require typed reasons, no new orphan IDs, no scene mutation and no
history/version change. Locked retarget source and wrapped target are documented
refusals, rather than successes that cannot survive saving.

Independent checkers must load these saved files without toolkit/test imports.
Verify the expected modifier classes, settings and resolved relative paths;
evaluate active/inactive and influence behavior inside `modification_processed`.
Observe final influence through an inert final modifier, since the engine blends
after the original modifier's signal. Repeat source/peer playback to prove no
changes to shared source scenes.

## Evaluation beyond a single solver

Use explicit target motion and nonzero simulation delta to test stateful spring
response, collision selection and continued playback after Undo/Redo. Compare
ordered parent/child look-at and combined IK/look-at/twist stacks. Test different
orders only where the engine contract permits them, with an independent expected
result. Numerical movement alone does not approve visual quality.

Use native Undo/Redo on representative new modifier, caller-node reparent and
existing retarget reconfiguration requests. Repeat external MCP after core
reload and in a fresh editor. Require Windows/Linux headless/editor/public-route
CI before closing this checkpoint; update operation evidence and recovery files.

## Following checkpoint

Bake restoration gets separate fixtures for active/inactive AnimationTree,
ordered modifiers, retarget, continued stateful springs, outside-rig animated
properties, custom mixer processing and late sampling failure. Preserve private
state where supported; otherwise refuse explicitly. Motion/sequence history and
fixed-camera visual approval follow those correctness gates.

Reproduce a last active modifier with fractional influence first: the current
bake capture subscribes to each real modifier's signal, while Skeleton3D blends
influence afterward. Source inspection therefore indicates that the last
modifier may be baked at full influence. Compare baked keys with the final
blended engine pose using the independent witness technique; preserve this
baseline before changing the bake capture. This is a source-based inference,
not a runtime-confirmed bake result yet.
