# Character quality and manual video review

Approved 2026-10-08. Work on `repair/toolkit-quality`, unreleased, using Godot
4.7.2 and Godot AI's public custom-tools API. Work alone. Level surfaces only.

## First checkpoint

Record the **current walk baseline on all four rigs before changing motion**:
bundled dummy, local X Bot, short synthetic and tall Z-up synthetic. Save this
plan, build reusable recording/checking tools, preserve invocations and saved
scenes, inspect the recordings, commit and push the checkpoint. Deliver
continuous videos and **stop for human baseline feedback**. Neither numerical
passes nor a plain “continue” approve visual quality.

## Recordings

- Native playback of saved, reopened scenes; 1080p60 H.264 MP4.
- Fully shaded dummy and X Bot; solid body segments driven by played bones for
  synthetic rigs. X Bot's third-party source asset stays local.
- Front and side views with matched framing. Cameras follow translation only;
  the floor grid remains stationary so travel and sliding remain visible.
- Loops play at least six continuous seconds per view. One-shots play twice,
  including anticipation and recovery; resets happen outside each action.
- Label operation, rig, profile, revision and time. Candidate reviews compare
  baseline with grounded and baseline with responsive, covering all four rigs.
- Separate diagnostics show contact, support, hip/support projection and root
  travel. The hip projection is **not** a center-of-mass measurement.
- Contact sheets supplement videos; they never substitute for human video review.

## Review loop and durable state

For each revision: generate through Godot AI; save/reopen; run relevant native
checks; record and inspect videos; preserve source, scenes, route receipts,
metadata and hashes; document concerns; commit/push a labelled checkpoint;
show the videos and stop for feedback. Persist state in
`docs/character-quality-review.json` and phase notes in `FIX_ROADMAP.md`.

The reviewer can approve either profile and request changes to the other.
Explicit approval of both profiles on all four rigs allows promotion of defaults,
regression gates and movement to the next operation. “Approve both and continue”
advances; plain “continue”, silence, elapsed time, crashes or usage resets do not
grant approval. Shared changes that alter approved output invalidate its approval.

## Motion implementation after baseline feedback

Tune existing stance/swing, reachable feet, stable knee poles, pelvis/torso/arm
coordination and anticipation/recovery. Grounded natural motion becomes the
approved default; responsive game motion becomes optional `style="responsive"`.
An unimplemented operation/profile returns a typed unavailable error.

Use one profile resolver for dedicated operations, cycle aliases and
`character_setup`. Preserve explicit duration, speed, height, distance, angle
and overrides. Responsive implicit timing retains travel/action goals. Match
start/stop/contact/neutral poses to approved walk/idle and sequence composition.
Decide tuning coefficients from recorded revisions. Preserve baselines; promote
defaults, evidence status and goldens only for explicitly approved output.

## Operation order and checks

1. Walk (current baseline review first).
2. Run.
3. Idle.
4. Walk start.
5. Walk stop.
6. Turn, including left/right and a two-step 180-degree turn.
7. Strafe, both directions.
8. Jump, in place and forward.
9. Separate final `character_setup` and idle/start/walk/stop sequence review,
   both profiles, all rigs.

Pause after each operation. Review transitions from both walking contact phases;
exercise cycle aliases with the corresponding recipe.

Fresh native playback uses actual `1/fps` steps at 30, 60 and 120 FPS:
stance slide <= min(2% leg length, 3 cm), penetration <= 1% leg length,
no knee flips/nonfinite output/default reach clamps, continuity, contact timing,
full single-owner root travel, valid saved track paths/types/counts. Retain
dry/refusal/history/isolation/reload protections. Sampling a non-one-second clip
with `samples=fps+1` is not evidence of playback at that FPS.

The final approved revision passes full Windows/Linux headless, editor and live
MCP gates. Other-family visual review, integration combinations and agent task
usability follow this phase. No tag, release, merge or media upload is authorized.
