# R1 exit: approved walk goldens and regression

2026-10-10. The user viewed the delivered r005 set and replied, “they look very
good.” Record acceptance against animation source `056cc8d` and the exact video
hashes already delivered. This approves the presented five-style/four-rig walk
set; no other motion or release is approved by this feedback.

## Fixture migration

- Preserve `golden_walk.json` and `golden_spec_walk.json` byte-for-byte as the
  pre-v2 historical fixtures. Add separate `golden_walk_responsive_v2.json` and
  `golden_spec_walk_responsive_v2.json`; do not widen tolerance or remove checks.
- The editor walk fixture uses the ordinary default sampling (60/s), with the
  same one-second linear-loop fixture and real motion handler. Run/idle fixtures
  and their explicit sampling stay unchanged until their own R2 reviews.
- The synthetic spec fixture retains its independent 12/s arithmetic test and
  rig. It measures the new default table rather than claiming full played or
  visually reviewed humanoid output.
- Golden recording requires explicit `ANIMATION_TOOLKIT_RECORD_GOLDENS=1` and
  is refused in CI. Normal tests must fail for a missing fixture, never create
  their own expected result. Record deliberately, then compare in a fresh
  normal run. Preserve existing quantization (2048) and tolerance (2).
- Save a provenance manifest with old/new fixture hashes, source, parameters,
  engine, review receipt and changed track/key shapes. Generator code remains
  unchanged; approved videos retain their original source/hash provenance.

## Gates and recovery

Use Godot 4.7.2 and the separate released Godot AI v4.2.1 checkout. Restart the
visible validation editor for changed test helpers. Invoke the focused motion
suite through authenticated public MCP, then run the complete editor/registration
harness and all fourteen headless suites. Unexpected failures are repaired and
reported. No blanket error/skip suppression.

Push a candidate checkpoint and require the existing Windows/Linux source CI
jobs (including both full live MCP routes) to pass. Inspect exact results and
core/source commits; advisory core-main outcomes are reported separately. The
expanded v4.3.0/package matrix remains R3/R4 work.

Archive tests, source, hashes, approval state and closing notes under
`release_r1_20261010/accepted-r005-regression`. Keep the original r005 review
delivery and historical receipts intact; its archive helper deliberately refuses
to reset recorded feedback.

R1 closes only after green regression. Then plan and implement the R2 run review,
with a new continuous-video pause. No release before the remaining R2-R5 gates
and final candidate approval.
