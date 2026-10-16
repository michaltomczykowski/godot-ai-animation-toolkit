# Setup grounding and final-pose bake integration

Read-only audit against root runtime helper from dd029f / 0570270. No native,
editor, GPU or public MCP process was launched by the worker.

## Proven integration gap

`pose_bake_sampler.gd` rejects every active scripted SkeletonModifier3D before
opening its sandbox. The setup-owned grounding helper is an active scripted
SkeletonModifier3D, so a real setup Tree bake currently returns typed
OPERATION_UNAVAILABLE. It does not currently silently bake FK.

Simply allowing its script would be incorrect: `evaluation_sandbox.gd` uses
duplicate(0), strips node scripts and copies only native properties. Grounding
configuration and its processing would be absent. Its anchor/phase caches must
also start fresh in the private replay, rather than copy a warmed live take.

The existing final Witness is appended after all modifiers and compared with
the native skin pose. Its capture location is already appropriate. Retarget
descendant rigs use the same sampler. No evidence supports changing that order.
However, grounding rejects every foreign active modifier, including an appended
Witness. For grounded rigs only, use a RefCounted capture record connected to
the exact full-influence grounder's modification_processed signal and retain
the skeleton_updated skin comparison. Other native rigs keep their existing
appended Witness. Do not weaken the runtime's ownership check.

## Bounded repair

Only the sampler will recognize the exact toolkit setup_grounding.gd script and
its supported contract version. Keep foreign scripts refused. Require its bound
Tree/Player to match the explicit source Tree replay. Reinstall that exact script
on its private native copy, copy only declared scalar/vector/name/path config,
and remap paths through the existing sandbox. Reset only private grounding
anchors/phases; never modify or restore guessed live caches.

After each native evaluation require active grounding to report a successful,
finite final solve. A failed/inactive solve must return typed refusal and free
the private hierarchy, never turn the uncorrected pose into successful output.
Keep the existing final Witness and skin comparisons.

## Regression to run through public test_run

Create two real character_setup outputs through the public dispatcher, with the
actual setup-owned helper and active interpolated Tree. Warm the subject to give
it live anchors/phases. Bake a fresh zero-origin Tree replay at an intermediate
speed, then compare every baked bone sample against an independently advanced
native reference captured at the helper's modification_processed signal. Check
that at least one corrected stance pose differs from the ungrounded FK control.

Verify dry/write/repeated replay preserve the subject's live helper caches,
diagnostics, Tree phase/parameters, pose and continuation. Check one output
history action plus Undo/Redo. Inject a late private sampler failure and require
unchanged live state, no output/history and no orphan nodes. Include a foreign
scripted modifier refusal control. Add a retarget-descendant case only if the
actual supported wiring requires a different path; do not infer it from totals.

Runtime/motion ownership and collector resource-ID policy are outside this edit.
The root owns parsing and all actual editor/native/public execution after its
capture queue; static/Python checks do not constitute native qualification.

## Implemented scope; execution pending

The sampler recognizes only the exact toolkit script resource, contract1 and
the declared configuration-field set. It also refuses non-name role values.
Generic sandbox script stripping remains unchanged. Only the trusted active
helper is rebuilt after native hierarchy isolation, with duplicated/remapped
configuration and fresh script state. The original helper is never reset.

Grounded rigs use a RefCounted final capture on the helper's own native signal.
Influence1 and exclusive modifier ownership are validated before cloning and
again in the private graph. Thus this signal is the last supported writer;
the existing skeleton_updated skin comparison additionally rejects divergence.
Other rigs still use the last appended native Witness. Post-evaluation checks
reject unavailable/inactive grounding, nonfinite/excess residual or unreachable
targets before returning any pose to the bake writer.

`rig_bake_setup_grounding` is a new public-test-run regression suite. Its two
tests exercise real public character_setup and rig bake dispatcher calls using
the shipped synthetic-short rig at30/60FPS. Assertions require a measurable
raw-Tree-FK/final-grounded difference, every final TRS key against the independent
modifier signal, identical repeated replay, warmed source-cache/phase equality,
untouched native-control continuation, output Undo/Redo, and private late/solve
failure cleanup. Missing explicit Tree, wrong Tree binding and foreign scripted
modifiers must still refuse. No hand-restored bone pose is used as the oracle.

The default scope deliberately does not claim a newly qualified retarget plus
grounding combination. Retarget descendants share this sampler and the generic
native path must regress. A foreign active modifier on the same grounded rig
remains outside the runtime ownership contract and returns a typed refusal.

Worker verification is limited to source review and `git diff --check`; no
Godot parse or runtime execution occurred while the root's GPU queue ran.
Root must parse the sampler/new suite, invoke
`test_run(suite="rig_bake_setup_grounding", verbose=true)`, then run the existing
rig_bake_restoration/graph/modifiers/continuation/root-motion/retarget gates.
Any actual failure must remain preserved and localized before qualification.
