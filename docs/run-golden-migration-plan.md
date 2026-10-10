# Run golden migration — after human approval

Prepared 2026-10-10 while run videos are recording. This is a plan; no fixture
has been recorded or replaced. Follow the manual gate in the run review plan.

## Preconditions

1. Present all ten continuous run videos through PC Explorer. Preserve their
   hashes, ordinary route source `97f17ce`, native/history/reload receipts and
   recovery archive. Pause for explicit feedback on Responsive/default,
   Grounded, relaxed, heavy and sneaky across the four presented rigs.
2. Record the user's actual words and scope against those files. A request to
   continue or a usage reset is not approval. Revisions need new scenes/videos
   and another review; never reset an existing approval in the archive helper.

## Fixture design

- Preserve `golden_run.json` byte-for-byte as legacy evidence. Preserve the
  already accepted walk/spec-walk and legacy idle fixtures too.
- Add `golden_run_responsive_v2.json`, format version 1, quantization 2048 and
  tolerance 2. Reuse the recording guard that rejects normal runs, toolkit CI
  and standard CI recording. Never change tolerance to accept a mismatch.
- Change only the run branch of `_check_golden`: ordinary omitted style,
  duration, sampling, speed and overrides. Keep explicit clip name/loop setup
  and the established in-place fixture convention. The implicit rig-relative
  period and normal 60/s sampling must now be part of the expectation, rather
  than retaining the old explicit 1s / low-sampling request.
- Leave walk's accepted request and idle's legacy request unchanged. Keep run
  aliases, distinct Grounded, setup matched-input, deterministic output,
  optional-anatomy refusals and public Undo/Redo checks active.
- Add a provenance JSON/short fixture note: approval words/scope/date, reviewed
  animation commit, exact fixture-generation source, engine/core commits,
  asset SHA, invocation, digest format, thresholds and video hashes. Distinguish
  the helper's in-memory FBX player path from saved review-scene paths; the
  shared recipe is approved, and separate native checks establish binding.

## Explicit recording and independent comparison

1. Commit the test selector/provenance changes first, without a fixture. A
   normal focused run must fail missing expected data and create no file.
2. With CI/recording flags cleared, restart the visible Godot 4.7.2 editor on
   the separate released-core validation project. Use a one-test public MCP
   run with `ANIMATION_TOOLKIT_RECORD_GOLDENS=1` to record the new fixture.
   Preserve the recording receipt; it is not comparison evidence.
3. Quit/restart with recording cleared. Require a normal focused motion run
   comparing the committed expectation with zero failures/skips, followed by
   all headless suites, full editor and ten-family registration/reload gates.
4. Commit/push source and fixture, verify remote SHA and archive it. Require
   complete Windows/Linux source CI on the exact tracked tree. Select required
   jobs by their names; advisory core-main remains separate. Preserve named
   private-X-Bot skips and local runs including that asset, never a generic
   allowance for other skips/errors. Changed animation needs renewed review.
5. Close run only when approval plus independent regression are complete.
   Update the roadmap/review state, source/CI receipts and recovery documents.
   Then plan/measure idle as the next R2 operation. R3-R5/final release review
   remain required; no merge/tag/publication at this migration checkpoint.
