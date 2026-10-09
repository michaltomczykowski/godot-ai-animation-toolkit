# Repair closure and GitHub release plan

Proposed 2026-10-09 after the user accepted r004 and asked how to finish the
repairs, merge into main and publish a release. Work alone on Godot 4.7.2.
This adds release preparation to the earlier unreleased repair scope. The
publishing checkpoint follows a concrete reviewed candidate and completed gates.

## Verified repository state

- Toolkit remote main: `5e13a6c0099b1a0f9255d661f5c5ac17fc9c9082`.
- Repair checkpoint: `890f3a08304eedba08da08383f5b691362f7933a`, pushed on
  `repair/toolkit-quality`, 112 commits ahead of remote main at this checkpoint.
- One toolkit PR: [#1](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/pull/1),
  draft, mergeable. Its long description contains outdated milestone counts.
  The checkpoint's headless/editor checks pass; its two full MCP jobs were
  running when inspected. Exact animation source `68e06aa` already passes all
  34 Windows/Linux validation jobs.
- Latest toolkit release: v1.13.0 (2026-09-26). The addon still declares 1.13.0.
- Godot AI is a separate upstream repository. The local core is 4.1.0; CI
  pins v4.2.1 and also exercises upstream main. The released core v4.3.0 needs
  an explicit packaged-install check. No core PR must be merged to use the
  toolkit's public custom-tools API.
- The local toolkit `main` has an extra old demo commit compared with
  `origin/main`. Use the verified remote main as the release base; preserve
  that local commit in history and avoid pushing local main wholesale.

## R0 — record walk acceptance and choose its release profile

The user's exact feedback is: “yeah it's okay, what can we do next then to
wrap up the fixes and push it as release on GitHub? because we have prs open
and nothing pushed to the main”. Record acceptance of r004 and playback, while
keeping the reviewed profile/rig coverage explicit. An optional profile question
asks which comparison was reviewed. Grounded is the proposed natural default;
responsive remains optional once its own review is confirmed.

Preserve all earlier recipes, scenes, videos, source archives and feedback.
The accepted clips are override recipes; they are not yet the API defaults.

## R1 — make accepted motion reachable with normal Godot AI calls

1. Add one quality-profile resolver shared by dedicated motion operations,
   `cycle` aliases, start/stop and `character_setup`. Promote only the selected,
   reviewed coefficients. Preserve explicit duration, speed, distance, height,
   phase and per-call overrides. Define migration behavior for existing styles.
2. Make optional hand features capability-aware on rigs without validated
   fingers. Report which optional features were applied. Explicit requests for
   unavailable hand geometry must retain their typed refusal. Default promotion
   must not accidentally make previously supported basic rigs unusable.
3. Generate default calls through actual Godot AI, save/reopen and compare played
   output with the accepted recipe on all four reference rigs. Verify both
   aliases and setup outputs, Undo/Redo, dry run, contact thresholds and ownership.
4. Capture default playback for the manual checkpoint. Update goldens and
   operation evidence only after the promoted output matches accepted output.

**Exit:** A normal walk request generates the accepted profile without a long
override dictionary, with documented capabilities and unchanged explicit inputs.

## R2 — finish the remaining character and family visual gates

Preserve the operation order: run, idle, start, stop, turn, strafe, jump, then
character setup and idle/start/walk/stop sequence. Use baseline/candidate
continuous videos on dummy, X Bot, short and tall Z-up rigs, actual 30/60/120
FPS checks, and PC Explorer delivery. Pause for each operation's review. Review
left/right turns and strafes, in-place/forward jumps, and transition contact
phases. Keep the existing saved-history, active-tree and modifier-bake gates.

Record representative effect/playback from every other family: presets, FX/UI,
graphs, clip edits, rig poses/recipes, modifiers, library and inspector previews.
Use chaptered review videos with explicit per-operation evidence. File/read-only
operations need their actual effect contract rather than an invented animation
quality criterion. The diagnostic flykick demo is not a substitute for these
tool contracts.

**Exit:** Reviewed supported behavior for the release. Repair a failed contract
or hide its unsupported operation/variant with a typed unavailable reason.
Do not extend this closure to terrain, arbitrary rigs or new features.

## R3 — close the evidence ledger and agent integration

At planning time all 103 rows remain partial. Current annotations include 18
pending Undo/Redo checks, 14 pending dry runs, 13 pending playback checks, four
pending save/reopen checks, 29 pending track checks, and 49 pending/partial error
checks. Many later history/playback matrices already provide relevant evidence;
these counts measure missing annotations, not 103 demonstrated failures.

1. Reconcile each row with exact existing suite, matrix, source and CI receipts.
   Run targeted checks only for genuine missing coverage. Normalize pass,
   failure, pending and justified not-applicable statuses. The current exporter
   requires literal `pass` for every check on verified rows; repair its treatment
   of justified read/file/structural cases before claiming ledger completion.
2. Bind visual evidence to reviewed clips/variants. A technical bake preview or
   static contact sheet cannot grant authored character quality approval.
3. Add a release audit gate that fails for an advertised operation with a real
   missing or failed required contract. Read-only and file operations must keep
   accurate Undo semantics. Unsupported variants stay clearly unavailable.
4. Test fresh projects on Godot 4.7.2 with the documented minimum Godot AI core
   and released v4.3.0, including toolkit-suite selection, discovery of all ten
   families, eight promoted tools, actual invocations and core reload. Verify
   remaining real-project combinations in dedicated fixture scenes.
5. Complete representative agent tasks through Godot AI: create locomotion,
   compose an action, edit a clip, set up a modifier, and animate UI/FX. Record
   tool discovery, selected operation, errors/retries and saved result. No manual
   scene scripting should be required to compensate for missing tools.

**Exit:** Release-supported operations have complete, accurately scoped evidence;
the public tool-suite path works for real agent tasks and documented core versions.

## R4 — prepare and test the installable release candidate

Proposed version: **1.14.0**; finalize after reviewing compatibility/migration
changes. Align addon version, metadata, both READMEs, generated op docs,
compatibility table, limitations and changelog. Fix the stale nine-tool plugin
description to match ten families/eight promoted. Label historical demo media.

Build the addon-only ZIP from the committed candidate, including LICENSE.
Install that ZIP in a clean project with the public Godot AI addon; verify enable
order, public tool access, generation, save/reopen, playback, Undo/Redo and reload.
This check must use packaged files rather than development junctions. Ensure
tests, local rigs, review snapshots and private media are excluded. Record ZIP
contents, checksum, source commit and the tested compatibility combinations.

Update PR #1 with the final release scope and evidence, resolve review feedback,
and make it ready for review. Keep one canonical toolkit repair PR. Prepare
release notes locally with remaining supported limitations. Full exact-candidate
Windows/Linux headless, editor, registration and MCP jobs must pass.

**Exit:** A concrete installable candidate, current PR and release notes ready
for final review. Report the exact version/commit and completed/open gates.

## R5 — merge and publish from main

After final candidate review and publishing authorization:

1. Confirm PR head, latest remote main and green required checks; merge PR #1.
   Preserve the detailed repair history in the canonical branch/PR.
2. Wait for main's CI and verify the merged source is the tested candidate.
3. Tag the verified main commit with the version matching `plugin.cfg`.
4. Let the existing tag workflow run its version, headless, editor and MCP gates
   and create the GitHub release with the addon ZIP. Verify the published tag,
   source commit, release notes, asset contents and checksum. The workflow
   currently auto-publishes a normal release after successful tag CI; use a
   prerelease flag/workflow change if the user chooses a preview instead.

The previous exclusion of public media uploads stays in effect. Publishing the
addon ZIP and release notes does not authorize uploading local X Bot assets or
private review videos.

## Recommended next implementation phase

Start **R1: approved walk defaults/profile integration**. Finish the focused
plan before source edits, preserve the r004 references, and avoid reopening
completed history matrices without a concrete regression. Then follow R2–R5.
If an earlier release is desired, choose an explicitly scoped prerelease rather
than declaring the full repair roadmap complete.
