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
| Reconfigure an existing native retarget with non-rest child poses and no persistence helper | Its original Undo scene has no restoration helper; native tree entry clears the authored child inputs. Exact Undo cannot add a helper to the original hierarchy | Toolkit-created retargets, or existing native modifiers whose children use their rest pose |

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
| Individual IK/look-at/twist/spring/retarget variants | 51 |
| Direct target instance and different-rest retarget variants | 2 |
| All five operations on the bundled dummy | 5 |
| Ordered stacks, two final weights | 12 |
| Total | **92** |

The 51 individual variants include existing toolkit/native-rest retarget cases; total
counts are enforced by the explicit ID set in `mcp_rig_modifier_history.py`.
There are **276 saved scenes** played at **30/60/120 FPS**, giving **828 saved
state checks**, plus **276 native reference runs**. Twelve stacks contribute
108 saved-state checks. The editor suite has **15 required named tests**.

The engine checker imports no toolkit handler or test helper. It configures
native references independently from the recorded requests, checks saved
settings and resolved paths, and compares their played results. It observes
raw modifier output, final influence blending through an inert last modifier,
and `skeleton_updated`. Missing states, duplicate/missing IDs, samples or reports
fail the Python gate. Generated scenes can contain the retarget restoration
script described above; this dependency is exercised by the fresh process.

All 720 individual Do/Redo/native runs require influence 0/0.5/1, giving
2,160 weight checks. Retarget has a different engine contract: influence blends
source rest toward source pose before rest-space conversion, rather than blending
the target's authored pose toward its result. A separate geometric calculation
checks local/global conversion, transform flags, motion scale, disabled bones
and different rests. Raw/final/skin poses must agree and source inputs stay
unchanged. The strict report rejects missing weights or the wrong contract.

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

- Initial source `a09c30a`: 14/14 matrix tests, 810 saved states and 270 native
  references pass; full fresh editor 314/314 across 22 suites, no captured
  engine/tool-route/discovery errors. All 14 headless suites pass.
- [CI 37659896020](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/37659896020)
  passes all 34 non-release jobs on that source: Windows/Linux headless,
  four editor/core combinations and both complete 116-gate public routes.
- A stronger all-rig tree-entry check subsequently exposed 12 authored-input
  failures in existing native retarget Undo scenes (two children, two layouts,
  three frame rates), with zero engine errors. The typed refusal above closes
  that unsupported baseline; the supported matrix now includes toolkit-created
  existing modifiers and two native rest-pose cases. Final local regression is
  **315/315** across 22 suites, with **15/15** named matrix tests; the strict
  fresh-process gate passes **828 saved states / 276 native references** with
  zero captured errors. All 14 headless suites pass the guarded source too.
- Native Windows shortcuts: new look-at, spring collider reparenting and
  existing retarget reconfiguration pass exact before/after snapshots.
- Direct external `custom_manage`: all five operations are checked for
  dry/write/save/force-reopen before and after core reload. The attach client
  reconnects after reload and waits for the new fixture's unique sentinel.
- `ci_mcp_route.py` requires the matrix on Windows and Linux. Full suite,
  hosted CI and final preview results are recorded below as they complete.

- Guarded source `04e8754`: [CI 37662645355](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/37662645355)
  passed 33 required jobs, including both modifier history gates. The Windows
  direct modifier reload gate failed while reconnecting to the plugin-managed
  server during restart. Its fixed one-second delay was insufficient. The
  client now waits up to 60 seconds for the authenticated endpoint, a different
  session ID for this exact project and editor readiness. Only connection and
  readiness calls are retried; all required writes run once. Reports require
  both ready connections and all ten operations. The local repeat passes.
- The final weight gate passes locally through Godot AI: all 15 named tests,
  828 saved states / 276 native references / 108 stack states, zero errors,
  and all 2,160 mandatory weight checks. Retarget-only playback passes its
  378 geometric weight checks with zero measured pose discrepancy. The hosted
  result below closes the reconnect/weight follow-up.

The route job now has a 25-minute limit: the prior complete Windows run took
almost 15 minutes. Per-gate deadlines and all required states/IDs remain strict.

Recovery directory:
`F:/GODOTAITESTING/toolkit_repair_snapshot_2026-09-30/modifier_history_20261007`.
It contains source snapshots, patches, baseline failures, native boundary
diagnostics, exact suite/runtime reports and shortcut witnesses.

These checks cover setup/history/evaluation. They do not approve locomotion,
action readability or active AnimationTree/modifier baking. Operation audit
statuses remain partial until the broader visual and bake gates are complete.

## Phase closure — 2026-10-07

