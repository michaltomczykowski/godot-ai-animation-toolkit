# Graph history and playback ownership

Godot 4.7.2; unreleased `repair/toolkit-quality` branch.

## Repairs

The shared graph commit now configures trees while inactive and attached.
Undo of an existing tree restores its graph, player path and parameter values
before restoring its active flag. Undo of a newly created tree stops and
removes it; it does not run path-dependent setters on a detached tree.
Redo attaches the tree before configuring it.

Instanced graph children and new trees under instances need Editable Children
to preserve overrides/additions when saving. That permission is now part of
the same scene undo action and is restored on Undo. Graph replacement retains
the original resource identity and leaves a second source instance unchanged.

`wire` rejects unknown graph parameter paths, missing values, wrong types,
nonfinite values, fractional integers and invalid enum choices. JSON vector
values are converted to engine vectors. Boolean conditions require booleans.
Activating a tree without a graph root returns a typed error; `wire` with
`active=false` still creates its documented structural connection.

Dry runs and rejected builders free any detached tree allocated during
context resolution. They leave the scene, history and orphan-node count
unchanged.

## Regression gates

`test_graph_route_history.gd` invokes all eight advertised graph operations
through the Godot AI dispatcher. The seven writes have new/replaced graphs
and new/replaced graphs under an instance, with a peer isolation control.
Every case checks dry run, rejected input, one exact scene history action,
no global action, Undo/Redo, and save/reopen of undone and redone states.
The suite captures engine errors with a temporary Logger and fails on them.
Additional cases cover read-only `graph_get` and typed parameter writes.

`tools/mcp_graph_history.py` requires all eight named tests through external
MCP `test_run`. Its optional runtime gate starts a fresh Godot process for
each of the 28 saved redone results. Walk, jump and lean must play through
the AnimationTree while its AnimationPlayer stays stopped. `wire` is checked
for its structural connection. The existing eleven topology scenarios and
ten saved playback checks remain in CI, as do the complete FX history gates.

## Evidence

The initial regression failed on the detached-node Undo error and lost
instanced overrides. Those failures are retained in
`F:/GODOTAITESTING/graph_history_before_20261005.log`.

After the fixes, the local full editor suite passed 241/241 tests. The
restarted visible editor passed all eight external MCP tests and all 28 saved
runtime cases (`mcp_graph_complete_20261005.log`). A harness dependency bug
was corrected by giving every instanced case a unique source filename; its
failure log is retained. Core-reload and Windows/Linux results are recorded
in `FIX_ROADMAP.md`.

Core-plugin reload retained all ten tool families and the graph matrix passed
again. Visible editor Ctrl+Z removed the toolkit-created state machine;
Ctrl+Shift+Z restored an identical graph and resolved player connection.

Graph visual quality remains open. Motion character_setup Undo still logs
detached-tree errors, and inspection-suite duplication errors remain separate
roadmap work; passing assertions are not an error-free claim for the toolkit.

Windows/Linux Actions [run 37296846889](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/37296846889)
passed code commit `692177f`: headless suites, four editor/core combinations,
and both full live MCP routes, including the graph history and runtime gate.
