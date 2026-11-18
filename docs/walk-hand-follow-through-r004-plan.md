# Walk hand and forearm revision r004

2026-10-09 feedback: “it's way better! but the hands/forearms/wrists feel way
too stiff, maybe add a moving randomizer to these parts or so something?”
This requests another revision. r003 playback is confirmed; no complete
profile/all-rig approval or default promotion is inferred.

1. Preserve r003 recipes, clips and videos. Measure its played elbow/wrist
   ranges and inspect arm/hand rest geometry on all four rigs.
2. Add opt-in axial forearm rotation, a second wrist axis and small seeded,
   smooth periodic variation. Carry axes through the animated parent and use
   actual elbow-to-hand geometry. Tune elbow swing/delay and wrist follow-through
   together; no per-frame random rotations or additional runtime bone writers.
   The saved loop is reproducible: its variation repeats at its own seam, and
   selecting a different seed produces a different authored clip.
3. Ask whether to include relaxed fingers while implementing wrist/forearm
   mechanics. If included, validate finger chains and palm geometry before
   posing them; a rig without usable fingers must get a clear refusal to a
   requested finger pose, not an inert success. Preserve thumb posing unless
   its axes are validated separately.
   Preview choice: include gentle measured finger curl while the optional
   preference question is pending. All four fixtures have finger chains. This
   is a reviewable candidate choice, not approval of fingers or defaults.
4. Validate finite values, bounded amplitudes, integer seed and usable roles/
   hierarchy before generation. Keep defaults/goldens unchanged. Add native
   regressions for independent bone axes/orientations, seeds, loop continuity,
   dry run, missing roles and undo/redo.
5. Use a fresh visible Godot 4.7.2 editor and the real Godot AI public route to
   generate, save and reopen eight candidate clips. Check contacts, reach,
   root travel and joints at actual 30/60/120 FPS, including before/after core
   reload and Windows/Linux source CI.
6. Record four continuous 48s 1080p60 front/side comparisons on all four rigs:
   same-profile r003 left, r004 right; clean/diagnostic for both recipes. Archive
   sources, scenes, invocations, exact parameters, media and hashes; push the
   unreleased checkpoint. Open PC Explorer and stop for human review.
   Include enlarged continuous hand-detail copies from the same recorded
   playback so wrist/finger articulation can be judged remotely.

Current anatomy/physiology reference:
[The elbow is the load-bearing joint during arm swing](https://pmc.ncbi.nlm.nih.gov/articles/PMC10277704/)
measures flexion and axial rotation during arm swing; coefficients here remain
authored preview choices, not a fit to measured subjects.
[Godot bone track contracts](https://docs.godotengine.org/en/4.7/classes/class_skeleton3d.html)
require skeleton-space/rest-aware conversions. Continuous video review remains
the quality gate. Contacts are ankle/marker measurements, not skin-sole or COM proof.
