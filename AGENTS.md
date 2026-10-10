# Agent notes

## Current instruction (2026-10-10)

The user approved the presented run set with “they look okay.” The five style
approvals and exact ten video hashes are recorded; individual watched files were
not enumerated. State: `approved_run_styles_pending_regression`. Never reset
that feedback or rerun the delivery archive. Follow
`docs/run-golden-migration-plan.md`: separate v2 fixture, prove missing-fixture
failure, explicit local recording, fresh normal comparison, full local and
Windows/Linux CI before closing run/starting idle. Closing evidence belongs in
`release_r2_run_20261010/accepted-r001-regression`. Notes below preserve delivery
and earlier expected-failure checkpoints.

Run v2 fixture recorded explicitly after the missing-expectation refusal passed;
fresh normal Godot 4.7.2 public MCP motion passes 61/61, zero skips/errors, run
drift zero. Fixture: 38 tracks/59 keys, 0.9697s. Historical fixtures are unchanged.
Full local and source CI are pending. On every editor restart set APPDATA to
`release_r1_20261010/appdata`, and clear recording/CI flags for normal runs:
the default PC profile targets occupied old-core port 18131. That failed startup
attempt is preserved; correct profile adopts the isolated 8000/9500 backend.

R2 run animation source is `97f17ce`; candidate UUID
`6bcece032a55484297d9d5b113f6af8d`. Forty public ordinary writes each pass actual
Undo/Redo, dry/pose preservation and save/reopen. The complete 240 native runs,
60 explicit-prototype comparisons, 40 reload dry calls and ten-family discovery
pass. Motion 60/61 has only the deliberately preserved legacy run golden failing;
14/14 headless pass. Four source CI editor jobs have the same one failure and
two private-X-Bot skips, zero engine/route/discovery errors. Animation source is
unchanged by later renderer/checker tooling commits. Validation:
`docs/run-quality-validation.md`. Recovery: `release_r2_run_20261010`.
All ten continuous 48s/1080p60 run MP4s are recorded and independently decoded
(2,880 frames each); `candidate/recording-progress.json` is complete. Do not
restart the recorder or overwrite earlier archives. Archive/delivery completion
is recorded in `candidate/review-delivery.json` and `pc-review-delivery.json`.
Strict archive passed: 80 saved scenes, exact animation source and local rigs,
ten verified videos. PC Explorer's review folder and Responsive clean selection
are observed. State is `awaiting_run_styles_feedback`; all five run approvals
are null. Do not rerun the archive after feedback or reset approved records.
`check_run_review.py` requires 240 native and 60 prototype comparisons;
`archive_run_review.py` requires all ten continuous MP4s and public history.
In-place world contacts use an unanimated gameplay parent outside the visual
mixer subtree, explicitly identified in receipts. Two failed checker attempts
are preserved; final matrix has zero engine errors. Do not change run goldens
before explicit run video feedback. Deliver through PC Explorer and pause.
The latest request to continue is not run approval. Preserve the prior walk
approval; run has its own five-style/four-rig feedback gate.

R1 closed on `8f7b6e7`: Actions `38057817851` passes all 32 required source
jobs and two advisory main jobs. Four editor jobs: 382/384, two explicit private
X Bot skips, zero failures/engine/route/discovery errors; locally 384/384.
Both live MCP jobs: 118 pass markers, zero fail markers. Merge tree
`d16d599...` matches the source. Final receipts are in accepted-r005-regression.
Current state: `approved_walk_styles_regression_complete`. R2 run is active;
its own visual approval and all later release gates remain pending. Older
pending-CI notes below describe earlier checkpoints.


The approved closure is `docs/release-wrap-up-plan.md`: stable v2.0.0,
Responsive default, Grounded optional, retuned relaxed/heavy/sneaky, Godot
4.7.2 and core >=4.2.1. Work alone. r004 acceptance and the new default choice
supersede old wait/default-selection notes below. Start R1, then pause for
continuous default/style video review before R2. Historical media-upload and
unreleased-only checklists below are superseded: private media/assets stay local;
merge/tag/release follow completed gates and final candidate review. Keep phase
notes, review state, pushed source SHAs and recovery snapshots current.

