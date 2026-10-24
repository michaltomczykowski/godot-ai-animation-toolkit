# First serialized production setup group

Source `c19a25e`, Windows/Godot4.7.2 `ed1daf0bf`, released Godot AI4.2.1
(`bfc264200584ea5823f18356acb164781f57796d`). Private receipts are in
`E:/GodotAI-toolkit-release-2.0.0/20261014/setup/production-r003`.

## Public creation and saved playback

The corrected remote-root save/reopen regression passes28 assertions in a fresh
editor with zero engine errors. The earlier parented-dialog failure remains in
production-r002. Its cause was test fixture ownership: retained scene instances
and their inherited children were serialized twice. The repaired test preserves
instance ownership, uses a local tree for deliberate reparenting, asserts one
saved Player and fails on scoped engine errors. No production generator changed.

The first bounded group uses Responsive defaults, extracted stationary jump,
no turn and the dummy/X Bot/short/Z-up tall rigs. Four actual external
`character_setup` requests pass dry run, exact pose/binding preservation,
single external Undo/Redo, save and forced reopen. Each external history witness
passes50 assertions including the saved helper/configuration/order. PID5232 was
quit through public Godot AI before native replay; the complete editor log has
no engine errors.

All60 saved native Tree plays pass: four rigs × half idle/walk, walk,
half walk/run, run and jump ×30/60/120FPS. Every sampled final pose is witnessed
by the saved production helper's signal. No prototype or replacement modifier
is installed. Report SHA256:
`03f19430326703b57c3ee1c64b7b9c1231576121395461cc1d9d48c85e123798`.

| Measurement | Maximum/result |
| --- | ---: |
| ankle-plane penetration |0.0000016094m |
| stance slide |0.0000009763m |
| IK residual |0.0000016888m |
| root endpoint error |0.000085831m |
| bone speed |9.423061leg/s |
| unreachable targets / knee flips / engine errors |0 /0 /0 |

An independent comparison matches all60 exact case/spec/FPS identities against
the preserved failed production baseline:24pass/36fail becomes60pass. Actual
world root distances are exactly unchanged in every cell. These are level rest
ankle-plane checks, not shoe-sole geometry or terrain collision. Existing bounds
are unchanged. This group does not approve visuals or other styles/modes.

## Dynamic and ownership controls remain partially open

The original768-cell control run and its failed summary are immutable in
`grounding-controls-r001`. Godot's15-significant-digit JSON echo caused the first
Python wrapper to reject otherwise matching numeric request identities. The
repaired wrapper keeps exact IDs/FPS/keys/strings/bools and one-to-one cells;
only finite nonzero echoed numeric fields permit machine serialization error
(max8ULP or relative1e-14). Physical metrics keep their original gates.13 offline
controls pass, including altered specs, duplicate cells and absent/error logs.

Root's hash-bound `grounding-controls-reanalysis-r002.json` applies that adapter
to the original reports without replaying or modifying them. All768 identities
match. Eleven control groups qualify, including480 expected-negative cells and
positive/residual-recovery/unrelated-rig admission. Dynamic96/108 cells pass;
the12 deliberate reset cases still fail endpoint/continuity checks. They have
not been relabeled as passes. The first post-reactivation sample loses one root
delta and the animation phase restarts; a bounded new-take contract is being
diagnosed before changing its checker. No runtime or threshold repair is inferred.

Continuous setup recordings, reset-case closure, the broader approved setup
matrix, operation qualification and exact-source compatibility/release gates
remain. See `qualification-gap-analysis-20261016.md` for the observed per-operation
evidence gaps; its old CI coverage is explicitly not current qualification.
