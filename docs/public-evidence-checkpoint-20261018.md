# Public evidence checkpoint, 18 October

Actual sourcec5c2483, Godot4.7.2.ed1daf0bf, released core4.2.1, Windows.
Private root: `E:/GodotAI-toolkit-release-2.0.0/20261014/setup/production-r006`.

Fresh visible editor invokes graph_route_history and rig_modifier_history through
the public Godot AI test_run API:8graph tests and15modifier tests pass,0skips.
After the editor exits, the unchanged native modifier/reference gate passes
828saved states,276native states and108ordered stack states, with no failures
or engine errors. No native process overlaps the live editor.

Strict collection yields137inner rows:28graph rows and109modifier history/refusal
rows. One modifier adapter row fails despite the native engine gate passing:
local_twist_setup_reference serializes its Quaternion as `(0, 0, 0, 1)`, while
the new adapter only recognizes three-component Vector3 tuples. The actual
saved and independently configured native values are identical. The converter
now preserves the engine checker's approximate Vector3 comparison and exact
Quaternion comparison; different Quaternion components/signs still fail.
This repairs evidence conversion, not the modifier or its .001physical limits.

Eight actual inspection reads complete. Seven pass the new exact predicates;
dry_run's unknown-family refusal returns VALUE_OUT_OF_RANGE, as its source
explicitly specifies. The auditor incorrectly expected INVALID_PARAMS and
halts the queue before setup generation. Its exact code map is corrected, with
a regression rejecting the former wrong expectation. It is not widened to an
arbitrary set of uppercase errors. All original raw/failed receipts are retained.

The original operation-cases.json SHA256 is
`2eeaffe0b4d9d87fcc39c85e79da0d6a4e6fff70ed81d871d58585a590ad26d3`.
Its failed rows are not rewritten as passes.47mixed offline controls pass after
the two converter fixes. Fresh CI/public verification at the corrected source
remains required. Actual native results retain their c5c2483 source identity.

The precedingr005 attempt never enters these suites: it waits for main while
Godot restores the last old test scene. The private editor layout had270open
scenes. Its exact bytes/hash are backed up in
setup/validation-editor-state-recovery-r006.json; only the disposable tab list
is reset to main. Explicit public scene_open now precedes stable readiness.
Saved scenes/models are unchanged. Intentionally mutated native control copies
are excluded from editor UID indexing by a local .gdignore; they remain on disk.

Next: corrected eight inspection reads and the broader30group public setup
matrix, with15completedr004rows reused only after exact request/dependency/scene
checks. The already executed graph/modifier engine gates remain separate scoped
evidence; final CI reexecutes them at the eventual candidate. No release yet.
