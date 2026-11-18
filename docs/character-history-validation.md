# Character setup history and audit isolation

Godot 4.7.2; unreleased `repair/toolkit-quality` branch.

## Scope and repairs

`animation_motion.character_setup` is one transaction across a clip library,
a graph and mixer root-motion settings. The transaction stops an attached
tree before clip changes, configures attached inactive trees, restores existing
graphs before their active state, and removes new trees without detached
path setters. Dry/rejected calls free temporary trees. `root_motion=false`
clears extraction paths left by a prior rooted graph.

The shared clip commit now distinguishes instance resource ownership from
Editable Children. Already-editable instances still receive a local library
copy; source and peer instances retain their original clips. Undo restores
library and graph resource identities as well as permission flags.

`motion_audit` copies live nodes with scripts and scene reinstantiation
excluded, then gives its target player a separate library copy. This retains
unsaved nodes/clips and prevents script constructors from running in the
read-only sandbox. Reference: [Godot Node duplication flags](https://docs.godotengine.org/en/4.7/classes/class_node.html#enum-node-duplicateflags).

## Required gates

- Seven named Godot AI dispatcher history cases: new, replacement, missing
  library, instanced replacement, instanced new tree, already-editable instance,
  and explicit in-place replacement. Each checks dry/rejected state, orphan
  count, one scene action, no global action, exact Undo/Redo, saved undone and
  redone state, and zero captured engine errors. Instances include source and
  peer controls; existing resources must retain their identity after Undo.
- Played motion audits run through Godot AI with engine-error capture.
  Existing source pose/playback and 30/60/120 FPS contact assertions remain.
  A separate copy test checks unsaved child isolation and no script constructor.
- External MCP requires all seven history tests and the named audit tests.
  Optional saved playback launches 21 fresh processes: seven redone scenes at
  30/60/120 FPS. The tree must pose the thigh, extract travel only when rooted,
  leave its character root position unchanged, and keep its player stopped.
- Retain graph and FX route/history gates; verify core reload and Windows/Linux
  CI. These checks do not approve character visual quality.

## Evidence

Initial failures are retained in `character_history_before_20261005.log`.
They reproduced dry-run orphan trees and the stale root-motion path. The
first test harness also expected Dummy travel, but this fixture's nested
character root owns translation; the expected path is `.:position`.
Local full-suite results reached 249/249 after the added instance case.
Final MCP, reload and platform outcomes are recorded in `FIX_ROADMAP.md`.
Other suites still emit engine errors; zero-error claims apply to the captured
setup and audit calls only.

The following [clip edit phase](edit-history-validation.md) repaired those
test-generated errors and explicit spring collision wiring, and added a
whole-suite engine-error gate. Its local full suite passes 257/257 with zero
captured errors; the earlier scoped results above remain historical evidence.

Final external MCP passed 7/7 history tests, 27/27 inspector tests and all
21 saved runtime cases. Core reload preserved ten toolkit families and both
suites passed again. Visible Ctrl+Z restored original clips and removed the
setup tree; Ctrl+Shift+Z restored identical generated clips and graph.

Windows/Linux [Actions run 37353723524](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/37353723524)
passed code commit `8154101`: all headless suites, four editor/core combinations
and both full live MCP routes. The phase log and recovery folder retain logs.
