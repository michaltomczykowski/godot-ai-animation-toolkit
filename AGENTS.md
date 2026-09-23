# Agent notes

What to build lives in `ROADMAP.md` (per-phase status) and `docs/` (tool
reference + generated op index). This file is the *how*: workflow details that
are not obvious from the code, so a fresh session can continue without
re-discovering them.

## Layout

- `addons/godot_ai_animation/` - the addon.
  - `registry/op_registry.gd` - single source of truth for op names, params and
    descriptions; `docs/op-index.md` is generated from it.
  - `handlers/` - one script per tool family (`generate.gd` presets, `fx.gd`,
    `graph.gd`, `edit.gd`, `inspect.gd`, `library.gd`, `rig.gd`), all extending
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
- Release zip: `powershell -ExecutionPolicy Bypass -File tools\release_zip.ps1`
- Parse check without the editor:
  `& "<godot>" --headless --path test_project --check-only --script res://path.gd`

## Editing addon code

- The **running editor keeps old code**. After changing anything under
  `addons/`, quit and relaunch the editor before using the MCP tools again.
  `editor_reload_plugin` reloads only the godot-ai plugin and drops this addon's
  custom tools until the editor restarts.
- Launch: `& "<godot>" --editor --path test_project`.
- Run `git checkout -- test_project/project.godot` before committing: the editor
  rewrites the plugin enable order.
- Custom tools are callable from `batch_execute` as `custom_tool:<name>`; when
  that starts failing, the registry is stale - restart the editor.

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
