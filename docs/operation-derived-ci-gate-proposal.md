# Strict derived-check CI gate proposal

Separate from the motion/sequence oracle corrections. The existing CI runner writes derived operation-case-results but returns its green raw-public/native status without checking explicit failed derived checks. CLI collection similarly checks only missing successful operations/core identity.

Apply the minimal two-file integration patch plus the new pure helper. Preserve the full result artifact before failing. Any explicit fail on a check other than mcp_invocation returns nonzero in actual CI case collection, even when all external public totals pass. Exact mcp_invocation failures remain expected negative/refusal observations and are not counted. Empty dry checks and pending/missing checks are not reclassified as success or failure by this narrow gate. Malformed cases/check records refuse processing.

The patch adds no retries, timeouts, coverage reductions or workflow changes. CLI --allow-partial continues to permit incomplete invocation coverage; it does not waive explicit semantic failures. This is integration-ready source/patch only, not an actual CI qualification. Root must integrate and run after reviewing all remaining real derived failures (four historical FX effect cells remain outside this worker's adapter scope).

Offline four helper tests cover intentional invocation refusals, six independent derived failure categories despite green public/core metadata, pending applicability and malformed records. The old actual Linux report must yield805 failed non-invocation checks; the historical motion-adapter recollection yields four residual FX failures, so both correctly remain non-green under this proposal.
