# Motion valid-effect linkage plan (read-only audit, 24 October)

## Exact scope and source

Inspected actual CI596 Linux421 operation-case-results.json under
E:/GodotAI-toolkit-release-2.0.0/20261014/ci-596e278-r001.
Its tested_source is 505cfe195c0687e5cb4a0ad91440faf789b83ba6, not the name of
this worktree or current primary. Nine clip writer keys lack valid_effect:
walk_cycle, run_cycle, idle_cycle, cycle, jump, turn_cycle, strafe_cycle,
walk_start, walk_stop. secondary_motion already has 18 independent valid_effect
passes. character_setup is the tenth missing motion key and belongs to the
other worker's three-channel observer. Do not duplicate or overwrite that work.
Missing is pending, not failed physical motion.

## Smallest reuse route

First join existing raw public events; do not call generation or audit again.
ci_mcp_route.py::motion_gate already runs mcp_motion_remaining_cycles.py then
mcp_motion_audit_saved.py on the SAME run_id/op saved scenes, at 30/60/120.
short_run_gate adds the short-rig default run boundary. The audit driver retains
reduced summary rows, but public-calls JSONL retains full motion_audit responses.
Use these complete responses, not stdout suite totals. Relevant CI421 raw files
include *-d12bef28afe94f76b104bf150217263c.jsonl and
*-f392f06df3bc441bba569a9f4252ac18.jsonl; determine driver/operation on each
actual row rather than naming filenames as an identity oracle.

Every qualifying join must bind context SHA, tested source/dependency hashes,
exact successful generation event ID/request, opened saved scene, player,
skeleton, animation name, save event and intervening mutation-free span, sample
clock and audit request/response. The full generation scene SHA is preferable;
if historical traces lack persisted bytes identity, explicitly leave that join
pending rather than infer equality from a path. Compare inspect.gd and
rig_analysis.gd dependencies separately from producer dependencies. No source
relabel: old artifacts only reuse if exact relevant blobs match.

## Independent criteria by key

| Key | Reusable independent native criterion | Additional proof / limits |
| --- | --- | --- |
| walk_cycle | Existing played world foot slide, penetration, knee pole, hip bob in inspect.gd::inspect_motion_audit | Need nonzero alternating support/foot motion and requested forward travel; contact PASS alone admits static rest. Bind independent request speed/duration, not output key interpolation. |
| run_cycle | Same plus existing run_flight and run_leg_extension checks (clearance >= .02 measured leg, flight >=5%, extension <=.985) | Existing short_run_gate is extra resolver boundary evidence; require finite raw values and original budgets. |
| idle_cycle | Existing contact/penetration and stationary actor proof | Generic contact audit cannot distinguish inert idle. Reuse accepted idle independent native variation/loop/upper-body evidence only if exact source/scene binds. Otherwise minimal additional native observer of rest-relative finite nonzero chest/hips change and loop recovery is needed; threshold must come from existing approved idle gate, not newly chosen here. |
| cycle | Dispatch exact request.preset to walk/run/idle criterion | One walk alias does not prove all presets. History matrix already contains cycle_walk/run/idle; preserve cell scope. |
| jump | check_jump_quality.gd: requested height/apex/flight timing, world travel, contact/recovery and continuity | Generic motion_audit skips jump hip-bob grading and lacks requested apex predicate: cannot alone qualify jump. Reuse jump/candidate-r002 route/native matrices only with exact scene/dependency/request linkage. No generated-key expected curve. |
| turn_cycle | check_turn_quality.gd: request-angle anatomical heading and intermediate stage heading, final feet recovery, stationary actor, support | Existing .001 rad heading, .001 leg endpoint, contact/slide/knee limits unchanged. Generic contacts cannot prove turn angle. |
| strafe_cycle | check_strafe_quality.gd: world requested lateral travel/direction plus contact, crossing, finite continuity | Keep nonlinear intermediate trajectory contract already in checker; do not replace it with constant-speed intermediate position. Existing strafe/candidate-r001 native/controls are candidates, not automatic CI case matches. |
| walk_start | check_start_stop_quality.gd: independent accepted idle/walk endpoint and continuation, forward travel/hold, support | Bind accepted reference scene/clip hashes and source dependency bridge. Existing root .0001m and pose/contact thresholds unchanged. Output seek reference alone establishes playback, not effect. |
| walk_stop | Same, reversed accepted endpoint roles | Keep original terminal hold and no backward travel predicates. |
| secondary_motion | Existing motion_sequence native adapter source/rest reference and noninert mathematical witness | Already passes18; no new generation or physical criterion required. |

inspect.gd lines649-1100 implements played geometry, including raw checks with
values/budgets; lines842-843 explicitly exempt default jump hip bob. Existing
check_motion_remaining_runtime.gd compares native samples to the OUTPUT key:
useful playback/path proof only, never independent valid_effect. Likewise
motion_sequence_native_reference.gd motion output.duplicate is not effect proof.

## Bounded implementation sequence (not implemented)

1. Inventory per-source exact raw generation/save/open/audit joins and required
   values. Emit a small coverage table: independently qualified versus missing
   identity or missing predicate. Preserve all old reports.
2. Add a standalone strict adapter for existing full audit rows; validate exact
   named check set, finite numeric values (bool is not numeric), original budgets,
   sample clocks/roles and both feet. Recompute predicates from observed values;
   do not accept passed/failed_checks alone. Missing role/contact/flight evidence
   stays pending. Scope walk/run contact quality separately from whole effect
   until noninert/requested travel proof is present.
3. Link existing dedicated physical manifests only where immutable source,
   scene/request/rig and native command/report identity prove the SAME case.
   Historical physical cases may qualify their own public event IDs without
   promoting 165 history matrix cells by operation name. No duplicate calls.
4. Only genuine missing independent observations require extending an existing
   native checker; no broad framework or generated expected-key oracle. Root
   executes any necessary native work. Character_setup stays separate.
5. Corruption controls: inert gait/idle; missing foot/flight; wrong sign/distance,
   apex/angle; unrelated scene with same animation name; missing saved SHA;
   wrong source/context/event/FPS; omitted/nonfinite check value; altered budget;
   false passed flag with bad numeric; motion-duplicate oracle mislabeled source.

## Renderer pending execution disclosure

5bc3f82 renderer has only offline validation so far. Root must parse, import UID
cache, run fresh four-second all-operation native preflight before GPU, then
validate all 2400 accepted PNG/native/skin/framing clocks and full encode/decode.
Awaitable observation hooks, process_frame/post_draw freshness and camera fit
are execution gates, not proven behavior. Native mode must create no display
nodes. No known measured runtime defect is asserted without root execution.
