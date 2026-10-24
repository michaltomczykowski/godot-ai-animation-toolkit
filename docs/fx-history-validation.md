# FX scene history validation

Godot 4.7.2; unreleased `repair/toolkit-quality` branch. The target is the
16 operations advertised by `animation_fx`, invoked through Godot AI.

## Implemented matrix

`test_project/tests/test_fx_route_history.gd` obtains the live custom-tool
dispatcher and the edited scene's exact UndoRedo history. It does not fall
back to the global history. A registry comparison fails when an advertised
FX operation has no case.

Every operation runs in four configurations: a new clip/resource, replacement
of an existing clip/resource, an absent default animation library, and a
child of an instanced scene with a second instance as an isolation control.
The replacement SpriteFrames baseline has a prior named, paused animation;
the existing `animation_fx` suite additionally covers playing replacement,
frame/progress restoration and custom playing speed.

Each case checks dry run, rejected input, an observable write, exactly one
scene action, no global-history action, Undo, Redo, original library identity,
and save/reopen of both undone and redone states. Instance cases also check
peer isolation and restoration of Editable Children on Undo. Wave covers a
three-target clip; wipe transition covers the clip and pivot change together;
counter, flipbook and audio cover their respective track types.

`tools/mcp_fx_history.py` invokes this suite using the external MCP `test_run`
route and requires all five named tests, zero failures and nonzero assertion
counts. With `--godot`, it plays all 64 saved redone scenes in separate Godot
processes. The Windows/Linux live-route CI invokes this gate after core reload.

## Defects repaired

- SpriteFrames overrides on instanced children were lost on save. The handler
  now enables Editable Children in the same undo action, restoring the prior
  permission on Undo.
- Restoring a null SpriteFrames resource then assigning its old `default`
  animation name raised an engine error. Undo selects the prior name against
  a temporary valid resource, then removes that resource. The raw selection
  string and null assignment are now restored exactly without that error.

## Evidence and remaining checks

The Windows editor run passed 233 tests, including the five new matrix tests;
the restarted visible editor also passed the new suite through external MCP.
Logs are retained under `F:/GODOTAITESTING/` with the `fx_history` prefix.

Visible Windows shortcut checks created unsaved results through MCP: wave
Undo removed its three-track clip and Redo restored it; wipe Undo removed the
clip and restored pivot `(0, 0)`, while Redo restored pivot `(640, 180)`;
SpriteFrames Undo removed the resource and Redo restored the same assignment
and requested animation. Logs use the `fx_ui_` prefix. These check editor
history, not visual quality.

The initial matrix exposed engine selection errors on Undo and reloading the
saved null-resource baseline. The follow-up restoration fix removes these
errors, and the matrix compares raw selection names even with null frames.
The full editor run still reports pre-existing graph/inspection engine errors
despite passing assertions; those belong to the remaining roadmap work.

All 64 saved redone scenes passed fresh-process playback locally, with no
reported playback failures (`mcp_fx_history_playback_20261004.log`).

After a real core reload, the live MCP matrix again passed all five tests.
Visible scene-switch isolation also passed: Undo in the transition scene left
the wave clip intact, Undo in the wave scene left the transition's undone
state intact, and Redo in the transition scene left the wave undone.

Actions run `37228583599` on commit `bfddd46` passed all Windows/Linux
headless, editor and live MCP jobs, including 64 saved redone playback cases
per platform. Windows live MCP passed on rerun: its initial attempt failed
before any toolkit test because the core could not capture the backend
process identity. The preceding checkpoint also passed in run `37228150013`.

The functional history/persistence gate is complete. Final FX visual approval
remains open; no operation is promoted to fully verified by this phase.
