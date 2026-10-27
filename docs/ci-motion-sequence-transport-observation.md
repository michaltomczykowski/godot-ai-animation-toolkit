# Windows4.2.1 history timeout: bounded diagnostics

The preserved CI38973858932/head29d3147 Windows clean-ZIP core-first run reaches
all13 matrix completion markers and the dispatcher `run_tests -> ok` marker,
but the Python caller remains in suite_start until the unchanged420s gate.
Original artifacts remain under the private release root `ci-29d3147`.
Earlier CI38972644006/head1a9a5f7 Windows core-first reports history duration
79998ms and completes the whole gate in263.412366s. This is comparison evidence,
not proof that the failed run spent80s in the suite.

## What is known and unknown

Released core4.2.1 `dispatcher.gd` logs `[send]` immediately before returning its
result to `connection.gd`; the latter subsequently serializes and invokes
WebSocket `send_text`. Therefore that log establishes handler completion, not
successful socket delivery, backend future completion, HTTP response or attach
stdio delivery. The serviced test runner supplies per-test duration only in
its result; those durations are absent for the failed RPC. No backend log was
included by the clean-ZIP artifact glob, so transport warnings are unavailable.
No definite production fault or slow-test cause is identified. Nothing here
raises timeouts, retries writes, reduces coverage or qualifies the failed run.

Primary source inspected locally at the exact released v4.2.1 checkout:
`plugin/addons/godot_ai/dispatcher.gd:326`, `connection.gd:1171`,
`testing/test_runner.gd:165`, and `src/godot_ai/transport/websocket.py:565`.
The receive loop validates frames, claims request ownership and resolves the
pending future; it logs malformed/unowned frames and session closure. Those
warnings must be preserved before diagnosing a dropped response.

## Added bounded observation

Toolkit history suite logs each test start, end duration/assertion-failure flag
and suite epilogue count/duration, without modifying test bodies/coverage.
These markers are diagnostic: runner post-test cleanup can still fail later.
The existing awaited test_run call is wrapped once; a30s background observer
records bounded coroutine file/function/line chains (no frame locals), request
start and response-return/error/cancellation events. It sends no extra RPC,
sets no timeout and never substitutes a result. Successful result byte count
and SHA256 identify the payload observed by the caller. Original error and
cancellation propagate. The ordinary420s enclosing deadline remains exact.

CI backend logs now have distinct per-editor filenames instead of the shared
mcp-backend.log; clean-ZIP artifacts include them. Attach stderr remains in the
existing complete timeout stderr, and observer JSONL sits inside the existing
gate-diagnostics artifact directory. Backend logs can include local session
identifiers; preserve as CI diagnostic artifacts, not release quality claims.

## Exact next reproduction

Run the same Windows4.2.1 clean-ZIP matrix at the new exact source, preserving
its fresh project/session and both enable orders. Do not rerun a completed
mutation in an existing project. Keep all ordinary suite/native/direct/reload
checks and420s gate. On failure correlate per-test and suite epilogue times,
last observer await chain, complete backend warnings, editor log and caller
stdout/stderr. If handler completed but observer stays in transport, inspect
actual backend response/session evidence before any transport repair. If suite
never ends, use its named final test/duration instead. Success proves the new
run only; it does not erase the prior timeout or establish its root cause.

Offline observer3tests pass (identical response/one invocation, original error,
cancellation, heartbeat preservation and watcher teardown). Python compilation
passes. GDScript parsing/live CI remain pending root scheduling. No Godot,
editor, native or GPU process was launched for this diagnostic change.
