# Saved bake source parity and spring cache diagnosis

This phase replays exact original public source and saved redo scenes from
gait-bake-public-r001, producer26a35eb2dc7106cdd951b4771f9ec8c3971861bc.
It does not regenerate clips, substitute native modifiers, widen tolerances or
approve media. Private root:E:/GodotAI-toolkit-release-2.0.0/20261014.

## Preserved failed observations

bake-eight-current-preflight-r002 parsed under official4.7.2. Its32spring
source/output/take/pacing/reset observations complete with no engine errors and
identical fresh takes. All16parity pairs fail: warm original spring curves
differ from saved bake by up to.011149rad (spring) and.009168rad (ordered
spring/look-at). Flushing the deferred reset does not repair this discrepancy.

The first full8observer exposes two independent observer errors: an unchanged
retarget source skin cache need not emit a new skeleton_updated signal, and an
AnimationTree-controlled Player need not have a current animation. Its original
failed report and engine log remain unchanged. The evaluator now permits a
nondecreasing cached skin count only when actual final poses exactly equal the
complete previously observed skin pose; changed/stale poses still fail. It
records absent Player clocks as null and reads actual Tree state separately.
No forced skin update, source pose or graph write is added by those fixes.

## R003 unchanged-source result

Native8 completes32runs with zero observation failures/engine errors. Both
fresh takes are exact. State machine, OneShot, retarget and all three root
movement modes pass original .0001position/.001rotation/.0001scale limits.
Both spring families still fail. This separates the actual bake defect from
the corrected clock/skin observation assumptions.

native-eight.json SHA256:
9e4cce61fad8f6b485693643ea9e308ef71930688ef17d8ea6eda780ee6474dd.
native-eight-comparison.json SHA256:
af9ca6695c5c8914d54258684cc527c7c77f9ce04af5b626226fd549ca4feaeb.

## Causal startup control

R00324cells cover two spring cases, source/redo, two fresh takes and three
startup strategies. All complete under actual4.7.2 with zero engine/observation
errors. No setting setter, replacement modifier or new animation is used.

| Source startup | Stored stiffness/drag/gravity/radius | Actual joint values | Saved bake parity |
| --- | --- | --- | --- |
| Original saved source, two loading frames |.7/.3/.1/.02|.7/.3/.1/.02|Fails up to.011149rad.|
| Original saved source, immediate synchronous replay |.7/.3/.1/.02|1/0/0/.1|Passes within4.22e-8rad.|
| Exact production evaluationSandbox copy, synchronous replay |.7/.3/.1/.02|1/0/0/.1|Passes within4.22e-8rad.|

This demonstrates the private synchronous path samples uninitialized joint
configuration. Agreement between the prior Native.replace reference and the
production sandbox did not establish requested-setting fidelity: both share
the same deferred initialization condition. The earlier201-case saved playback
proof remains valid in its original scope; it does not override this failed
comparison with a warmed unchanged source.

cache-diagnostic.json SHA256:
4deebceab04502034adaa0f6db95a3213a6186d4048de1bab003afd4e6dd078c.
cache-summary.json SHA256:
832b0f6ec913a16f4b8eaf8a48d4a53eac1276c8c2673a843f930664400de406.

## Next repair gate

Initialize the private native per-joint configuration deterministically through
supported APIs before sampling; handle all supported setting/curve semantics or
refuse the unsupported narrow case before commit. Preserve the author's nodes,
synchronous isolation, all physical/parity limits and accepted non-spring
behavior. Add a regression against independently warmed native source, then
obtain fresh public bakes and repeat saved playback/history/unchanged-source
parity. Old wrong bakes are retained as negative evidence. Continuous capture
remains blocked until those comparisons pass; no GPU approval is inferred.
