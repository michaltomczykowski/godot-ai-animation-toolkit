# Run fixture epochs

`golden_run.json` preserves the pre-v2 baseline byte-for-byte. The approved run
will use `golden_run_responsive_v2.json`, with digest format version 1,
quantization 2048 and tolerance 2. The new fixture is not yet recorded in this
selector checkpoint: normal tests must fail its absence without creating it.

The fixture request uses the real run handler and bundled dummy. Style,
duration, speed, sampling and overrides are omitted; the rig-relative cadence
and normal 60/s sampling are part of the expectation. Explicit animation name
and linear loop retain the established in-place fixture convention. The helper's
in-memory FBX player path differs from saved review scenes; the shared recipe is
reviewed, while the separate native matrix validates playback bindings.

Approval: 2026-10-10, “they look okay,” in direct response to the presented
five-style/four-rig run set from animation source `97f17ce`. Individual watched
filenames were not enumerated. Exact source, media hashes and provenance are in
`golden_run_v2_provenance.json` and the review state. This feedback does not
approve other motions or the final release.

Local recording requires `ANIMATION_TOOLKIT_RECORD_GOLDENS=1`. Normal runs and
CI cannot create missing expectations; both toolkit and standard CI flags reject
recording. After one deliberate recording, restart without the flag and compare
normally, then require the complete local and Windows/Linux regression gates.
The recorded fixture is not itself comparison evidence.