R1 animation source is `056cc8d`; released-core public routes, 60 native contact
runs, 24 original-r004 playback comparisons and 40 reload calls pass. Initial
57/58 editor and 13/14 headless results are preserved as historical evidence.
After review, separate v2 walk fixtures pass: focused public MCP 59/59, full
editor 384/384 across 32 suites, all 14 headless suites, and both ten-family/
103-operation reload probes. No skips or engine errors in the full local suite.
All ten style videos are
complete, independently decoded/hashed and strictly archived under recovery's
`release_r1_20261010`. PC Explorer's review folder and Responsive clean selection
are verified. The user approved the presented set on 2026-10-10 (“they look very
good”); all five approvals and exact hashes are recorded. Current state is
`approved_walk_styles_pending_ci`. Versioned fixtures preserve old files and
normal/CI runs cannot record missing expectations. The remaining R1 exit gate
is green Windows/Linux source CI; see the migration plan and validation note.
Fixture source `9a35063` passed all 34 source jobs in Actions `38056657619`;
standard-CI recording refusal is now a small follow-up with 59/59 focused
passes and its own full CI pending. R2's run plan is saved. Baseline measurement
is allowed against unchanged animation source, but generation-code changes
still wait for final R1 CI.
Do not rerun `tools/archive_walk_styles_review.py` after this approval; it refuses
feedback reset. Preserve the delivered archives and write new closing evidence
under `accepted-r005-regression`. R2 follows green R1 regression and still needs
its own continuous-video feedback. No release before R2-R5 and final candidate
review. Exact receipts and limitations are in
`docs/walk-default-integration-validation.md`.

What to repair lives in `FIX_ROADMAP.md` (phase plan and evidence). `ROADMAP.md`
records older feature/release history and `docs/` has the tool reference and
generated op index. This file is the *how*: workflow details that
are not obvious from the code, so a fresh session can continue without
re-discovering them.

## Layout

- `addons/godot_ai_animation/` - the addon.
  - `registry/op_registry.gd` - single source of truth for op names, params and
    descriptions; `docs/op-index.md` is generated from it.
  - `handlers/` - one script per tool family (`generate.gd` presets, `fx.gd`,
    `graph.gd`, `edit.gd`, `inspect.gd`, `library.gd`, `rig.gd`, `motion.gd`,
    `sequence.gd`), all extending
    `animation_tool_base.gd`.
  - `spec/` - clip-spec engine (`clip_spec`, `spec_builder`, `spec_io`,
    `spec_modifiers`, `fx_specs`, `graph_builders`, `spec_json`, `pose_math`).
- `test_project/` - Godot project used for tests and demos (addon linked via a
  junction by `tools/setup_dev.ps1`).
  - `tests/` - `tier1_*.gd` (pure, headless) and `test_animation_*.gd` (editor
    suites run through the godot-ai test runner).
  - `demo_*.tscn` - committed demo scenes, recorded into the release videos.
  - `models/human_dummy/` - committed rigged character fixture (56 bones,
    `B-hips`, `B-upperArm.L`, ...).
- `tools/` - `test_tier1.ps1`, `gen_docs.ps1`, `release_zip.ps1`,
  `setup_dev.ps1`.

## Commands

Godot binary (local):
`F:\GODOTAITESTING\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe`

- Tier-1: `powershell -ExecutionPolicy Bypass -File tools\test_tier1.ps1 -Godot "<godot>"`
- Editor suites (CI mode, every suite in a fresh headless editor):
  `$env:ANIMATION_TOOLKIT_CI="1"; $env:GODOT_AI_ALLOW_HEADLESS="1"; & "<godot>" --headless --path test_project --editor`
  The runner prints `CI_SUITE_RESULTS={...}` and `CI_SUITE_PASS`/`FAIL`.
- Docs: `powershell -ExecutionPolicy Bypass -File tools\gen_docs.ps1 -Godot "<godot>"`
  (tier-1 fails while `docs/op-index.md` is stale).
