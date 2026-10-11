# Idle golden migration — only after video approval

Prepared 2026-10-11 while final idle videos record. This is a plan. No idle
fixture or test selector has changed, and idle has no human approval yet.

## Review gate

Deliver all ten continuous five-style/four-rig videos through PC Explorer.
Preserve source `8665980`, route/history/native/reload evidence, source CI and
video hashes. Pause for the user's explicit feedback. Record their words and
actual review scope; continuation or a usage reset does not approve motion.
Revisions need new saved scenes, media, regression and another review.

## Versioned expectation

- Preserve `test_project/tests/fixtures/golden_idle.json` and every accepted
  walk/run fixture byte-for-byte. Save their SHA-256 values before migration.
- Add `golden_idle_responsive_v2.json`, using the existing digest format v1,
  quantization 2048 and tolerance 2. Keep recording guards unchanged: missing
  data fails normal tests; toolkit CI and standard CI can never record it.
- Change only idle's `_check_golden` request and selector in
  `test_project/tests/test_animation_motion.gd`. Omit duration, samples, speed,
  style, overrides and loop mode so the ordinary three-second idle and normal
  density become the expectation. Keep the helper's explicit clip name and
  in-memory rig/player paths. Idle is stationary under either requested root
  policy; the fixture retains the established default in-place convention.
- Add `golden_idle_v2_provenance.json`: approval words/date/scope, ten delivered
  video hashes, reviewed animation SHA, fixture-generation SHA, engine/core
  commits, dummy FBX hash, exact invocation, digest contract and fixture hashes.
  Distinguish in-memory golden bindings from the reviewed saved-scene bindings;
  actual route/playback receipts establish saved binding and history behavior.
- Preserve the 64 focused motion tests, including optional anatomy/refusals,
  profiles/aliases/setup parity, deterministic controls, planted reach and
  public history. Do not lower thresholds or disable tests to get a green run.

## Execute and compare independently

1. Commit selector/provenance changes without the new expectation. A fresh
   normal public one-test run must fail because the expectation is missing,
   and create no file. Preserve the failure receipt as evidence of the guard.
2. Start a fresh visible Godot 4.7.2 editor on the isolated released-core project
   using its recorded APPDATA/8000/9500 profile. Explicit local recording uses
   `ANIMATION_TOOLKIT_RECORD_GOLDENS=1`, with CI flags cleared, for only
   `test_the_idle_matches_its_golden` through public MCP. Record this result as
   recording evidence, never as a comparison pass.
3. Quit normally and restart with recording cleared. Require fresh normal
   focused motion comparison, then all 14 headless suites and full editor
   discovery/registration/history gates. Expect 64/64 focused and 389/389 local
   editor with no skips or engine/route/discovery errors, including local X Bot.
   Verify approved walk/run digests and historical fixture hashes unchanged.
4. Commit/push source plus fixture and verify the remote SHA. Archive source,
   provenance, all local receipts and exact fixture bytes under
   `release_r2_idle_20261011/accepted-r001-regression`, preserving the delivered
   candidate archive. Confirm addon bytes still match approved source `8665980`.
5. Require complete Windows/Linux source CI against that tracked tree: pinned
   core v4.2.1 required jobs selected by name; core-main advisory results kept
   separate. All required jobs must pass. Preserve only the two named missing
   private-X-Bot skips, with local no-skip evidence. Each live route must retain
   its complete pass/fail markers; registration probes cover all ten families.
   Verify the tested synthetic merge tree matches source and record core SHAs.
6. Close idle only after explicit review plus independent green regression.
   Update roadmap, validation, review state and recovery notes; push and verify.
   Then plan start/stop together, including one-shot timing and continuation
   into the approved walk. Remaining R2-R5 and final candidate approval are
   still required before merge, tag or release.
