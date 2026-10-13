# R2 turn quality and public-tool playback

## Scope and starting checkpoint

2026-10-13: the user says “they look okay, continue” in response to the
remaining start/stop styles and complete-sequence review. The delivered r002
set is approved; individual watched files were not enumerated. Preserve its
22 movies, saved scenes, feedback, source identities and green regression/CI.
Approved walk, run, idle and start/stop must remain unchanged.

Work alone, on `repair/toolkit-quality`, using Godot 4.7.2 and the separate
released Godot AI 4.2.1 public custom-tools API. No release at this phase.

## A. Preserve and measure the ordinary turn

Use a fresh isolated visible editor project and UUID scene directories. Generate
90-degree left/right and two-step 180-degree left/right turns with all five
styles on dummy, local X Bot, short and tall Z-up rigs. Default 90-degree calls
omit angle, duration, sampling and overrides; 180-degree calls request angle 180
and steps 2. Responsive omits style. Explicit directions define the cases.

Exercise both requested root flags, documenting effective ownership: the current
turn writes skeletal heading, not actor yaw extraction. Do not invent root
translation or apply a second bone writer. Verify binding safety and reported
versus saved tracks. This is 160 public clips and 960 Player/Tree/FPS plays.
Public history witnesses must undo/redo the external write, without generating
another clip. Check dry pose/binding nonmutation, save/forced reopen, track
types/paths/counts, markers, one-shot endpoint and reported errors.

First capture the existing ordinary Responsive turns before animation changes.
Preserve failing measurements and scene/source hashes as the baseline. Do not
request approval of a candidate that fails required numerical gates.

## B. Independent engine checks and repair targets

Play saved scenes through one active AnimationPlayer or linked AnimationTree at
actual 30/60/120 FPS. Use played world-space feet, rest-derived up/forward and
leg lengths; no private generator sampler, IK or hand-applied poses in checks.

- Stance slide <= min(2% leg length, 3 cm); penetration <= 1% leg length.
- Contact windows require a foot to stay planted, swing clearance while moving,
  and correctly timed replants. Expose absent/inaccurate metadata as a failure.
- No nonfinite output, knee flips, default reach clamps or inert playback.
- Verify signed final heading, both final foot headings, recovery/terminal hold,
  intermediate 180-degree step heading and continuity between steps.
- Measure frame-to-frame position/angular changes at boundaries. Rotate knee
  pole comparisons with the moving body; a natural 180-degree heading change
  must not itself count as a flip.
- Check Player/Tree parity, reported sampling, markers and root binding. A
  translation-only extraction binding does not extract a skeletal turn.
- Negative controls: moved stance foot, wrong final heading, missing contacts,
  double actor yaw and unchanged/inert output must be rejected independently.

Current code questions: only one foot swings per requested step; its lift window
ends before its target yaw finishes changing; the other foot retains its old
heading at settle. Reach solves are not aggregated in turn metadata. Knee poles
use a fixed rest direction while pelvis yaw accumulates. Existing upper-body
lead/arm keys need rest-frame and recovery checks. These are audit targets,
not claims of completed verification.

Fix turn-local planning/keys first: explicit weight transfer, reachable ankle
targets, a release/step/replant schedule for both feet, stable moving knee poles,
coordinated hips/torso/head/arms and truthful metadata. Retain caller angle,
steps, timing and style contracts. Typed nonmutating errors cover unsupported
requests; never silently clamp a requested angle or report success for inert
output. Shared changes require exact approved-output regression.

## C. Coverage and regression closure

After a focused fix passes four-rig Responsive checks, complete all 160 ordinary
public/history calls and 960 native plays. Check nondefault angles, step counts,
short/long periods, sampling and refusal nonmutation only for concrete remaining
risks. Exercise `cycle` turn alias and character_setup parity and actual core
reload discovery. Run public motion, relevant history, full local editor,
headless and exact-source Windows/Linux CI; retain expected private-rig skips.
Protect all eleven existing fixtures and compare accepted saved motion if shared
code changes. Preserve previous source receipts rather than overwrite them.

## D. Continuous review and pause

Record saved native playback in 1080p60 MP4 with simultaneous fixed front/side
views, floor grid and two complete anticipation/action/recovery takes per rig.
Use clean and diagnostic pairs; compare the same baseline/candidate cases if
changed. Keep private X Bot assets and footage local. Decode movies, verify
frame/scene/source hashes, and archive sources, parameters, scenes and receipts.

Deliver Responsive first for focused feedback if a broad repair is needed;
otherwise deliver the complete style/direction pack. Open PC Explorer and stop
for explicit feedback. User visual approval is a separate gate from numerical
passes. Then record feedback and finish approved regression before strafe.

## Execution ledger

- Start/stop r002 user approval: received; recording durable receipt next.
- Turn source inspection: complete; baseline public generation/checks pending.
- Turn implementation, negative controls, recordings and visual approval pending.
- R3 operation/integration closure and R4/R5 release gates remain pending.
