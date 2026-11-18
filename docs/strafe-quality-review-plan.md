# Next R2 phase: lateral locomotion

Prepared while turn recordings run. **Do not generate or change strafe output
until the remaining turn-style review has received feedback.** Work alone with
Godot 4.7.2 and the separate released Godot AI public custom-tools API.

## Preserve and measure

Freeze approved walk/run/idle/start-stop and accepted turn scenes/media, source
identities and eleven fixtures. Use a fresh validation project and UUID scenes.
Start with ordinary Responsive left/right strafe calls on all four rigs, both
default extracted travel and explicit in-place mode: 16 public clips/96 native
plays. Preserve a continuous baseline before changing generation.

Each call needs dry pose/binding nonmutation, external Undo/Redo of that actual
write, save/forced reopen and resolved native tracks/counts/markers. No private
handler call may substitute for the Godot AI route.

## Independent playback and ownership

Play saved clips through one Player or Tree at 30/60/120 FPS for several cycles.
Derive up/forward/lateral axes, ankle plane and leg lengths from fixture rest
geometry, independently of the generator. Require the established stance slide
limit min(2% leg length, 3 cm), penetration <=1% leg length, correct release and
replant timing, no knee flips/clamps/nonfinite output and continuous loop seams.
Check lateral direction, net travel, forward drift, foot separation and readable
leading-foot/trailing-foot order; feet must not cross inadvertently.

Ownership must be explicit in the test scene:

- Extracted: one consumer applies engine root displacement in the declared
  local convention. Check that reported travel and actual world movement agree.
- In place: the clip has no actor-translation writer/extraction; one explicit
  test controller supplies the reported lateral speed. Measure world contact
  during that real actor movement. A frozen actor's treadmill playback is not
  evidence of stationary world-space stance.
- Negative controls must detect doubled travel, reversed direction, moved
  stance feet, missing/mistimed contacts, inert output and knee discontinuities.

## Inspect before repair

Current strafe delegates to shared gait_keys with lateral_step/lead_side and a
forward knee pole. It has dedicated support shift, marker and speed-cap paths;
the approved walk's pelvis reach plan is skipped for lateral stepping. Treat
these as measurement targets, not proven defects. Inspect actual clamp/reach
reporting and upper-body feature application before choosing a repair.

Fix the strafe branch/config first: coordinated support transfer, reachable
lead/trailing targets, pelvis/body response, restrained arm/forearm/hand motion
and a stable heading. Avoid arbitrary noise. A shared gait change requires exact
approved-output regression; never replace fixtures merely to make tests pass.
Unsupported requests must return typed nonmutating errors, not silent speed
changes or inert success.

## Complete, record, pause

After a focused repair passes, cover both directions, all five styles, four rigs
and both travel modes: 80 public clips/480 native plays. Add only risk-driven
timing/speed/reach/refusal cases. Verify discoverability and actual core reload;
the latent generic strafe alias is currently outside the advertised preset enum,
so explicitly resolve its supported contract before promoting it. character_setup
does not advertise strafe generation; do not invent that feature in this phase.

Run relevant public history/motion checks, full local suites and exact-source
Windows/Linux CI. Retain failures and source/media/scene hashes. Record native
1080p60 clean/diagnostic MP4s with simultaneous front/side views, world floor grid
and at least six uninterrupted seconds per rig. Choose fixed camera framing from
the complete travel bounds so the actor remains visible. Contact sheets remain
supplementary. Keep private X Bot media/assets local.

Deliver the continuous videos in PC Explorer and **pause for explicit feedback**.
Numerical passes alone do not approve quality. Then record feedback and proceed
to stationary/forward jump. Remaining R3 integration/audit and R4/R5 release
gates still apply.