- Operation audit: `powershell -ExecutionPolicy Bypass -File tools\gen_operation_audit.ps1 -Godot "<godot>"`
  (`docs/operation-evidence.json` contains manually reviewed evidence;
  `docs/operation-audit.json` is the generated 103-operation inventory).
- Live Godot AI route on a running editor: `tools/mcp_probe.py` lists the
  current session and checks all ten families. `tools/mcp_motion_remaining_cycles.py`
  writes selected motions through MCP; `tools/mcp_motion_audit_saved.py` plays
  their saved scenes at 30/60/120 FPS. `tools/mcp_locomotion_sequence_review.py`
  creates a single-player start→walk→stop action through `custom_manage`.
- Isolated graph/modifier bake gate: `tools/mcp_rig_bake_restoration.py` runs six
  public-route suites, requires 201 cases/603 saved history states, then invokes
  graph/all root-motion modes directly before and after core reload. Its fresh
  checker is `test_project/tools/check_rig_bake_restoration.gd`; the paired native
  renderer is `render_bake_restoration.gd` and composer is
  `tools/compose_bake_restoration.py`. See the phase validation document for args.
- Motion/sequence history gate: `tools/mcp_motion_sequence_history.py` runs guard,
  continuation and complete history suites in that order, requires 273 cases /
  819 saved states / 2,457 native playback runs, and invokes four examples before
  and after core reload. Fresh checker: `check_motion_sequence_history.gd`;
  independent engine references: `motion_sequence_native_reference.gd`.
  Each external attempt uses a UUID output directory to avoid cached scene
  subresources from earlier attempts. See the phase validation document for args.
- Release zip: `powershell -ExecutionPolicy Bypass -File tools\release_zip.ps1`
- Parse check without the editor:
  `& "<godot>" --headless --path test_project --check-only --script res://path.gd`

## Editing addon code

- The running editor may keep old code after changing `addons/`; launch a fresh
  editor before treating a live MCP result as evidence for new code.
  `editor_reload_plugin` was verified on 2026-09-28 to restore all ten toolkit
  families through the addon registry callback in the connected test project.
- The persistent recovery snapshot is
  `F:\GODOTAITESTING\toolkit_repair_snapshot_2026-09-30` (tracked patch,
  untracked source copies, roadmap, operation ledger, logs and Movie Maker
  frames). Refresh it after substantive edits. The current review branch is
  `repair/toolkit-quality`; it is unreleased and the operation ledger remains
  partial until visual, undo and Linux gates are satisfied.
- Active graph/modifier bake restoration completed on `e3a9e93` (Actions
  37702850985). Its closing validation and next-scope limits are in
  `docs/rig-bake-restoration-validation.md`; recovery reports, native scenes and
  media are in the snapshot's `bake_restoration_20261007` folder. Broader roadmap
  work remains open; do not infer complete operation approval from this phase.
- Motion/sequence history completed on `7513708` (Actions 37783627161); local
  reports, 1,366 native scene files, exact source, preview scenes and media are in
  `motion_sequence_history_20261008` under recovery. The approved scope and gates
  are in `docs/motion-sequence-history-plan.md` and its validation document.
  Selected guard/continuation suites reset the saved matrix manifest: run the
  complete history suite last and archive it before running selected tests.
  Generated native clips now refuse running destinations/active linked trees;
  extracted nonlooping motion/sequence clips report a 34.333 ms terminal hold.
  Full humanoid/action visual quality remains a separate roadmap gate.
