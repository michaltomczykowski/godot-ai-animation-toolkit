# Modifier history and playback validation

Implementation checkpoint, 2026-10-07. Godot **4.7.2**, unreleased
`repair/toolkit-quality` branch. This implements
[the approved plan](rig-modifier-history-plan.md).

## Repairs

- Generated point-IK targets start at the current effector origin; virtual
  two-bone ends use their requested direction and length.
- Look-at explicitly sets secondary rotation, including the advertised false
  default. A primary axis parallel to the forward axis is refused before commit.
- Retarget Do/Undo/Redo preserve authored child poses and the target's original
  sibling index. Scene/version tickets protect against deferred engine cache
  resets overwriting later edits.
- A scene-owned `ToolkitRetargetPoseRestore` node stores current authored child
  poses when packing and restores inactive retarget inputs once after loading.
  It uses `retarget_pose_restore.gd`, which must accompany the saved scene.
  It makes no per-frame writes and captures later authored edits at save time.
- Spring Redo calls the public `reset()` after attachment, configuration and
  collider wiring. The restored history node restarts from the current pose.
- Twist influence and mutable axes are now discoverable schema parameters.
  Class names and the spring example were corrected in the generated reference.

## Supported boundary

Existing callers receive **OPERATION_UNAVAILABLE** for these choices:

| Choice | Reproduced native 4.7.2 limitation | Available alternative |
| --- | --- | --- |
| `ik_setup.kind=jacobian` | 9.79 mm endpoint error on a reachable 0.9 m chain after 4 seconds, at 30/60/120 FPS; exceeds the required 0.5% chain-length tolerance | TwoBone, CCDIK or FABRIK for point targets |
| Spring collisions with node/bone center | Correctly sized reachable sphere: node center penetrates 79.9 mm and bone center 8.85 mm with rotated parents, versus 0.46 mm in the corresponding world-center probe | `center_from=world_origin` with collisions; relative centers without collisions |

Jacobian is removed from advertised solver choices. Relative-center collision
combinations are explicitly unavailable in the spring description. Re-enable
only after independent world-space playback passes the same contracts.
Single-leaf springs remain unavailable from the earlier repair checkpoint.

The diagnostic modes `probe_jacobian` and `probe_centers` in
`check_rig_modifier_history.gd` deliberately return failure on these native
limitations. They are separate from the supported-operation gate.

## Required matrix

`test_rig_modifier_history.gd` invokes the actual Godot AI dispatcher route,
including dry mode and typed refusals. Each supported write must produce one
scene action and no global action. Exact snapshots cover owners, sibling order,
editable permissions, transforms, bone rests/poses/metadata/enabled flags,
modifier settings, resource sharing, source bytes and untouched peer instances.
Do, Undo and Redo are saved and reopened. History retains node identities.

| Group | Saved cases |
| --- | ---: |
| Local, locked and editable base layouts | 14 |
| Four nested permission combinations, IK and spring | 8 |
| Individual IK/look-at/twist/spring/retarget variants | 49 |
| Direct target instance and different-rest retarget variants | 2 |
| All five operations on the bundled dummy | 5 |
| Ordered stacks, two final weights | 12 |
| Total | **90** |

The 49 individual variants include the existing editable retarget case; total
counts are enforced by the explicit ID set in `mcp_rig_modifier_history.py`.
There are **270 saved scenes** played at **30/60/120 FPS**, giving **810 saved
state checks**, plus **270 native reference runs**. Twelve stacks contribute
108 saved-state checks. The editor suite has **14 required named tests**.

The engine checker imports no toolkit handler or test helper. It configures
native references independently from the recorded requests, checks saved
settings and resolved paths, and compares their played results. It observes
raw modifier output, final influence blending through an inert last modifier,
and `skeleton_updated`. Missing states, duplicate/missing IDs, samples or reports
fail the Python gate. Generated scenes can contain the retarget restoration
script described above; this dependency is exercised by the fresh process.

Geometry checks require point IK within 0.5% chain length, unrestricted
secondary look-at to aim its requested forward axis at the target, finite
poses, and world-center spring sphere penetration below **3 mm** at every
sample. A separate unobstructed run must show that the collider changes the
trajectory. The obstacle starts outside the tail and scales with the chain;
an oversized sphere engulfing the dummy's short forearm was corrected as a
fixture error. Native collision projection followed by the bone-length
constraint leaves a measured worst residual of 2.59 mm at 30 FPS on that rig.

Parent/child look-at in both orders, IK/look-at/twist and IK/spring stacks in
changed orders are sampled against native stacks. Final influence 0.5/1 is
applied once, signal order is exact, and the final witness must agree with
skinning. Live spring Undo/Redo accumulates momentum, changes the authored
pose/parent transform while detached, and compares eight restored steps against
an explicit current-pose reset at all three frame rates.

## Integration and evidence

- Local required matrix: 14/14 editor tests and 810/810 saved-state checks;
  270/270 native references, no engine errors.
- Full fresh editor regression: 314/314 across 22 suites; no captured engine,
  tool-route or discovery errors. All 14 headless suites pass.
- Native Windows shortcuts: new look-at, spring collider reparenting and
  existing retarget reconfiguration pass exact before/after snapshots.
- Direct external `custom_manage`: all five operations are checked for
  dry/write/save/force-reopen before and after core reload. The attach client
  reconnects after reload and waits for the new fixture's unique sentinel.
- `ci_mcp_route.py` requires the matrix on Windows and Linux. Full suite,
  hosted CI and final preview results are recorded below as they complete.

Recovery directory:
`F:/GODOTAITESTING/toolkit_repair_snapshot_2026-09-30/modifier_history_20261007`.
It contains source snapshots, patches, baseline failures, native boundary
diagnostics, exact suite/runtime reports and shortcut witnesses.

These checks cover setup/history/evaluation. They do not approve locomotion,
action readability or active AnimationTree/modifier baking. Operation audit
statuses remain partial until the broader visual and bake gates are complete.

## Engine contracts

Reference contracts: [modifier timing and influence](https://docs.godotengine.org/en/4.7/classes/class_skeletonmodifier3d.html),
[manual skeleton evaluation and signals](https://docs.godotengine.org/en/4.7/classes/class_skeleton3d.html),
[spring reset/collisions](https://docs.godotengine.org/en/4.7/classes/class_springbonesimulator3d.html),
[look-at axes and origins](https://docs.godotengine.org/en/4.7/classes/class_lookatmodifier3d.html),
and [retarget child ownership](https://docs.godotengine.org/en/4.7/classes/class_retargetmodifier3d.html).
