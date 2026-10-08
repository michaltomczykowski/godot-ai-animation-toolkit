# Motion and sequence history/playback repair

Godot 4.7.2; separate Godot AI 4.1.0 addon; unreleased
`repair/toolkit-quality`. Approved scope:
[saved plan](motion-sequence-history-plan.md).

## Checkpoint: native generation and saved history, 2026-10-08

The fresh visible editor and external Godot AI route pass 29 named tests:
17 history/coverage tests, ten atomic/native regressions, and two continuation
matrices. The matrices export every required 273 case ID and 819 Do/Undo/Redo
state. Each write owns one scene action and zero global actions. Paused reverse
playback, sections, queue, speed, library/clip identities, editable-instance
permissions, unrelated source/peer data and source bytes remain unchanged.
Dry/refusal calls require exact orphan sets; writes permit only freed old Redo
objects, with no new orphan nodes. The locked fixture's control clip keys all
authored channels so its paused preview is reproducible without unsaved overrides.

The independent checker imports engine-only reference code. It loads fresh
saved scenes, plays all 2,457 state/rate combinations, and checks all target
paths/types, finite ordered keys, native interpolation, required source channels,
segment/fade endpoints, marker names/times/colors and reported metadata. Motion
references verify saved playback against the pre-save generated native clip;
the existing rig/contact gates remain necessary for motion quality. Sequence
references evaluate native source curves and authored baselines independently.
Secondary references independently integrate the angular spring against native
unmodified parents. No reference calls production composition/spring helpers.

| Measurement | Checkpoint result |
| --- | ---: |
| Required cases / saved states | 273 / 819 |
| Fresh playback runs at 30/60/120 FPS | 2,457 |
| Key / intermediate samples | 2,052,322 / 4,892,901 |
| Complete single-owner travel runs | 270 |
| Largest played position / scale error | 0 / 0 |
| Largest played rotation error | 0.000000450 rad |
| Largest root-delta error | 0.000000534 m |
| Captured engine errors / missing cases | 0 / 0 |

Key/interpolation tolerances are 0.1 mm, 0.001 rad and 0.0001 scale. Separately,
48,011 continuous-approximation samples measure source sequence midpoints and a
denser secondary integration. The largest differences are 0.2784 mm, 0.01634 rad
and 0.000000179 scale. Those values describe sampling approximation, not failed
serialization or approved humanoid visual quality.

Four direct external examples (walk start, two spring branches, rooted
composition and inline pose composition) pass dry/write/refuse/save/forced-reopen
before and after core reload. A separate pose request observes the deferred
refresh and retains the input pose. The new required CI gate fails on missing
suite names, case IDs, states, samples or reload output.

## Closing source and review

The final local editor run passes **375/375 tests, zero skips** in a fresh,
visible Godot 4.7.2 editor. The final external phase gate passes all 32 tests:
13 atomic/native regressions, two continuation matrices and 17 history tests.
Each of the eight direct examples also writes a later hand pose in the same
batch; a separate RPC requires that pose to survive deferred refresh.
The final fresh-process replay repeats every measurement in the checkpoint
table above: 273 cases, 819 states, 2,457 runs and zero captured engine errors.

The final regressions reject scripted resources in enabled or disabled source
event keys before duplication can construct them. Extremely large finite spring
coefficients that exceed floating-point precision, degenerate sampled parent
transforms and missing isolated player/rig copies receive typed errors with
cleanup. No inert spring output may report success for those inputs.

Four fixed-camera pairs were captured from native playback, 316 frames at 60 FPS,
with zero captured render errors. The start/walk/stop output is created through
four actual Godot AI calls, cropping source terminal holds at the requested
endpoints. Jump, two spring branches and cropped rooted/pose composition use
saved public-route matrix scenes and independent native references.

| Representative | Technical visual review |
| --- | --- |
| Start/walk/stop | Leg phases, approach/stop timing and final hold match the native clip; no extra actor or doubled travel. |
| Jump/recovery | Anticipation, airborne pose, landing compression and recovery match saved native playback. |
| Two spring branches | Authored rests and changing parent frames match the independent spring reference, with no playback-induced flip. |
| Rooted/pose sequence | Source timing, pose hold and character travel match the independent composition reference, with one movement owner. |

The capture tool now frees each case's overlay/floor with that case. An earlier
capture retained preceding-case geometry and was replaced. Bone/axis fixtures
approve technical playback fidelity only. They do not approve the remaining
humanoid/action animation quality work. Continuous approximation remains the
separate measurement in the table above.

