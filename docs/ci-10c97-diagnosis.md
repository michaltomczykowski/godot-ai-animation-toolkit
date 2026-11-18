# Actual CI 38814930955 evidence and failures

Read-only inspection on 2026-10-16. Run branch head was
`10c97dab9ac159e62f2d748cc55062fd2f6052dc`; every downloaded operation context
identifies actual tested PR merge checkout
`46594f6ebe9e87740018042e6542c7c6915d9a30`. These identities are not interchangeable.

All four public MCP cells, four clean ZIP cells, six editor cells and pure suites
passed. No history timeout occurred in this run. Only Linux rendered-preview
jobs 116697096849 (core4.2.1) and 116697096895 (core4.3.0) failed.

Both complete preview editor logs report actual startup errors:
`Required Vulkan instance extension VK_KHR_surface not found`, followed by
`initialize` returning `err != OK`. OpenGL llvmpipe startup precedes them.
The strict complete-log check correctly rejects both attempts; do not exempt
these errors. Core4.2.1 produced four PNGs and checkpoint snapshots, but they
are not qualified. Core4.3.0 additionally changed from the requested copied
fixture back to `main.tscn` before its first walk request, which failed with
`Node not found ... scene root 'Main'`. This is a real scene-readiness race.
The release worker owns explicit OpenGL startup and readiness-barrier repairs.

Downloaded artifacts remain under ignored `dist/ci10c` in the audit worktree.
Public source artifacts are available from the Actions run. The portable
[coverage summary](ci-10c97-operation-coverage.json) records exact report hashes,
context hashes, operation-specific passing case IDs and missing required checks.
It is an observation summary, not a release qualification receipt.

Each of four reports contains1171 case records,102 successful advertised public
operation keys and only `animation_inspect.preview` missing. Actual derived
passing coverage is71 playback keys and15 FX track/path/type keys. No dry-run,
save/reopen or history result is present: the later snapshot instrumentation
was not part of this tested source. Invocation-only coverage cannot close those
checks, nor semantics, general source invariance, typed errors or visual review.

The collector itself had four false negative graph cases per cell. Raw native
subprocesses exited0 without errors and emitted the exact source checker's
successful branch markers: wired `condition_walk_x`, locomotion state-machine
`walk_x` plus `run_x`, OneShot `jump_y`, and additive `lean`. The adapter previously
accepted only the ordinary `walk_x` marker. Its repair now parses each exact
branch and preserves the native thresholds20/70/-20/0.05 and player-idle check.
Pure corruption controls reject wrong markers, below-threshold values and
engine errors. Existing downloaded reports retain their original failures;
they are not rewritten as new candidate passes.
