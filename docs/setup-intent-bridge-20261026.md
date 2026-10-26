# Scoped setup intent bridge and three-play fallback

Offline implementation only. Nine focused Python tests pass, including actual
hash-bound historical rows/traces, exact dependency/source audit, wrong
group/request/scene/spec/speed/sign/dependencies, falsely green physical metrics,
missing clocks/feet, changed prepared model and exclusive offline staging.
No worker engine/server/ffmpeg launch, production edit or push occurred.

The selected group is `responsive-extracted-stationary-no-turn`, bundled dummy.
Original request: character_setup on `/RepairRigFixture/AnimationPlayer` and
`/RepairRigFixture/Dummy/Skeleton3D`, include_jump true, include_turn false,
active false, root_motion true. The native playback input is the fixed explicit
blend specification speed0.410319762167571m/s, six seconds, controller speed0.
Expected signed travel comes from that playback command and measured rig frame,
never response `speed_values` or native `expected_world_distance_m`.
It does not certify how omitted default walk/run speeds were selected.

Actual provenance is longer than the prior shorthand:

| Role | Source |
| --- | --- |
| Original public producer, production-r003 | c19a25e3ea7e574361c239d254e3f45528121795 |
| First route reuser, production-r004 | 233ad02853e74cbd21327954fe4f2086c34faf1d |
| Second route reuser, production-r007 | 233562a776bf8deac6177cf9b67cbe2ae1efdedf |
| Historical native executor, native-matrix-r009 | 54744b138f0767da317f0f4eeac90e58cf478768 |

The r009 native report `source_head` echoes the r007 route source. It does not
identify the native executable source. Original matching trace events are
`3997ef950c1b425cbc94d5b223e4904d-00c2242597134bcdb39200a2ae05d8f9:2`
(independent profile), `:16` (actual write), `:25` (save), `:26` (forced reload).
The auditor pins original context/trace/route/matrix/report/log bytes and checks
the entire route reuse chain. It retains r004's unrelated overall matrix failure.
The selected original scene SHA256 remains
`209136530e6cc93db46d4ebb31c7012f41806350d5cccae10b4bd917320c7412`.

All three public matrices and r009 have the same613 production hashes. The
auditor verifies all46 toolkit sources at all four historical commits, native
checker dependencies at54744b1, and all567 core files against released421 commit
bfc264200584ea5823f18356acb164781f57796d and the actual current core checkout.
Current toolkit comparison is44 exact, two explicit known changes: rig_pose_list
typed-directory refusal and private Spring bake cache priming. It records their
exact before/after hashes, source diff and scoped non-use rationale, plus the
new Spring helper/UID. Unknown changed/missing/extra dependencies refuse.

Historical runtime receipts hash checked-out Windows CRLF bytes. Those runtime
hashes remain exact. Git source verification explicitly permits LF versus CRLF
serialization only; it never transforms physical observations or substitutes
canonical source hashes for runtime hashes. Use the primary Windows checkout
as `--repo`; a separately checked-out LF worktree is not byte-identical runtime
evidence and is deliberately refused by the exact inventory check.

The old public context and r009 report omit contemporaneous FBX/imported-cache
and rest hashes. Committed original/current model source bytes agree, but this
does not bind actual historical loaded rig bytes. Therefore the read-only
auditor emits historical numeric PASS and candidate valid_effect PENDING.
It does not close the seventh gap using old green flags or1800-play totals.

The minimal fallback stages the unchanged original scene and four current
inputs in an exclusive new minimal project: existing setup checker, grounding
helper, its motion-space dependency and exact original FBX. It copies original
FBX import settings and script UIDs, copies no import cache, and disables no
saved writers or physical checks beyond the existing checker schedule.
Only the root operator runs its three subprocesses: exact official version,
fresh native model import, then three30/60/120FPS plays of one explicit spec.
No public regeneration or1800-play repeat. Version/import/native PID, command,
timeout, monotonic timing, raw logs and completion receipts persist. Timeout
terminates only its own child, preserves failure and refuses retry.

Before and after playback it verifies copied scene/model/checker/helper/config
bytes and the freshly generated import cache. Numeric recomputation checks
every signed extraction step and cumulative position against requested speed,
actual elapsed clocks and world distance, native final signals, bilateral
ground/contact/knee/slide budgets, grounding residual/reach/correction,
noninert continuity, ownership and the exact no-reset/no-take schedule.
The resulting proof keeps all original identities and records the fresh
candidate native executor separately. It emits valid_effect PASS only after
those checks; original r009 rig hash limitations remain stated explicitly.

Root commands from the primary repository, with a fresh `$attempt`:

```powershell
$python = 'G:/godot-ai-dev/godot-ai-v4-animation/.venv/Scripts/python.exe'
$repo = 'G:/godot-ai-dev/godot-ai-animation-toolkit'
$core = 'G:/godot-ai-dev/godot-ai-release-core-4.2.1'
$setup = 'E:/GodotAI-toolkit-release-2.0.0/20261014/setup'
$project = 'E:/GodotAI-toolkit-release-2.0.0/20261014/validation'
$godot = 'F:/GODOTAITESTING/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe'
& $python tools/run_setup_intent_replay.py prepare --repo $repo --core-root $core --setup-root $setup --project-root $project --output $attempt
& $python tools/run_setup_intent_replay.py run --prepared $attempt --godot $godot
```

Read-only audit alone (preserves its prior output):

```powershell
& $python tools/audit_setup_intent_bridge.py --repo $repo --core-root $core --setup-root $setup --project-root $project --output $newAuditJson
```

Offline controls, workdir `tools`:

```powershell
& 'G:/godot-ai-dev/godot-ai-v4-animation/.venv/Scripts/python.exe' -m unittest -v test_setup_intent_bridge
```

No collector files changed. The standalone `setup-intent-proof.json` is a scoped
historical/public plus fresh-native bridge with candidate metadata and raw
receipt paths/hashes, not a fabricated fresh public operation event. Root's
phase5 integration must preserve that distinction. Other rigs/styles, setup
jump/turn/reset/take behavior, visual and Linux qualifications remain outside
this one fixed effect proof.
