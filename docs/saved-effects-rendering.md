# Saved FX comparison tooling

The tooling covers all 47 producing operation keys in FX (16), presets (9),
edit (20), and library apply (2). There are 49 cases: both template forwarding
variants and both split outputs are explicitly selected. It reuses preserved
`new` Undo/Redo scenes; it never calls the toolkit or creates animation keys.
No playback or footage
was produced while developing this increment.

## Plan (no Godot launch)

From the repository root, using a project containing the fixture resources:

```powershell
python tools/plan_saved_effects.py --family all --project test_project --output dist/all-effects-plan-r001.json
```

The output is exclusive-create. Preserve failed attempts and choose a new output
name for retries. Schema 1 contains 49 cases with `--family all` (or use `fx` / `remaining`) with operation/case identity, two
absolute private saved-scene paths and SHA256s, resolved `res://` resource hashes,
historical source/checker associations, renderer/planner/checker hashes,
60FPS native clock, two6second reset takes, and explicit audio requirements.
The planner refuses changed known Redo files, missing Undo files, or unresolved
resources. It hashes the preserved Undo file; this is an identity observation,
not independent proof that historical Undo behavior was correct.

## Root-owned capture queue only

Example command for case0, to be scheduled by the root agent in an isolated
project with these tools and the hashed fixture assets. Do not use `--headless`
for the visual capture. The source scene paths remain untouched.

```powershell
& $Godot --path $Project --fixed-fps 60 --resolution 1400x800 --write-movie "$Capture/frame.png" --script res://tools/render_saved_effects.gd -- "$Plan" 0 "$Capture/native-observations.json"
python tools/check_saved_effects.py --plan "$Plan" --case 0 --observations "$Capture/native-observations.json" --output "$Capture/native-check-r001.json"
```

Repeat the selected plan case indices (0–48 for `all`) with distinct output directories. Renderer exits after12seconds;
there is no external `--quit-after` truncation. Each side loads its own saved
scene, resource instances, AnimationPlayer and native SpriteFrames clock. Both
scenes are destroyed and re-instantiated for the second take. SpriteFrames are
explicitly started for review, even though the historical resource-assignment
case intentionally saved `play=false`; this playback override is recorded.
There is no manual frame assignment, seek-based animation, bone pose authoring,
or generator invocation.

Display adjustments are explicit: cyan child polygons show otherwise invisible
Node2D transforms; unrelated CanvasItems are hidden, unkeyed bar/panel extents
are220x50, and cameras are disabled for stable framing. Camera animated position
and zoom remain in the native numerical readout. This is a diagnostic saved-effect
comparison, not a claim that the original fixture has a production layout.
Invisible Control targets get cyan child polygons, and invisible Node3D targets
get a rigid child cube plus an independent display camera/light. These display
children never key or pose the target. Showcase retains its real seven players
and native scene geometry, with the2D presentation scaled to0.55 for framing.
Split head/tail are separate cases; merge uses the original walk as its Undo
reference.

The renderer verifies scene/resource/renderer hashes before starting and records
every native frame's observed properties, clock error, engine, plan identity and
both reset takes. Its receipt is exclusive-create. No media is silently qualified.

## Native checker scope

The checker requires complete ordered60FPS samples, both independently played
clones and takes, progression of the **operation's actual target**, and a changed
effect versus Undo. Damage-bar30, fill100 and counter100 endpoints are independent
history-case inputs. Flipbook/SpriteFrames must show all four native frame cells.
Presets and edits add independent native played-value spot expectations from
`check_preset_library_history.gd` and `check_edit_history_runtime.gd`, selected
using the actual AnimationPlayer position rather than assumed process ordering.
Exact t0 noise keys and the seven showcase effects retain their separate native
reference-check requirements. Cleanup is intentionally static; resample/reduce
can preserve visible motion. Those cases waive only inapplicable progression or
visible-difference checks, not the independent played-value or history checks.
Missing required Redo players/clips fail explicitly.

Other FX effects have progression/difference checks only; their precise shape,
amplitude, easing, contact and readability require independent temporal review
and existing native history-contract evidence. These checks intentionally cannot
turn a continuously changing but semantically wrong effect into visual approval.

Audio-cue playback events may be observed as `playing`, but silent PNG capture
cannot certify audible output. Actual audio capture and independent event/output
proof remain required. Output always retains pending visual/audio qualification
and the human-review waiver separately. No files in this workflow are candidate
release qualification receipts by themselves.

## Pure verification

```powershell
python -m unittest discover -s tools -p test_saved_effects.py
& $Godot --headless --path $DisposableProject --script res://render_saved_effects.gd --check-only
```

Six checker tests include incorrect independent endpoints, borrowing unrelated
node progression, missing second take, wrong operation identity, duplicate frame
and nonfixed native clock. Godot4.7.2 parse-only passed. The complete 49-case planner (47 unique operation keys) was
run against existing archives; render/runtime behavior remains unexercised until
the root capture queue runs it. Private scene/media locators stay local; do not
publish raw private assets or this machine's generated plan as public footage.
