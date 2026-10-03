# Animation Toolkit repair roadmap

Started 2026-09-28. This is the working repair plan and phase log for the
unreleased `repair/toolkit-quality` branch. `ROADMAP.md` records the older
feature/release history; it is not evidence that a feature works today.

## Goal and rules

Make this a dependable procedural animation tool suite **through Godot AI's
public custom-tools API** on Godot 4.7.2. A successful handler response must
produce its documented effect after save, reopen and playback. An operation
that does not pass its contract is hidden from discovery and returns a typed
unavailable error to stale callers. No tag, release or media upload is part of
this repair.

The primary acceptance route is an AI/MCP client -> Godot AI server -> active
editor session -> toolkit handler -> saved Godot scene. Direct GDScript calls
and editor-dispatch smoke tests are useful diagnostics, not substitutes.

Each phase below must record its changes, exact tests, failures, remaining
risks and decision before it is marked complete. Work sequentially. Keep the
branch reviewable and do not merge or release while a required gate fails.

## Baseline (2026-09-28)

- Toolkit HEAD: `735706d`, branch `repair/toolkit-quality`, with substantial
  uncommitted work from the interrupted attempt. Preserve it while auditing.
- `test_project` links Godot AI checkout `godot-ai-v4-animation` at `eefd4fe`.
  The real project `F:\GODOTAITESTING\godotaitesting` links `godot-ai-v4-theme`
  at `102aad4` and currently enables only Godot AI, not this toolkit.
- Working-tree registry: 10 families, 103 family-qualified operation entries
  (102 distinct names; `walk_cycle` occurs in rig and motion). Eight families
  are promoted; `animation_rig_modifiers` and `animation_sequence` require
  `custom_manage`.
- Fourteen tier-1 headless suites pass locally. The editor suite has 203 tests,
  one failure in `test_motion_audit_grades_planted_feet_and_hips` after an
  unfinished playback-audit change. The new 103-op route probe supplies only
  `{op, dry_run: true}` and therefore does not establish functional success.
- The flykick builder edits and rendered frames are diagnostic work, not the
  repair target. Do not use them as a quality gate until the toolkit itself
  meets the contracts below.

## Phase 0 — preserve and measure the baseline

**Plan:** Inventory HEAD versus uncommitted changes; preserve a recoverable
snapshot; classify each change as integration, shared animation engine,
tests/docs or demo. Reproduce both headless and editor results before further
edits. Record what is installed in the real project and which core checkout
each fixture uses.

**Exit:** A baseline report with command output and a safe path for every
existing change. No user work is silently discarded.

**Status:** Complete 2026-09-28. Snapshot and test evidence below.

## Phase 1 — Godot AI integration and tool contracts

**Plan:** Fix typed batch registration; verify actual MCP `tools/list`, the
eight promoted names/schemas, all registered names via active-session
`custom_manage`, invalid-input typed errors, disable/re-enable, core reload,
and `tools/list_changed`. Exercise both core checkouts and then install the
toolkit in the real project. Implement quiescence for completed handlers and
correct per-operation write/undo behavior: file writes cannot promise scene
UndoRedo rollback, and inspection writes must respect editor readiness.

**Exit:** A model-facing tool can discover and invoke a valid operation in the
real project. A stale/disabled/missing operation fails with a typed reason.
Core update preparation succeeds after finished toolkit calls, and fails only
while a genuinely active deferred call needs to finish. Batch rollback cannot
claim to undo file side effects it leaves behind.

**Status:** In progress. The live MCP catalog, fixture invocation, real-project
installation, core reload, direct-backend disable/re-enable notifications and
rollback pass on Windows. The pinned-core registration/reload route also
passes in Windows/Linux CI. Stdio attach notification forwarding and the
remaining real-project/core combinations remain to verify.

**Execution order:**

1. Add and test handler quiescence. Synchronous handlers can report idle after
   a call; the deferred preview must track its own live render and report busy
   until it sends the final response, including after a transport timeout.
2. Make family metadata conservative. An `undo=true` batch must reject a
   family containing direct file writes until its operations are split by
   effect or those writes become genuinely reversible. Gate `rig_profile`
   saves and PNG preview writes while the editor is playing/importing.
3. Use the live Godot AI server and MCP client, not `_dispatcher._dispatch`,
   to check tool list/schema, active-session list/invoke, disabled/stale calls
   and tool-list updates. Run against both local core checkouts.
4. Install/enable the toolkit in the real project only after the fixture MCP
   checks pass; repeat a harmless read and a valid undoable clip operation
   there, save/reopen, and check undo. Keep the real project's existing scene
   intact by using a dedicated repair fixture scene.

## Phase 2 — operation contract and honest discovery

**Plan:** Generate an audit matrix from the registry, one row per
family-qualified operation. Each row contains valid invocation fixture,
claimed effect, result/error shape, target paths and types, dry run, undo/redo,
save/reopen, playback or other effect assertion, and platform. Add operation
status to the single registry: supported or unavailable with a reason. Both
schema choices and handler dispatch must use that status. Enforce resource
budgets before allocation or mutation; start with motion duration × samples.
Fix shared commit/spec failures before individual families.

**Exit:** Every advertised operation has a passing effect contract. Stale
callers to unavailable operations get a typed error, never a false success.
The matrix is produced by CI and identifies uncovered operations explicitly.

**Status:** In progress. A 103-row operation evidence ledger and generated
audit exist; all rows remain partial until visual, per-operation undo and
Linux gates are satisfied. The motion allocation limit and jump-distance
fix pass on Windows. Live Godot AI dry/write/save/reopen and typed-error
evidence covers the families, while gaps remain visible in the ledger.

## Phase 3 — character motion and a trustworthy evaluator

**Plan:** Validate roles, rest pose, axes, proportions, reach and coordinate
conversion before generating. Require explicit mapping when detection is
ambiguous. Use one typed, rest-relative pose-at-time representation for
generation, composition, preview and audit. Evaluate audit/preview on an
isolated character, with engine interpolation and AnimationTree playback
parity; preserve all editor state. Give root translation one owner and check
AnimationMixer extraction. Rebuild stance/swing timing, reachable foot
targets, knee poles, pelvis weight shifts, starts/stops, turns, strafes and
jumps. Fix explicit jump height/crouch alias scaling on non-reference rigs.

**Exit:** Bundled dummy, available X Bot and independent synthetic rigs pass
at 30/60/120 FPS on a level surface: stance slide <= min(2% leg length,
3 cm), penetration <= 1% leg length, no knee flips or loop discontinuities.
Idle/walk/run/start/stop/turn/strafe/jump playback and root-motion extraction
are measured. Fixed-camera contact sheets pass human visual review for
anticipation, impact, weight transfer and recovery.

**Status:** In progress. Root extraction and private played contact audits
cover the bundled dummy, X Bot, half-size and Z-up tall rigs at 30/60/120
FPS. The strafe now has a played foot-crossing check. Walk visual quality,
reach clamps, loop/pose quality, full action review and Linux remain open.

**Next visual-quality subphase:** Preserve fixed-camera continuous clips of
the current defaults on all four rigs, with front and side views and a
contact/COM overlay, before changing keys. Redesign strafe as a leading-foot
placement followed by trailing-foot recovery: move the pelvis over the
support foot before toe-off, let the leading foot travel beyond the original
ankle width without crossing, and give the trailing foot a separate swing
window. Do not use the current symmetric forward-gait span cap as the sole
side-step design. Re-run all 30/60/120 FPS contact, crossing, reach and loop
checks, then compare continuous playback and sheets. Next tune walk torso
pitch and run flight/support timing by the same visual and numeric cycle.

## Phase 4 — sequencing, graphs and remaining families

**Plan:** Make character-owned action sequencing a supported operation only
after boundary, overlap, gap, pose, root-motion, contact-marker and output-key
budget tests pass. Prevent multiple mixers from driving the same bones.
Check graph baselines and active playback ownership; clip edits against
Godot's interpolation; modifier wiring and post-mixer timing; and UI/FX
previews. Resolve each failed operation or mark it unavailable.

**Exit:** The operation matrix is green for all supported families, including
saved-scene replay and one-step undo where promised. Representative output
from every family has a recorded visual/effect review.

**Status:** In progress. Eleven graph scenarios have live MCP save/reopen and
dry-run checks; ten saved graphs have fresh-process AnimationTree playback
evidence. All five rig-modifier operations have measured saved playback, and
all 16 advertised FX operations have saved runtime checks in Windows/Linux
CI. All 20 clip edits have played interpolation checks in Windows/Linux CI.
All nine presets and seven library operations have live route checks in both
platforms; saved playback covers the eight standalone presets, showcase's
seven players, and both library-applied clips.
Sequence compose has a live MCP save/reopen and played-bone check; its
boundary, gap, pose and ownership review remains open.

## Phase 5 — agent usability, CI and review

**Plan:** Run task prompts with the connected coding model through the live
Godot AI MCP surface. Capture discovered tools, selected operation, parameters,
typed failures, resulting scene and revision attempts. Simplify the promoted
surface if the model cannot use broad family schemas reliably. Run headless,
editor, registration, full MCP and playback gates on Windows and Linux against
the pinned core and current compatible core. Update docs to match the audit,
remove unsupported claims, and deliver a reviewed, unreleased branch with
before/after media and the operation matrix.

**Exit:** Representative user intents complete through Godot AI without manual
GDScript authoring. All required CI gates pass and review evidence is attached
to the branch. No release action is taken.

**Status:** Pending. "Space Bunny Alpha" identifies the coding agent that
produced much of the earlier work; it is not a toolkit runtime dependency.

## Phase log

### 2026-09-28 — roadmap created

- **Changes:** Added this repair roadmap. No phase has been declared complete.
- **Evidence:** Local branch, addon junctions, registry, test outputs and
  GitHub/Godot AI core audit from the planning pass.
- **Known failing gate:** Editor motion-audit test (1 of 203 failures).
- **Next:** Preserve baseline and produce the operation/change inventory.

### 2026-09-28 — Phase 0 complete

- **Preservation:** The pre-phase tracked diff was saved with `git diff
  --binary` to `F:\GODOTAITESTING\toolkit_repair_snapshot_2026-09-28\tracked.patch`
  (617,540 bytes). All eight then-untracked files were copied under that
  snapshot's `untracked/` directory, including `HANDOFF-flykick.md`. The
  working tree was not reset or stashed.
- **Change inventory:** Integration candidates are `plugin.gd` (typed batch
  registration) and the CI plugin (editor dispatcher probes). Engine changes
  are `handlers/inspect.gd`, `handlers/motion.gd` and their tests. New but
  unverified sequencing is the registry change plus
  `handlers/sequence.gd`, `spec/sequence_specs.gd`, the generated op index and
  one editor test. The six demo scene UID edits, flykick scene/builder, and
  README/ROADMAP wording are separate demo/documentation work. None was
  silently discarded.
- **Tests:** `tier1.log` in the snapshot records 14/14 suite passes, exit 0.
  `editor.log` records 203 editor tests, one failure, exit 1:
  `animation_inspect/test_motion_audit_grades_planted_feet_and_hips` says the
  left foot never contacts the ground. The route probe reports 10 families
  and 103 operation-name dry-run routes, both before and after simulated core
  registry loss. It does not use the Python MCP server.
- **Project installation:** The toolkit test project has both addon junctions.
  `F:\GODOTAITESTING\godotaitesting` has only a Godot AI junction and enables
  only `res://addons/godot_ai/plugin.cfg`. The real project's core is the
  `godot-ai-v4-theme` checkout; the toolkit fixture uses
  `godot-ai-v4-animation`. Their custom-tool registry API was verified as
  identical in the read-only audit, but no end-to-end MCP invocation has been
  proved against either project.
- **Decision:** Proceed to Phase 1 with the editor failure visible. Do not
  treat the 103-op route probe or the demo render as acceptance evidence.

### 2026-09-28 — Phase 1, tool lifecycle and conservative metadata

- **Changes:** Added `quiesce_for_script_swap()` to the shared synchronous
  handler base. `animation_inspect` counts pending deferred preview renders
  and refuses quiescence until the final response is sent. Editor CI now asks
  the actual Godot AI dispatcher to quiesce after materializing all toolkit
  handlers; a suite test checks the pending-preview guard.
- **Changes:** Marked `animation_library` and `animation_rig` as not batch
  undoable while they mix scene actions with direct file writes. Their direct
  scene operations retain their own undo behavior; `batch_execute(undo=true)`
  now rejects these families before running anything. Added a preflight check
  for both families to editor CI. `animation_inspect` checks editor readiness
  before profile/preview file writes and rejects preview dry runs without
  creating PNGs.
- **Tests:** Editor route and quiescence checks pass twice (initial and after
  simulated registry removal). 204 editor tests run, with only the previously
  recorded motion-audit failure. The Phase 1 MCP/server and real-project gates
  remain open.
- **Risk/next decision:** Family-wide `undoable=false` is intentionally
  conservative. Phase 2 should split file operations into a non-undoable
  family or provide a genuinely reversible file transaction before restoring
  batch undo for the remaining rig/library operations.

### 2026-09-28 — Phase 1, live Godot AI route and real project

- **Changes:** Added `tools/mcp_probe.py` to inspect the MCP catalog and call
  both promoted and `custom_manage` routes. Its port parameters are required:
  the running editor used HTTP 18131 / WebSocket 18132. An initial run against
  the probe's former 8000/9500 defaults found zero sessions; this was a probe
  configuration error, not a toolkit registration failure.
- **Tests:** Against the fixture's connected Godot AI server, `tools/list`
  exposed all eight promoted family tools with an `op` schema property;
  `custom_manage(list)` exposed all ten families. A promoted
  `animation_inspect.describe` call returned two real clips. Unknown ops on
  promoted inspect and unpromoted sequence returned `VALUE_OUT_OF_RANGE`.
  `editor_reload_plugin` returned `reloaded` with a new session id, after
  which the same list and inspect checks passed.
- **Real project:** Backed up `project.godot` in the Phase 0 snapshot, linked
  the toolkit addon into `F:\GODOTAITESTING\godotaitesting` and enabled it.
  Added only `repair_toolkit_fixture.tscn`; the existing main scene was not
  changed. `tools/mcp_real_fixture.py` activated this project's Godot AI
  session, opened the fixture, ran a valid `animation_presets.pulse` dry run
  and write, saved, forced a disk reopen and re-inspected the clip. The saved
  result has a resolved `Target:scale` value track and three keys. The real
  project uses the separate `godot-ai-v4-theme` core checkout, so this also
  checks the toolkit against both local core versions.
- **Remaining Phase 1:** Verify disabled/stale tool behavior and MCP
  `tools/list_changed` notification, plus an actual rollback test. Run this
  integration on Linux in CI after the contract tests are added.

### 2026-10-01 — Phase 1, live enable/disable and motion undo

- Godot AI 4.1.0's visible Tools settings displayed all 10 registered
  toolkit families. Disabling `animation_edit` immediately changed the
  enabled count to 9/10. A live MCP client then found the promoted tool
  absent from `tools/list`, the family absent from `custom_manage(list)`,
  and a stale `custom_manage(invoke)` call returned typed
  `CUSTOM_TOOL_DISABLED`. Reenabling it restored 10/10 and both routes.
- A persistent MCP client connected directly to the Godot AI HTTP backend
  received two `tools/list_changed` events, with the correct absent/present
  tool lists after the toggle. The ordinary stdio `attach` client saw the
  lists change on new requests but received no event on its existing
  connection. Core `attach` creates a new downstream backend session for
  each proxied request; forwarding backend list-change notifications remains
  a Godot AI core integration gap, separate from toolkit registration.
  `tools/mcp_tool_list_watch.py` can reproduce both transports. The UI
  finished with 10/10 toolkit families enabled.
- Created a fresh scene through the actual Godot AI route and generated a
  `walk_start` clip with 21 tracks. Godot editor Ctrl+Z removed it; MCP
  `animation_inspect.describe` returned `INVALID_PARAMS` because no clips
  remained. Ctrl+Y restored the same 21-track clip. Logs
  `mcp_motion_ui_undo_setup.log`, `mcp_motion_ui_undo_after.log`, and
  `mcp_motion_ui_redo_after.log` are in the recovery snapshot. This checks
  the shared motion commit's one-step undo/redo. Per-operation undo coverage,
  Linux CI and the stdio notification gap remain open.
- `tools/mcp_batch_rollback.py` exercised the actual Godot AI
  `batch_execute(undo=true)` route in a fresh scene. A valid toolkit
  `walk_start` committed first; a second invalid motion op stopped the batch.
  Core reported one success, failure at command 1 and `rolled_back=true`.
  Toolkit inspection found no clip immediately afterward or after save and
  forced disk reopen. The same route rejected file-writing
  `animation_library` and mixed-effect `animation_rig` families up front
  with typed `CUSTOM_TOOL_NOT_UNDOABLE`. Windows log:
  `mcp_batch_rollback.log` in the recovery snapshot. This verifies the
  conservative family metadata without claiming individual file writes are
  undoable.

### 2026-09-28 — Phase 2, first shared failure controls

- **Changes:** `animation_motion` now rejects a request above 1200 sampled
  intervals before building clip keys. Top-level jump `height` and `crouch`
  aliases now count as explicit metre values when scaling defaults for a rig.
- **Tests:** Two new editor tests for the allocation rejection and jump
  scaling pass. Editor suite is now 206 tests, still with exactly the baseline
  `motion_audit` failure. The route probe again passes ten families and 103
  operation-name dry-run routes before and after simulated registry loss.
- **Diagnosis:** The failing generated root-motion walk had zero detected
  contact time on both feet. Its audited left-foot world height was around
  0.20 m through the expected stance against a rest-ground estimate of
  0.116 m, with further discontinuities later in the cycle. This points to
  the generated/evaluated pose and contact baseline, not a test assertion
  typo. Keep this gate red until isolated playback and foot placement agree.