Code checkpoint **`623e776`** passes
[CI 37667134975](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/37667134975):
all **34 required non-release jobs**, including all fourteen headless suites on
Windows/Linux, four editor/platform/core combinations and both complete
**116-gate** public Godot AI routes. Each hosted editor run has 314 passing
tests and one optional X Bot asset skip, with zero captured engine/tool-route/
discovery errors. Local editor coverage includes that asset: 315/315.

Decision: the supported modifier setup/history/playback matrix is complete.
All 92 cases, saved states, native references, influence weights and reload
reports are mandatory; the three native limitations remain typed refusals.
Windows/Linux route logs, editor summaries, gate integrity checks, source
hashes, all 276 required saved scenes and local media are in the recovery
directory. The review branch and its existing draft PR remain unreleased.

Next: plan and reproduce active AnimationTree/ordered modifier bake restoration,
including fractional final influence, retarget child poses, stateful springs,
outside-rig properties and late sample failures. Motion/sequence history and
character action visual approval follow. This phase does not close those gates.

## Local playback media

`render_modifier_history.gd` loads the actual saved Godot AI scenes, supplies
controlled authored inputs/target stimuli, and renders the native output from a
fixed camera at 30 FPS. It imports no handler or test helper. Capture contains
840 frames / 28 seconds: all five dummy operations plus IK/look-at/twist and
IK/spring stacks (final spring influence 0.5). No saved fixture is modified.
The left view is the authored input with the modifier inactive; it is a
functional before/after comparison, not footage from the old addon version.

Contact sheets were reviewed for target response, pose transfer, stable bend
direction and spring behavior. IK follows its reachable target, look-at turns
the head with secondary=false, twist distribution is subtle in the mesh but
visible in the bone axes, and retarget transfers the arm input. Springs move
away from the obstacle without an observed divergent response. Synthetic stack
poses demonstrate evaluation order; they are not anatomical character actions.
These previews do not approve anticipation, impact, weight transfer or recovery.

Media lives under the recovery directory's `media/`: `modifier_history.mp4`,
seven contact sheets and `modifier_history_overview.png`. Rendering now captures
errors and exits nonzero; an initial preview incorrectly dropped root targets
and hid the receiver mesh. Those renderer fixture errors were fixed before
the final capture, which has zero captured engine errors. Compose reproducibly
with `tools/compose_modifier_history.py`; no media was uploaded.

## Engine contracts

Reference contracts: [modifier timing and influence](https://docs.godotengine.org/en/4.7/classes/class_skeletonmodifier3d.html),
[manual skeleton evaluation and signals](https://docs.godotengine.org/en/4.7/classes/class_skeleton3d.html),
[spring reset/collisions](https://docs.godotengine.org/en/4.7/classes/class_springbonesimulator3d.html),
[look-at axes and origins](https://docs.godotengine.org/en/4.7/classes/class_lookatmodifier3d.html),
and [retarget child ownership](https://docs.godotengine.org/en/4.7/classes/class_retargetmodifier3d.html).

## Reproduce the matrix

Start a fresh Godot 4.7.2 editor in the configured `test_project`, then run one
mutation client at a time. The local paths/ports below match this checkpoint;
use the active editor session's ports when testing another installation.

```powershell
$taskRepo = 'G:/godot-ai-dev/godot-ai-animation-toolkit'
$taskCore = 'G:/godot-ai-dev/godot-ai-v4-animation'
$taskPython = "$taskCore/.venv/Scripts/python.exe"
$taskGodot = 'F:/GODOTAITESTING/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe'
Set-Location $taskRepo
& $taskPython tools/mcp_rig_modifier_history.py --core-root $taskCore --project-root "$taskRepo/test_project" --godot $taskGod --session-hint test-project --port 18131 --ws-port 18132
& $taskPython tools/mcp_rig_modifier_ui_history.py --mode route --core-root $taskCore --project-root "$taskRepo/test_project" --session-hint test-project --port 18131 --ws-port 18132 --record "$env:TEMP/modifier_reload_report.json"
```

The first command recreates the manifest and all saved states through Godot AI,
then runs the independent engine and strict ID/state/weight report gate. The
second repeats all five operations before/after core reload with fresh clients.
Both commands return nonzero on any required failure. CI executes these inside
the full public-route gate, alongside headless and editor suites.

After generating the manifest, repeat the diagnostic native probes with:

```powershell
& $taskGodot --headless --path "$taskRepo/test_project" --script res://tools/check_rig_modifier_history.gd -- probe_jacobian
& $taskGodot --headless --path "$taskRepo/test_project" --script res://tools/check_rig_modifier_history.gd -- probe_centers
```

These probes are expected to fail on the documented engine limitations; they
cannot approve the supported-operation gate.
