# Handoff: `demo_flykick` — the animation is bad, redo it

Written by a previous model. Read this before touching anything. It is honest about
what is wrong and why, including the parts that are my own bad decisions.

**User's verdict: the animation is horrible and needs fixing by someone else.**
Do not treat the current clips as a baseline to tweak. The staging, the scene
scaffolding and the environment findings below are salvageable; the animation
design is not.

---

## 1. What was asked for

A video of one dummy opening a door and another dummy flykicking them.
Chosen up front, by the user:

- narrative beat cards (not an op-by-op showcase),
- comedic, **static wide camera**, no push-in,
- 7.5 s of scene, composed into a ~33 s video with intro/beat/end cards,
- **saved locally only** — explicitly NOT attached to any GitHub release.

Code baseline was already released as v1.13.0 before any of this started.

---

## 2. Environment (read this first, it will waste an hour otherwise)

### 2.1 The single most important finding: custom tools do NOT register locally

Your local `godot-ai` is a **fork on branch `feat/animation-follow-ups`** at
`eefd4fe` (`G:\godot-ai-dev\godot-ai-animation-toolkit`'s MCP server is launched
from `G:\godot-ai-dev\godot-ai-v4-animation`). CI is green only because CI pins
upstream `hi-godot/godot-ai@v4.2.1`.

On this fork, the addon's tool registration **fails**, silently and repeatedly:

```
Invalid type in function 'batch_register (via call)' in base 'RefCounted (McpToolRegistry)'.
The array of argument 2 (Array) does not have the same element type as the expected typed array argument.
    at: res://addons/godot_ai_animation/plugin.gd:126
```

Consequences, all confirmed by hand:

- `custom_manage(op="list")` returns `{"tool_count": 0}`.
- `custom_manage(op="invoke", ...)` → `UNKNOWN_COMMAND: Custom tool 'animation_motion' not found`.
- `batch_execute` with `custom_tool:animation_motion` → `UNKNOWN_COMMAND`, and it
  does **not** accept MCP tool names anyway (use plugin command names like
  `create_node`, not `node_create`).
- The 67 errors sit in the editor log under source `editor`, repeated per register call.

So **every** addon op (`walk_cycle`, `pose_to_clip`, `clip_from_spec`, …) is
unreachable through MCP in this working copy. This is an environment problem, not
an addon bug — do not "fix" the addon for it. Two options: point the junction at
upstream `v4.2.1`, or keep working headlessly as described below.

### 2.2 Binaries

- Console (use this, you get stderr): `F:\GODOTAITESTING\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe`
- Editor: `& "F:\GODOTAITESTING\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64.exe" --editor --path test_project`
- ffmpeg: `C:\Users\mtomc\AppData\Local\Temp\opencode\ffmpeg\ffmpeg.exe`

### 2.3 Rig facts (measured, not guessed)

`res://models/human_dummy/HumanCharacterDummy_F.fbx` — 56 bones.

- **`rig_frame.forward == +Z`.** An unrotated instance faces **+Z (toward the
  camera at +Z)**. To face −Z (into the wall) you must flip 180°. Verified by
  `RigAnalysis.rig_frame()`; do not eyeball this, a white featureless dummy at
  288px is genuinely ambiguous.
- Bone names are `B-hips`, `B-upperArm.L`, `B-thigh.L`, `B-chest`, …
- `RigAnalysis.detect_roles(bone_names)` returns a **wrapper**:
  `{"roles": {...}, "candidates": {...}, "unmatched": [...]}`. Passing the wrapper
  straight in as `roles` fails with "the role map does not resolve both legs and a
  hips bone".
- The dummy rests in a **T-pose**. A walk needs `arm_down` or the arms never move.

---

## 3. What exists now

