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

## Later actual execution

All four motion films pass capture/full decode: each1440frames/24s/1080p60.
Right clean SHA bb6fb2fb1411cd47054b80c8410954fa02dcbf1fecf45378006669d2f7886244;
right diagnostic 1c4a6a12999783c250227a101d8e9cfb3c4f12646480d75cdc65e8e740bb6b9e;
jump clean f249487ccd260ddd8bfb52ec438c3220b2f617136b8d65f14bc97824cfe77a22.
The complete four hashes and independent assessment are pinned in the separate
motion representative assessment document. Strafe is one continuous6s take/rig;
jump has two fresh3s takes/rig. No two-fresh-strafe approval is claimed.

Bake render r001 rejected: copied runtime godot.log incorrectly bound as input;
overlay Basis.scaled shrank world rows rather than local cylinderY, producing
visibly clipped axes despite intended-endpoint bounds. b5c4c94 excludes runtime
logs, scales the localY column and checks actual transformed mesh AABB corners
plus raster fringe. Original r001 and its images remain untouched.

Actual bake-eight-render-r002 child exits0, zero engine/observation failures,
776PNG/776native samples,32runs. Its Python postprocess failed because the shared
sha helper required Path but received str. A read-only admit step now requires
the original successful child exit/command/override cleanup, original engine log,
every frozen input, all32 exact native traces and every image/camera before
composition. It preserves the failed execution receipt and records that error
in media.current_native_admission. No engine replay or source relabeling.
Image clocks use the same1e-12 mathematical schedule limit as the independent
native comparer (Godot JSON prints1/60 as .0166666666666667); each image time and
delta must additionally equal its actual native serialized sample exactly.

All16source/redo pairs and16fresh-take comparisons pass original physical limits.
Current bake-eight-pair-media-r001 movie:2808frames/46.8s/1080p60/full decode,
SHA d1a8f1d05cb480a485b51489f03aea2aa9dc768562a546cab95cc765e548a658.
Each actual sample displays for6frames, with30extra endpoint frames explicitly
marked as presentation holds; no extra solver steps. Eight cases, two fresh
takes each, two fixed views. Independent assessment of214actual decoded images/
27ordered sheets is active. Sixteen focused native/render/admission controls
pass, including failed-child/cleanup/foreign-command/binding refusals.

Remaining sequence/secondary/static inputs staged by a9d63f2 (integratedf75c324).
Reuse full88s sequence after current saved-input admission and assessment;
minimum new capture queue is secondary branches and chain create/append,
1680frames total. See remaining-sequence-static-media-plan-20261027.md.

Fresh CI40359394495/head49fc16a: all jobs except Linux421 cleanZIP pass, including
the prior Windows430 monotonic-binding failure. The new cleanZIP failure is a
120s Python modifier-allocation gate timeout after the editor returned test_run
ok, not a proven heap crash. Raw job log and9MB artifact retained privately under
ci-49fc16a-clean-linux-421. This timeout requires diagnosis before qualification;
the separate official Linux heap crash remains unresolved.