- **Root-motion isolation experiment:** Temporarily clearing the player's
  `root_motion_track` during the same test made the left stance foot return to
  its 0.116 m rest-ground height with 0.9 mm reported slide; with extraction
  enabled it stayed around 0.20 m and contact vanished. The current generator
  uses the **hips position track** for both pelvis pose and extraction.
  Godot removes that track from the rendered pose when it is designated as
  root motion, invalidating the leg solve. The Phase 3 repair must author a
  separate character-root translation track, keep hips bob/sway local, and
  solve feet in the extracted frame. This is a concrete cause of the red gate.
- **Inventory:** `tools/gen_operation_audit.ps1` now exports
  `docs/operation-audit.json` from the registry and reviewed evidence in
  `docs/operation-evidence.json`. It contains 103 rows and currently zero
  fully verified operations. `animation_presets.pulse` and
  `animation_inspect.describe` carry their limited MCP evidence as `partial`;
  every missing check remains `pending`. This inventory is intentionally not
  an acceptance claim. Fourteen tier-1 suites still pass.

### 2026-09-28 — Phase 3, separate root translation and planted swing

- **Cause and change:** Godot removes the configured root-motion track from the
  rendered pose. The old generator used `B-hips` for both pelvis bob/sway and
  travel, so extraction removed the pose the leg IK had solved against. Rooted
  gaits now keep hips local and key a separate `Node3D:position` track owned by
  the character. `animation_motion.character_setup` wires the same path to
  its AnimationPlayer and AnimationTree. The rooted foot target subtracts
  extracted travel during stance and delays world-space swing translation
  until after lift, finishing it before lowering.
- **Evidence:** The editor suite now passes 208/208 tests, including
  AnimationPlayer root-motion playback and stance/penetration checks at
  30/60/120 FPS plus AnimationTree extraction. Fourteen tier-1 suites pass.
  A live Godot AI MCP client built a 120-sample rooted walk and run, saved and
  force-reopened each. The played `motion_audit` measured walk slide of 1.1 mm
  left / 1.0 mm right and revised run slide of 0.9 mm left / 3.1 mm right;
  body travel persisted. Earlier live values before swing correction were
  51.1 mm / 59.6 mm for the walk. These are measurements on the bundled dummy,
  not claims for X Bot or arbitrary rigs.
- **Visual review:** Rendered fixed-camera 60 FPS frames under
  `F:\GODOTAITESTING\toolkit_repair_snapshot_2026-09-28\media\walk_review`
  and `...\media\run_revised` using a local floor/reference scene and a
  script applying the extracted delta. The walk has readable alternating
  contacts and continuous travel. The run remains a broad, stylized stride;
  its default knee bend, lift, lean, arm swing and stride were reduced after
  seeing the first render. The revised run is still a limited review on one
  rig, not full visual acceptance.
- **Regression fixtures:** Backed up the old walk, run and spec-walk golden
  JSON in the Phase 0 snapshot, then regenerated only those three after the
  intentional motion change. The editor suite and tier-1 suite pass with the
  revised fixtures. The operation matrix records walk/run as `partial` and
  remains at zero fully verified operations.
- **Next:** Make `motion_audit` inspect an isolated character so read calls
  cannot trigger scene tracks or leave pose state. Validate the new root owner
  and stance thresholds on X Bot and synthetic rigs, then expand visual review
  to idle, start/stop, turn, strafe and jump. Keep the run's broad stride in
  the review log until it is accepted on those rigs.

### 2026-09-28 — Phase 3, isolated motion audit

- **Change:** `animation_inspect.motion_audit` now evaluates a private
  `SubViewport` scene copy. It strips game scripts, disables competing
  AnimationTrees, and accepts only 3D transform tracks. Godot reconstructs
  instanced scene children during duplication, dropping unsaved libraries and
  mixer settings and collapsing an imported skeleton axis in this fixture.
  The evaluator therefore copies the live animation libraries, root-motion
  setting and node transforms into the private scene before playing the clip.
- **Tests:** Added assertions that the edited skeleton pose and AnimationPlayer
  clip/playhead survive the audit, plus a method-track rejection check. The
  editor suite passes 208/208, including 103 operation-name dispatcher routes
  before and after simulated registry loss. A fresh Godot AI editor session
  built a rooted walk through MCP, audited it before saving and after force
  reopening, and passed both; the persisted walk travels 1.0801 m with
  1.1 mm left / 1.0 mm right worst stance slide. Output is in
  `F:\GODOTAITESTING\toolkit_repair_snapshot_2026-09-28\mcp_motion_private_audit.log`.
- **Remaining:** The audit still needs penetration, reach and continuity
  checks, independent rig coverage and visual approval. The private-copy
  technique must be checked against larger real scenes; it is presently
  validated on the bundled dummy.

### 2026-09-29 — Phase 3, X Bot and stable knee pole

- **Rig coverage:** Added the supplied 1.75 MB `X Bot.fbx` to the test
  project. Godot 4.7.2 imported its 65-bone Mixamo skeleton. Name detection
  now maps `LeftLeg`/`RightLeg` to shin roles after `UpLeg` maps to thighs.
  An editor test builds and audits a rooted X Bot walk at 30, 60 and 120
  sample rates. A live Godot AI MCP client built the walk on a dedicated X
  Bot scene, saved and force-reopened it, and measured root travel 1.1401 m.
- **New evaluator check:** `motion_audit` reports each foot's maximum
  penetration below its rest ground, the time of that sample, and a default
  budget of 1% of leg length. The Godot AI tool schema and generated operation
  index expose `max_penetration` and describe the private playback copy.
- **Failure and cause:** The stricter live audit found the dummy walk's right
  foot 3.42 cm below ground at 0.3193 s even with 120 authored samples. The
  old leg pole used the mostly vertical hip-to-knee vector; its projection
  against a changing ankle target could reverse during swing. The solver now
  uses the knee's bend component perpendicular to the rest hip-to-ankle line,
  with a forward fallback for nearly straight rest poses. Leg aiming also
  uses the actual child rest offset instead of assuming every imported bone
  points along local +Y. Under-sampled walk/run requests are raised to at
  least 24 intervals per loop; durations too short to do that at 120 keys/s
  return `VALUE_OUT_OF_RANGE` before mutation.
- **Verification:** Through the real MCP route, 120-key dummy and X Bot walks
  pass before save and after force reopen. Worst measured penetration is
  under 0.5 mm on both; 24-key dummy and X Bot walks also pass dense 120-sample
  audit (worst 3.9 mm and 2.9 mm respectively). A 24-key dummy run passes the
  same route (worst penetration 3.5 mm, slide 4.3 mm). The logs are preserved
  as `mcp_*pole_fix.log` and `mcp_*24keys_pole_fix.log` in the repair snapshot.
  The four previous golden files were backed up there as `*_pre_pole.json`
  and rerecorded for the intentional solver change. A second, non-recording
  verification passes 209/209 editor tests and all 14 tier-1 suites on
  Godot 4.7.2. Fixed-camera walk contact sheets for the dummy and X Bot live
  under `media/walk_pole_fixed` and `media/xbot_walk_pole_fixed` in the repair
  snapshot; both show continuous travel and alternating steps at six review
  frames. These are local review evidence, not full visual acceptance.
- **Remaining:** Synthetic orientation/proportion playback, X Bot actions
  beyond walk/run, agent prompts, the
  operation matrix and Linux remain open. The 120-key live penetration
  failure also demonstrates that a coarse audit can pass a defective clip;
  acceptance must sample densely enough to see the swing turn.

### 2026-09-29 — Phase 3, played knee-pole continuity and X Bot run

- **Change:** `motion_audit` now samples the played hip, knee and ankle on
  each leg, projects the knee bend across the current hip-to-ankle axis and
  reports pole direction jumps over 90 degrees. Nearly straight samples are
  ignored until the bend becomes measurable. A synthetic test plants a real
  side switch and checks that it is reported.
- **Tests:** The editor suite passes 210/210, including X Bot walk **and run**
  contact, penetration and pole checks at 30/60/120 samples. Through Godot AI
  MCP, an X Bot run with 24 authored intervals passed before save and after
  force reopen: slide 2.2/2.4 mm, penetration 7.0/3.1 mm, zero pole flips.
  The log is `mcp_xbot_run_knee_metric.log` in the repair snapshot. A 60 FPS
  contact sheet lives under `media/xbot_run_pole_fixed`.
- **Visual decision:** The X Bot run is continuous and grounded, but its
  crouch and forward kick remain stylized. It is **not** approved as a
  physically credible general-purpose run. Motion Phase 3 remains open.

### 2026-09-29 — Phase 2, live preset operation contracts

- **Version:** The repair target is Godot **4.7.2 stable**. The visible editor
  was launched and remained responsive during this pass; its live Godot AI
  session reported `4.7.2-stable (official)` and exposed all ten toolkit
  families, including eight promoted tools.
- **Schema defect:** `animation_presets.showcase` requires neither an existing
  player nor a target, but the family MCP schema required both. Godot AI could
  reject the call before it reached the toolkit. The schema now requires only
  `op`; handlers validate their own operation-specific inputs. A registry
  test checks that any family-level required field applies to every op.
- **Dry-run defect:** Through MCP, `showcase` with `dry_run=true` inserted its
  subtree, causing the next real call to fail on a duplicate name. The handler
  now returns the planned path, seven players and clip count before allocating
  or adding nodes. An editor regression test asserts zero scene mutation.
- **Live contract run:** `tools/mcp_presets_audit.py` called all nine preset
  ops through Godot AI, one fresh scene per op. Its final 4.7.2 run
  (`mcp_presets_verified.log` in the repair snapshot, run id
  `20260929_061918`) reports **9 operations, 0 contract failures** for MCP
  invocation, dry-run no mutation, created effect, resolved track paths,
  save and force reopen. `showcase` saved seven individually inspected clips.
  `tools/mcp_presets_playback.py` then reopened the eight ordinary preset
  clips, called Godot AI's `animation_manage(play)`, and observed each
  targeted node property change through `node_get_properties`; **8/8** passed
  (`mcp_presets_playback_verified.log`). The registry-driven matrix records
  these as **partial**, not verified: `showcase` runtime playback, UI undo/redo
  and visual review are still pending. Godot AI currently has no MCP
  `editor_undo` or `editor_redo` tool. A Windows touch-keyboard overlay first
  covered Godot's external-file-change dialog; after dismissing the dialog,
  the editor keyboard shortcuts worked. A fresh MCP-created `pulse` clip in
  `res://repair_ui_undo/20260929_063332.tscn` disappeared after Ctrl+Z and
  reappeared with the same resolved track after Ctrl+Shift+Z, as checked
  through MCP `describe`. Only the `pulse` UI undo/redo cell is marked pass;
  the other preset operations remain pending.
- **Visual check:** Godot 4.7.2 Movie Maker played the saved `showcase` scene
  for 60 frames at 30 FPS. Early and full contact sheets under
  `media/presets_showcase_472` in the repair snapshot show the button scale
  response, orbit dot, sweep bar, drifting line, pulsing label and two 3D
  cubes moving. `showcase` playback and visual-review cells are marked pass;
  the eight isolated preset ops still need individual visual review.
- **Audit gate:** The generated 103-operation matrix now includes reported
  error behavior and separate Windows/Linux cells. Its exporter refuses a
  `verified` claim unless every required check and both platforms are marked
  pass; the nine preset rows remain partial. A fresh export succeeded on
  Godot 4.7.2 with zero fully verified rows.
- **Tests/docs:** The full editor suite passes **211/211** and all **14/14**
  tier-1 suites pass on 4.7.2 after the handler fix; the focused registry
  suite passed 1989 checks. The generated op index no longer claims all read
  and file-writing calls create scene undo actions. Phase 2 remains open.

### 2026-09-29 — Phase 4, graph baseline and runtime probe

- **Live route:** Eight `animation_graph` operations were invoked through
  Godot AI MCP on fresh scenes with idle/walk/run/jump/lean clips. All returned
  without reported errors, saved, force-reopened, and were readable through
  `graph_get` (`mcp_graph_dry_resources.log`, run id `20260929_064753`,
  automated 8/8 no-error gate). Dry runs left both the node hierarchy and
  serialized graph root/parameter state unchanged. Their audit
  rows are partial; this is a topology smoke test, not eight playback passes.
- **Playback ownership:** The graph schema deliberately defaults `active` to
  false and the saved state machine reports `inactive_tree`, so calling a
  builder without `active=true` creates topology only. A separate live MCP
  call built an active BlendSpace1D and used `wire` to set
  `parameters/blend_position=1.5`. After save/reopen, Godot 4.7.2's actual
  60-FPS game loop moved the Character from x=0 to x=75 over 30 frames with
  `anim_player` resolved; see `mcp_graph_active.log` and
  `test_project/tools/check_graph_runtime.gd`. This confirms the combined
  blend-space/wire path, not all graph ops. A second active state machine was
  built through MCP and saved/reopened; at runtime,
  `parameters/playback.start("walk")` selected walk and moved the character
  from x=0 to x=50 over 30 fixed 60-FPS frames. The auto-start/transition
  contract remains untested (`mcp_graph_state_active.log`).
- **Next:** Test graph resource identity across undo, state-machine travel and
  transitions, layering ownership, additive blend semantics,
  and runtime replay for every graph operation before approving Phase 4.

### 2026-09-29 — Phase 4, sequence through the actual Godot AI route

- **Fixture:** `test_project/tools/create_sequence_fixture.gd` saved a minimal
  Skeleton3D with two source rotation clips using Godot 4.7.2. It is a contract
  fixture for character-owned sequencing, not a rebuilt flykick demo.
- **Live route:** `tools/mcp_sequence_audit.py` invoked the unpromoted
  `animation_sequence.compose` through `custom_manage(invoke)` on the connected
  Godot AI editor. Its dry run left no output clip; the write returned a single
  output track, 55 keys and one contact marker. `animation_inspect.describe`
  found its resolved track before and after save/force reopen. See
  `mcp_sequence_audit.log` in the repair snapshot, run id `20260929_170242`.
- **Playback:** `test_project/tools/check_sequence_runtime.gd` played the
  reopened scene in Godot 4.7.2. The root bone's X rotation increased from
  0.08 to 0.56 radians and `contact_impact` was placed at 1.1 seconds.
  This proves the output is animated, not that the action looks credible.
- **Still open:** boundary and gap behavior, overlap continuity, saved-pose
  sources, root-motion ownership, error reporting, UI undo/redo, visual review
  and Linux. The operation remains `partial` in the registry audit.
- **Source range repair:** The handler had accepted `source_end` beyond an input
  clip and silently sampled its held final key. It now rejects non-finite,
  negative, reversed or out-of-clip source ranges with `VALUE_OUT_OF_RANGE`.
  The direct editor test passed. A core plugin reload alone left the toolkit
  GDScript handler cached in the visible editor, so the first MCP retry still
  returned success. After restarting visible Godot 4.7.2 (PID 25548), the
  same MCP invalid call returned the typed error and the full sequence audit
  passed (`mcp_sequence_range_verified.log`, run id `20260929_170810`).
- **Adjacent rig inspector fix:** While running the editor suite from the
  saved sequence scene, `rig_get` falsely reported this scene's Root bone as
  an unknown bone on an instanced dummy. Its scan matched the suffix of a
  track's node path, allowing unrelated Skeleton3D nodes with the same name
  to cross-contaminate the report. It now resolves track paths from each
  AnimationPlayer root and compares actual node identity. The negative test
  now inserts a resolvable bogus bone track. Full editor suite: **211/211**
  pass on Godot 4.7.2, including this regression.
- **Timeline boundaries:** The editor test now samples the resulting Godot
  Animation on each side of overlap start/end, checks the contact marker at
  1.1 seconds, and confirms that a gap holds the preceding pose. Previously,
  a first segment starting after zero silently animated from its first pose
  before the requested start. That timing is now rejected as invalid. The
  registry description states the first segment and gap rules; generated
  docs were refreshed. Full editor suite remains **211/211** on 4.7.2.
- **Saved-pose source:** `sequence_root.json` uses the toolkit's exported pose
  format. A second live `custom_manage(invoke)` call composed it into a
  3-track, 48-key clip on the same Skeleton3D; dry run left no clip and
  save/force reopen kept all tracks resolved (`mcp_sequence_pose.log`, run id
  `20260929_171133`). Played in Godot 4.7.2, it set the Root bone to the
  authored 0.6-radian pose. Sequence remains partial until ownership, undo,
  visual review and Linux are checked.
- **Fresh live timing check:** With the latest sequence script loaded by a
  visible Godot 4.7.2 editor restart, the Godot AI route rejected a first
  segment at 0.2 seconds as `INVALID_PARAMS` and an out-of-clip source range
  as `VALUE_OUT_OF_RANGE`. The valid clip and saved-pose clip still saved,
  reopened and played at the expected bone angles. See
  `mcp_sequence_timing_verified.log`, run id `20260929_192033`.
- **Gate:** All 14 pure tier-1 suites and the 211-test editor suite pass on
  Windows with Godot 4.7.2. This is still a partial phase result: the
  103-operation matrix has no fully verified rows because visual and Linux
  checks remain open.

### 2026-09-29 — Phase 4, active graph startup

- **Finding:** The original live MCP `state_machine(active=true,start="walk")`
  saved successfully but stayed on Godot's `Start` node at runtime, moving the
  Character zero units in 30 frames. Only an explicit
  `parameters/playback.start("walk")` made it move. This was a real inert
  success for an active graph. Godot's AnimationTree documentation says a
  state machine must either receive `start()` or have a transition from
  `Start` before it can play.
- **Repair:** `GraphBuilders.state_machine` now validates the selected start
  state and connects Godot's `Start` to it with an automatic zero-time
  transition. Without an explicit `start`, the first state is chosen;
  `locomotion(mode="state_machine")` chooses idle. Result metadata counts the
  actual transition and separately reports user-authored transitions. The
  response hint now says the active tree enters its start state automatically
  and shows how to override it at runtime. The no-transition warning excludes
  this implicit entry edge.
