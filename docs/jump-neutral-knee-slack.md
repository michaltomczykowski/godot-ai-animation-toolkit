# Jump neutral knee slack

Jump generation lowers its neutral pelvis by at least 2.5% of measured mean leg
length. Additional geometric reach correction remains available. This affects
jump only; existing clips and other motion generators retain their behavior.

A numerical IK reach margin prevents clamping but leaves a nearly straight knee
with excessive speed during push-off and landing. A local controlled replay of
four real saved rig fixtures reproduced the original 120 FPS failures exactly.
One percent lowering passed 120 FPS but the short rig still exceeded 10 leg lengths
per second at 240/480 FPS. Two percent passed; 2.5% provides additional margin
without changing the strict 10 leg-lengths-per-second gate.

`neutral_knee_drop_fraction` reports the fixed 0.025 fraction.
`neutral_knee_drop_m` reports its metric amount; `pelvis_base_drop_m` reports the
actual total neutral lowering, including any larger reach correction. Public
metric conversion applies world scale once to each metric value.

Run `res://tools/check_jump_neutrality_native.gd` in an isolated local project
with a four-rig public route JSON and a fresh evidence directory. It regenerates
bone channels from measured geometry, retains the saved carrier/timeline, and
requires native Player/Tree 120 FPS checks to pass below the unchanged velocity
bound. This controlled regression is separate from public generation, history,
saved-scene qualification and independent visual assessment. Private rig assets
and controlled local scenes remain local.

## Explicit loops and forward skeletal travel

A jump with nonzero `distance` and `root_motion: false` requires
`loop_mode: none`. Explicit `linear` and `pingpong` requests return typed
`OPERATION_UNAVAILABLE` before changing clips, poses, extraction bindings or
undo history, including dry runs and the `cycle` jump alias. Linear playback
connects different travel endpoints; pingpong reverses the one-shot and walks
its landing back through flight. A repeating forward-return jump is not a
supported recipe. Stationary jumps and extracted travel retain their existing
loop controls.

Nonzero turns likewise refuse explicit `linear` loops before authoring: native
playback otherwise connects different heading endpoints with a wrap snap.
Omitted/`none` remains a one-shot. `pingpong` is supported as intentional
forward-and-reverse turn playback, with the original end heading preserved.
