# Rig history repair checkpoints

Unreleased branch: `repair/toolkit-quality`. Engine: Godot 4.7.2.

## First checkpoint: poses, files and chain construction

The actual public Godot AI dispatcher reproduced four failing pose tests and
three failing chain tests. The captured failures include success/Undo actions
for poses matching no bones, malformed JSON/value script errors, overwrite
validation disagreement on dry runs, and duplicate bone names on new-chain
Redo. Code inspection also found ignored 2D pose scale/reset, existing 2D
parent lookup, and omitted scale/skew in subtree conversion.

Repairs:

- Decode pose document shapes and types before typed casts. Require finite
  Quaternion/Vector3 values, nonzero rotations/scales and rest-relative data.
  Normalize supported quaternions and reject nonfinite blend/factor values.
- Refuse a pose matching no target bones before creating history. Resolve
  complete final values before commit; reset-first blending starts at rest.
  Apply and undo complete 2D transforms, including scale/skew and reset bones.
- Check file overwrite before the dry-run return; parse JSON without emitting
  engine errors. Pose files and blended pose data remain non-undoable.
- Rebuild new 3D skeleton bones on Redo, resolve existing 2D parent bones, and
  preserve complete subtree rests. Reject mixed spatial dimensions, invalid
  2D node names and malformed/nonfinite chain transforms before committing.
  A new skeleton defaults to the requested destination basename.
- Plan dry-run chains before allocating Nodes. The precise orphan-ID regression
  reproduced leaked new skeletons/Bone2D nodes even though scene/history checks
  passed. Dry runs now report the same destination path as commits and leave
  orphan IDs unchanged. Invalid or occupied skeleton names are refused before
  allocation, preventing silent engine renames.

### Coverage and verification

- `test_rig_pose_history.gd`: **30 writes** across 2D/3D, local/locked/editable
  instances and apply/blend/reset/reset+blend/mirror variants. Asymmetric
  rotated rests and nonunit poses measure untouched bones and source/peer
  isolation, one scene action, zero global actions, dry/rejected effects,
  permissions and exact persisted Undo/Redo.
- `test_rig_chain_history.gd`: **18 writes** across both dimensions, three
  layouts and creation/append/subtree modes. Rest, pose, hierarchy, metadata,
  enabled flags, ownership and source/peer isolation are checked. Rejections
  must leave scene history unchanged and emit no engine errors. Every dry run
  compares `Node.get_orphan_node_ids()` before/after, including append mode.
- File/read checks cover dry/rejected bytes and histories, pose save/blend/list
  and rig inspection separately. The registry inventory classifies all 14 rig
  and five modifier operations; it does not claim unimplemented matrices pass.
- External `tools/mcp_rig_pose_history.py`: all nine named tests pass before
  and after core reload. Three fresh Godot processes independently check
  **96 saved states**, with no engine errors. These states contain authored
  poses/skeletons, so they are persistence checks rather than clip playback.
- Native visible Godot Ctrl+Z/Ctrl+Shift+Z passes 3D pose, 2D pose and new
  3D chain actions, checked through external MCP.
- Local full editor suite: **278/278**, zero captured engine errors. Four
  existing Bone2D leaf warnings and the deliberate NaN-request serialization
  warning are reported separately. All fourteen local headless suites pass.
- `rig_pose_history` is mandatory in the complete live MCP CI route and retains
  all earlier family gates. The complete fresh-editor external route passes
  locally, including core reload and the 96-state gate. Platform results are
  recorded below.

Source checkpoint `a9319eb` passed
[GitHub Actions run 37441215437](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/37441215437).
All fourteen headless suites passed on Windows/Linux, as did both complete
live MCP routes. All four editor/platform/core combinations (v4.2.1 and main)
passed 277 tests with one optional X Bot asset skip and zero engine/tool-route
errors. The local 278/278 run includes the available asset.

The fixture initially used runtime instancing, which drops native-default
overrides when repacked. It now uses the same
[PackedScene editor instancing mode](https://docs.godotengine.org/en/4.7/classes/class_packedscene.html)
as Godot AI's node creation API; the runtime reopens use ordinary instancing.
Pose/reset semantics follow
[Skeleton3D](https://docs.godotengine.org/en/4.7/classes/class_skeleton3d.html)
and [Bone2D](https://docs.godotengine.org/en/4.7/classes/class_bone2d.html).

## Remaining phase work

The [rig clip five-layout matrix](rig-clip-history-validation.md) and
[source bake playback restoration](rig-bake-state-validation.md) now have
their own completed checkpoints. Active graph/stateful modifier bake
restoration remains open. The [modifier allocation checkpoint](rig-modifier-allocation-validation.md)
covers dry/refusal cleanup, predicted paths and local history integrity.
The five modifier setups still need complete instance creation and supported
reconfiguration history/evaluation coverage, measured at
[modification_processed](https://docs.godotengine.org/en/4.7/classes/class_skeletonmodifier3d.html).
Broader motion/sequence history and fixed-camera visual review remain open.
All operation statuses stay partial; this checkpoint does not approve visuals.

Recovery folder:
`F:/GODOTAITESTING/toolkit_repair_snapshot_2026-09-30/rig_history_20261006`.