- **Tests:** Focused tier-1 graph builder suite **126 checks pass**, all
  **14 tier-1 suites pass**, and the full editor suite **211/211 passes** on
  Godot 4.7.2. A live MCP-built, saved and
  reopened active state machine entered walk without `start()` and moved the
  Character 50 units in 30 fixed 60-FPS frames
  (`mcp_graph_auto_start.log`, scene
  `res://repair_graph_active/state_machine_20260929_192633.tscn`). A second
  live build connected Start→idle and conditional idle→walk; `wire` set
  `parameters/conditions/walking=true`. The reopened scene transitioned to
  walk and moved 50 units in 30 frames (`mcp_graph_condition.log`, scene
  `res://repair_graph_active/condition_20260929_192747.tscn`). Graph undo,
  other layer operations, visual review and Linux remain open.
- **Blend tree playback:** A separate live MCP call built an active Blend2
  tree, verified `output_wired=true`, and used `wire` to set
  `parameters/Mix/blend_amount=1.0`. The saved/reopened scene moved
  Character.x from 0 to 50 over 30 fixed 60-FPS frames in Godot 4.7.2.
  See `mcp_graph_blend_tree.log` and
  `res://repair_graph_active/blend_tree_20260929_193007.tscn`. The
  `animation_graph.blend_tree` audit row now has playback evidence, but still
  needs undo, visual and Linux checks.
- **One-shot inert success:** Before repair, `one_shot_layer(active=true)`
  returned a saved, resolved graph and `parameters/OneShot/request=FIRE` was
  present, but runtime Character.y stayed at 0 for 30 frames
  (`mcp_graph_one_shot_before.log`). Godot 4.7.2 exposes OneShot ports
  `in` and `shot`: the handler had put the Jump clip on `in`, left `shot`
  empty, and routed the node through a default-zero Blend2. The handler and
  pure graph builder now connect Base→in, Jump→shot and OneShot→output.
  The live MCP rebuilt scene saved/reopened, and firing its request moved
  Character.y from 0 to -80 in 30 fixed 60-FPS frames
  (`mcp_graph_one_shot_after.log`, scene
  `res://repair_graph_active/one_shot_20260929_193428.tscn`). Focused
  graph builder checks **126/126** and full editor suite **211/211** pass.
- **CI fixture isolation:** The editor harness originally opened `main.tscn`
  before Godot finished restoring the previously open scene. With the
  one-shot audit scene still open, seven unrelated graph tests found its
  AnimationTree and failed. The harness now reopens and verifies `main.tscn`
  immediately before suite execution. The full suite passes from this
  restored-scene state.
- **Nested OneShot contract:** `blend_tree` accepted a one-child OneShot
  node, connecting only its `in` input and leaving `shot` empty. It now
  requires both ordered inputs (base, shot). Focused graph tests **127/127**
  and full editor suite **211/211** pass. A live MCP-created active nested
  OneShot saved/reopened and moved Character.y from 0 to -80 after FIRE in
  the Godot 4.7.2 game loop (`mcp_graph_nested_one_shot.log`, scene
  `res://repair_graph_active/nested_one_shot_20260929_193652.tscn`).
- **Additive layer playback:** Through live MCP, `additive_lean` built an
  active Base+Add2 graph and returned its amount parameter. A `wire` call set
  `parameters/Add2/add_amount=1.0`; the saved/reopened scene rotated the
  Character from 0 to 0.12 radians in 30 fixed 60-FPS frames under Godot
  4.7.2 (`mcp_graph_additive.log`, scene
  `res://repair_graph_active/additive_20260929_193750.tscn`). This proves
  an explicitly enabled additive layer plays; the default zero weight and
  discoverability of that requirement still need review.
- **Ready-made locomotion playback:** Live MCP
  `locomotion(active=true,mode="blend_space")` created idle/walk/run points;
  `wire` set `blend_position=1.5`. The saved/reopened scene moved
  Character.x from 0 to 75 in 30 fixed 60-FPS frames under Godot 4.7.2
  (`mcp_graph_locomotion.log`, scene
  `res://repair_graph_active/locomotion_20260929_193857.tscn`). A second
  live call built the state-machine mode with Start→idle and wired walking
  true; the reopened scene transitioned to walk and moved Character.x from
  0 to 50 in 30 frames (`mcp_graph_locomotion_state.log`, scene
  `res://repair_graph_active/locomotion_state_20260929_193946.tscn`).
  Visual, undo and Linux gates remain open.

### 2026-09-29 — Phase 2/4, first clip-edit contract pass

- **Method:** `tools/mcp_edit_audit.py` copies a saved clip fixture into one
  fresh scene per operation and invokes `custom_animation_edit` through the
  connected Godot AI MCP server. It compares `animation_inspect.describe`
  before/after dry run and write, then saves, force-reopens and checks that
  described tracks still resolve. Serialized float timestamps are compared
  with a 1e-5 tolerance; exact `0.6` becoming `0.6000000238` is not a lost
  edit.
- **First run:** Seven operations were attempted: retime, reverse, mirror,
  trim, amplitude, resample and layer. Six succeeded; `layer` returned
  `VALUE_OUT_OF_RANGE` for a valid Vector2 position overlay. Its additive
  value routine handled Vector3 and floats but omitted Vector2. This was a
  toolkit bug, not an unsupported Godot track (`mcp_edit_first.log`).
- **Repair and rerun:** Added weighted Vector2 deltas and a direct 2D layer
  regression. Focused quality suite **82 checks pass** and full editor suite
  **211/211 passes** on Godot 4.7.2. After a visible editor restart,
  the fresh live MCP rerun reports **7 operations, 0 contract failures**
  (`mcp_edit_seven_verified.log`, run id `20260929_194514`). Their matrix
  rows are partial: UI undo/redo, typed error cases,
  visual review and Linux remain. The other 13 edit operations have not yet
  received this route-level effect audit.
- **Played values:** `test_project/tools/check_edit_runtime.gd` loaded each
  saved scene and used Godot 4.7.2 AnimationPlayer interpolation to sample
  Character.x at the start, midpoint and just before the end. All seven
  matched their operation-specific expected values within 0.02 units:
  retime 0→100 over 0.5 s, reverse 100→0, mirror 0→-100, trim 20→80,
  amplitude 0→50, resample 0→100 with 31 keys, and Vector2 additive layer
  0→180. Their playback cells now pass. UI undo, typed errors, visual review
  and Linux remain; the other 13 edit ops are unaudited through live MCP.
- **Recovery snapshot:** Current tracked diff, Git status, this roadmap,
  operation evidence/matrix and new sequence/graph test scripts were copied
  to `F:\GODOTAITESTING\toolkit_repair_snapshot_2026-09-29`. This preserves
  the in-progress branch state across an app interruption. The original
  pre-phase snapshot from 2026-09-28 remains separate.
- **Actual key budget:** The old `length * samples <= 1200` precheck still
  allowed 1,201 keys at 10 seconds × 120 samples/s because both endpoints
  are included. Sequence composition now counts unique output times before
  allocating the clip and rejects any result over 1,200 keys per track with
  `VALUE_OUT_OF_RANGE`. A regression checks no clip is committed; the full
  editor suite remains **211/211** on 4.7.2. After restarting visible Godot,
  live MCP returned `VALUE_OUT_OF_RANGE` for the same 1,201-key request while
  the valid normal and saved-pose clips still saved and played. See
  `mcp_sequence_budget_verified.log`, run id `20260929_192244`.

### 2026-09-29 — Phase 2/4, wrapped edit seam correction

- Expanded the live Godot AI edit audit from seven operations to eleven.
  Initial wrapped `offset` and `overlap` calls falsely reported success on
  the fixture's 0→100 position track: the keys at 0 and 1 second both
  wrapped to the same time, deduplication left one constant key, and the
  saved clip had no motion (`mcp_edit_eleven.log`, run id
  `20260929_194935`). The harness's changed/persisted checks were too weak
  to catch this; these two results are **invalid**, despite its 0-failure
  count. `loop` and `key_edit` also need engine playback checks.
- `edit_offset` and `edit_overlap` now detect conflicting key values that
  would merge after modulo time shift and return `VALUE_OUT_OF_RANGE`
  before committing, with a message naming the track and suggesting
  `wrap=false`. The same calls with `wrap=false` remain available. Direct
  editor regressions check that rejected clips retain their keys, and the
  full editor suite passes **211/211** on Godot 4.7.2; all 14 tier-1 suites
  pass.
- A second playback check found that even `wrap=false` delayed clips could
  begin at the prior loop's final value: there was no key at time zero, and
  Godot interpolated across the loop seam. Positive nonwrapped shifts now
  insert an initial hold key on value tracks. Focused tier-1 spec/quality
  suites pass **1,989/83 checks**, and the full editor suite passes
  **211/211**. The visible Godot 4.7.2 editor was restarted and Godot AI
  MCP reran 11 edit operations plus two typed wrap rejections on fresh
  scenes with **0 contract failures** (`mcp_edit_hold_verified.log`, run id
  `20260929_195930`). Saved-scene engine playback at start, midpoint and
  end passed all 11 with worst error below 0.02 scene units, including
  `offset`, `loop`, `key_edit` and `overlap`. These remain partial pending UI
  undo, representative visual review and Linux checks.
- The expanded first pass attempted all 20 edit operations through the live
  Godot AI route (`mcp_edit_twenty_first.log`, run id `20260929_200337`).
  Eighteen passed the initial inspect comparison. `ease_range` and
  `set_interp` returned successful writes but `inspect.describe` omits
  transition and interpolation settings, so that summary could not prove
  either change. The harness now also records `inspect.timeline`, which
  exposes both properties. A full rerun and played-value checks are next.
- `inspect.timeline` confirmed those settings after save/reopen. Saved
  playback then exposed a real `merge` defect: when two source clips shared a
  track and conflicting values at the same cut time, the first clip's end
  key disappeared, leaving its motion inert. `SpecModifiers.merge` now keeps
  the outgoing value just before the cut and the incoming value at the cut;
  a pure regression checks both. The deliberately hard 0.1 ms cut between
  incompatible source positions is still a quality limitation to review.
  The first nearest-interpolation playback expectation was also corrected:
  Godot holds the preceding value until the next key.
- After restarting the visible Godot 4.7.2 editor, a fresh live Godot AI MCP
  audit of **all 20 advertised edit operations**, plus two expected wrapped
  seam rejections, had **0 route contract failures**
  (`mcp_edit_twenty_merge_fixed.log`, run id `20260929_200905`). Every saved
  edit passed operation-specific engine playback checks. `retarget` moved
  the track to the existing alternate node; `ease_range` evaluated its
  transition curve; `set_interp` held a nearest value; both split clips
  played; `merge` played both halves; `cleanup` retained its static pose;
  `smooth` changed the jump shape; `reduce` kept the linear travel while
  removing 29/31 keys; and seeded `add_noise` played its saved perturbation.
  Focused spec tests pass **1,993 checks**, focused quality tests **83**,
  and the editor suite **211/211**. Rows remain partial pending UI undo,
  visual review, more typed errors, and Linux.

### 2026-09-29 — Phase 2, basic read-only inspection contracts

- `tools/mcp_inspect_audit.py` invoked eight inspection operations through
  the live Godot AI MCP route on a saved fixture: `describe`, `timeline`,
  `audit`, `compare`, `stats`, `motion_report`, `dry_run`, and `help`. All
  returned specific expected facts: one two-key walk clip (0→100), five
  clips/12 keys in stats, walk/run difference, a 100-unit loop seam warning,
  a predicted 1.0→0.5-second dry-run retime, and the 20 edit ops in help.
  The source walk timeline stayed identical after every call. The verified
  run has **8/8 contract checks and 0 failures** in
  `mcp_inspect_basic_verified.log`. These rows remain partial pending typed
  error and Linux checks; `motion_audit`, `rig_profile`, `sample`, and
  `preview` need separate 3D fixture/effect review.
- `tools/mcp_inspect_3d.py` exercised those four remaining inspection
  operations through the visible Godot 4.7.2 editor and live Godot AI MCP.
  On the saved 56-bone dummy walk, profile detection found the expected
  hips/thigh/foot roles without writing a file; `sample` returned both feet
  at eight times; the private played `motion_audit` passed with 1.0801 m
  body travel and zero failed checks. `preview` wrote four valid 480×270
  PNGs, and the source clip summary stayed identical. See
  `mcp_inspect_3d_verified.log` and
  `res://animation_toolkit/previews/repair_inspect/walk_*.png`. I inspected
  all four frames: the changing leg pose is visible, but the character is
  small in frame, so this is output validity evidence, not visual approval
  of motion quality. Typed errors, save=true profile behavior, pose-state
  restoration and Linux remain open.
- A second live MCP pass supplied invalid targets to all 12 inspection
  operations. Each returned a typed `NODE_NOT_FOUND`, `INVALID_PARAMS`, or
  `VALUE_OUT_OF_RANGE` instead of a success or crash. The eight basic
  results are in `mcp_inspect_errors.log`; the four 3D results are in
  `mcp_inspect_3d_errors.log`. Every inspect row now has a basic valid
  response and a typed error case on Windows. The save=true profile path,
  pose restoration, larger preview variants and Linux are still unverified.

### 2026-09-30 — Phase 2/4, library contracts through Godot AI

- `tools/mcp_library_audit.py` invoked all seven `animation_library`
  operations through the live Godot AI MCP route on a dedicated saved scene
  and timestamped files beneath `res://animation_toolkit/repair_audit/`.
  `template_save` created a reusable drift call; list showed it; a dry-run
  delete retained it; delete removed it from the JSON file. `spec_export`
  wrote the two-key walk as a versioned clip spec and `spec_import` reported
  its shape. `template_apply` and `spec_apply` made separate resolved tracks
  on `OtherCharacter`; both survived scene save and forced reopen. Dry-run
  save/export made no file and dry-run apply made no clip. All seven invalid
  calls returned typed errors. See `mcp_library_verified.log`, run id
  `20260929_202724`, **0 contract failures**.
- `test_project/tools/check_library_runtime.gd` played both reopened clips
  under Godot 4.7.2: at 0.5 s, the template drift set
  `OtherCharacter.x=30`, the imported walk set `OtherCharacter.x=50`, and
  the original `Character.x` stayed zero. File writes correctly reported
  `undoable=false` and scene applies reported `undoable=true`. Actual editor
  undo/redo for the applies, Linux and visual review remain open.

### 2026-09-30 — Phase 2/4, FX route and persistence (in progress)

- Added `test_project/tools/create_fx_fixture.gd` and
  `tools/mcp_fx_audit.py` for a dedicated 2D/audio fixture and live Godot AI
  MCP calls. All 16 advertised `animation_fx` operations reached the toolkit
  in the visible Godot 4.7.2 editor. Dry runs did not add clips; writes
  produced resolved tracks (or a `SpriteFrames` resource), and all results
  survived scene save and forced reopen. The last run also covered a second
  `sprite_frames` call with `play=false`: `mcp_fx_sprite_fixed.log`, run id
  `20260930_153136`, 17 cases and zero route-contract failures. This proves
  route, structure and persistence only; engine playback, typed errors, undo,
  and visual quality still need checks.
- The first live route pass caught a real `sprite_frames` dry-run violation:
  it assigned a resource and started playback before returning. The handler
  now guards resource assignment behind the write branch and respects
  `play=false`; its UndoRedo transaction assigns or restores the resource and
  starts or stops playback as requested. A focused editor test covers dry
  state, stopped write, undo and redo. The Godot 4.7.2 editor suite passes
  **212/212** after this change.
- `test_project/tools/check_fx_runtime.gd` then played all 15 clip results
  from their saved scenes. It exposed a second real defect: `wave` wrote
  value tracks to `Card1`, `Card2`, and `Card3` without the `:position`
  property, so those clips were inert despite resolved nodes. The handler
  now writes `CardN:position`; the editor regression asserts the paths.
  A fresh live Godot AI rerun (`mcp_fx_wave_fixed.log`, run id
  `20260930_154357`) saved/reopened the corrected clip, and engine playback
  matched each of its three position tracks. The editor suite remains
  **212/212**. The other 14 clips played with expected node values; `counter`
  set the label text to 50 at 0.5 s with immediate method evaluation, and
  `audio_cue` started its player past the 0.2 s cue. The resource-only
  `sprite_frames` result retained four cells after reopen; visual frame
  advancement is not yet checked.
- `tools/mcp_fx_errors.py` invoked each of the 16 FX operations with an
  invalid target through the live Godot AI route. All 16 returned typed
  `NODE_NOT_FOUND` errors (`mcp_fx_errors.log`). Partial FX rows and their
  remaining undo, visual, animation-play and Linux work are recorded in
  `docs/operation-evidence.json`.
- To prevent another node-only value track from reporting success,
  `SpecBuilder.validate` now rejects `Animation.TYPE_VALUE` paths without a
  property subname. A pure regression checks this case. All 14 tier-1 suites
  pass (including **1,994** spec/modifier checks), and the 4.7.2 editor suite
  remains **212/212**. This is a structural guard; it does not replace
  scene-specific playback checks.
- One actual editor UndoRedo check now covers `wave`: live Godot AI MCP
  created `ui_undo_wave` in a fresh unsaved scene, Ctrl+Z in the visible
  Godot 4.7.2 editor removed it (`inspect.describe` returned not found), and
  Ctrl+Shift+Z restored its three resolved position tracks and 51 keys.
  This is one representative undo path; the other FX clip operations still
  need their own undo checks.

### 2026-09-30 — Phase 2/4, rig pose apply (in progress)

- `pose_apply` had another false-success path. Its dry run opened and
  committed an UndoRedo action, mutating the skeleton while claiming
  `dry_run=true`. `_apply_pose` now counts matching bones and returns before
  opening an action. A direct dummy regression verifies the bone stays at
  rest; the Godot 4.7.2 editor suite now passes **213/213**.