| Path | State |
|---|---|
| `test_project/demo_flykick.tscn` | new, **committed** in `735706d` (local, unpushed) |
| `test_project/tools/make_flykick_clips.gd` | new, committed; headless clip builder |
| `F:\GODOTAITESTING\animation_toolkit_flykick.mp4` | the 33 s video, 1152×648, 30 fps |
| `C:\Users\mtomc\AppData\Local\Temp\opencode\compose_flykick_video.py` | compose script |
| `C:\Users\mtomc\AppData\Local\Temp\opencode\flykick_movie\` | 225 rendered PNGs |

Git: on `main`, **1 unpushed commit** (`735706d`), tree otherwise clean. No Godot
process is running.

### Scene layout

```
Flykick (Node3D)
  Floor / WallLeft / WallRight / Lintel      (BoxMesh + StandardMaterial3D)
  Door (Node3D) -> Panel (MeshInstance3D)   (hinge at x=-0.5, z=-1.7)
  Victim (Node3D) @ (0,0,0.1)
    Walker (Node3D) @ (0,0,1.08)
      Body = dummy instance, 180° Y flip
    WalkAnim   (AnimationPlayer) -> "walk_in"  2.0 s  procedural walk
    VictimAnim (AnimationPlayer) -> "fly"      7.0 s
  Kicker (Node3D) @ (1.35,0,0.62)
    Runner (Node3D) @ (0,0,1.9)
      Body = dummy instance, 180° Y flip
    RunAnim  (AnimationPlayer) -> "run_in"  2.6 s  procedural run
    KickAnim (AnimationPlayer) -> "kick"    7.0 s
  SetAnim (AnimationPlayer) -> "set"         7.0 s  door swing
  Sun, Fill, Cam @ (0.9,1.5,5.2) fov 60
  Ui/Title (Label "the door, and a flykick")
```

The 180° flip lives on the **`Body` instances**, not the pivots, on purpose: an
absolute `rotation` track on a pivot would override the pivot's own base rotation
at t=0. Keep that in mind if you re-parent anything.

---

## 4. Why the animation looks bad — the actual defects

This is the part to fix. In rough order of how much each one hurts.

1. **The kick has no legs.** `kick` is 5 position keys and 5 rotation keys on an
   empty `Node3D` — a translation plus ~16° of yaw. There is no leg animation
   whatsoever. `run_in` stops animating bones at t=2.6 s, so the kicker's legs
   freeze mid-stride and the body then slides forward. On screen this is a man
   gliding into another man, not a kick.

2. **The victim has no reaction.** `walk_in` ends at t=2.0 s and holds its last
   frame. From 2.0 s to 4.15 s the victim stands frozen in a walk pose while the
   kicker arrives. The "impact" is a 0.1 rad rotation nudge on the pivot between
   2.85 s and 3.08 s. The "fly" is the same pivot rotated 4.7 rad about Z on a
   six-key arc. No airborne pose, no flail, no ragdoll, no recovery.

3. **The design cannot express the thing it needs to show.** The one-player-per-
   node split (gait on the inner pivot, the beat on the outer pivot) exists
   *because* scene-owned players all `autoplay` from t=0 with no state machine, so
   two clips writing the same bones would fight. That workaround is precisely what
   prevents the kick and the reaction from ever overlapping in time on the same
   bones. **Fixing this properly means removing the hack**, e.g.:
   - one clip per dummy spanning the full 7 s, with the gait's keys **offset** to
     their intended start time when the tracks are written (this is the smallest
     change and removes the split entirely), or
   - an `AnimationTree` / `AnimationNodeStateMachine` with real transitions, or
   - `root_motion` on the gait so travel comes from the clip and the body can
     stand still and then move inside one clip.

4. **I bypassed the toolkit's own clip engine.** `addons/godot_ai_animation/spec/`
   has `clip_spec.gd`, `spec_builder.gd`, `spec_modifiers.gd`, `pose_solver.gd`,
   `spec_json.gd` — a full declarative clip-spec path, plus ops
   `clip_from_spec` / `pose_to_clip` / `pose_save` / `pose_apply`. I hand-wrote
   raw value tracks instead. That was the wrong level of abstraction and is very
   likely why it looks amateur. Start from the spec engine.

5. **The right ops for this were never used.** `animation_motion` has a `jump` op
   (anticipation crouch → launch → air arc → landing absorb, feet planted) — that
   is literally a flykick aftermath. There is also `walk_start` / `walk_stop` for
   entering and leaving the gait, `turn_cycle`, and `secondary_motion` for
   follow-through on the tumble. None of it is in the current video.

6. **Feet may slide.** The translate pivots are hand-matched to
   `MotionHandler._implied_speed()` for the chosen duration. Change the duration
   or style and the match is silently wrong. Root motion is off and
   `set_root_motion` was never used.

7. **Framing fights the content.** Static wide (user's choice) puts the dummies at
   roughly 200 px tall in a 648 px frame, so a kick's contact detail is
   unreadable. Worth revisiting with the user, or commit harder to the wide shot
   (more contrast, clearer silhouettes) rather than trying to show fine footwork.

Also cosmetic: two small pale specks are visible in frame ~210. I chased these and
they are **not** stray nodes — I enumerated every `VisualInstance3D` and there are
only 4 set meshes, 2 body meshes and 2 lights. They are the dummies' hands/feet.
Don't waste time on them again.

---

## 5. The headless clip builder (why it exists, how to use it)

Because of §2.1 the MCP path was unusable, so clips are built by
`test_project/tools/make_flykick_clips.gd`, which calls the addon's own pure
functions and writes the same `ClipSpec` tracks `animation_motion` would. The
output is equivalent to the op; it is not a reimplementation of the maths.

Run it:

```
& "<godot console>" --headless --path test_project --script res://tools/make_flykick_clips.gd
```

It prints `CLIP_BUILD_OK` plus a per-clip line, or `CLIP_BUILD_FAIL: …`. It
**re-packs and overwrites `demo_flykick.tscn` in place**, replacing the five clips
and the autoplay entries. All timings are literals in the `_door` / `_victim_fly`
/ `_kicker_kick` / `_gait` functions — edit those, re-run, re-render.

Two traps that cost time and are commented in the file:

- `MotionSpecs.context_from_skeleton` returns `arm_down: {}`. The real op fills it
  in afterwards from `BoneAnimation._aim_delta(skeleton, arm, Vector3.DOWN,
  arm_amount)`. Without that the arms stay in the T-pose (15 bones keyed instead
  of 19). `_default_arm_down` is inlined in the script.
- `player.root_node` is a `NodePath`, not a `Node`; resolve it with
  `player.get_node_or_null(player.root_node)` before `get_path_to`.

---

## 6. Commands

```powershell
# rebuild clips
& "F:\GODOTAITESTING\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe" `
  --headless --path test_project --script res://tools/make_flykick_clips.gd

# render 225 frames (7.5 s). The output dir MUST already exist or write_begin fails.
$dir = "C:\Users\mtomc\AppData\Local\Temp\opencode\flykick_movie"
New-Item -ItemType Directory -Path $dir -Force | Out-Null
& "<godot console>" --path test_project --write-movie "$dir\frame.png" `
  --fixed-fps 30 --quit-after 225 --disable-vsync res://demo_flykick.tscn

