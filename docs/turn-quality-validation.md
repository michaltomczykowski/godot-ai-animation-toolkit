# R2 turn execution and retained evidence

## Baseline, 2026-10-13

Source `2446bce`: 32 public Responsive calls (90 left/right, two-step 180
left/right; four rigs; both requested root flags) pass dry pose nonmutation,
actual external Undo/Redo, saved-scene reopen and track inspection through
Godot AI 4.2.1 on the visible Godot 4.7.2 editor. Each write ran once. Separate
session attach retries only perform connection/readiness reads.

UUIDs are recorded in each `baseline-r001/<variant>/attempt-*.json`. Independent
checker receipt: `baseline-r001/native-c4d8ee6f81174e4389f267dede725047/matrix.json`.
All 192 Player/Tree/FPS runs complete with zero engine errors and correctly
fail quality checks. Missing contacts/reach metadata, planted-foot rotation,
unfinished foot recovery and played discontinuities are exposed. In the 60 FPS
left-90 Player examples, the unrecovered foot endpoint error is 0.1293 m on
dummy, 0.1298 m on X Bot, 0.0711 m on short and 0.2070 m on tall Z-up.
Planted-foot heading changes exceed 90 degrees. A passing final hip heading
alone does not establish a working turn.

The old turn test applied only one rotation track to a reset skeleton when
measuring torso yaw, ignoring animated parents. Its helper now uses actual
AnimationPlayer seek with all tracks and a rest-relative projected heading.
New checks compare pole directions in the played hip frame, so accumulated
body yaw alone is not a knee flip. Controls corrupt isolated Animation
resources and replay them; original scenes/poses are never edited by checks.

Four continuous baseline clean movies are recording before wiring the new
planner. Partial receipts and raw logs remain in the recovery folder. No
baseline visual approval or turn candidate approval has been requested.

## Repair design refinement

Keep requested `steps` as dominant pivot stages, alternating leading feet.
Add one final catch-up/recovery footfall so both feet settle in the new heading;
report `recovery_steps` and `footfalls` explicitly. A two-stage 180 turn has two
dominant heading transfers and a final stance recovery. During a contact window,
both the ankle target and foot heading remain fixed. Swing yaw and displacement
finish before contact resumes. Torso targets must be converted against played
generation-parent frames instead of keying full accumulated yaw into every
joint. Planning computes reachable pelvis lowering before solving legs; no
silent clamps, inert zero-angle successes or silent step-count truncation.

Reference contracts: [AnimationMixer](https://docs.godotengine.org/en/4.7/classes/class_animationmixer.html)
for manual Player/Tree evaluation and separate rotation/translation extraction;
[Animation](https://docs.godotengine.org/en/4.7/classes/class_animation.html)
for saved native bone track paths and interpolation. Actual turns currently own
skeletal heading; they do not extract actor yaw. Requested root flags must be
reported separately from effective ownership.

## Pending gates

Wire and measure the turn-local repair, preserve failures, validate controls,
complete style/timing/alias/setup/reload/regression and source CI as required.
Record continuous candidate footage and pause for explicit user feedback.
R2 turn is not yet approved; remaining R2/R3-R5 release gates still apply.
