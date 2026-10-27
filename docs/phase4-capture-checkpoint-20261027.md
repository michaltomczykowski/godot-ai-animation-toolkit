# Remaining recordings, 27 October

Phase4 remains active. Official4.7.2 Windows capture; released421 original public
outputs. No new motion generation, pose writes or threshold changes.

## Two motion representatives

Private `motion-representatives-r005` binds capture source cb70cab and original
right-strafe44089be / stationary-jump f5da034 producers. The latter is an in-place
jump with zero horizontal distance, not zero height (dummy requested/default
height .470113754m). Probe timestamps0/1.5/2.983s miss the actual early flight;
the full movie and ordered assessment must include anticipation/flight/landing.

Both fresh admission suites (10controls each) and both24-play physical matrices
pass. Both framing probes pass. Right clean movie complete:1440frames,24s,
1920x1080/60FPS, full decode verified. Diagnostic and two jump movies pending
at this checkpoint; original probe/native/execution bytes stay private.

## Eight bake pairs

New render_saved_bake_capture extends the unchanged shared saved-scene evaluator.
Original scene roots are moved together under a viewport; children, authored
poses, modifier configuration, graph schedule and keys remain unchanged. Camera
layer20 displays only technical rods/axes derived from actual final witnesses.
Both cameras fit the source/redo/two-fresh-take native world union.

Each native sample uses synchronous RenderingServer.force_draw(false,0) and
force_sync, with process/physics clocks, source observations, witness solve count
and body/graph state compared before/after. No process-frame yield occurs inside
the authored schedule. This avoids allowing a deferred Spring reset to execute
between the otherwise synchronous native samples. Full native/render traces
must match exactly, alongside original independent parity limits. Actual .205/
.605s endpoints and pre-event samples remain authoritative. Display repetition
and endpoint holds belong in later composition with explicit delta0 labels.

run_saved_bake_capture copies the admitted r004 input project/userdata into an
exclusive output, keeps original manifest bytes and public/native identities,
pins every input and records the child PID, logs and override cleanup. Six
offline corruption controls cover trace changes, missing runs, nonfinite
geometry and source/redo/take union. Actual parsing/runtime capture, composition,
decode and independent assessment are pending. This implementation is not a
product repair or visual qualification.

Reference: Godot RenderingServer force_draw forces viewport redraw on the main
thread; force_sync synchronizes CPU/GPU. The explicit zero frame_step and raw
state/clock guards test this contract rather than assuming drawing is inert.
https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html

Linux phase2 remains unresolved and publication gated. Exact candidate audit,
final four-cell qualification and merge/tag/release remain pending.
