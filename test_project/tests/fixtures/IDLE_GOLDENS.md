# Reviewed idle expectation

`golden_idle_responsive_v2.json` records the ordinary Responsive idle approved
in revision `idle-review-r002` (animation source `9188ffa`). The public test
runner builds it with only the operation, clip name and resolved in-memory
rig/player paths. Style, duration, density, overrides, loop mode and root policy
are omitted: the three-second default and its normal sampling are part of
the expectation. The 36 tracks contain 179 or 181 keys; these counts are part of the
committed expectation.

Digest format v1 retains quantization 2048 and tolerance 2. The legacy
`golden_idle.json`, every historical fixture and the approved walk/run fixtures
remain unchanged. Normal tests and CI refuse missing expectations; deliberate
local recording is separate from a fresh comparison with recording disabled.

`golden_idle_v2_provenance.json` records the user's approval, ten delivered
video hashes, exact sources, fixture/asset hashes, invocation and regression
receipts. The golden's in-memory bindings differ from the saved review scenes;
independent public custom-tools/history and native Player/Tree receipts cover
those bindings and playback. This fixture protects reviewed output; it does
not replace continuous visual review or contact measurement.
