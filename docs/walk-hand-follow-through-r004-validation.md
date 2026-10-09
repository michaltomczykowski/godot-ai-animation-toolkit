# Walk hand/forearm/wrist r004 — recording in progress

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

## Pending delivery gate

Animation source CI passes all **34 Windows/Linux validation jobs**, including
both public MCP routes, in [Actions 37982111931](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/37982111931).
The archive gate checks the complete job list against the exact animation SHA.

Continuous same-profile r003/r004 comparisons are being recorded: four rigs,
six seconds front and six seconds side per rig, clean and diagnostic modes.
Enlarged hand-detail copies use fixed crops of the clean recordings, preserving
timing and frame order. No media has been delivered or approved at this point.

Recovery root:
`F:\GODOTAITESTING\toolkit_repair_snapshot_2026-09-30\character_quality_20261009\walk-review-r004`.
Finish recording/decode checks, exact-source CI, archive/hash verification and
PC Explorer delivery, then stop for human review of both profiles/all four rigs.
