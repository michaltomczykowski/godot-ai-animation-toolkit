# Eight rig clip native raw intention adapters

Bounded increment on top of a6a888f plus root's739c6d1 origin hooks (local
cherry-pick085b784). The new source patch excludes that cherry-pick entirely.
No production, fixed request, fixture, checker threshold or native launch changes.
No Godot/editor/public calls were run by this worker.

## Existing authored contracts, now raw per case

check_rig_clip_history.gd retains all existing native checks/times/thresholds.
It additionally prints each saved scene path/SHA/layout/kind/op/state, generated
clip metadata, actual resolved track path/type/target/bone index, manual-clock
requested time/actual position/assigned clip/speed/process mode, and observed
quaternion/vector/direction values at the already-existing authored sample times.
Expected values never come from generated Animation keys. The report retains
all18original undo/redo states, including two2Dpose_to_clip states; new semantic
qualification selects each original3Dredo case independently.

The standalone operation_rig_clip_native_checks adapter re-derives the original
fixed expectations: rest-relative0->0.6rad arm pose; +/-25deg stride/hip bob;
1.6deg chest/-1deg head and .01hip breath; discrete eye scales; raised jack
arms/hip; held squat hip/ankles at the authored synthetic skeleton rest; alternating
punch forward direction/crouch; and source/input's0.1+0.6t baked hip rotation,
(.02,1.13,0)position and(1.1,.9,1.05)scale. Existing rotation error<.002,
Godot approximate vectors, ankle distance<.003 and punch dot> .95 remain gates.
Additional unit quaternion, exact fixed manual-clock and required path/type
checks strengthen the raw proof without relaxing an original threshold.

Runtime clock fields must match the existing seeked time, generated assignment,
speed1 and MANUAL process2. Each generated track must resolve to the synthetic
Skeleton3D and a real named authored bone, with exact Skeleton:bone path and
3Dposition/rotation/scale type. Required per-operation tracks cannot be omitted.
The native renderer never loads toolkit/test scripts to calculate expectations.

## Exact public and saved origin join

mcp_rig_clip_history.py executes exactly the existing five native subprocesses
with their original commands/45s timeouts. After each completes, it records eight
raw native events, one exact3Dredo scene per operation. The full native output,
return code, stderr and actual command are retained, including failures.

The adapter selects the one matching operation/layout/kind/state/path row from
the report, then requires exactly one rig_scene_history_v1 original inner-dispatch
row with the same operation/layout/3Dkind and persist_redo path/SHA256. It reuses
operation_rig_scene_history_checks.verify_event to bind the real fixed request,
actual response/history/source witness and public test_run begin/end/scene/test.
Native completion must follow actual public suite completion. Engine command and
source dependencies must match the context. An18-state count or green suite
total cannot replace missing per-case raw values or a missing producer.

The new native case derives valid_effect, track_paths_types and playback only.
The original739c6d1 history validator separately owns its observed checks. This
adapter adds no broad source, editor error, history or visual approval. Any failed
origin check/native error/failed case or nonzero native exit remains failure.
There is no external per-operation MCP invocation claim: the producer is an
identified actual inner dispatch in a real public test_run.

## Scope and pending verification

All eight cases are the existing synthetic UNskinned fixtures. Expected ankle
positions are relative to that authored skeleton, not physical floor grounding.
No skinned mesh quality, target-character/gait/media approval or broadened input
support is inferred. Other types/layouts/times are outside the fixed case scope.
Actual Godot4.7.2 parse/native/public CI for this increment remains PENDING.

12new offline tests pass, including40operation/layout positive cases and actual
value/clock/path/type/source/SHA/scene/public-result/command corruption controls,
missing raw cases despite total18, inert/nonfinite observations, original threshold
boundary failures and retained native errors. Existing4 rig scene origin and15
collector controls pass; Python driver/adapter compile. These are synthetic
controls, not runtime qualification.

## Integration

First integrate root739c6d1 and its rig_scene_history_v1 collector hook. Then apply
this increment's source-only patch and minimal native collector patch against
2613e36bc99419541ac0ab8a6d3d41ee4f96902a. The patch preserves other workers'
collector dispatches. Full own-worktree collector replacement is inappropriate.

The original739 docs collector patch no longer applies verbatim to2613 context. Its rig_scene_history_v1 dispatch was inserted identically in an isolated2613 collector copy; the native-only patch then applies cleanly. Root should retain its actual rig scene dispatch while integrating this native-only branch. Original _check callsites independently compared unchanged.