- `tools/mcp_rig_pose_apply_audit.py` exercises the promoted rig tool on a
  static imported dummy scene, with a 0.6 rad arm pose. The live route proved
  that the dry run left the arm at rest and the write rotated it. The first
  saved-scene test then lost the pose. An earlier test fixture also had an
  autoplay clip, so I repeated on `repair_rig_fixture.tscn` with no autoplay
  to rule that out (`mcp_rig_pose_apply_static.log`). The loss was real:
  imported scene children were not editable, so Godot did not serialize the
  bone override. `pose_apply` now enables editable instance levels in the
  same UndoRedo action, as clip commits already do. Fresh live Godot AI MCP
  run `mcp_rig_pose_apply_editable.log` (id `20260930_160635`) retained the
  arm's exact quaternion after save/forced reopen, and the invalid skeleton
  returned typed `NODE_NOT_FOUND`. Live editor undo, animation playback
  interaction, and Linux remain.
- A separate live Godot AI route audit (`tools/mcp_rig_pose_crud.py`, log
  `mcp_rig_pose_crud_first.log`, id `20260930_161028`) covered `pose_save`,
  `pose_list`, `pose_blend`, `pose_to_clip`, and `rig_get` on the same static
  imported dummy. Dry-run pose save/blend wrote no files; writes saved JSON
  poses and list found them. The blended pose contained 56 bones, and a
  missing source returned typed `INVALID_PARAMS`. `pose_to_clip` dry run left
  no clip; its one-track arm clip survived save/forced reopen. Headless
  Godot 4.7.2 playback of that saved scene measured arm rotation 0, 0.6, 0
  radians at 0, 0.5 and 1.0 s, with worst error below 0.000001 rad.
  Operation-specific typed errors, editor undo and visual review remain for
  several rows; the matrix records these as partial.
- Actual editor UndoRedo on the imported dummy now passes for `pose_apply`:
  live Godot AI MCP applied the 0.6 rad pose in an unsaved scene, Ctrl+Z in
  the visible Godot 4.7.2 editor restored the bone's identity rotation, and
  Ctrl+Shift+Z restored quaternion `(0, 0.29552, 0, 0.955336)`. The fixture
  and readback are in `tools/mcp_rig_pose_ui_undo.py` and
  `res://repair_ui_undo/rig_pose_20260930_161530.tscn`.
- `rig_chain` append had the same false-success persistence defect:
  `mcp_rig_chain_first.log` reported 57 bones after write but 56 after save
  and force reopen on the imported dummy. The shared node commit helper now
  enables editable instance levels for existing setup targets too. Live
  Godot AI rerun `mcp_rig_chain_editable.log` (id `20260930_162157`) retained
  the 57th bone, its original hand parent and 5 cm rest offset. Dry run kept
  56 bones, and an unknown parent returned typed `INVALID_PARAMS`.
