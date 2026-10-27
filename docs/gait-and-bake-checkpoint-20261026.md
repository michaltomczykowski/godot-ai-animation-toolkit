# Completed default gait and current bake checkpoint

Recovered26October after a usage-limit interruption. The actual engine run
completed25October; no interrupted generation or bake call is restarted.

## Exact source and route

- Source:26a35eb2dc7106cdd951b4771f9ec8c3971861bc, pushed repair/toolkit-quality.
- Visible official Godot4.7.2.stable.ed1daf0bf, Windows, released Godot AI4.2.1
  bfc264200584ea5823f18356acb164781f57796d and its exact backend environment.
- Private root:E:/GodotAI-toolkit-release-2.0.0/20261014/gait-bake-public-r001.
  execution.json records complete drivers; operation-context.json and raw traces
  retain tested source/dependency/core/engine identities. Public quit completed.
- operation-case-results.json SHA256:
  779a70d427258337a7c725dca6cc339aac124712d84f58ffa64700d9598d4d2b.

## Results

| Existing driver | Elapsed seconds | Scoped result |
| --- | ---: | --- |
| mcp_motion_remaining_cycles.py |11.156|Three default walk_cycle/run_cycle/cycle writers pass.|
| mcp_motion_audit_saved.py |7.453|Nine original audits at30/60/120FPS pass, including run flight checks.|
| mcp_rig_bake_restoration.py |66.078|Six public suites,201native cases and direct calls before/after core reload pass.|

All nine gait valid_effect observations pass the bounded translating-default
criteria: immutable saved-scene identity, actual disk reload, original public
generation/save/audit order, noninert hip and both-foot motion, support/swing,
and existing contact/knee/bob limits. Run additionally retains flight and reach
checks. This is neither an exact omitted-speed oracle nor visual approval,
all-parameter coverage or qualification of the other motion recipes.

The bake runtime report preserves603saved states,402played states,10764key
samples and10362intermediate samples, zero failures and zero engine errors.
Worst saved-playback errors: position1.01327896118164e-6, rotation
1.60932550485847e-6, scale3.37174782316652e-7. The separately reported native
motion approximation is not this playback error and is not silently substituted
for it. Existing comparisons and driver caps90/90/180seconds are unchanged.
This matrix is numeric/history/restoration proof, not the pending continuous
source-versus-bake workflow film.

Four public direct calls before and four after actual core reload pass.
Old session validation@2e353c7a260569a1 becomes
validation@b55f20c27155c149. Strict collection reports zero derived failures.
The immutable bake-restoration.json and runtime.manifest_path now provide a
fresh current anchor for the eight-case workflow evaluator; archived historical
matrices remain separate.

## Scope correction after execution

The adapter previously rejected otherwise valid in-place requests and run
audits using the generic gait branch without the optional flight gate. These
requests are outside this translating/flight-qualified witness. They now emit
no new effect qualification, leaving the channel pending. Unknown audit branches
and invalid translating-request types still reject; every admitted predicate
and physical budget remains unchanged. Eleven focused unittest methods pass,
including default positives, in-place/no-flight pending, invalid scope and
numeric/source/order corruptions. The26a receipt is preserved under its actual
source, not relabeled after this adapter change.

## Continue

CI40173858488 at26a completed successfully. Independent raw/source/case review
is pending; a green attempt does not establish a fix for intermittent Linux
allocator corruption. Finish the bounded Linux doc-loader writer diagnostic,
two missing Responsive motion representatives, eight-case bake/workflow media,
portable103-operation audit and exact final install/publication gates. No
main merge, tag, release or private-media upload has occurred.