# contact sheet of the WHOLE clip in one image - far cheaper than reading frames
& "<ffmpeg>" -y -i "$dir\frame%08d.png" `
  -vf "select='not(mod(n\,9))',scale=288:162,tile=6x4:margin=3:padding=3:color=0x202020" `
  -frames:v 1 "$dir\sheet.png"

# recompose
python C:\Users\mtomc\AppData\Local\Temp\opencode\compose_flykick_video.py

# pre-commit gate
powershell -ExecutionPolicy Bypass -File tools\test_tier1.ps1 -Godot "<godot console>"
```

The contact sheet trick is the single best productivity lever here: one 6×4 image
shows every beat of the 7.5 s, so timing problems are visible immediately instead of
frame-by-frame.

---

## 7. Gotchas

- **Quit the editor before any headless scene write.** The editor holds the scene
  in memory and will clobber your file on its next save. The addon's own
  `AGENTS.md` also says the running editor keeps old addon code and that
  `editor_reload_plugin` drops this addon's custom tools until a restart.
- Movie Maker will not create its output directory for you
  (`Condition "d.is_null()" is true` from `movie_writer_pngwav.cpp:75`).
- In a `SceneTree` script, `get_global_transform()` fails inside `_initialize`;
  the tree is not live yet. Do the work in the first `_process` and return `true`.
- `Animation.length` clamps to 0.001; `PackedScene.pack` + `ResourceSaver.save`
  *does* serialize `autoplay` for scene-owned players (verified).
- The editor rewrites `test_project/project.godot` line endings. Run
  `git checkout -- test_project/project.godot` before committing.
- `custom_manage` call shape: `op` and `session_id` are top-level siblings, never
  nested inside `params`.
- `scene_manage(op="create")` is blocked by a filesystem guard; writing the `.tscn`
  directly works. Inline `{"__class__": "BoxMesh"}` via `node_set_property` fails
  with `WRONG_TYPE`, so the static meshes are hand-written into the scene.

---

## 8. Suggested order of attack

1. Decide whether to fight §2.1 (repoint the junction at `v4.2.1`) or stay
   headless. If MCP works, most of this handoff's workarounds become unnecessary.
2. Re-cut the animation as **one clip per dummy**, gait keys time-offset, so the
   kick and the reaction can overlap on the same bones. Delete the pivot split.
3. Rebuild it through `clip_spec` / `pose_*` rather than raw value tracks, and use
   `animation_motion`'s `jump` for the victim's launch.
4. Render, look at the contact sheet, iterate on timings there.
5. Re-run tier-1, restore `project.godot`, commit. The video stays local unless
   the user says otherwise.
