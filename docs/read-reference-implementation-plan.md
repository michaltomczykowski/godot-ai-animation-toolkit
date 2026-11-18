# Bounded read reference implementation plan — 24 October 2026

Base54744b138f0767da317f0f4eeac90e58cf478768. New isolated E: worktree;
primary and prior worker leftovers are untouched. Root owns all live engines.

1. Preserve every existing operator request and invocation count in the eight
   2Dread driver and three3Dread driver. Do not retry a failed public operator.
2. Add a shared optional public test_run witness begin/end around each existing
   positive/refusal call. The editor helper persists only a logger and immutable
   snapshot between those calls. Exact helper test spans, marker token, operation,
   request, scene, timing, context and original actual call must all bind.
3. Snapshot source node structure/stored properties, resource graph identities/
   stored contents (packed arrays hashed), all skeleton rests/poses, clips and
   Player readable playback state, scene/global history versions and known input/
   write-root file hashes. Unsupported/unreadable state leaves source proof
   pending; no generic equality or clip-only proof promotes source_unchanged.
4. Keep logger capture active from begin snapshot through end snapshot. Derive
   case-local reported_errors from actual raw logger entries, not suite totals.
   No claim of unrelated whole-editor/session cleanliness.
5. For the existing sample8 and motion_audit120 positives, obtain a numeric
   reference in the SAME editor after the captured operation: independently load
   the committed public scene into an isolated viewport; strip scripts; use
   native manual AnimationPlayer with fixed0..1clocks and the authored clip.
   No production handler/spec sampling/grading helper is loaded by the reference.
   Sample keeps extraction (FK response excludes actor root travel); audit plays
   the saved root track on the reference actor so world positions include travel.
6. Preserve raw world bone/rest positions and native clocks. Independently compare
   sample foot coordinates and reconstruct contact/support/bob/penetration/slide/
   knee metrics and original published budgets from reference positions. Keep
   any unimplemented/reference-incompatible check pending. Do not loosen any
   existing physical threshold, invent a reference or promote visual/native
   qualification without execution. Numeric report rounding is a separate
   explicit representation contract, with corruption controls.
7. Add strict standalone adapters and meaningful missing/corrupt/wrong-source/
   wrong-value/state/history/file/logger/clock controls. Supply minimal collector
   and CI patches rather than replacing whole files. Offline checks only here;
   root parses Godot4.7.2 and executes actual fresh public/CI qualification.