- Character quality starts with `docs/character-quality-plan.md`. The first
  walk baseline on all four rigs is recorded under recovery's
  `character_quality_20261008/walk-baseline-r001`; review state lives in
  `docs/character-quality-review.json`. The user viewed the baseline and requested
  less stiff hands/arms and pelvis on 2026-10-08. Revise the walk upper body;
  **pause for human review of the next continuous comparison videos.**
  Plain “continue”, silence and usage resets do not grant
  visual approval. Current walk has green ankle checks but raised Z-up arms.
  The public-route baseline script, engine-only native checker/renderer and MP4
  composer/archive tools are documented in its validation file. Videos must be
  continuous; contact sheets alone never approve motion. Do not redo completed
  history phases or promote defaults merely because numeric checks pass.
  The user reviews remotely: chat file links and GIFs are inaccessible. They chose
  PC viewing instead: open File Explorer with the review MP4 selected, then ask
  for feedback. Do not retry chat attachments. Public media upload is excluded
  from the approved plan. Preserve baseline files; defaults stay unpromoted.
  The r002 upper-body plan/recipes are in `docs/walk-upper-body-*`; final animation
  source is `671a2ff`, with Godot AI scene UUIDs recorded in its validation doc.
  Recovery root is `character_quality_20261008/walk-review-r002`. The first
  `9fbbae3` attempt failed the new played torso-sign check and is preserved in
  `attempt-9fbbae3`. Read `recording-progress.json` before resuming captures;
  `tools/record_walk_review.ps1` produces four continuous comparison MP4s and
  `archive_walk_revision.py` requires every route/native/media gate before marking
  review pending. New controls are opt-in; no profile/default/finger-pose approval
  has been granted. Deliver through PC Explorer and stop for the next review.
  All four r002 MP4s are complete and decode-verified. Explorer's `review-videos`
  window is confirmed, with grounded clean selected. The source/scene/tooling
  archives and receipts are complete. On 2026-10-09 the user viewed r002 and
  requested a less stiff torso/head and a small walking head bob. Follow
  `docs/walk-head-torso-r003-plan.md`; record same-profile r002/r003 continuous
  comparisons and pause again. No profile approval or default promotion yet.
  r003 animation source is `86ea12a`: 52 fresh editor tests, 24 native contact
  runs and 24 upper-body traces pass; all 34 Windows/Linux source CI jobs pass
  (Actions 37925284348). Four 48s 1080p60 comparisons are complete under
  `character_quality_20261009/walk-review-r003`; left is same-profile r002,
  right is r003. Validation: `docs/walk-head-torso-r003-validation.md`.
  `archive_walk_revision.py --revision walk-review-r003 --editor-tests 52
  --ci-report <root>/ci-source-86ea12a.json --baseline <r002-root>` enforces
  the archive gate. `deliver_walk_review.py` prepares verified PC copies.
  **Pause for r003 head/torso video feedback after opening PC Explorer.**
  The archive/receipts and four review copies are complete; Explorer's r003
  `review-videos` window is confirmed with grounded clean selected.
  **Wait for r003 human feedback now.** No playback/profile approval yet.
  r003 feedback subsequently received: greatly improved, but hands/forearms/
  wrists still stiff. Follow `docs/walk-hand-follow-through-r004-plan.md`.
  Preserve r003 as the comparison reference; new multi-axis forearm/wrist
  controls and bounded seeded variation remain opt-in. Review finger curl
  using validated chains/palm geometry; pause again after continuous videos.
  r004 animation source is `68e06aa`: 54 fresh editor motion tests, fourteen
  headless suites, 24 native contact runs and 24 upper-body traces pass; all
  34 Windows/Linux source jobs pass (Actions 37982111931). Eight saved/reopened
  public Godot AI clips and sixteen before/after-core-reload dry routes pass.
  Four continuous full-body comparisons and two enlarged hand-detail MP4s are
  complete, each 48s / 1080p60 / 2,880 independently decoded frames.
  The verified archive has sixteen reference/candidate scenes/local rigs,
  exact sources, parameters and receipts under
  `character_quality_20261009/walk-review-r004`. See
  `docs/walk-hand-follow-through-r004-validation.md`.
  Explorer's r004 `review-videos` folder is confirmed open with six verified
  copies. Start with grounded hand-detail. **Wait for r004 human feedback now.**
  Both profile approvals and new playback confirmation remain pending. No
  default promotion or next motion is authorized by these verification passes.
  Subsequent user feedback (2026-10-09): r004 is okay; asks to wrap the fixes,
  merge to main and publish on GitHub. Follow `docs/release-wrap-up-plan.md`.
  Record acceptance/playback separately from which profile/all-rig coverage
  was reviewed; an optional question asks for the profile. Plan the approved
  default/profile integration next. The release request expands the earlier
  unreleased scope; prepare a concrete candidate and final review checkpoint.