## Repairs and behavior

- Individual writers refuse playing destinations, including zero-speed playback,
  or active linked AnimationTrees. Guidance identifies a paused/unlinked output.
  Extraction changes that affect another destination clip are refused.
- Secondary motion samples an isolated native AnimationPlayer, excludes private
  modifiers and retains invocation-authored unkeyed rotations. Local rest rotation
  is not removed twice. Angular error and premultiplied velocity use skeleton
  space consistently; a covariance regression rotates the whole parent frame.
  Stable small-angle evaluation prevents floating-point spring drift.
- Sequence composition holds authored values before their first appearance and
  preceding values through missing channels/gaps. It uses native source easing
  and cubic interpolation, captures source/segment/fade boundaries, handles
  zero-fade/nearest discontinuities with native-safe held bridges and refuses
  boundaries too close for native key lookup. Float key/grid deduplication also
  applies to discontinuities. Marker naming avoids collisions globally.
- Sequence supports translation extraction. Rotation/scale extraction and a
  third contributor before the previous fade finishes receive typed unavailable
  errors. Scripted source resources are rejected before native duplication can
  run constructors. Secondary source events are refused; it is an offline clip
  spring, not a final-stack bake.
- Rooted nonlooping individual motions and composed sequences have a stationary
  tail of 1/30 second + 1 ms. A native 1.405-second regression reproduced 3 mm
  of lost final travel without it. This tail permits arbitrary motion endpoints
  to deliver their last delta before Godot's finishing tick at 30/60/120 FPS.
  `capture_duration` retains the requested endpoint; actual `length`/`duration`,
  counts and `root_motion_terminal_hold` report the full output. Playback below
  30 FPS has not been approved. Sequence source crops can exclude a source tail.
- Rigs without toe roles now infer forward from up and hip separation; the
  orthogonal fallback avoids a zero lateral axis during idle/strafe generation.
- Source/graph/spring continuation matches untouched native controls for all
  three families at 30/60/120 FPS after dry/write/refusal/Undo/Redo. These
  synchronous checks capture the final modifier pose inside its native callback.

## Reproduce

```powershell
& "$core\.venv\Scripts\python.exe" tools/mcp_motion_sequence_history.py --core-root $core --project-root "$repo\test_project" --session-hint test_project --port 18131 --ws-port 18132 --godot $godot --record "$evidence\motion-sequence-route.json"
& $godot --headless --path test_project --script res://tools/check_motion_sequence_history.gd

# Generate public-route start/walk/stop and select three saved native cases.
& "$core\.venv\Scripts\python.exe" tools/mcp_motion_sequence_preview.py --core-root $core --project-root "$repo\test_project" --session-hint test_project --port 18131 --ws-port 18132 --checkpoint "$evidence\final-source-route.json" --record "$evidence\review-manifest.json"
& $godot --path test_project --script res://tools/render_motion_sequence_history.gd --rendering-method gl_compatibility --resolution 1280x720 --fixed-fps 60 --disable-vsync -- "$evidence\review-manifest.json" "$evidence\media\frames"
& "$core\.venv\Scripts\python.exe" tools/compose_motion_sequence_history.py --frames "$evidence\media\frames" --manifest "$evidence\review-manifest.json" --output "$evidence\media" --ffmpeg $ffmpeg
```

Run the checker immediately after the complete history suite: selected regression
suites reset the exported manifest. Always use a fresh editor after addon or
preloaded test/reference edits. External gate checks guard/continuation suites
first and the complete matrix last.

## Platform verification

Checkpoint source `0c75b58` passes all 34 validation jobs in
[Actions run 37779095835](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/37779095835):
fourteen headless suites on each platform, four editor/core combinations and
both complete live Godot AI routes. Current-core editor jobs are informational
and also pass. Final follow-up source and hosted confirmation are still required
to close this phase.

Recovery:
`F:/GODOTAITESTING/toolkit_repair_snapshot_2026-09-30/motion_sequence_history_20261008`
contains the approved plan, baseline 22c85c8 source and failing public-route
evidence, checkpoint-route.json, final-editor-all.json, final-source-route.json,
saved native scenes, current source snapshot and media. The media directory has
the paired video, four contact sheets, render/media reports and technical review.
No release, tag, merge or media upload.
