# Repair closure and v2.0.0 release

Approved for implementation on 2026-10-10. Work alone on
`repair/toolkit-quality`, using Godot 4.7.2 and Godot AI's public custom-tools
API. This replaces the 2026-10-09 proposal. The release request expands the
original unreleased scope; private review footage and X Bot assets stay local.

## Locked decisions and checkpoints

- Complete the full repair closure before publishing stable **2.0.0**.
- Require Godot AI **4.2.1 or newer**. Test released v4.2.1 and v4.3.0
  explicitly; core main is advisory. Older cores receive a dependency diagnostic.
- **Responsive** is the default. Grounded is optional. Retune relaxed, heavy
  and sneaky on Responsive. Existing clips remain intact; regeneration changes
  are documented as a major-version migration.
- Level surfaces, four rigs, no new families. Work alone.
- Pause for continuous-video feedback after each operation and final candidate
  review. Silence, plain continue, crashes and usage resets are not approval.
- Record changes, source commit, tests, failures, feedback and next action in
  FIX_ROADMAP.md and review state. Commit/push checkpoints, verify remote SHAs,
  and refresh the persistent recovery archive.

Starting source: `1185f38bb446381c4f6266cd729335ca605c10b5`, already pushed.
Canonical draft toolkit [PR #1](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/pull/1).
r004 was accepted, but its recipe remains opt-in. All 103 audit rows are
partial; reconcile annotations with completed history/bake receipts. Local main
has an unrelated extra commit: do not push it wholesale.

## R1 — ordinary calls generate the accepted walk

One resolver serves dedicated motions, cycle aliases, transitions and setup.
Style choices: default, responsive, grounded, relaxed, heavy, sneaky. Omitted
or default resolves to Responsive; named variants decorate its motion-specific
table. The profile parameter continues to mean rig mapping.

Precedence: per-motion defaults -> style -> overrides -> canonical top-level
controls -> existing friendly aliases. Apply only consumed fields. Preserve
explicit timing, speed, distance, height, phase and operation-specific root
contracts. Use exact r004 walk JSON coefficients; tune other motions separately
in R2 instead of copying walk settings into them.

Resolve configuration before rig context/arm axes. Implicit upper-body and hand
features require validated geometry; omit/report unavailable optional features.
Explicit unsupported requests retain typed errors before writes. Invalid
essential roles/rest transforms and ambiguous bindings remain errors. Never
inject defaults into caller overrides: rig scaling must preserve provenance.

Return requested style, resolved_style, applied_features and omitted_features
(with reasons), including individual setup clips. Keep deterministic periodic
seeded variation and one translation owner. Default sampling is 60/s; retain
explicit requests, safety increases and the 1200-interval budget. Report actual
effective sampling, including denser transition/turn generation.

Through actual Godot AI: dry/write/undo/redo/save/reopen; compare played Responsive
defaults with the exact r004 explicit recipe on all four rigs. Check alias/setup
parity, in-place/extracted playback, precedence, optional anatomy and Z-up axes.
Record default, Grounded and all three retuned variants; pause before approving
promotion. No approved golden/ledger replacement before this review gate.

## R2 — character and other-family review

Order: walk/styles, run, idle, start, stop, left/right and two-step 180-degree
turn, both strafes, stationary/forward jump, then setup and idle/start/walk/stop
sequence. Each motion covers Responsive, Grounded and retuned styles on dummy,
local X Bot, short and tall Z-up rigs. Check both walking contact phases.

Native saved playback at actual 30/60/120 FPS: stance slide <= min(2% leg length,
3 cm), penetration <= 1% leg length, no knee flips/nonfinite output/default reach
clamps, correct contact timing and single-owner root travel. Keep stricter
existing seam/root tolerances. One-shots require continuity/recovery, not false
loop closure. Ankle-plane/hip-support diagnostics do not prove sole collision/COM.

Generate through MCP, save/reopen, validate; capture matched clean/diagnostic
front/side 1080p60 MP4s. Loops show >=6 continuous seconds/view; one-shots play
anticipation/action/recovery twice. Archive source, parameters, scenes, hashes
and receipts; commit/push; open PC Explorer with videos selected; **stop for
explicit feedback**. Contact sheets supplement videos. Changes to approved
output invalidate its approval.

Review recorded effects from presets, UI/FX, graphs, edits, rig operations,
modifiers, library and inspection. Every animation-producing operation needs
effect footage; file/read-only operations receive appropriate effect evidence.
Finish a public-route sequence with clips/saved poses, blends/contact markers
and one character-owned player. Existing flykick is optional evidence after
toolkit validation, not a separate demo-rebuilding phase.

## R3 — truthful availability, audit and integration

Retain all 103 inventory rows, including unavailable entries. Reconcile exact
existing matrix/source/CI receipts first; target real gaps. Registry status
controls schema/docs/dispatch: supported choices advertised; stale unsupported
calls return OPERATION_UNAVAILABLE plus reason before writes. Missing annotations
alone do not justify hiding a working operation.

Migrate checks to pass/fail/pending/not_applicable with evidence and required N/A
reasons. Verification requires applicable passes, both platforms and required
visual approval. Keep accurate scene-undo/file-write semantics. Blocking release
audit rejects incomplete/stale rows, unsupported advertising, unjustified N/A
and unreviewed required output. New tooling uses required job names, not a
hard-coded 34; preserve historical source receipts.

Blocking editor/full MCP/packaged-install matrix: Godot 4.7.2, Windows/Linux,
core v4.2.1/v4.3.0 recorded commits. Core main remains advisory. Test registration,
toolkit-suite selection, ten families/eight promoted tools, custom_manage,
enable order, disable/re-enable, stale calls and reload. Missing families fail
even when direct handlers pass. Retain typed batch registration and compatible
single-registration fallback. Leave user core checkouts intact. Complete actual
agent tasks for locomotion, sequencing, editing, modifiers and UI/FX; record
discovery, calls, errors and saved results.

## R4 — installable candidate and final review

Bump 2.0.0; align metadata, READMEs, references, compatibility, limitations,
migration and curated notes. Correct family counts/unsupported claims. Build
addon-only ZIP from a committed candidate with LICENSE, excluding tests/models,
recovery and private footage. Install ZIP files into clean projects without
junctions; verify discovery, creation, save/reopen, playback, Undo/Redo and reload
across the supported matrix. Verify rendered previews in a visible editor and
typed refusal where rendering is absent.

Exact candidate passes full headless/editor/registration/MCP/history/audit/package
gates. Unexpected engine errors fail; known core exceptions are narrow/documented.
Update PR #1, resolve feedback and mark ready. Present exact commit, checksum,
audit, compatibility and limitations. **Pause for final candidate approval.**

## R5 — merge, tag and verify publication

After approval recheck head/base/checks, merge PR #1 with a merge commit preserving
history, compare merged addon contents with tested candidate, wait for required
main CI. Tag that verified commit v2.0.0. Tag workflow requires audit/package
gates before publishing ZIP/checksum/curated notes. Verify tag/source/version and
asset contents. ZIP bytes may differ after merge; compare entry contents and
publish the main ZIP's own checksum.

Changed source needs a new validated candidate. Never move published tags;
later fixes use a new patch version. Completion: every advertised operation has
applicable evidence/approval, clean installs pass, PR merged and 2.0.0 published.

## Execution state

- R0: locked decisions pushed as `917ec02`.
- R1: animation source `056cc8d` pushed; configuration/context, optional anatomy,
  sampling/loop defaults and public-route parity are implemented. Twenty normal
  style clips plus eight matched clips, 60 contact runs, 24 r004 playback parity
  runs and 40 before/after reload dry calls pass. All ten continuous comparison
  videos are decoded/hashed/archived under recovery's `release_r1_20261010`.
  The user approved the presented set (“they look very good”). Separate v2
  goldens preserve historical fixtures; normal/CI recording is refused. Fresh
  local public motion 59/59, full editor 384/384 in 32 suites and headless 14/14
  pass; both ten-family/103-operation reload probes pass. See the validation
  note and review JSON. Final source `8f7b6e7` passes Windows/Linux Actions
  `38057817851`; R1 is complete.
- R2: distinct ordinary run profiles are pushed as `97f17ce`. Forty public
  clips/history checks, 240 native runs, 60 prototype comparisons and 40 reload
  calls pass. Ten continuous comparison videos are complete; deliver/archive
  through PC Explorer and pause for explicit run feedback. The preserved legacy
  run golden remains the sole expected editor/CI failure until that approval.
- R3-R5: pending preceding exit gates. No release action yet.