- Launch: `& "<godot>" --editor --path test_project`.
- Run `git checkout -- test_project/project.godot` before committing: the editor
  rewrites the plugin enable order.
- Custom tools are callable from `batch_execute` as `custom_tool:<name>`.
  Inspect `session_manage(list)` and `custom_manage(list)` before diagnosing a
  missing tool: the MCP port or active editor session may be wrong.

## Demo scenes and videos

- Demo scene shape: root Node3D with the dummy instance, a current `Cam`, a
  `Sun`, `CanvasLayer/Ui/Title` naming the op, and one `AnimationPlayer` per
  animated thing with `autoplay` set (autoplay is editor-only but *is*
  serialized for scene-owned players).
- Modifiers (IK, springs, look-at, retarget) must be created with
  `active: true` in demo scenes, otherwise they do nothing on playback.
- Record a segment (windowed; Movie Maker writes PNG frames):
  `& "<godot>" --path test_project --write-movie "<dir>\frame.png" --fixed-fps 30 --quit-after 225 --disable-vsync res://demo_x.tscn`
  (225 frames = 7.5 s).
- Compose: `python C:\Users\mtomc\AppData\Local\Temp\opencode\compose_<name>_video.py`
  (`compose_pose_video.py` is the template: intro, one card + segment per step,
  "and the rest", end card). ffmpeg lives in
  `C:\Users\mtomc\AppData\Local\Temp\opencode\ffmpeg\ffmpeg.exe`.
- Videos go to `F:\GODOTAITESTING\animation_toolkit_*.mp4` and are attached to
  the matching GitHub release.

## Release checklist

1. Bump `version` in `addons/godot_ai_animation/plugin.cfg` (CI checks it
   against the tag).
2. Commit + push; wait for CI on `main`.
3. `git tag vX.Y.Z; git push origin vX.Y.Z`; the tag CI run's `release` job
   creates the GitHub release with the zip.
4. `gh release upload vX.Y.Z <files>` for the videos - a name collision fails
   the whole batch, so upload only what is missing and re-check with
   `gh api repos/.../releases/tags/vX.Y.Z` (the API lags a few seconds).
5. Update `F:\GODOTAITESTING\animation_toolkit_discord_post.md` (tool paragraph
   + one line per demo video) and `ROADMAP.md`.

## Gotchas worth remembering

- **SkeletonModifier3D results are only readable at `modification_processed`.**
  Reading `get_bone_pose_*` later in the frame returns the pre-modifier pose
  even though skinning used the modified one - measure inside the signal.
  Modifiers only process in the skeleton's deferred update, so a synchronous
  tool call must nudge it with `skeleton.notification(NOTIFICATION_UPDATE_SKELETON)`
  and capture inside the signal (this is what `bake_pose_sequence` does;
  `Skeleton3D.advance()` does *not* run modifiers).
- **A custom tool's `params_schema` is capped at 8192 bytes on both sides of the
  wire, measured differently**: the plugin uses Godot's compact `JSON.stringify`,
  the Godot AI server re-measures with python `json.dumps` (spaced separators,
  ~5% bigger) and dropping one over-cap definition drops the whole catalog for
  that session. Keep ~400 bytes of headroom; the tier-1 registry check counts
  the separators to stay on the server's side.
- **TwoBoneIK3D requires a pole target**; without one it silently solves
  nothing. IK/look-at settings resolve NodePaths **relative to the modifier**.
- **Clips written into an instanced scene** only survive the save when the
  instance has Editable Children; the toolkit enables it and swaps in a
  scene-local library copy (`_commit_node_add_many`).
- **RetargetModifier3D** only drives its own children, and the target's *scene
  root* (not the bare skeleton) must move so skinned meshes keep their binding.
- `Animation.length` clamps to 0.001; `animation_inspect` is read-only and is
  rejected by `batch_execute`; registry descriptions must stay under the
  600-character custom-tool cap.
- 2D IK/spring/look-at are intentionally unsupported: the
  `SkeletonModificationStack2D` path is Experimental in Godot 4.7.
