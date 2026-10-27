# Five bounded public read response hooks

Isolated implementation after58f3dda; integration target frozen root233562a.
No production/fixture/request/threshold changes and no Godot/public calls.
No changes to the corrected inspect dry_run code map or preview contracts.

## Actual sources and added observations

- mcp_inspect_3d.py: preserve original rig_profile(save=false), eight-paired-foot
  sample, 120-sample motion_audit, preview and invalid-skeleton requests.
  Emit full raw response/refusal rows for the three reads after the existing
  before/after describe calls. Preview retains its existing separate contract.
- mcp_rig_pose_crud.py: preserve original pose_list at the point where exactly
  rest/arm were saved and half was not yet created. Capture exact UTF8 pose-file
  bytes/content/SHA256 immediately before/after list and monotonic bracket times;
  retain actual original pose_save requests/results as producer support.
- mcp_rig_pose_apply_audit.py: retain the full already-existing rig_get response
  after the fixed0.6rad upper-arm pose_apply instead of keeping only its arm
  projection. Add one necessary rig_get missing-skeleton refusal. Existing pose
  apply/dry/save/reopen/invalid requests and assertions remain unchanged.

The new bounded_read_v1 raw snapshot event is independently recomputed by
operation_bounded_read_checks.py. The adapter binds exact driver, operation,
request, scene, actual public call/response, ordered refusal, actual scene open,
producer calls, describe observations, context dependencies and event order.
Per-case output IDs identify those exact public/support events; no suite total
creates a pass. Pose directory byte observations must bracket the actual list
call. Dynamic paths are confined to the existing exact timestamped driver forms.

## Checks and explicit pending scope

rig_profile valid_effect checks the authored dummy's56bones,3D/path, exact
hips/thigh/foot names, walk capability, no missing locomotion roles and saved="".
It does not prove absence of all file writes from a response field alone.

rig_get valid_effect checks all56 distinct bone names against literal Model
names independently extracted from the committed public HumanCharacterDummy_F
FBX; validates index/parent/vector/quaternion shapes and finite components; and
requires the actual B-upperArm.L rest-relative quaternion to match independently
specified sin(0.3)/cos(0.3) and zero position. The exact prior fixed pose_apply
request and actual successful response must be present. This is the applied arm
readback plus full-name/shape contract, not independent numeric verification of
all rest transforms. Imported FBX settings are generated/ignored and are not
misrepresented as a committed dependency. The source FBX itself is explicitly
bound; private XBot is never used.

pose_list valid_effect checks exactly arm/rest, correct directory/path/source,
56bones per entry, and matching original pose files with56authored bone names,
valid pose format/version/rest-relative markers, exact UTF8/content hashes and
before/after byte equality. Actual successful original rest/arm pose_save calls
must precede listing. This proves listing the known files, not pose generation.

sample and motion_audit valid_effect remain PENDING even when their original
structural predicates pass: count8/times0..1/finite paired-foot positions and
120-sample support trace/counts/finite extrema. Malformed or missing data fails.
No independent FK or played-contact numeric reference was added. Their counts
or passed=true flags alone cannot establish correctness.

Four missing-skeleton typed_errors use exact NODE_NOT_FOUND. pose_list
 typed_errors remains PENDING: the actual handler intentionally returns successful
exists=false/zero poses for a missing directory; no typed refusal was observed.

ALL FIVE source_unchanged and reported_errors remain PENDING. A describe clip
snapshot and pose-directory hashes cannot establish live Player/pose/history/
whole-scene invariance or complete engine error cleanliness. No file_effect,
playback, visual_review, audible-output or candidate qualification is inferred.

## Offline verification and integration

12new tests pass: all five rows with correct pending states, authored FBX name
constant check, corrupt/missing/wrong-source/scene/request/call/dependency/claim,
wrong role/arm quaternion, nonfinite sample, inconsistent audit counts, changed
pose bytes/content/hash and missing producer/timing controls. Existing15collector
and13inspect-adapter tests pass. Python compile of modified drivers/adapter passes.
Historical233ad02 actual Windows421 raw responses were read only for compatibility:
profile matches, sample/audit remain pending, and rig_get before/dry vs after/
persisted distinguishes the fixed arm quaternion. Historical data is not relabeled
or promoted to the candidate. Root must execute fresh public CI for these hooks.

Use the source-only patch excluding collector/FIX_ROADMAP plus the minimal
collector patch against233562a. Add repair_motion_fixture/repair_rig_fixture and
publicFBX to source context; preserve any other worker's added fixture/binary
bindings. No full collector replacement and no old inspect error-map replacement.

Oct23 resume: all12new +15collector +13inspect tests rerunPASS; modified Python sources compile. Minimal collector patch applies cleanly to an isolated exact233562a collector copy. This is offline patch validation, not Godot or public qualification.
