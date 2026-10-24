# CI 38769129375: actual coverage and timeout diagnosis

Run38769129375 (`pull_request`, API head5466b7c5cf729f1380f562820760d92d30a55f73)
has one failed job:116540134075, clean ZIP / Ubuntu / core4.3.0 / core-first.
All four live MCP jobs succeeded. This is not a collector failure.

## Exact actual source and coverage

The four downloaded `operation-evidence/operation-case-results.json` files each
record actual tested checkout64f8c0780f7f07779d46a386a8d872f0c07ebadd, the GitHub PR
merge checkout. Do not relabel these receipts with branch head5466b7c5. Their
context dependency identities and actual source remain intact. Main/tag release
qualification must bind the actual final checkout; changing the display label or
regenerating an inventory cannot change what ran.

Each cell (Windows/Linux × released4.2.1/4.3.0) has1093 actual call cases and102
successful public operation keys. The sole missing success is
`animation_inspect.preview`, whose headless rendering refusal remains explicit.
No extra narrow public call is needed for the other102 keys based on this run.
This invocation coverage does not close semantic/history/native/visual checks.

Downloaded artifact identities:

| Artifact | GitHub artifact ID |
| --- | --- |
| mcp-editor-windows-latest-4.2.1 |11992351797 |
| mcp-editor-windows-latest-4.3.0 |11992077018 |
| mcp-editor-ubuntu-latest-4.2.1 |11991975670 |
| mcp-editor-ubuntu-latest-4.3.0 |11991970676 |
| clean-install-ubuntu-latest-4.3.0 |11990704100 |

Private local downloaded copies remain under ignored `dist/ci5466/`.

## Failure evidence and limit

The clean core-first route passed prior family gates through sequence playback.
Its420second outer `mcp_motion_sequence_history.py` subprocess then timed out.
The editor log shows all13 motion/secondary/sequence matrix groups completed and
`run_tests -> ok`. It does not expose which subsequent native/direct/reload
substage was still running. The child prints no phase progress before its final
summary in the failed version, so it is not honest to declare a specific
substage hung or merely needed more time.

The same run's successful public raw traces give approximately144.16s Linux4.2,
139.91s Linux4.3,210.50s Windows4.2 and229.66s Windows4.3 from the last sequence
call to the first direct history call (three inner suites plus native batch and
small setup overhead). These are observations, not a replacement timeout rule.

Repeated headless `texture_2d_get` null-texture errors occur while the core editor
creates scene thumbnails. They are visible and retained in editor logs. They
are not an assertion failure report from the native history checker, nor proof
of the timeout's cause.

## Diagnostic repair, thresholds unchanged

The driver now flushes stage events for connection, each suite, native batch,
each exact direct case before/after reload, reconnect and completion. An atomic
`.progress.json` retains full returned suite/native payloads and ordered phase
history. Each CI invocation uses a unique attempt path under `gate-diagnostics`.
The existing240second native and420second outer limits remain unchanged.

On either timeout, `gate_diagnostics.bounded_run` preserves complete original
partial stdout/stderr bytes, SHA256s, command, timeout and current phase snapshot
in exclusive-create files. It returns status124; normal gate validation still
fails. The compact timeout/last-stage summary is appended last so existing
failure tails retain it. No timeout or partial suite is converted to a pass.

Existing `operation-evidence/**` uploads include live-route diagnostics. The
clean ZIP artifact upload should additionally preserve
`clean-install-evidence/gate-diagnostics/**`. Existing combined route logs also
retain the compact last-phase summary when a timeout occurs.

Three pure tests cover exact timeout bytes, phase retention, unchanged limits,
exclusive failed-attempt preservation, actual nonzero statuses and no inferred
suite pass. No editor, MCP or rendering process was launched for this repair.
