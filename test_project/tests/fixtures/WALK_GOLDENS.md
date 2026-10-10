# Walk fixture epochs

`golden_walk.json` and `golden_spec_walk.json` preserve the pre-v2 baseline.
They are historical evidence, not the expected output of new Responsive defaults.
Run now has separate approved v2 provenance in `RUN_GOLDENS.md`; its historical
fixture is preserved too. Idle still uses its original fixture until review.

The approved r005 walk is guarded by:

- `golden_walk_responsive_v2.json`: real handler, bundled dummy, one-second
  linear loop, ordinary default style/sampling; 38 tracks with 61 keys each.
- `golden_spec_walk_responsive_v2.json`: independent synthetic 0.85 m leg,
  raw spec arithmetic at 12/s; ten tracks with 13 keys each.
- `golden_walk_v2_provenance.json`: source/approval, parameters, fixture shapes
  and hashes. Digest format version remains 1; v2 names describe the output epoch.

Quantization stays 2048 and tolerance stays 2. A missing fixture fails a normal
or CI run. Local recording requires `ANIMATION_TOOLKIT_RECORD_GOLDENS=1`; CI
always refuses recording, through either `ANIMATION_TOOLKIT_CI=1` or standard
`CI=true/1` (including pure headless jobs). Generate a new versioned path after review,
then restart without the flag and compare against it. Do not overwrite historical
files or regenerate goldens to suppress an unexplained failure.

Approval: 2026-10-10, “they look very good,” against the delivered five-style/
four-rig r005 videos from animation source `056cc8d`. Fixtures are regression
checks; human review and played contact checks remain separate evidence.
