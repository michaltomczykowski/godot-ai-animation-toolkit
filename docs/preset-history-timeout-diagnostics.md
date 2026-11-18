# Preset/library history timeout diagnostics

The preset/library route keeps its original 120-second outer gate and all
existing suite, assertion and saved-runtime checks. There are no retries or
partial-success paths.

The child fsyncs a progress snapshot before session activation, scene navigation,
each public suite call, transport exit and each saved native layout. A returned
suite payload is persisted before the next await, so a subsequent timeout does
not discard actual results already received. Elapsed phase events distinguish
a long editor suite from a blocked reply, second call, transport exit or native
subprocess.

The existing bounded subprocess wrapper preserves complete partial stdout,
stderr, their hashes and the last durable phase when the 120-second gate expires.
Files named `*-preset-library-history*` are uploaded with route/install evidence.
Timeout remains a nonzero failure. Diagnostics do not qualify any operation.

The observed Linux core-4.2.1 failure completed all five preset matrix markers
and logged the first `run_tests -> ok`, without a following `library_contracts`
request. Untimestamped editor output cannot establish whether that reply arrived
before the outer deadline. Fresh diagnostics are required before selecting a
behavioral repair; this observation does not justify increasing the gate.
