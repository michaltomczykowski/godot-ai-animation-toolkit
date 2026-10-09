# Agent notes

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
