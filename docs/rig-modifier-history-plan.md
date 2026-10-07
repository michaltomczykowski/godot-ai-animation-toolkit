# Modifier history and playback implementation plan

Approved 2026-10-07. Baseline: `1074877`, Godot 4.7.2, public Godot AI
`animation_rig_modifiers` route. Work alone on `repair/toolkit-quality`.

## Checkpoint 1: history and persistence

Use authored synthetic rigs, immutable source scenes and untouched peer
instances. Base matrix: IK, look-at, twist and spring in local/locked/editable
layouts; retarget in local/editable layouts and a typed locked-source refusal.
For each write run dry mode first, require one scene action/no global action,
then save/reopen Do, Undo and Redo. Record exact owners, order, transforms,
settings, node identities, editable permissions, source bytes and resource
sharing. Add IK/spring nested instances with all four outer/inner permission
combinations. Preserve the earlier allocation gate.

## Checkpoint 2: individual playback

Audit all five IK kinds with generated/supplied targets or paths, all four
two-bone target/pole ownership combinations, virtual ends and rotated parents.
Look-at covers generated/supplied targets, every origin, six forward axes,
secondary rotation omitted/false/true, limits, relative mode and interpolation.
Twist covers even/weighted, weights 0/0.5/1, rest/reference, extended end and
influence. Spring covers all/list/excluded collisions, world/node/bone centers,
multiple settings, mutable axes, name collisions and caller transforms.
Retarget covers new/existing modifier, transform flags, global mode, different
rests and direct target instances. Run one valid dummy case per operation.

Independent engine checkers import no toolkit/test helpers. Validate requested
settings and resolved paths, capture each stage in modification_processed and
the final influence blend through an inert witness, cross-checked against
skeleton_updated. Require inert Undo, effective Do, equal replay of Redo, and
active/inactive plus 0/0.5/1 influence. Reachable non-spline IK must reach within
0.5% of chain length. Use independently configured native references for spline,
twist, retarget and stateful solvers; add geometric checks so a shared inert
native result cannot approve success.

Reproduce before repairing look-at secondary=false, generated IK endpoint
placement, persistence and ordering problems. Expose already accepted twist
influence/mutable_bone_axes in the schema; preserve defaults and response shapes.
Predictable refusals must precede history commit; never clear user history to
hide a failed action. Correct class names and examples in generated docs.

## Checkpoint 3: state and order

User selected: newly created/restored springs restart from the current pose
after attachment/configuration and before their first simulated step. Use the
public reset API; do not reset unrelated running modifiers. Drive nonzero delta
and deterministic animation at 30/60/120 FPS. Test collision separation, finite
poses and repeated Do/Redo response. Compare ordered parent/child look-at,
IK/look-at/twist and IK/spring stacks against independent native stacks; include
changed creation order and fractional final influence.

## Checkpoint 4: integration

Direct external custom_manage calls must cover every operation before/after
core reload and in a fresh editor. Native Windows Undo/Redo covers new look-at,
spring collider reparenting and existing retarget reconfiguration. Required
Windows/Linux headless/editor/public-route CI must pass; retain current-core
drift reporting. Missing case IDs, samples, states or reports fail validation.

## Checkpoint 5: evidence

After each checkpoint update FIX_ROADMAP, operation evidence and the persistent
recovery snapshot; commit/push verified source. Deliver required case IDs, saved
state counts, measurements/refusals/CI links and fixed-camera previews of each
family and combined stacks. Review for incorrect targets, flips, snapping and
unstable springs. Keep operation statuses partial where visual/bake acceptance
remains open. No release, tag, merge or media upload.

## Following work

Active AnimationTree/ordered modifier bake restoration, fractional last-modifier
influence, retarget/private spring state/outside-rig property restoration and
late sampling failures are the next separate checkpoint. Motion/sequence
history and full locomotion visual approval follow.

## Implementation boundary discovered during playback

The independent native 4.7.2 checks reproduced two engine limitations. Jacobian
stalls 9.79 mm from a reachable target on a 0.9 m chain, beyond the 0.5% contract.
Node/bone spring centers with collisions penetrate a reachable sphere on rotated
rigs (79.9/8.85 mm). These choices now return `OPERATION_UNAVAILABLE` before
allocation or history commit. Jacobian is removed from advertised choices;
world-center collisions and relative centers without collisions remain supported.
Keep the native diagnostic failures as evidence before reconsidering either
choice. A final all-rig tree-entry check also reproduced native authored-child
pose loss in original Undo scenes. Reconfiguring existing native retargets with
non-rest child inputs and no helper is unavailable before allocation/history;
toolkit-created modifiers and native rest-pose baselines remain supported.
The supported gate covers 92 cases / 276 saved scenes, with 828 saved
playback checks and 276 independent references at 30/60/120 FPS. See
[implementation evidence](rig-modifier-history-validation.md).
