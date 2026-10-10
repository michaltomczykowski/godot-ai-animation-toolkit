# Motion and sequence history/playback repair

Approved 2026-10-08. Godot 4.7.2; unreleased `repair/toolkit-quality`.
Work alone through Godot AI's public custom-tools API.

## Contract

Repair individual motion writers, secondary_motion and animation_sequence.compose.
Retain character_setup's existing history gate. Preserve operation names,
parameters and explicit destination semantics. Write and dry-run calls require
a stopped/paused destination and inactive linked AnimationTrees; otherwise return
OPERATION_UNAVAILABLE with guidance to pause or choose an inactive player.
Refuse extraction changes that would invalidate another destination clip.

Each successful write is one scene Undo action, with no global-history action.
It owns clips, local libraries, instance permissions, extraction settings and
authored pose restoration. Preserve unrelated resources, source/peer scenes and
live playback state. Deferred restoration must retain scene/history/ticket guards.
Dry/refused calls keep exact orphan sets; commits may free prior Redo objects but
must introduce no new orphan nodes. Validate inputs and overwrite before sampling.
Live transient playback state is separate from serialized scene properties.

## Checkpoints

1. Preserve baseline/source/evidence and establish public-route history suites.
2. Protect playback; make all clip/history/extraction changes atomic and extend
   deferred pose restoration to secondary motion and composition.
3. Replace secondary_motion's live hand-applied poses with native AnimationPlayer
   evaluation in the existing private sandbox. Disable private modifiers: this
   remains an offline angular spring driven by a clip, not final-stack baking.
   Preserve the spring model; validate finite coefficients, bones, sampling budget
   and supported tracks; correct native rest coordinates and endpoint timing.
   Inject late failures; require complete cleanup and unchanged live continuation.
4. Validate sequence inputs before sorting. Retain previous values for missing
   channels, using invocation-authored transforms before their first appearance.
   Gaps hold endpoints. Refuse a segment starting before the preceding fade ends.
   Use native source interpolation, including easing/cubic; include segment ends
   and fade boundaries in samples. Bridge intentional zero-fade discontinuities;
   refuse spacing too close for native key lookup. Support translation extraction
   with cropped/overlapped sources; refuse rotation/scale extraction in this phase.
   Retain ordinary bone rotation/scale, marker timing/colors/duplicate names, and
   report counts/duration matching saved output.
5. Complete independent native playback, live continuation, direct MCP/reload,
   fixed-camera review and Windows/Linux CI, then close docs/evidence/recovery.

## Required matrix

- Motion: eight dedicated recipes plus cycle walk/run/idle across local, locked,
  editable, missing-default-library and overwrite layouts (55 configurations).
- Secondary: one bone and two independent branches with different rests across
  local/locked/editable layouts (6 configurations).
- Composition: gap/hold, partial-channel overlap, saved pose, inline pose,
  cropped rooted clips/contacts, and source/output overwrite across five layouts
  (30 configurations).
- Generate all 91 configurations at 30/60/120 FPS: 273 required case IDs and 819
  Do/Undo/Redo scenes. Replay all saved states at all three rates. Do/Redo play
  generated outputs; Undo verifies and plays original clips/settings.
- Every case checks dry/refused/write/Undo/Redo, one scene action, no global
  action, exact resource identities, authored input, source/peer isolation and
  immutable source bytes. Missing required IDs/reports/samples fail the gate.
- Independent references must not call production sequence/spring helpers.
  Key/interpolation limits: 0.1 mm position, 0.001 rad rotation, 0.0001 scale.
  Report continuous-motion approximation separately from key fidelity.
- Named regressions: busy destinations, incompatible extraction, malformed and
  nonfinite inputs, close boundaries, late failures and deferred later-action
  protection. Live graph/spring continuation must match untouched controls.
- Direct external MCP calls before/after core reload must dry/write/refuse/save/
  force-reopen representative motion, secondary and composition output.
- Review fixed-camera start/walk/stop, jump/recovery, secondary motion and rooted
  clip/pose sequences for snaps, timing shifts and doubled travel. This is
  technical output approval; full humanoid/action quality remains a later gate.

## Delivery

After each verified checkpoint update FIX_ROADMAP, operation evidence and the
persistent recovery snapshot, then commit/push the review branch. Preserve all
existing required gates. Require both full Windows/Linux MCP routes and all
headless/editor combinations. Deliver validation notes, saved scenes and local
media. No release, tag, merge or media upload.