- [Godot 4.7 Skeleton3D](https://docs.godotengine.org/en/4.7/classes/class_skeleton3d.html)
  exposes `clear_bones()` but no individual bone-removal method. Before this
  repair, `rig_chain` append claimed `undoable=true` without an undo for the
  appended bone. The shared node commit helper now accepts ordered undo
  setup calls, and `rig_chain` snapshots and rebuilds the original bone
  names, rests, poses, enabled flags, metadata and parent indices on undo.
  [Godot's UndoRedo ordering](https://docs.godotengine.org/en/4.7/classes/class_undoredo.html)
  confirms undo operations run in insertion order by default. A direct
  imported-dummy editor regression checks that one undo restores 56 bones
  with the original hand. The 4.7.2 editor suite stays **213/213**; live UI
  undo/redo and rig_chain's new-skeleton/subtree modes remain to verify.
- Live editor UndoRedo now passes for that append too. Godot AI created
  `ui_undo_tool_tip` in an unsaved imported-dummy scene; Ctrl+Z restored 56
  bones with no tip, and Ctrl+Shift+Z restored 57 bones with the tip under
  parent index 7. `tools/mcp_rig_chain_ui_undo.py` read back both states.
  The strengthened direct regression compares all 56 original names,
  parent indices, rests and pose rotations after undo. The editor suite
  remains **213/213**.
- `rig_chain`'s three other creation modes now have live Godot AI route
  evidence (`tools/mcp_rig_chain_modes.py`, `mcp_rig_chain_modes_first.log`,
  id `20260930_163804`): a new two-bone Skeleton3D, a new two-bone
  Skeleton2D, and a three-bone Skeleton3D generated from a Node3D subtree.
  Dry runs created no skeleton, and the exact names, parent relationships
  and rest positions survived scene save and forced reopen in each case.
  Visual inspection and Linux remain.
- `tools/mcp_rig_recipes.py` audited six more advertised `animation_rig`
  clip operations on separate static imported-dummy scenes through the live
  Godot AI tool route: `walk_cycle`, `idle_breathing`, `blink`,
  `jumping_jack`, `squat` and `punch`. Dry runs added no clip; writes produced
  respectively 7/5/1/5/7/9 resolved typed bone tracks and 25/19/7/15/28/45
  keys. All survived scene save/forced reopen; bad skeleton paths returned
  typed `NODE_NOT_FOUND` (`mcp_rig_recipes_first.log`, run
  `20260930_164109`). `test_project/tools/check_rig_recipe_runtime.gd`
  played every saved clip in Godot 4.7.2 and confirmed all 34 sampled bone
  tracks set actual bone poses to their authored keys, with a moving bone in
  every clip. These are playback-validity checks. Contact, visual quality,
  live editor undo, independent rigs and Linux remain open for these rows.
- The last `animation_rig` operation, `bake_pose_sequence`, now has a live
  Godot AI route check (`tools/mcp_rig_bake.py`). It sampled a generated
  dummy walk at 10 FPS for 0.5 s, made 112 resolved rotation/position tracks
  and 672 keys, restored the source skeleton pose, and survived save/forced
  reopen. Dry run left no baked clip or pose change; missing source returned
  typed `INVALID_PARAMS`. Headless 4.7.2 playback compared source and baked
  rotations across 24 bone/time samples with zero measured difference.
- The first bake pass showed two new editor errors even though the tool
  returned success. `logs_read(source="editor")` identified a read of
  `current_animation_position` when the player had no current animation.
  The handler now reads that property only when there is a current clip.
  After restarting the visible editor, `mcp_rig_bake_fixed.log` (run
  `20260930_164952`) had **112/112** tracks inspected and no new editor
  errors; the editor suite stays **213/213**. Live modifier-stack behavior,
  editor undo, visual quality and Linux remain.
- A separate editor warning came from the audit harness copying a scene
  file with its UID intact. `tools/fixture_copy.py` now strips the copied
  scene's header UID, and the MCP fixture harnesses use it. I removed the
  one duplicated UID in an already generated audit scene; a scan of all
  `test_project/**/*.tscn` scene headers now reports **0 duplicate UIDs**.
  This changes fixture bookkeeping only, not authored clips.
- Refreshed a recoverable copy at
  `F:\GODOTAITESTING\toolkit_repair_snapshot_2026-09-30`: the tracked
  patch passes `git apply --stat`, and the snapshot includes this roadmap,
  current evidence/audit JSON and the FX/rig code and harnesses. The
  original 2026-09-28 snapshot still preserves the pre-repair state.
- `tools/mcp_motion_remaining_cycles.py` exercised seven more advertised
  `animation_motion` clip operations through the live Godot AI custom tool
  on the imported dummy: `idle_cycle`, generic `cycle` (walk), `jump`,
  `turn_cycle`, `strafe_cycle`, `walk_start`, and `walk_stop`. The run
  `20260930_170226` in `mcp_motion_remaining_first.log` had no route failures:
  dry runs left no clip, writes made 18-21 resolved typed tracks, save and
  forced reopen preserved them, and invalid skeleton paths returned typed
  `NODE_NOT_FOUND`. `check_motion_remaining_runtime.gd` loaded each saved
  scene in Godot 4.7.2 and played every bone track at an authored key; all
  134 sampled bone tracks matched with zero measured error, and each clip
  moved a bone. These checks establish route and playback validity, not
  credible contact or visual quality. The seven operations remain partial:
  editor undo, independent rig orientations, 30/60/120 FPS contact and loop
  measurements, visual review and Linux are still open.
- `character_setup` and `secondary_motion` were next exercised together
  through live Godot AI (`tools/mcp_motion_setup_secondary.py`). The first
  route pass created idle/walk/run/jump/turn clips, a locomotion AnimationTree
  and a spring track on the previously unkeyed `B-jaw`; dry runs left the
  respective clip unchanged and all data survived forced reopen. Saved-scene
  playback exposed a real spring-bake error that direct tests missed: the
  authored jaw's first pose was 1.5708 rad from identity, exactly its local
  rest-basis rotation. Skeleton3D rotation tracks take rest-relative pose
  deltas, so `motion_secondary` now removes the local rest basis when turning
  the simulated global orientation into a bone track. A regression asserts
  the first spring key is identity. The Godot 4.7.2 editor suite is again
  **213/213** after this fix.
- After restarting the visible editor, the live Godot AI rerun
  `mcp_motion_setup_secondary_fixed.log` (run `20260930_171447`) passed
  route, dry-run, typed-error and save/reopen checks. Headless 4.7.2 replay
  of the saved scene activated the tree, changed the walking thigh by 0.417
  rad and extracted 0.28 m root translation over five 0.1 s advances.
  The corrected spring track begins at identity and its sampled key plays
  exactly; it spans 0.693 rad on this deliberately jaw-based test. A hair or
  tail fixture, modifier ordering, editor undo, visual review and Linux are
  still needed before approving spring behavior or character setup.
- Four `animation_rig_modifiers` operations were exercised through the
  advertised Godot AI `custom_manage(invoke)` route on separate imported
  dummy scenes (`tools/mcp_rig_modifiers_audit.py`). The latest run
  `mcp_rig_modifiers_leaf_rejected.log` (id `20260930_173516`) has clean dry
  runs, typed invalid-target errors, one persistent modifier per scene and
  unchanged `rig_get` descriptions after save/forced reopen for `ik_setup`,
  `spring_setup`, `look_at_setup` and `twist_setup`. Headless 4.7.2 replay
  activates each saved modifier and samples at its
  `modification_processed` signal, as required by
  [SkeletonModifier3D's timing contract](https://docs.godotengine.org/en/4.7/classes/class_skeletonmodifier3d.html).
  The IK arm moved 0.394 rad after target movement, the look-at head moved
  0.310 rad, a two-bone forearm/hand spring moved 0.043 rad under external
  force, and twist from the spine was distributed to the hips by 0.393 rad.
  Runtime values are from `check_rig_modifiers_runtime.gd`; editor undo,
  visual quality, additional IK kinds, and Linux remain open.
- The first spring fixture used the leaf `B-jaw` for both root and end. It
  saved a `SpringBoneSimulator3D` but did not move at the modifier callback.
  [Godot 4.7's spring documentation](https://docs.godotengine.org/en/4.7/classes/class_springbonesimulator3d.html)
  allows a single bone when its tail is extended. I tried that with a
  positive virtual-tail length; the saved jaw still produced zero observed
  rotation under a nonparallel external force. `spring_setup` now rejects
  same-bone and non-descendant end bones before mutation with a typed
  `INVALID_PARAMS` reason. The live route confirmed the leaf error. A
  two-bone chain remains supported and showed actual playback response.
- The active twist probe initially rotated the requested end bone and saw
  no effect. Godot's [BoneTwistDisperser3D contract](https://docs.godotengine.org/en/4.7/classes/class_bonetwistdisperser3d.html)
  explains that without an extended end, the reference is the end's parent.
  Rotating that reference produced the measured response. `twist_setup`
  now returns `reference_bone` and explains it in its result and advertised
  summary, so agents know which input pose it processes. The editor suite
  remains **213/213** after these changes.
- The fifth modifier operation, `retarget_setup`, now has live Godot AI route
  evidence on a scene-owned source/target pair of matching three-bone names
  and different rests (`create_retarget_fixture.gd`,
  `mcp_retarget_first.log`, id `20261001_083650`). Dry run left both
  skeletons untouched. Write moved the target to be a direct child of the
  RetargetModifier3D, reported three mapped bones, and both modifier and
  target survived save/forced reopen. A missing target returned typed
  `NODE_NOT_FOUND`. Headless 4.7.2 activated the saved modifier, posed the
  source head 0.6 rad, sampled the `modification_processed` callback and
  measured 0.6 rad on the target head. Editor undo, alternate profiles,
  visual deformation and Linux remain pending. All **103 advertised
  operations** now have at least a per-operation evidence row; none is fully
  approved under the roadmap's visual/Linux acceptance gates.
- Played world-space contact audits on the seven saved motion clips at
  30/60/120 FPS (`mcp_motion_saved_audit_details.log`) found that `idle_cycle`,
  generic walk `cycle` and `strafe_cycle` pass the current audit on the dummy.
  **Four clip operations fail despite passing route, track and authored-key
  replay checks:** `jump` penetrates 80.8 mm after landing; `turn_cycle`
  slides the planted feet 79.4/51.6 mm and penetrates 8.9 mm on the left;
  `walk_start` slides 88.4/142.3 mm and penetrates 34.2/29.8 mm;
  `walk_stop` penetrates 25.3/19.5 mm (120 FPS figures). The allowed
  penetration on this rig is 8 mm. `check_motion_trace.gd` confirms jump
  and turn feet are grounded at authored phase keys but dip below ground
  between sparse keys; the transitions blend bone deltas instead of
  resolving the feet through the blended pelvis pose. This is a quality
  blocker, not a passing audit. The `motion_audit` hip-bob failure on jump
  additionally reflects a gait-specific budget applied to a jump and must
  be classified by action type rather than counted as physical failure.
- **2026-10-01, contact repair (Godot 4.7.2 visible editor + Godot AI route).**
  The first dense jump pass still had 16.1 mm landing penetration and ~150 mm
  slide because horizontal travel ran through contact. `jump_keys` now solves
  legs at 120 Hz, moves the root only between takeoff and landing, and writes
  an actual character-root position track when `root_motion=true`. The handler
  only reports root extraction if such a track exists. `motion_audit` now takes
  `motion_kind` so a jump's intended rise is reported as height without being
  failed against the gait hip-bob limit; an explicit `max_hip_bob` still caps it.
  The saved Godot AI jump (`mcp_jump_rooted_second.log`, run
  `20261001_084915`) passes its played contact audit at 30/60/120 FPS with
  0.50 m travel, <=8.7 mm slide, no penetration and no knee flips under a
  16 mm slide cap (`mcp_jump_rooted_audit_fixed_kind.log`).
- `turn_keys` now anchors the support ankle, advances the swing ankle only
  while lifted, and resolves IK at 120 Hz through the pivot. The previously
  inert-looking 79/52 mm stance slide and 8.9 mm penetration are 0 mm in the
  saved-scene Godot AI audit at 30/60/120 FPS (`mcp_turn_anchored_first.log`,
  run `20261001_085408`; `mcp_turn_anchored_audit.log`). The two-step direct
  regression now checks the dense keyed midpoint and 180-degree endpoint;
  editor suite **213/213**.
- `walk_start`/`walk_stop` no longer merely slerp gait joint deltas. They
  generate a 120 Hz grounded step with one support foot anchored, swing-foot
  lift before horizontal travel, a continuous root track for requested root
  motion, and an exact gait pose at the seam; stopping reverses that trajectory.
  The first pass missed the 16 mm slide cap by 2 mm while the swing foot was
  within the 5 mm contact band. Shifting its translation to the lifted interval
  fixed this without changing the contact threshold. Both saved clips now
  pass 30/60/120 FPS with 0.21 m body travel and zero measured slide or
  penetration (`mcp_transition_grounded_second.log`, run `20261001_085929`;
  `mcp_transition_grounded_audit_second.log`). Headless saved-scene playback
  matched all 76 sampled bone tracks across these four repaired clips with
  zero authored-key error. The legacy idle/walk/strafe saved clips also pass
  the stricter 16 mm slide cap (`mcp_motion_legacy_strict_audit.log`).
- These are numerical contact passes on the imported dummy. The motion family
  remains **partial**, pending X Bot and varied synthetic-rig contact tests,
  seam/discontinuity checks, visual review of all actions, undo and Linux.
  The branch remains unreleased and no clip is visually approved yet.
- **2026-10-01, imported X Bot validation and static visual review.**
  `mcp_motion_remaining_cycles.py --rig xbot` invoked all seven remaining
  character clip operations through the live Godot AI API on copies of the
  imported X Bot scene, including dry run, write, typed invalid skeleton,
  save and forced reopen. Runs `20261001_090238`, `20261001_090436` and
  `20261001_090832` have zero route failures. Saved world-space contact audits
  at 30/60/120 FPS and a 16 mm slide cap pass all seven operations. The
  initially reported 0.1203 m transition hip range exceeded the gait-cycle
  fixed 0.12 m cap by 0.3 mm; `motion_audit` now applies a rig-relative 18%
  leg-length default only to start/stop transitions, preserving caller caps.
  That classification reflects their move from rest height into gait crouch.
- The first X Bot walk-start preview exposed a T-pose at its neutral endpoint.
  The generator used identity for all non-leg bones; imported X Bot rests with
  arms horizontal. Transitions now calculate relaxed arm/forearm deltas using
  the same arm solver as gait before blending to the exact gait endpoint.
  Both X Bot transitions still pass the 30/60/120 FPS played contact audit.
  Preview images in `test_project/animation_toolkit/previews/repair_xbot_*`
  show arms down at start/stop rest poses. The preview operation previously
  omitted extracted root travel; it now shifts the copied character and
  camera bounds by the AnimationPlayer's configured root position track.
  The live preview route rendered seven jump images and six images per turn,
  start and stop without missing PNGs. These are static pose checks. Full
  continuous fixed-camera playback, weight/timing review and alternate
  synthetic proportions/orientations remain required for visual approval.
- **2026-10-01, synthetic proportions and orientation.** The first script
  changed rest bones on an imported FBX instance; PackedScene dropped those
  overrides when saved. The replacement `create_synthetic_motion_fixture.gd`
  copies the source hierarchy into scene-owned Skeleton3D bones and sets
  live pose transforms to their rests. Reopen checks measure 0.439 m
  hip-to-foot on the half-size rig and 1.276 m on the 1.6x rig whose local up
  points +Z; pose/rest error is below 0.2 micrometres. The first Z-up played
  audit then exposed the actual toolkit defect: all seven clips had pelvis
  offsets in skeleton space written directly to parent-local bone position
  tracks. Jump moved along forward instead of up and measured ~0.49 m stance
  slide. `MotionSpecs` now records the hips parent's global rest basis and
  converts pelvis offsets before keying; the transition endpoint converts
  its sampled local offset back to skeleton space for IK. The new editor
  regression plays a Z-up jump and checks height and contact. The editor
  suite is **214/214**.
- Live Godot AI dry/write/typed-error/save/forced-reopen passes all seven
  motion clips on both synthetic fixtures (runs `20261001_092232` and
  `20261001_092052`). At 30/60/120 FPS all seven Z-up tall clips pass the
  played audit under a 25 mm slide cap; its jump slides 15.2 mm, with zero
  penetration. The short strafe initially failed at a fixed 5 mm contact
  height: its low swing was counted as planted and showed 30 mm slide.
  `motion_audit` now caps contact height at 5 mm and scales that default down
  for legs shorter than the 0.85 m reference. With the new default, all seven
  short clips pass at 30/60/120 FPS under an 8 mm slide cap. An explicit
  `contact_threshold` still overrides the default. Logs:
  `mcp_synthetic_zup_tall_converted_audit.log` and
  `mcp_synthetic_short_adaptive_audit.log`. After regenerating the registry
  docs, 14/14 tier-1 suites and 214/214 editor tests pass on Windows.

### 2026-10-01 — Phase 3, fixed-camera X Bot playback review

- Added a saved-scene review fixture with one AnimationPlayer controlling
  the imported X Bot and one character owner consuming extracted root motion.
  Godot 4.7.2 Movie Maker rendered jump, turn, walk start/stop, idle, strafe
  and generic walk cycle at 60 FPS; each scene produced 70 frames (idle 130)
  with no runtime errors. PNG sequences and labeled contact sheets are in
  `F:\GODOTAITESTING\toolkit_repair_snapshot_2026-09-30\media\xbot_*_review`.
  The first headless Movie Maker attempt crashed; a visible renderer worked.
- The sheets are useful visual evidence, but **do not pass visual approval**.
  The turn reads as a pivot and the jump has a visible crouch/lift/landing.
  Idle is subtle. Walk start, walk stop and generic walk are numerically
  grounded yet look like a long, deeply flexed lunge at the gait endpoint.
  Strafe also needs a second camera angle and groundedness review. The
  transition endpoint needs a better neutral gait phase/pose and shared
  weight transfer, then another save/reopen, played contact audit and movie
  pass. The operation ledger stays partial until this is fixed.
- Tested candidate gait phases through live Godot AI, not a hand-edited
  animation. Phase 0.30 gave a calmer X Bot endpoint and passed 30/60/120
  contact checks on X Bot, dummy, half-size and Z-up tall rigs, yet travelled
  only 2.26 cm on X Bot. That is insufficient for a walk start, so this
  candidate is **rejected** despite its green audit. Phase 0.15 travelled
  18.32 cm and passed X Bot contact checks, but its saved Movie Maker
  transition still ends in a pronounced stride. Reducing default knee bend
  from 30 to 16 degrees as an explicit request also passed numerical checks
  but barely improved the silhouette. No default values were changed by
  these experiments. Logs and contact sheets named `*phase030*`,
  `*phase015*` and `*knee16_phase030*` preserve the comparisons. The next
  repair must model support transfer and a continuous start→cycle→stop
  sequence, with body travel included in the visual acceptance gate.

### 2026-10-01 — Phase 3/4, forward stop and composable root travel

- Built `walk_start`, `cycle` and `walk_stop` on one X Bot through Godot AI,
  then invoked unpromoted `animation_sequence.compose` through
  `custom_manage`, saved/reopened, and played the resulting single-player
  clip. The first composition returned success with 22 resolved tracks but
  failed contact badly: 0.834 m left and 1.140 m right planted-foot slide.
  Its source root tracks each began at zero, so the compositor reset travel
  at both segment boundaries. `SequenceSpecs.compose` now carries the
  configured AnimationPlayer root track's displacement into each segment,
  including an overlap's actual start. An editor regression checks both a
  contiguous seam and overlapping blend. The same live route rebuilt and
  saved the sequence; `motion_audit` passed at 241 samples with 1.140 m net
  travel and no failed contact checks (`mcp_locomotion_sequence_first.log`,
  `mcp_locomotion_sequence_root_carry.log`).
- That pass still hid a directional defect: the old `walk_stop` was a
  time-reversed start, so its extracted root moved **backward** while the
  planted foot stayed fixed. Replaced this with an explicit forward stop:
  the leading foot lands, root travels forward, and the former support foot
  lifts into the neutral endpoint. A leftover pelvis endpoint override
  initially kept a 4.5-degree gait rotation at the final frame; the editor
  regression caught its 6.7 cm foot offset, and the stop now ends at the
  rig rest pose. A new test requires every rooted start and stop key to move
  forward. Editor suite: **216/216** on Godot 4.7.2.
- Fresh Godot AI route, dry run, typed invalid target, save and forced reopen
  for `walk_stop` pass on dummy, X Bot, half-size and Z-up tall fixtures.
  Played contact audits pass at 30/60/120 FPS under the same 16/16/8/25 mm
  slide caps, with forward travel of 0.205/0.217/0.152/0.260 m, respectively
  (`mcp_*_walk_stop_forward*.log`). The rebuilt X Bot
  start→walk→stop sequence now passes its 241-sample played audit with
  **1.573 m** net travel (`mcp_locomotion_sequence_forward_stop.log`).
  Fixed-camera Godot Movie Maker recorded 132 frames at 60 FPS with no
  runtime errors; sheet and PNGs are in
  `media/xbot_start_walk_stop_forward`. It has continuous forward staging
  and a neutral stop but a stylized, deep stride; full visual approval is
  still pending. All 14 tier-1 suites and the 216 editor tests pass on
  Windows. `animation_sequence.compose` and `walk_stop` remain partial in
  the ledger pending broader visual, undo and Linux checks.

### 2026-10-01 — Phase 3, strafe foot spacing and played crossing gate

- A front fixed-camera view of the imported X Bot revealed crossed feet in
  the original strafe even though its contact, penetration and knee checks
  passed. The 14-degree default lateral stride spanned about 0.43 m across
  ankles only about 0.16 m apart. The old saved clip remains at run
  `20261001_090436`; `motion_audit` with `motion_kind=strafe` now reports a
  **−0.1862 m** minimum signed lateral ankle gap and fails `foot_crossing`
  at 30/60/120 FPS. The prior green contact result did not approve its
  visual behavior. Before sheet: `media/xbot_strafe_front/sheet.png`.
- `MotionSpecs.gait_keys` now caps a lateral step to 80% of rest ankle
  spacing, reports the effective speed and cap, and the motion handler
  returns typed `VALUE_OUT_OF_RANGE` when an explicitly requested speed
  requires crossing. A rig with coincident rest ankles is rejected with
  `INVALID_PARAMS` before it can produce an inert clip. The default X Bot
  clip was regenerated **through the
  live Godot AI MCP route**, dry run left no clip, write/save/force-reopen
  preserved 21 resolved tracks, and an invalid skeleton gave typed
  `NODE_NOT_FOUND` (run `20261001_161512`). Its effective speed is
  0.2189 m/s and it travels 0.2189 m over the cycle. After front sheet:
  `media/xbot_strafe_foot_spacing_front/sheet.png`.
- `motion_audit` now has `motion_kind=strafe` and checks signed lateral foot
  order from **played world-space ankle poses**. The new X Bot clip keeps a
  0.0547 m minimum gap. Fresh Godot AI clips on the dummy, half-size and
  Z-up tall rigs (runs `20261001_161945`, `20261001_161955`,
  `20261001_162004`) keep 0.0588/0.0323/0.0941 m minimum gaps and travel
  0.2353/0.1294/0.3766 m. All four pass the 30/60/120 FPS contact and
  crossing audit under 16/16/8/25 mm slide caps; worst measured stance
  slide is 1.9 mm. Evidence:
  `logs/mcp_*_strafe_gap_audit.log` in the recovery snapshot. The new
  editor regressions cover the crossing check and coincident rest ankles;
  editor suite **218/218**, tier-1 **14/14** on Godot 4.7.2. Full visual approval,
  undo for this operation, and Linux CI remain open.

### 2026-10-01 — Phase 3, walk silhouette experiments rejected

- The default X Bot start→cycle→stop sheet still shows an overly crouched,
  long-stride walk. I added optional stride and knee-bend arguments to the
  live Godot AI review scripts and generated saved `cycle` clips with
  `stride=18,knee_bend=30`, `stride=24,knee_bend=0` and
  `stride=18,knee_bend=0`. Each passed the 30/60/120 FPS played contact
  audit; the shorter stride travelled 0.866 m per cycle versus the 1.140 m
  default. Their fixed-camera sheets are in `media/xbot_cycle_stride18`,
  `media/xbot_cycle_knee0_stride24` and
  `media/xbot_cycle_knee0_stride18`.
- Composed start→cycle→stop candidates with `stride=18,knee_bend=0`,
  `stride=18,knee_bend=8`, and `stride=24,knee_bend=8` through the real
  `custom_animation_motion` and `custom_manage(animation_sequence)` routes.
  All saved/reopened and passed the played sequence contact audit (worst
  stance slide 1.5/1.7/2.2 mm); Movie Maker rendered 132 frames each.
  The sheets are in `media/xbot_start_walk_stop_knee*_stride*` with matching
  `mcp_locomotion_sequence_knee*_stride*.log` route evidence.
- Lower crouch improves the silhouette but increases the solver's reported
  unreachable ankle-target shortfall: the default X Bot cycle reports
  0.017 m; the knee 0/stride 18, knee 8/stride 18 and knee 8/stride 24
  candidates report **0.064/0.041/0.078 m**. The independent half-size
  rig also exceeds its 5%-of-leg reach budget when knee bend 8 is made the
  default. These candidates are **rejected as defaults** despite green
  contact checks. The default remains knee bend 30 and stride 24; 14/14
  tier-1 suites pass after restoring it. Next, the pelvis trajectory and
  reachable step targets need a coordinated solve, followed by new
  cross-rig contact and visual review. The experiment exposes why the
  audit must report reach shortfall as a quality gate.
- The gait result now emits an actionable warning when an ankle target was
  shortened by more than 1% of leg length; previously only the boolean and
  raw metre shortfall were returned. A fresh live Godot AI X Bot cycle
  (run `20261001_164224`) reports its actual 0.017 m / 1.9% shortening and
  suggests reducing stride/speed or lowering the pelvis. The editor test
  checks the warning for an impossible requested speed. This **reports**
  degraded reach; it does not approve or repair that gait. Windows suites:
  14/14 tier-1 and 218/218 editor tests.
- `motion_audit` now reports each leg's smallest **played** knee angle and
  greatest hip-to-ankle extension, with times, under `feet.*.pose_range`.
  This is a diagnostic, not a new pass criterion. On saved X Bot cycles at
  120 FPS, the default reaches 116.4/116.9° minimum knee angles and
  0.999 leg-length extension; the knee-0/stride-24 candidate reaches
  145.5/146.5° with the same near-full extension, and knee-0/stride-18
  reaches 150.5/151.7°. The latter's solver shortfall remains 0.064 m,
  so a straighter pose alone does not prove reach. Logs:
  `mcp_xbot_*_pose_range.log`. Editor test checks the metric shape; suite
  **218/218** on Godot 4.7.2. A future quality limit needs cross-rig
  calibration before it can judge these angles.

### 2026-10-01 — Phase 3, reachable default walk and cross-rig playback

- **Changes:** `MotionSpecs.gait_keys` plans one periodic pelvis path against
  both legs' two-bone reach before solving the feet. It spreads the required
  vertical drop over neighbouring keys, then shares those offsets between the
  hips track and both IK solves. When the first plan is infeasible, it searches
  for a reachable shorter span. An implicit speed reports the reduced speed;
  an explicit speed returns typed `VALUE_OUT_OF_RANGE` before any write.
  A residual walk target shortfall over 1% of leg length is also rejected.
  Default walk knee bend is now 8 degrees, with the old 30-degree default
  preserved in the pre-change snapshot. `character_setup` now omits its
  1.4 m/s walk assumption and lets the rig choose a reachable default speed;
  explicit requests remain exact or fail. The schema, README and tool
  reference describe that contract. Old and new golden walk fixtures are
  retained at `goldens_before_reach_pelvis/` and in the working tree.
- **Numerical evidence:** After restarting the visible Godot 4.7.2 editor,
  live Godot AI created default `cycle`, `walk_start` and `walk_stop` clips on
  the dummy, X Bot, half-size and Z-up tall rigs, with dry run, write,
  save/forced reopen and typed missing-target checks. Runs
  `20261001_173338`, `20261001_173347`, `20261001_173355` and
  `20261001_173403` passed with zero cycle reach shortfall. All 36 saved
  played-world audits at 30/60/120 FPS passed contact, penetration and
  knee-pole checks; worst stance slide was 2.5 mm on the half-size rig.
  Logs are `logs/mcp_*_walk_default_reach.log` and
  `logs/mcp_*_walk_default_played_audit.log` in the recovery snapshot.
- **Godot AI composition and setup:** `animation_sequence.compose` rebuilt
  the default X Bot start→walk→stop clip through `custom_manage`, saved and
  reopened it (run `20261001_173502`). The 241-sample played audit passed
  with 1.5734 m forward travel. A separate live `character_setup` call with
  omitted speed chose 1.08015 m/s on the dummy; a request for 8 m/s returned
  `VALUE_OUT_OF_RANGE` with a 1.229 m/s reachable limit and left no clip
  (run `20261001_173756`). Logs: `mcp_xbot_sequence_default_reach.log`,
  `mcp_setup_auto_walk_reach_verified.log`.
- **Visual decision:** Movie Maker rendered 132 frames at 60 FPS without
  runtime errors. `media/xbot_start_walk_stop_default_reach/sheet.png`
  shows a less persistently crouched walk than the old default, but its
  weight transfer and step silhouette remain stylized. A heavy-style trial
  with bob multiplier 3.0 passed numerical checks yet looked too compressed
  in `media/xbot_cycle_heavy_reach/sheet.png`; that multiplier was reverted
  to 1.5. Visual quality is **not approved**. The test now distinguishes
  authored bob from the final reach-adjusted pelvis excursion.
- **Tests and status:** Godot 4.7.2 Windows tier-1 **14/14** and editor
  **218/218** after the final source change. The 103-row operation audit
  still reports **0 verified**, as its strict per-operation visual, undo and
  Linux gates are not complete. The branch remains unreleased. Next: improve
  the walk's visible weight transfer without losing zero reach shortfall;
  then close operation-specific undo and Linux evidence before promoting
  any row to verified.

### 2026-10-01 — Phase 3, shorter walk default selected

- **Candidate comparison:** The reach-aware 24-degree X Bot cycle required
  up to 0.092 m extra pelvis drop and moved at 1.140 m/s. An 18-degree
  config needed 0.047 m drop, moved at 0.866 m/s, and produced a more upright
  fixed-camera start→walk→stop sheet with zero reach shortfall. The composed
  candidate moved forward 1.1954 m and passed its 241-sample contact audit.
  Before/after sheets are `media/xbot_start_walk_stop_default_reach/sheet.png`
  and `media/xbot_start_walk_stop_reach_stride18/sheet.png`. This is a casual
  walk default; callers can request faster reachable speeds or shorter cycle
  durations. Full human visual approval of the character set is still open.
- **Decision and regression:** Walk config stride changed from 24 to 18
  degrees while knee bend stays 8. Previous goldens are in
  `goldens_reach_pelvis_stride24/`; the current walk goldens were regenerated
  on Godot 4.7.2. The 14 tier-1 suites and 218/218 editor tests pass. The
  tool reference now states the shared reach solve and separate character
  root track accurately.
- **Exact default route:** After restarting the visible Godot 4.7.2 editor,
  Godot AI created the default `cycle`, `walk_start` and `walk_stop` on all
  four rigs without overrides (runs `20261001_195315`, `20261001_195323`,
  `20261001_195332`, `20261001_195340`). Dry run, write, save, forced
  reopen and typed invalid-target checks passed. All 36 played 30/60/120
  FPS contact, penetration and knee-pole audits passed; worst stance slide
  was 4.6 mm on the half-size rig under its 8 mm cap. All four cycles report
  zero foot-target shortfall. The default X Bot sequence saved and reopened
  through `custom_manage`, passed its 241-sample played audit and rendered
  132 frames without errors (run `20261001_195436`). Its final contact sheet
  is byte identical to the reviewed 18-degree candidate. `character_setup`
  chose a 0.82064 m/s walk on the dummy; an 8 m/s request returned typed
  `VALUE_OUT_OF_RANGE` with a 1.229 m/s limit and no scene mutation (run
  `20261001_195442`). `editor_reload_plugin` restored eight promoted tool
  names and all ten families on the same live Godot AI server.
- **Open gates:** The visual review still flags stylized weight transfer and
  the 103-operation ledger stays at zero verified because per-operation
  visual, undo and Linux checks are incomplete. No release or merge.

### 2026-10-01 — Phase 3/4, live editor Undo/Redo for locomotion ownership

- Created fresh clips and a character setup through the connected Godot AI
  MCP route in the visible 4.7.2 editor, then used the editor's Ctrl+Z/Ctrl+Y
  actions. `cycle` and `walk_stop` each disappeared on undo and returned with
  21 resolved tracks on redo. One `character_setup` undo removed its four
  clips and AnimationTree together; redo restored the clips, tree and
  `Dummy:position` root-motion path on both player and tree.
- A fresh `animation_sequence.compose` used the three Godot AI-created source
  clips. One undo removed only `start_walk_stop`; the source `cycle` retained
  22 tracks. Redo restored the 22-track composed clip. The source scene was
  intentionally left unsaved during this test so the editor undo stack could
  be examined. Logs `mcp_*_ui_undo*.log` and `mcp_*_ui_redo*.log` in the
  snapshot record MCP inspections before/after the UI action.
- The operation ledger now marks UI undo/redo passing for these four rows
  (and the previously checked `walk_start`). Other operations still need
  their own undo evidence; the 103-row audit remains at zero fully verified.

### 2026-10-01 — Review branch CI fixture correction

- Pushed the unreleased `repair/toolkit-quality` branch and opened draft PR #1.
  The first GitHub Actions run passed all 28 tier-1 matrix jobs. All four
  Windows/Linux editor jobs reached 217/218: their sole failure was the X Bot
  playback test expecting `res://models/x_bot/X Bot.fbx`, a third-party local
  review asset intentionally absent from the repository. Both platform logs
  report no tool-route errors.
- The X Bot test now explicitly skips only when that review asset is absent.
  It still runs normally when X Bot is installed; the local Godot 4.7.2
  editor run with the asset present passed 218/218 with zero skips. CI must
  rerun after this correction. The missing CI asset does not count as visual
  approval of X Bot motion; local played/rendered evidence remains in the
  snapshot and the broader visual gate remains open.

### 2026-10-01 — Phase 2 audit freshness gate

- The registry-driven exporter now fails if any advertised operation lacks an
  explicit row in `docs/operation-evidence.json`, as well as when evidence
  names an operation removed from the registry. The pinned Linux editor CI
  leg regenerates `docs/operation-audit.json` and fails on a diff. This keeps
  registry changes and the review ledger tied together without pretending
  that a pending check has passed.
- On Windows Godot 4.7.2, export reported `103 operations, 0 verified` and
  left the committed audit unchanged; `git diff --check` passed. The 103
  evidence rows are all present. Visual, per-operation undo and cross-platform
  live MCP checks remain required before any row can become verified.
- The corrected second GitHub Actions run (`36919998639`) completed green:
  all 28 tier-1 jobs and all four Windows/Linux editor jobs passed against the
  pinned and current core. This confirms the optional-fixture skip on a clean
  checkout. The subsequent audit-freshness run (`36920325900`) also completed
  green on both operating systems and both core refs.

### 2026-10-01 — Phase 1/2, external family routing and rig isolation

- Expanded `mcp_probe.py` to activate the sole editor session, check the
  eight promoted schemas and ten-family catalog, and invoke an invalid op in
  **each** family through the external Godot AI MCP client. It also calls a
  rig modifier through `animation_rig` and a rig pose through
  `animation_rig_modifiers` to ensure cross-family requests are rejected.
- This found a real defect: both rig families share `rig.gd`; the unpromoted
  modifier family reported the rig family's choices, and because Godot AI
  forwards custom-tool params without enforcing the schema, a stale caller
  could dispatch an operation through the wrong family. The handler now gates
  on `ctx.spec.name` before any mutation. A fresh visible 4.7.2 editor and
  live MCP probe returned `VALUE_OUT_OF_RANGE` with the correct five modifier
  choices for both cross-family calls. The editor suite passed with the new
  regression test (219/219); logs are
  `editor_rig_family_gate_20261001.log` and `mcp_rig_family_gate_20261001.log`
  in the recovery snapshot.
- Added `tools/ci_mcp_route.py` and Windows/Linux CI jobs that install the
  pinned Godot AI backend, start a fresh headless 4.7.2 editor, then run the
  external probe before and after `editor_reload_plugin`. The launcher passed
  all three stages against the existing visible Windows editor. Fresh-runner
  CI run `36921193733` passed on Linux. Windows reached the launcher after
  installing the backend, then failed before editor startup because Python's
  Win32 process API could not execute the extensionless `godot` shim placed on
  PATH by setup-godot. The first correction also failed before startup because
  `bash` resolved to WSL on that runner, which has no distribution. The
  pinned setup-godot action installs the actual Windows executable at
  `%USERPROFILE%/godot/Godot_v4.7.2-stable_win64.exe`; the launcher now uses
  that path with Win32 CreateProcess. CI run `36921964461` confirmed it: all
  28 tier-1 jobs, all four editor jobs, and both live MCP route jobs passed.
  Each platform's MCP job found ten families, returned typed errors for their
  unknown-operation probes, rejected cross-family rig calls, and passed again
  after a core-plugin reload. This route check
  establishes family access and typed rejection; per-operation valid effects
  remain in the audit ledger.
- Normalized the five motion/sequence `pass_editor_ui` undo labels to the
  ledger's actual `pass` value; the evidence strings retain the UI method and
  run logs. The regenerated 103-row audit now counts six real UI undo/redo
  passes including `animation_presets.pulse`. Editor-only or incomplete undo
  checks retain their qualified states, and no operation is marked verified.

### 2026-10-01 — Phase 1, valid external MCP effect in the CI probe

- The external route probe now opens an isolated generated scene, calls
  `animation_presets.pulse` in dry-run and write modes, confirms dry run leaves
  clip inspection unchanged, saves, force-reopens, and checks the one-track
  result resolves to a real node. The same check runs before and after a
  core-plugin reload on each CI platform. This closes the registration test's
  previous blind spot: typed unknown-op errors alone proved handler reachability
  but not a useful generated clip.
- A local visible Godot 4.7.2 run of the three-stage probe passed; the saved
  scene is under ignored `test_project/repair_mcp_ci/`. The first local try
  misread Godot AI's flattened successful MCP payload (`dry_run` is top-level),
  then the assertion was corrected. Log `mcp_valid_pulse_dry_20261001.log` in
  the snapshot records the successful result. CI run `36922916346` then passed
  all 34 active jobs, including the expanded live MCP probe on Windows and
  Linux. Its two release-only jobs were skipped as expected for a draft PR.

### 2026-10-01 — Phase 3, pelvis yaw axis correction candidate

- Found `hip_yaw` applied around the rig's lateral axis in the shared gait
  generator. That is a pitch, while the torso's counter-yaw already uses the
  rig-relative up axis. Changed the pelvis channel to rotate about `ctx.up`.
  This keeps the same semantics on Y-up and Z-up rigs and removes a misleading
  pitch source from walk, run and strafe.
- The first test pass found only the expected walk/run/synthetic golden drifts
  and one one-shot assertion that used thigh rotation as a proxy for preserving
  a gait endpoint. The assertion now checks the pelvis rotation, the channel
  that actually carries the yaw endpoint. Previous goldens were backed up in
  `goldens_before_pelvis_yaw_axis/` and regenerated on Godot 4.7.2.
- Windows verification after regeneration: 14/14 tier-1 suites, 219/219 editor
  tests, live Godot AI default X Bot start→walk→stop composition, saved/reopened
  241-sample played audit, and individual dummy/X Bot walk save/reopen audits.
  The composed clip traveled 1.1954 m and reported no failed contact checks;
  both individual walks passed before and after reopen. Logs
  `mcp_pelvis_yaw_candidate_20261001.log`,
  `mcp_dummy_pelvis_yaw_walk_20261001.log`, and
  `mcp_xbot_pelvis_yaw_walk_20261001.log` preserve the exact route results.
- Godot Movie Maker rendered 132 frames at 60 FPS from fixed side and front
  cameras. Compare `media/xbot_start_walk_stop_final_default[_front]/sheet.png`
  with `media/xbot_start_walk_stop_pelvis_yaw_candidate[_front]/sheet.png` in
  the recovery snapshot. The pelvis rotation is semantically correct and the
  contact tests remain green, but the visible weight transfer improvement is
  modest. Human visual approval remains open; this is a reviewed candidate,
  not a claim that the walk is finished. Cross-platform CI for this source
  change remains pending.

### 2026-10-02 — Crash recovery and synthetic gait validation

- Relaunched the visible Godot 4.7.2 editor after the PC crash. Godot AI's
  managed server did not start on the first launch because the development
  venv path was missing from that process environment. Relaunching with
  `GODOT_AI_VENV_PYTHON` restored the editor's authenticated server on HTTP
  18131 / WebSocket 18132. A fresh external MCP probe found all ten toolkit
  families, all eight promoted family tools, typed invalid-op errors and
  correct cross-family rig rejection. The recovery startup log is
  `logs/godot_relaunch_20261002.log` in the snapshot.
- On the pelvis-yaw candidate, live Godot AI generated `cycle`, `walk_start`
  and `walk_stop` on both the short and Z-up tall synthetic rigs. All six
  operations passed dry-run immutability, save/force-reopen track resolution
  and typed invalid-skeleton checks. Played world-space audits passed at
  30, 60 and 120 FPS: 18/18 rig-operation-FPS rows, including contact,
  sliding, penetration and continuity checks. Logs
  `mcp_synthetic_{short,zup}_candidate_20261002.log` and
  `mcp_synthetic_{short,zup}_played_20261002.log` preserve the results.
- This establishes a useful cross-orientation regression for the yaw-axis
  correction. Broader visual approval and the per-operation audit remain
  open; the candidate is not a declaration that character motion is finished.
- Commit `0bde3cc` passed GitHub Actions run `37029256017`: all 28 tier-1
  jobs, four editor suites and both live MCP route jobs passed on Windows and
  Linux. The local duplicate-UID warnings after crash recovery came from two
  ignored, hand-copied review scenes. Their header UIDs were stripped in the
  local workspace; no tracked scene changed. Reviewing the fixed-camera side
  and front sheets again confirms the yaw correction is small visually and
  the walk's weight transfer remains unapproved.

### 2026-10-02 — Make played motion failures fail the live route

- Found that `mcp_motion_audit_saved.py` printed `passed=false` and
  `failed_checks` but exited zero whenever the MCP calls themselves returned
  without an error. The harness now returns nonzero for either failed checks
  or missing/false `passed`, and prints a compact failed-operation summary.
  A deliberately strict 0.1 mm slide cap failed two of three short-rig cycle
  samples with exit 1; the normal 8 mm cap passed all nine short-rig
  cycle/start/stop samples with exit 0. Evidence is in
  `mcp_audit_{expected_failure,positive_gate}_20261002.log`.
- The Windows/Linux live MCP CI route now creates dummy `cycle`, `walk_start`
  and `walk_stop` clips through Godot AI, verifies dry-run immutability,
  save/force-reopen and typed invalid-skeleton errors, then audits saved
  playback at 30/60/120 FPS with a 16 mm stance-slide cap. It runs after
  the existing before/reload/after tool-registration checks. Against the
  visible Godot 4.7.2 editor, the full route passed all three registration
  stages plus nine played audits (`ci_mcp_motion_gate_20261002.log`).
  GitHub Actions run `37030148239` then passed all 28 tier-1 jobs, four
  editor suites and both expanded live MCP jobs on Windows and Linux. The
  `cycle`, `walk_start` and `walk_stop` evidence rows now record Linux as
  partial with that specific dummy-rig route/contact evidence; regenerating
  the registry audit still reports 103 partial and 0 verified operations.

### 2026-10-02 — Character sheet review beyond the walk

- Revisited the fixed-camera X Bot idle, jump, turn and front strafe sheets
  under `media/` in the recovery snapshot and recorded each as a partial
  visual check in the operation ledger. The jump's crouch, airborne interval
  and landing are readable in sampled frames. Idle motion is subtle in stills.
  The turn changes heading, but the planted-foot pivot or stepping pattern is
  unclear. The corrected strafe keeps its ankles in order, yet its base closes
  narrowly and the weight transfer is weak. Continuous playback and
  operation-specific pose/contact review are still required; none of these
  four operations is visually approved.
- The next motion decision is to refine side-step and turn support poses and
  review full-rate playback, while keeping contact and reach measurements
  as regression gates. No generator default changed from this sheet review.

### 2026-10-02 — Strafe knee-bend experiment through Godot AI

- Extended the live motion fixture harness so strafe accepts the same
  knee-bend, stride and style overrides as walk. Godot AI created isolated
  X Bot strafe clips with knee bend 8 and 16 (runs `20261002_160441` and
  `20261002_160650`); dry runs were inert, saved tracks resolved after forced
  reopen and invalid skeletons returned typed errors. Both passed saved
  played contact/crossing audits at 30/60/120 FPS under 16 mm slide.
- The default 35-degree, 8-degree and 16-degree clips all kept 0.0547 m
  minimum ankle spacing and traveled 0.2189 m. At 120 FPS, their minimum
  knee angles were about 117.6, 144.0 and 134.7 degrees. The 8-degree
  candidate nearly locked a leg (0.999 extension ratio, 0.24 mm reach
  clamp); 16 degrees kept 0.971 maximum extension and zero clamp. Godot
  Movie Maker rendered 61 front-camera frames for each candidate without
  errors. Sheets `media/xbot_strafe_knee{8,16}_front/sheet.png` show a
  straighter 16-degree pose but still weak sideward weight transfer. The
  default stays at 35 until the support pose is redesigned and the full
  character/rig matrix is reviewed.

### 2026-10-02 — Reject inert played gait in the CI probe

- Strengthened the live MCP CI motion gate to require exactly the three
  requested operations and all nine op/FPS rows. Each saved played clip must
  move the dummy more than 0.1 m; a contact-clean but stationary result now
  fails CI. The visible Godot 4.7.2 editor passed the full probe again after
  plugin reload (`ci_mcp_motion_noninert_20261002.log`). GitHub Actions run
  `37032204179` passed all 28 tier-1, four editor and two live MCP jobs on
  Windows and Linux with this additional assertion.

### 2026-10-02 — Verify `graph_get` topology as a read-only operation

- Tightened `mcp_graph_audit.py` for `animation_graph.graph_get`. The live
  Godot AI result must name both `idle` and `walk` animations and states,
  include the `idle`→`walk` transition, remain identical after save/forced
  reopen, and return typed `NODE_NOT_FOUND` for a missing tree. Dry-run
  graph root and parameters must remain unchanged. The focused Windows
  Godot 4.7.2 run `20261002_161310` passed with zero failures; log
  `mcp_graph_get_contract_20261002.log` preserves the response. The ledger
  now records this read-only effect and its inapplicable clip/undo checks.
  The focused check was added to the pinned Windows/Linux live MCP CI route;
  the visible editor passed all registration, motion and graph stages in
  `ci_mcp_graph_get_20261002.log`. Full graph-family playback remains open.
- The first Windows CI attempt in run `37032883288` failed before any toolkit
  call: Godot AI core reported that it could not capture its managed server
  process identity (`identity_unavailable`), and MCP saw zero editor sessions.
  Linux passed. Rerunning only the failed Windows job with identical source
  passed registration, saved motion and `graph_get`; run attempt 2 is green.
  The ledger now marks Linux `graph_get` coverage partial. This startup
  failure is still an observed core/runner reliability risk, not a toolkit
  graph failure.

### 2026-10-02 — Full post-yaw motion matrix on four rigs

- Rebuilt and force-reopened the seven `idle_cycle`, `cycle`, `jump`,
  `turn_cycle`, `strafe_cycle`, `walk_start` and `walk_stop` clips through live
  Godot AI on the bundled dummy and local X Bot. Built the remaining four
  operations on the short and Z-up tall synthetic rigs, complementing their
  earlier post-change walk/start/stop checks. All 28 rig-operation cases
  passed dry-run immutability, resolved saved tracks and typed missing-rig
  errors (runs `20261002_163002`, `163053`, `154328`, `154352`, `163150`,
  `163233`).
- Played world-space audits passed **84/84** cases at 30, 60 and 120 FPS.
  Slide caps were 16 mm for dummy/X Bot, 8 mm for short and 25 mm for Z-up
  tall. The largest reported stance slide was 15.2 mm, largest penetration
  1.4 mm and smallest signed strafe ankle gap 32.3 mm. The saved-audit
  harness now exits nonzero on failed checks, so these passes are not merely
  successful MCP responses. Logs `mcp_*full_motion_pelvis*`,
  `mcp_*remaining_pelvis*`, `mcp_synthetic_*played_20261002.log` and
  `mcp_synthetic_zup_strict_played_20261002.log` are in the recovery
  snapshot. Visual quality and a four-rig Linux matrix remain open.

### 2026-10-02 — Move gait sway toward the planted leg

- Rig analysis defines `lateral` from the right hip toward the left hip. At
  quarter-cycle the left foot is planted, but gait sway had a negative sine
  amplitude and moved the pelvis toward the swinging right leg. Changed that
  sign in the shared gait recipe and added a tier-1 stance-side assertion on
  0.50, 0.85 and 1.70 m synthetic legs. The assertion passed before golden
  regeneration; the old spec golden failed by 82 quantized units as expected.
- Rendered 61 fixed-camera frames from live Godot AI-created X Bot walk clips
  before and after the change. The first review wrappers accidentally pointed
  at an old strafe clip and a missing clip; those sheets were discarded. The
  corrected front sheets are `media/xbot_walk_sway_{before,candidate}_front_fixed/sheet.png`
  in the 2026-09-30 recovery snapshot. The candidate shifts the pelvis toward
  support, but the visible change is subtle. A side sheet of the fresh run
  preset is `media/xbot_run_sway_candidate_side/sheet.png`; run remains only
  partially visually reviewed.
- Extended the live MCP fixture harness with `run_cycle` as a separate test
  case that calls `animation_motion.cycle` with `preset=run`. Fresh Godot AI
  dry/write/save/forced-reopen/typed-error checks passed for eight cases on
  the dummy and X Bot, and for the same eight cases across two runs each on
  the short and Z-up tall synthetic rigs. All **96/96** saved played audits
  passed at 30/60/120 FPS. Maximum stance slide was 15.2 mm, maximum ground
  penetration 5.5 mm and there were zero knee-pole flips. Strict slide caps
  remained 16/16/8/25 mm for dummy/X Bot/short/Z-up. Logs are
  `mcp_*sway_{candidate,remaining,full}*20261002*.log` in the snapshot.
- Backed up the previous three affected goldens under
  `goldens_before_sway_sign/`, then recorded replacements with Godot 4.7.2.
  All 14 tier-1 suites and all 219 editor tests passed on a second run against
  those fixtures. This is a support-direction fix with numerical regression
  coverage, not final approval of the walk, run or strafe visual quality. CI
  and Linux's full four-rig matrix remain to check.
- Added the run preset to the pinned Windows/Linux live MCP gate. A local
  `--existing` pass through the visible Godot 4.7.2 editor passed registration
  before/after core reload, four saved motion cases and all 12 played FPS
  rows, plus graph lookup (`ci_mcp_run_preset_existing_20261002.log`). Its
  cross-platform CI result is green: GitHub Actions run `37037107642` passed
  the sway change, and run `37037421063` passed the expanded run-preset gate
  across Windows and Linux (28 tier-1, four editor and two live MCP jobs).
- Reviewed fresh X Bot front-camera strafe sheets before and after the shared
  sway change (`media/xbot_strafe_sway_{before,candidate}_front/sheet.png`).
  Both remain a narrow shuffle. A separate live Godot AI candidate with
  0.06 m sway and 16-degree knee bend (run `20261002_165917`) passed
  dry/write/save/forced-reopen/typed errors and three played FPS audits, with
  54.7 mm minimum ankle gap, 1.8 mm worst slide and approximately 135-degree
  minimum knee angle. Its front sheet is
  `media/xbot_strafe_sway006_knee16_front/sheet.png`. The posture is more
  upright but weight transfer still reads weakly, so the default stays as it
  is. The next strafe phase needs a support-foot and pelvis pose redesign,
  followed by another four-rig played audit and continuous visual review.

### 2026-10-02 — Gate saved graph playback ownership

- Added `verify_saved_graph_playback.gd`, which loads Godot AI-created,
  editor-saved graph scenes in a fresh Godot 4.7.2 process. It enables the
  AnimationTree and checks idle→walk state-machine travel or blend-space
  walk→run switching. The state-machine fixture's Character reaches x=50
  after half a second while its AnimationPlayer remains idle; saved
  `blend_space` and `locomotion` fixtures reach about x=48.3 and switch to
  faster run playback. Checks passed the earlier full graph-audit scenes and
  the focused `graph_get` fixture (`graph_saved_playback_first_20261002.log`,
  `graph_get_saved_playback_20261002.log`).
- The pinned Windows/Linux live MCP CI route now runs this fresh-process
  playback check after save/forced-reopen topology checks for `graph_get`,
  `blend_space` and `locomotion`. Local `--existing` route passed registration
  before and after core reload, 12 motion FPS rows and all three graph
  playback paths (`ci_mcp_graph_three_existing_20261002.log`). GitHub Actions
  run `37038543479` passed the first state-machine-only version and run
  `37038999141` passed the three-graph expansion across Windows and Linux. Other graph
  shapes and gameplay-driven state transitions still need saved playback
  checks before visual approval.

### 2026-10-03 — Expand saved graph playback to seven operations

- Extended the fresh-process verifier for `blend_tree`, `one_shot_layer` and
  `additive_lean`. On editor-saved fixtures, Blend2 moves the Character to
  x=50 after half a second, the one-shot jump reaches y=-77.3 and additive
  lean reaches 0.116 radians. Their AnimationPlayers remain idle while their
  AnimationTrees drive playback. The earlier state machine, blend space,
  `graph_get` fixture and locomotion checks still pass on Godot 4.7.2.
- Expanded the live Godot AI CI route to create, save, force-reopen and play
  seven graph cases after a core-plugin reload. The local `--existing` run
  passed registration, 12 saved motion FPS rows, graph topology and all seven
  saved playback checks (`ci_mcp_graph_seven_existing_20261002.log`). GitHub
  Actions run `37070326691` passed the seven-graph expansion on Windows and
  Linux. Graph visual and gameplay transition review remain open.

### 2026-10-03 — Verify `wire`'s structural and parameter effects

- A bare `wire` call intentionally creates an inactive AnimationTree linked to
  the requested AnimationPlayer without a playback root. The live graph audit
  now checks that this structure survives save/reopen instead of pretending a
  clip should play. Added a second `wire_parameter` case: create a conditional
  idle→walk state machine, then call `wire` with `active=true` and
  `parameters/conditions/walking=true`. Godot AI dry/write/save/forced-reopen
  checks passed (run `20261002_220400`); a fresh Godot 4.7.2 process verified
  the saved condition and active flag, then the tree advanced the Character to
  x=48.3 with the AnimationPlayer idle. Logs `mcp_graph_wire_parameter_20261003.log`
  and `graph_wire_parameter_saved_playback_20261003.log` are in the snapshot.
- The nine-case local live route passed all structural checks and eight saved
  playback paths after core reload (`ci_mcp_graph_nine_existing_20261003.log`).
  Corrected the `wire` registry summary and example: the old example tried to
  set a parameter before any graph existed, which returned an error, and the
  summary implied the default tree was active. The first tier-1 rerun correctly
  caught the stale generated op index; after `tools/gen_docs.ps1`, all 14
  tier-1 suites and 219 editor tests passed on Godot 4.7.2. Windows/Linux CI
  run `37071048211` passed the nine-case gate on Windows and Linux. UI undo
  and visual graph review remain open.

### 2026-10-03 — Verify 2D blend and conditional locomotion modes

- Added separate live Godot AI fixtures for `animation_graph.blend_space` in
  two dimensions and `animation_graph.locomotion` in state-machine mode. Both
  passed dry/write/save/forced-reopen checks and resolved-player topology.
  Fresh Godot 4.7.2 processes played the 2D blend at the walk and run points,
  and the state machine responded to its `walking` and `running` conditions:
  Character x≈48.3 at walk and x≈93.3 at run with the AnimationPlayer idle.
  The first six-frame manual `travel("run")` check failed because these fixture
  clips key absolute position and crossfade to a run clip restarting at x=0;
  testing the intended condition flow over the transition passed. This is a
  fixture playback discontinuity, not evidence that the graph omitted run.
  Logs `mcp_graph_blend2d_20261003.log`,
  `graph_blend2d_saved_playback_20261003.log`,
  `mcp_graph_locomotion_sm_20261003.log` and
  `graph_locomotion_sm_conditions_20261003.log` preserve both results.
- The local live route now passes eleven graph cases after core reload: the
  bare `wire` structural effect and ten fresh-process playback paths, plus
  the 12 saved motion FPS rows (`ci_mcp_graph_eleven_existing_20261003.log`).
  Windows/Linux CI for this expansion remains pending. More natural fixture
  clips and representative gameplay transitions are still needed for visual
  approval.
- Added two editor Undo/Redo tests for `wire`: one restores/removes the bare
  tree, and the other restores/reapplies `active` and the walking condition
  on an existing state machine. All 221 local editor tests pass on Godot
  4.7.2 (`editor_graph_wire_undo_20261003.log`). This checks the editor
  UndoRedo manager through the handler; keyboard-driven undo through the
  external Godot AI route remains to verify.

### 2026-10-03 — Gate all saved rig modifiers on real playback

- GitHub Actions runs `37071590840` (2D blend/conditional locomotion) and
  `37071800484` (`wire` Undo/Redo) passed on Windows and Linux. The latter
  includes 221 editor checks; both live routes passed the eleven graph cases.
- The live Godot AI CI route now invokes all five `animation_rig_modifiers`
  operations through `custom_manage`, checks dry run, typed errors and forced
  save/reopen, then opens each saved scene in a fresh Godot 4.7.2 process.
  Activating the saved IK, spring, look-at, twist and retarget modifiers must
  cause measured bone motion at `modification_processed`. A saved but inert
  modifier fails CI. The local visible-editor run passed all five after core
  reload, along with 12 saved motion FPS rows and ten graph playback paths
  (`mcp_ci_modifiers_live.log` in the recovery snapshot). Windows/Linux CI
  run `37072351007` passed the same five saved playback gates. Other IK
  forms, spring tails, modifier stack order, editor undo and visual
  deformation remain open.
- Added Undo/Redo assertions for `twist_setup` to the editor suite. One undo
  removes the last disperser; redo restores a typed disperser at the same
  scene path. The local Godot 4.7.2 editor suite remains **221/221**
  (`editor_modifier_twist_undo_20261003.log`). Existing editor tests already
  cover undo for IK, spring, look-at and retarget, but their redo behavior and
  keyboard-driven undo through the live Godot AI editor route remain open.
  GitHub Actions run `37072554301` passed the 221-test editor suite and the
  modifier playback gate on Windows and Linux.

### 2026-10-03 — Expand live route to every FX operation

- Repeated all 17 FX cases through the visible Godot AI editor session
  (`mcp_fx_full_repeat_20261003.log`, run `20261002_223116`). Each case
  passed dry run, write, save/forced-reopen, resolved track or SpriteFrames
  checks, and the existing fresh-process Godot 4.7.2 runtime checker.
- Added the full FX audit and all 17 saved runtime checks to the live MCP CI
  gate. The SpriteFrames runtime check now starts the saved four-frame
  animation and observes a frame advance, so frame resources alone do not
  count as playback. The local full-route run passed registration before and
  after core reload, 12 motion rows, ten graph playback paths, five modifier
  callbacks, and all 17 saved FX runtime checks (`mcp_ci_fx_full_live.log`).
  Windows/Linux CI run `37073430671` passed the same FX gate and the other
  live-route and editor jobs. The 16 advertised FX operations now have
  per-operation Linux runtime evidence; `sprite_frames_stopped` is an extra
  `sprite_frames` parameter case. Visual previews, audio audibility and full
  editor Undo/Redo for every FX operation remain open.

### 2026-10-03 — Gate saved clip edits on engine playback

- Repeated the 22-case `animation_edit` audit through the visible Godot AI
  editor (`mcp_edit_full_repeat_20261003.log`, run `20261002_224359`). Twenty
  supported edit cases passed dry/write/save/forced-reopen and resolved-track
  checks. `offset_wrap_reject` and `overlap_wrap_reject` returned typed
  `VALUE_OUT_OF_RANGE` in both dry/write calls and left the clip unchanged.
  Fresh Godot 4.7.2 processes then played all 20 saved valid edits and met
  their operation-specific engine interpolation samples.
- Added those 22 cases to the live MCP CI route. The focused local gate
  passed all 20 saved playback checks (`mcp_ci_edit_gate_local.log`);
  Windows/Linux CI is pending. Visual review, full editor Undo/Redo and
  non-default interpolation/track combinations remain open. GitHub Actions
  run `37074375344` passed all 22 cases and 20 saved playback paths on
  Windows and Linux, together with the earlier motion, graph, modifier and
  FX gates.

### 2026-10-03 — Check saved preset and showcase playback

- Repeated all nine `animation_presets` scenarios through the visible Godot
  AI editor (`mcp_presets_full_repeat_20261003.log`, run `20261002_225011`).
  Dry/write/save/forced-reopen checks passed. The separate Godot AI play/read
  probe measured property changes for each of the eight individual presets.
- Added a fresh-process Godot 4.7.2 verifier that plays each saved preset and
  measures target property changes. It also plays the seven AnimationPlayers
  in the saved showcase and checks their resolved tracks, including 3D
  transform and quaternion tracks. All nine scenes and the focused CI helper
  passed locally (`mcp_ci_presets_gate_local.log`); Windows/Linux CI run
  `37075054528` passed the nine saved playback cases. Fixed-camera visual
  approval and complete editor Undo/Redo remain open.

### 2026-10-03 — Gate library file effects and imported playback

- Repeated the seven `animation_library` operations through the visible
  Godot AI editor (`mcp_library_repeat_20261003.log`, run
  `20261002_225602`). Template save/list/apply/delete and spec
  export/import/apply passed the audit's dry-run, file, typed-error and
  save/reopen checks. A fresh Godot 4.7.2 process played the template-applied
  drift and spec-applied walk on `OtherCharacter`, with source unchanged and
  zero measured position error.
- Added the live library audit and two saved clip playback assertions to the
  CI route. The focused local gate passed (`mcp_ci_library_gate_local.log`),
  followed by Windows/Linux CI run `37075228572`. File rollback semantics,
  UndoRedo promises and visual review remain open.

### 2026-10-03 — Check all inspector operations

- The visible Godot AI route returned expected facts and typed invalid-input
  errors for eight `animation_inspect` operations on a saved clip fixture
  (`mcp_inspect_repeat_20261003.log`). The audit asserts key counts, timeline
  values, clip comparison, a loop seam warning, dry-run prediction and
  registry help coverage. The other four operations (`rig_profile`, `sample`,
  `motion_audit`, `preview`) passed the live 3D audit on the saved dummy walk:
  56 profiled bones, eight paired-foot samples, a passing played contact
  grade and four nonempty preview PNGs (`mcp_inspect_3d_repeat_20261003.log`).
  Each returned a typed error for a missing skeleton. Added both audits to
  live MCP CI; the focused local gate passed
  (`mcp_ci_inspect_twelve_local.log`). Windows/Linux CI run `37108181377`
  passed the eight general inspectors and all four 3D inspector calls under
  their headless contracts.
- The first cross-platform run (`37076000513`) failed its inspector stage on
  both platforms because CI starts Godot with `--headless`: `preview`
  correctly returned typed `INVALID_PARAMS` explaining that a headless editor
  cannot rasterise frames. The CI audit now requires that typed response and
  no claimed PNG output, while the visible-editor audit still requires four
  real PNG files. The visible Godot 4.7.2 rerun passed after this split
  (`mcp_inspect_3d_visible_after_fix.log`). Windows/Linux run `37108181377`
  confirmed the typed headless preview response. Linux visible PNG rendering
  remains untested.

### 2026-10-03 — Gate sequence composition on saved playback

- Repeated `animation_sequence.compose` through Godot AI `custom_manage` on
  a generic two-segment rig fixture (`mcp_sequence_repeat_20261003.log`, run
  `20261002_230856`). Dry run left no clip. Out-of-range source time, late
  first segment and an over-budget output returned typed errors. The composed
  clip and a saved-pose clip survived forced reopen with resolved tracks.
  A fresh Godot 4.7.2 process played the clips: root pose angle rose from
  0.080 to 0.560 radians, the saved pose reached 0.600 radians, and the
  `contact_impact` marker remained at 1.1 s.
- Added this route and saved playback check to CI. Local evidence and the
  focused helper passed (`mcp_ci_sequence_gate_local.log`). Windows/Linux CI
  run `37108181377` passed the sequence route and fresh-process playback.
  Broader boundary/gap/ownership and visual review remain open.

### 2026-10-03 — Remaining-work checkpoint

- The registry still advertises **103 operations**, and the generated ledger
  still marks **103 partial / 0 fully verified**. The counts overlap: 82 rows
  have pending or partial UndoRedo evidence, 30 still have Linux marked
  pending, and 99 have visual review marked pending or partial. The cross-
  platform live route now covers saved motion samples, graph ownership,
  modifiers, FX, edits, presets, library effects, all inspector calls and
  sequence composition. Preview is intentionally a typed unavailable result
  in headless CI, with separate visible-editor PNG evidence.
- Next work order: finish that CI gate; expand actual Godot AI invocation and
  played checks for the fourteen `animation_rig` and remaining motion
  variants; then close the undo gaps and perform fixed-camera visual review
  across families. Character walk/run/strafe and action timing need visual
  improvement before approval. Finally run model-driven prompts in the real
  project, regenerate the audit, and review the draft PR. No release or merge.

### 2026-10-03 — Gate rig operations and saved recipe playback

- Repeated the fourteen `animation_rig` operations through the visible Godot
  AI route in five focused audits. Pose save/apply/list/blend/to-clip, rig-chain
  inspection, pose-sequence baking and all six generated recipes passed their
  dry-run, effect, typed-error and save/reopen assertions. The route logs are
  `mcp_rig_pose_crud_repeat_20261003.log`,
  `mcp_rig_pose_apply_repeat_20261003.log`,
  `mcp_rig_chain_repeat_20261003.log`, `mcp_rig_bake_repeat_20261003.log`
  and `mcp_rig_recipes_repeat_20261003.log` in the recovery snapshot.
- Fresh Godot 4.7.2 processes played the saved pose clip, 24-sample baked
  clip and all six recipe clips. Their expected sampled bone motion matched
  within the 0.02-radian runtime threshold. Added the same five route audits
  and eight saved-playback assertions to the Windows/Linux live MCP CI gate.
  The focused local gate passed (`mcp_ci_rig_gate_local.log`). Cross-platform
  CI run `37108958001` passed on Windows and Linux. The operation ledger now
  records Linux evidence for all fourteen rig operations. These tests
  establish runtime effects, not visual credibility of the generated poses.

### 2026-10-03 — Extend motion gate to every variant

- Extended the live Godot AI CI motion route from four to all eight motion
  variants: idle, walk, run, jump, turn, strafe, walk start and walk stop. The
  visible Windows Godot 4.7.2 focused run passed dry/write/save/forced-reopen
  and typed-error checks for every variant. The played world-space audit
  passed all 24 operation/FPS rows at 30, 60 and 120 FPS. Fresh Godot
  processes then played each saved clip and measured nonzero bone motion and
  authored-key agreement (`mcp_ci_motion_eight_local.log`). Windows/Linux CI
  run `37109098115` passed this eight-case gate; its run case used generic
  `cycle(preset=run)`, with the separate direct operation checked later.
  These numeric checks do not approve pose design, timing or
  weight transfer; the contact sheets and fixed-camera review remain required.

### 2026-10-03 — Reconcile the audit ledger and visual gap

- The earlier remaining-work checkpoint understated the open checks. Direct
  counts from the 103 generated operation rows show **82** Undo/Redo checks
  marked `pending*` or `partial*` and **99** visual checks marked that way.
  Seven graph rows had Linux marked pending despite the passed eleven-case
  Windows/Linux live-route run `37108181377`; the evidence ledger now records
  that run and the generated audit has 23 Linux-pending rows. Rig and motion
  CI can reduce that count further after both platforms pass. No row is yet
  marked fully verified.
- The inspector preview has partial Linux evidence from run `37108181377`:
  headless Godot returned a typed unavailable result, as designed. Its
  visible Linux PNG path is still untested and remains an explicit visual
  review gap; `partial` must not be read as rendered-frame approval.
- Reviewed the existing X Bot walk, run and strafe candidate sheets in the
  recovery snapshot. The strafe reads as a narrow shuffle with little lateral
  weight transfer; the walk sheet has a backward-leaning silhouette, and the
  run sheet reads as long alternating steps with weak flight timing. Some
  sheets predate the latest parameter changes, so these are problem leads,
  not current-output pass decisions. Fixing gait pose/timing and recapturing
  continuous playback remains a major phase.

### 2026-10-03 — Gate setup and baked secondary motion

- Added `character_setup` and `secondary_motion` to the live Godot AI CI
  route. The focused local Godot 4.7.2 pass exercised dry run, an unreachable
  gait rejection, valid writes, typed missing-rig errors and saved/reopened
  clips and tree (`mcp_ci_motion_setup_local.log`). In a fresh process, the
  saved AnimationTree moved the walking thigh and extracted root motion, and
  the jaw spring track varied and played its authored rotation. Windows/Linux
  CI run `37109446018` passed; both operation rows now record Linux evidence.
  The jaw is a controlled fixture, so believable hair or tail motion and
  modifier evaluation order still need visual review.

### 2026-10-03 — Include the separate walk-cycle operation

- `animation_motion.walk_cycle` has its own advertised operation, separate
  from generic `cycle(preset=walk)`. Added it to the live Godot AI motion
  fixture and played audit instead of inferring coverage from the generic
  case. The focused local pass covered all nine generated motion cases,
  **27/27** played 30/60/120 FPS rows and nine fresh-process saved clip
  replays (`mcp_ci_motion_nine_local.log`). Windows/Linux CI run
  `37109538463` passed, and the separate walk-cycle ledger row now records
  Linux evidence.
- During ledger review, found the `run_cycle` fixture still invoked generic
  `cycle(preset=run)`, which did not prove the separate advertised operation.
  Changed the route call to `run_cycle` and reran all nine cases through the
  visible Godot AI editor: 27/27 played FPS rows and nine fresh saved replays
  passed (`mcp_ci_motion_nine_direct_run_local.log`). In CI run `37109739873`,
  Windows passed the direct run, setup, graph and modifier stages but later
  failed in the FX route; Linux passed the whole route. The FX helper had
  hidden the audit's failure list by printing only the tail of a large JSON
  result. It now emits concise failure diagnostics for the rerun. The focused
  visible Windows rerun passed all 17 FX route and saved playback cases
  (`mcp_ci_fx_after_windows_failure_local.log`). Keep the
  direct run's cross-platform ledger row pending until the full Windows gate
  is green or the route failure is characterized and repaired.
- GitHub Actions run `37110256017` then passed the entire live route,
  including direct `run_cycle` and all 17 FX cases, on Windows and Linux.
  The prior Windows FX failure did not reproduce; its exact case was hidden
  by the old log truncation, so it remains a CI reliability observation.
  The direct run ledger row now has partial cross-platform evidence.

### 2026-10-03 — Correct broad documentation claims

- The top-level and addon READMEs had described every promoted operation as
  a pure clip-spec transformation with one scene undo action. That does not
  fit graph structure, rig modifiers, file-backed library/pose operations or
  inspection. Reworded the introduction to describe their actual effects and
  point readers to the per-operation audit. The top-level README now states
  explicitly that character motion lacks final visual approval.

### 2026-10-03 — Post-CI remaining-work checkpoint

- The regenerated registry ledger has **103 partial / 0 verified** operation
  rows. None has Linux marked pending, but platform `partial` means limited
  contract evidence, not full approval. Preview returned a typed unavailable
  response in headless Linux; visible Linux PNG output remains untested.
  **82** Undo/Redo checks and **99** visual checks are still marked pending
  or partial. These groups overlap and should not be summed.
- Windows/Linux run `37110256017` passed the full live Godot AI route after
  a core reload, including all advertised families and saved playback gates.
  The prior Windows-only FX route failure in `37109739873` did not recur;
  its specific audit failure was not captured, so retain it as an unresolved
  reliability observation rather than claiming it was fixed.
- Next execution order: capture current-default continuous motion on the
  dummy, X Bot and both synthetic rigs; redesign strafe support and transfer,
  then walk torso pitch and run flight timing; re-run contact and visual
  review. Complete editor Undo/Redo for mutating operations and file-effect
  semantics, visible Linux preview and representative Godot AI model prompts
  in the real project. Regenerate the ledger, review the draft PR, and keep
  the branch unreleased until those gates pass.

### 2026-10-03 — Recover after workstation crash

- The crash stopped the visible Godot editor and replaced the uncommitted
  `FIX_ROADMAP.md` with 138,510 zero bytes. Preserved that damaged image as
  `FIX_ROADMAP_crash_20261003_zeros.bin` in the recovery snapshot, restored
  the committed roadmap, and reapplied the phase notes and checkpoint above.
  Verified the restored file has no NUL bytes and both audit JSON files parse.
- Relaunched the visible Godot 4.7.2 editor on `test_project` (PID 19500).
  `mcp_after_crash_relaunch_20261003.log` confirms the actual Godot AI MCP
  route sees all ten toolkit families, all eight promoted tools and one ready
  active editor session, with no missing schemas. The previous cross-platform
  run `37110256017` remains green. No source implementation files were lost.

### 2026-10-03 — Fresh X Bot default-motion baseline

- Used the relaunched Godot AI MCP route to generate, save and force-reopen
  current-default `cycle`, direct `run_cycle` and `strafe_cycle` clips on the
  imported X Bot (run `20261003_090812`,
  `mcp_xbot_default_after_crash_20261003.log`). All nine world-space played
  audits at 30/60/120 FPS passed. Maximum stance slide was 3.3 mm for walk,
  0.4 mm for run and 1.8 mm for strafe; largest penetration was 3.0 mm and
  no knee-pole flips were reported. Strafe body travel was only 0.219 m.
- Godot 4.7.2 Movie Maker captured 61 frames at 60 FPS per clip. Fixed side
  sheets for all three and a front strafe sheet are in the recovery snapshot
  under `media/xbot_current_default_*_20261003/`. The current walk still
  leans backward, run reads as long alternating steps with weak flight timing,
  and strafe reads as a narrow shuffle with little support transfer. None
  receives visual approval. This is a fresh baseline from the current tool
  route, not an older candidate sheet; compare it with the next authored
  change before accepting new numeric results.

### 2026-10-03 — Strafe solver candidate design

- The current strafe calls the forward gait solver with a lateral axis and
  symmetric half-cycle foot trajectories. To avoid crossed feet it caps the
  span at 80% of rest ankle spacing; this explains the 0.219 m X Bot travel
  and the narrow shuffle. A cap change alone would cross the feet, so the
  candidate needs separate lead/trail timing.
- Candidate timing for one left or right step: the leading foot swings early
  and lands outward; the trailing foot remains planted, then swings later to
  recover the original stance width. Author a single smooth root translation
  curve. Each foot's character-local target must equal its planned world
  contact position minus that root curve. Move the pelvis toward the current
  support foot before toe-off, then over the leading foot before trail
  recovery. Write contact/toe-off markers at these actual phase boundaries.
- Keep the candidate isolated until it passes no-crossing, reach, contact,
  penetration, knee-pole and loop checks at 30/60/120 FPS on the dummy, X
  Bot, short and Z-up tall rigs. Render a continuous front and side movie of
  the same saved clips, compare to the fresh baseline above, and reject a
  numerically green result if it still reads as a shuffle or snaps at the
  loop. Explicit requested speeds beyond reachable lateral travel must
  return a typed range error instead of silently shortening the step.

### 2026-10-03 — Recovered strafe implementation and validation

- The workstation restart did not remove the uncommitted strafe solver. The
  visible Godot 4.7.2 editor and Godot AI backend were still running. The
  previous committed Windows/Linux Actions run `37112227953` completed green.
- Implemented an ordered rooted side step. The leading foot swings out during
  0.06–0.45, the trailing foot stays in contact and recovers during 0.55–0.94.
  A single smooth root track carries lateral travel; local foot targets are
  world contact targets minus that root travel. The pelvis shifts toward each
  support leg, and toe-off/contact markers match those phase boundaries.
  In-place unrooted strafe retains its earlier width-limited shuffle behavior.
- Fresh clips generated through Godot AI passed dry-run immutability, write,
  save, forced reopen, resolved track paths and typed missing-skeleton errors
  on X Bot, dummy, short synthetic and Z-up tall synthetic rigs. All 12 saved
  left-strafe played audits passed at 30/60/120 FPS. Travel was 0.4445,
  0.3996, 0.2198 and 0.6394 m respectively. Worst slide was 5.0, 4.5, 2.5
  and 0.1 mm; worst penetration was 0.4, 0.3, 0.2 and 0.5 mm; minimum signed
  foot gaps were 164.2, 176.5, 97.1 and 282.4 mm. No knee flips were
  reported. A rightward X Bot clip also passed the live route and three played
  FPS audits with the same travel and bounds. Logs are `mcp_*strafe_candidate*
  20261003.log` in the recovery snapshot; run IDs `20261003_091848`,
  `092112`, `092117`, `092123` and rightward `092641`.
- The 14 Godot 4.7.2 headless suites passed. The editor suite passed 222/222
  tests, including a new rightward test for lead/trail marker order, planted
  support and monotonic extracted root travel. Godot 4.7.2 Movie Maker saved
  61-frame front and side X Bot playback sheets in `media/xbot_strafe_candidate_*
  20261003/`. The front view now shows an outward lead step and trailing-foot
  recovery instead of the narrow 0.219 m shuffle. Torso anticipation and
  side-view weight transfer remain weak; this is an improvement checkpoint,
  **not visual approval**. Continue motion design before marking the operation
  complete. The ledger stays partial, and cross-platform CI must be rerun
  after this implementation is committed.

### 2026-10-03 — Make the authored side step the public default

- Found a tool-contract mismatch after the candidate passed: `strafe_cycle`
  inherited the shared `root_motion=false` default, so a Godot AI caller
  omitting that parameter still received the old in-place shuffle. The
  handler now defaults rooted travel on for `strafe_cycle` only. An explicit
  `root_motion=false` still requests the in-place variant. The registry,
  generated operation index and addon README describe that choice; the
  registry example no longer requests an unreachable 0.8 m/s on an arbitrary
  rig. The explicit speed error now describes the reach limit accurately.
- Added a default-root rightward regression test for phase-marker order,
  support-foot hold and monotonic root travel, and a separate explicit
  in-place test. Updated the generator contract to treat the default strafe
  as a travelling loop, whose root track intentionally ends displaced. The
  full local Godot 4.7.2 editor suite passed **223/223** tests.
- Restarted the visible Godot 4.7.2 editor (PID 21664) to load the changed
  handler. First `scene_open` timed out while the editor initialized, but the
  subsequent request in that same run wrote, saved and reopened a valid clip.
  A clean retry through live Godot AI (`20261003_184145`) passed all route
  stages with `root_motion` omitted, reported an extracted `XBot:position`
  track and 0.4445 m travel, then passed three saved played audits at
  30/60/120 FPS. The prior candidate commit `a778b8b` passed Windows/Linux
  Actions run `37113285227`. The default-root change then passed Windows/Linux
  Actions run `37145342521`.

### 2026-10-03 — Run reach failure and rejected stride shortcut

- The fresh default X Bot run through Godot AI (run `20261003_090812`) reports
  `clamp_shortfall_m=0.0825`, 9.3% of its 0.89 m leg, yet returns success.
  The dummy default run (`20261003_184725`) similarly shortens by 0.0944 m,
  11.8% of its 0.80 m leg. The X Bot played audit's maximum extension ratio
  is 0.9989. Both replies also incorrectly warn that a Froude ~0.82 run is
  "not a walk". This is a real generator defect despite green contact audits.
- Trialled `stride=24` and `stride=22` through Godot AI on X Bot, plus
  `stride=22` on the dummy. The 22-degree requests cleared reach clamping
  while retaining Froude ~0.61 and passed six saved played 30/60/120 FPS
  audits. A 61-frame X Bot side render is in
  `media/xbot_run_stride22_side_20261003/sheet.png`. It still reads as a
  long stepped walk with weak flight and the same backward torso posture,
  so **rejected** as a default adjustment. Logs `mcp_*run_stride*20261003.log`
  preserve the trials. The next candidate should plan a reachable pelvis
  path at the existing run speed, reject any remaining material target clamp,
  correct the walk-only warning, and check simultaneous airborne clearance
  and continuous side playback before acceptance.
- Tried sharing the walk's periodic pelvis reach planner with the run while
  preserving the existing run stride. Focused tier-1 checks passed, but the
  editor suite failed five tests: `character_setup` could not build its run
  clip on the dummy, the run seam's shin velocity changed, and the 4.7.2
  golden run drifted. The candidate was reverted; it is not on the branch.
  The shared planner's 16%-of-leg drop limit and smooth envelope are not a
  substitute for a run-specific contact/flight path. Kept only the verified
  correction that limits the "not a walk" warning to walking operations,
  with an editor regression assertion. Windows/Linux Actions run
  `37146046324` passed that warning correction. Run reach and visual quality
  remain unresolved.

### 2026-10-03 — Run swing timing candidate rejected

- The rooted run's old swing target moves too far ahead of the hip near
  landing: using its root travel, the local foot target overshoots the
  nominal half-stride. A direct relative-foot interpolation kept it within
  reach but failed the X Bot editor contact gate with 87 mm stance slide,
  because the foot moved horizontally while still inside the contact band.
- A smoother world-space swing beginning at 3% and ending at 98% of the
  swing window passed the 223-test editor suite and live Godot AI save/reopen
  and 30/60/120 FPS played audits. At default stride it reduced X Bot clamp
  from 82.5 to 40.5 mm and dummy clamp from 94.4 to 49.5 mm, still far above
  the 1%-of-leg target. Combining it with a 25-degree stride reduced X Bot
  clamp to zero and dummy clamp to 6.1 mm; speeds stayed 2.04/1.93 m/s.
  Yet played maximum extension remained 0.9946/0.9987, stance slide rose to
  11.8/8.7 mm, and the X Bot 61-frame side render still shows nearly straight
  knees and weak flight. The `media/xbot_run_phase_stride25_side_20261003/
  sheet.png` and `mcp_*run_phase*20261003.log` files preserve the comparison.
  Both swing candidates were reverted; no run default or golden fixture was
  changed. The next run solver needs explicit support and aerial phases with
  knee tuck and a deliberately pitched torso, plus a gate on target clamp
  and simultaneous foot clearance. The previous 10-frame sheet missed the
  flight windows; new sheets include frames 21–27 and 51–57 at 60 FPS.

### 2026-10-03 — Played run flight and extension gate

- Added `motion_kind=run` to `animation_inspect.motion_audit`. It uses the
  isolated Godot AnimationPlayer playback and world-space rig-up axis already
  used for contact. It reports the peak clearance shared by **both** feet,
  the sampled airborne fraction, and the largest hip-to-ankle extension.
  The run grade requires at least 2% of leg length simultaneous clearance,
  at least 5% airborne samples, and extension no greater than 0.985 of leg
  length. Existing `motion_kind=gait` behavior remains available for ordinary
  walk checks. An editor regression checks the run-specific reports.
- Through the live Godot AI tool route, the saved default X Bot and dummy
  runs were graded at 30/60/120 FPS. Both had real numerical flight: X Bot
  peak simultaneous clearance 44.2–59.3 mm and 19–25% airborne samples;
  dummy 49.9–64.3 mm and 26% airborne samples. Their extension ratios were
  0.9989 and 0.9987, so all six run-grade rows **failed the extension check**.
  This narrows the problem: flight exists numerically, but its near-locked
  legs and torso pose make it read poorly from the side. Logs
  `mcp_{xbot,dummy}_run_flight_gate_20261003.log` preserve the result. The
  Godot 4.7.2 editor suite passed 224/224 tests after the audit addition.
  Windows/Linux Actions run `37147218888` passed the audit addition. The
  run generator is still unresolved and remains unapproved.

### 2026-10-03 — Run pose parameter trial across four rigs

- Kept the generator defaults unchanged and tried parameters through the
  real Godot AI `custom_animation_motion` route. On X Bot and dummy, a
  25-degree stride, 4 cm added crouch, 15-degree forward lean and 11 cm
  swing-foot lift produced zero reach clamp at 1 s. The saved clips passed
  the new run flight/extension grade at 30/60/120 FPS: peak extension
  0.9734/0.9801, and simultaneous flight clearance at least 18.6 mm on
  both. Fixed-camera X Bot sheet
  `media/xbot_run_crouch004_lean15_side_20261003/sheet.png` shows a more
  forward torso and bent swing leg than the baseline, though the run still
  needs a continuous visual approval pass.
- On the 1.276 m Z-up tall rig, proportionate 6 cm crouch and 16.5 cm lift
  also gave zero clamp and passed all three run-grade FPS rows (peak
  extension 0.9108). The same recipe scaled to the 0.439 m short rig at a
  1 s duration overreached by 71.3 mm. A 0.7 s clip with explicit 1.43 m/s
  speed, 2.07 cm crouch and 7 cm lift gave zero clamp and passed all three
  run-grade rows (peak extension 0.956–0.963; minimum sampled flight
  clearance 8.8 mm). Logs are `mcp_*run_{crouch*,scaled*,speed143*}*
  20261003.log` in the recovery snapshot.
- A shorter duration by itself increased the implicit speed because the
  current default speed derives from reference stride divided by duration;
  the short rig then overreached by 67.5 mm. The solver needs a rig-aware
  feasible speed/cadence contract. An explicit unreachable request must
  return a typed range error; an omitted speed can be auto-selected only
  when the resulting run still has credible speed and flight. No default or
  golden was changed in this phase.
