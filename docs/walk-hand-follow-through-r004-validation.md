# Walk hand/forearm/wrist r004 — revision accepted

2026-10-09: the user says r004 is okay and asks to wrap up the repairs and
publish on GitHub. Revision acceptance/playback is recorded; the exact reviewed
profile/rig coverage is being clarified. The proposed next scope is
`release-wrap-up-plan.md`. This acceptance does not cover the remaining motions.

Animation source: `68e06aa5247145ecb8a8f1f09b000e9f4cd21123`.
Reference r003 source: `86ea12a8d2521c00c6155bb1a032ffdd3055d4ac`.
Unreleased branch: `repair/toolkit-quality`.

## Feedback and changes

The user confirmed substantial improvement in r003, then requested softer
hands/forearms/wrists and suggested a movement randomizer. The prior videos,
recipes, scenes, feedback and delivery receipts are preserved. The focused
plan is `walk-hand-follow-through-r004-plan.md`.

The shared gait generator adds opt-in forearm axial turn, a second wrist
axis and bounded periodic variation. Elbow bend/swing and wrist delay are
tuned together. Axes use actual connected rest geometry and animated parent
frames; local bone offsets stay unchanged. These are baked keys in the existing
clip, with one playback owner. No additional runtime bone writer is required.

Both comparison panels now draw the synthetic rigs' finger segments from played
bone globals. The left panel loads the original r003 saved clip; this makes its
rest fingers and the candidate's posed fingers visible in the same preview.

The seeded variation uses smooth periodic harmonics: a given seed reproduces
the same clip and its loop repeats the same variation. Changing the seed creates
another take. It is not fresh random motion on every frame or cycle.

Both candidates also include a gentle curl on the four finger chains per hand,
using measured segment and palm geometry. The optional finger preference
question remains unanswered; including fingers is a preview choice, not
approval. Thumbs stay at rest. Missing/ambiguous named chains or palm geometry
return `OPERATION_UNAVAILABLE` when finger posing is requested. This does not
claim support for arbitrary finger naming or automatic anatomical inference.

| Override | Grounded | Responsive | Accepted range |
| --- | ---: | ---: | --- |
| `forearm_twist` | 5.5° | 6.5° | ±20° |
| `wrist_sway` | 2.5° | 3° | ±10° |
| `arm_variation` | 0.9° | 1.2° | 0–3° |
| `variation_seed` | 241 | 241 | integer 0–2147483647 |
| `hand_relax` | 20° | 18° | 0–45° total chain curl |

Existing r003 hip/torso/head coefficients and same-profile recorded ground
speeds are retained. Complete recipes are the two r004 JSON files alongside
this document. Existing defaults and golden clips remain unchanged.

## Engine and public-route checks

- Fresh visible Godot 4.7.2, editor PID 9132: **54/54 motion tests**, no skips.
  Native articulation/history coverage adds 13,644 assertions across normal,
  short, Z-up and arbitrarily rotated-rest fixtures at actual 30/60/120 FPS.
  It checks local offsets, loop seams, seed repeatability/different takes,
  played axial turn, multi-axis wrists, palm-directed curl, dry run and undo/redo.
  Nineteen refusal assertions cover bounds, fractional seeds and ambiguous hands.
- **14 local headless suites pass.** Headless log and full editor result are
  in the local recovery folder.
- Eight clips generated through the actual Godot AI 4.1.0 custom-tools route;
  dry run, track resolution, save and reopen all pass. Grounded route UUID
  `a805d367eb0f4843954877ebf4441282`; responsive
  `125db16714764de4923a543897ebc16a`.
- Sixteen candidate dry invocations before/after core reload pass and preserve
  the inspected saved clips. Both candidate parameter sets remain
  available through Godot AI after reload.
- Twenty-four native contact/loop runs and twenty-four independent upper-body
  traces pass at **30, 60 and 120 FPS**. Engine-only checkers play the saved
  clips; they do not import the generator or hand-apply generated poses.

| Recorded maximum/minimum across all rigs/FPS | Grounded | Responsive |
| --- | ---: | ---: |
| Maximum declared stance slide | 0.115 mm | 0.115 mm |
| Maximum rest-ankle-plane penetration | 0.599 mm | 0.689 mm |
| Maximum root travel error | 0.0234 mm | 0.0234 mm |
| Maximum loop position error | 6.14e-8 m | 2.98e-8 m |
| Maximum loop rotation error | 1.51e-7 rad | 2.80e-7 rad |
| Maximum wrist local excursion | 12.01° | 13.50° |
| Maximum wrist step (worst 30 FPS) | 1.50° | 1.77° |
| Minimum wrist axis-vector cross magnitude | 0.977 | 0.988 |
| Minimum palm-directed finger-root gain | 0.0742 | 0.0662 |

Axial forearm projection ranges exceed 0.091/0.107 on every hand/FPS; the
independent regression measures this against the actual rest forearm direction.
Finger gain is a dimensionless change of direction projected toward the palm,
not a claim about skinned fingertip collision. Contact checks measure ankle
planes/markers; skin soles and whole-body center of mass are not validated.

## Media, recovery and manual review

Animation source CI passes all **34 Windows/Linux validation jobs**, including
both public MCP routes, in [Actions 37982111931](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/37982111931).
The archive gate checks the complete job list against the exact animation SHA.

Four continuous same-profile r003/r004 comparisons are complete: four rigs,
six seconds front and six seconds side per rig, clean and diagnostic modes.
Two enlarged hand-detail copies use fixed crops of the clean recordings,
preserving timing and frame order. **All six MP4s independently decode to
2,880 frames / 48 seconds, 1920×1080 H.264 at 60 FPS.** Every native capture
reports zero engine errors and one root consumer per view.

The archive gate verifies candidate/reference source revisions, exact native
scene paths and front/side chapter order, media hashes, all source CI jobs,
fresh editor results, actual-FPS checks and before/after-core-reload routes.
It preserves both exact sources, sixteen reference/candidate scenes with local
FBX dependencies, review tooling/docs and hashed receipts. Imported rigs and
videos stay local; this is an unreleased review branch.

Recovery root:
`F:\GODOTAITESTING\toolkit_repair_snapshot_2026-09-30\character_quality_20261009\walk-review-r004`.
Six hash-verified review copies and `START-HERE.txt` are under `review-videos`
inside that root. The Explorer window is confirmed open at this location.
Start with `walk-grounded-r004-hand-detail.mp4`, then responsive hand detail
and both whole-body clean comparisons. Previous r003 is left; r004 is right.
Chapters: dummy 00:00–00:12, X Bot 00:12–00:24, short 00:24–00:36,
tall Z-up 00:36–00:48. Diagnostic versions show contact/root markers.

The r004 feedback pause is complete. Plan integration of the selected accepted
profile as actual defaults next, preserving these reference files. Keep the
reviewed profile/rig coverage explicit; numerical/CI passes alone do not approve
other motions or promote unreviewed profiles. See `release-wrap-up-plan.md`.
