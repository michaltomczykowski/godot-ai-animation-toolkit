# Saved setup graph checker

`test_project/tools/check_setup_tree_quality.gd` evaluates saved public `character_setup` scenes. It does not generate clips, replace a graph, call a private generator, write source scenes or establish history/discovery evidence.

Run with Godot4.7.2:

```powershell
godot --headless --path test_project --script res://tools/check_setup_tree_quality.gd -- route.json native-setup.json
```

The route uses the existing `tools/mcp_turn_setup_review.py` case shape. Each case requires `id`, `scene` (`res://...`), `scene_sha256`, `player`, `skeleton`, `roles`, the setup `request` and the actual setup result in `write` or `setup_response`. The checker unwraps `data`/`result`/`response` dictionaries. In the old turn setup route, `write` is dedicated turn metadata and `setup_response` holds the setup bundle; that distinction is preserved. Player/skeleton paths may be scene-relative or public absolute paths beginning with the saved scene root. Tree path, speed parameter and jump request parameter come from the setup result; optional `tree` overrides only the scene path.

`roles` must identify hips/head, both thigh/shin/foot chains and left toe. Derive these from the fixture or public rig profile; setup clip summaries do not replace a role map. Geometry uses the local rest convention and transforms it through the Skeleton3D world basis, so rotated parents and Y/Z-up fixtures remain meaningful. It never chooses a dominant world axis.

Optional `quality_specs` selects exact tests:

```json
[
  {"kind":"blend","speed_mps":0.4,"duration_s":6.0,"controller_speed_mps":0.0},
  {"kind":"jump","speed_mps":0.0,"distance_m":0.5,"controller_speed_mps":0.0}
]
```

For extracted graphs the only consumer applies `owner.position += tree.get_root_motion_position()` in owner-parent coordinates. A nonzero external controller request is an error. For an in-place blend, use the exact world input speed as `controller_speed_mps`; a driver outside the player subtree applies it once. Expected distance remains the independent blend input speed multiplied by actual sampled elapsed time, so an incorrect controller speed is detected. Jumps receive zero controller travel. Setup now refuses unextracted forward jump bundles: OneShot fade-out cannot retain that skeletal displacement without a separate movement handoff. Stationary in-place jumps remain supported; standalone unextracted forward clips retain their existing contract.

Without explicit specs the checker selects half walk, walk, midpoint walk/run and run at the returned speed values, each for6 seconds, plus jump when present. It runs30/60/120FPS. Extracted default specs use zero external controller speed; in-place specs supply their exact selected world speed. Unknown kinds and invalid/excessive checker durations fail explicitly.

## Measurements and gates

The existing saved Tree must bind the requested player and have the same resolved `root_node`. The saved root-motion bindings must agree. Competing mixers are disabled for isolated playback, and exactly one active Tree is required. The saved setup-owned grounder must be present, active, at full influence, directly under the bound Skeleton3D, with the exact saved Player/Tree paths and reported role map. Foreign active modifiers fail ownership instead of being silently disabled. Every sampled pose is captured inside the saved helper's `modification_processed` signal; the checker never installs a replacement helper. Each run reloads the saved scene and verifies its hash.

Contact declarations use the actual read-only Godot `current_position` parameters of contributing animation nodes. A blend declares contact only when all nonzero-weight contributing clips declare it; idle is treated as planted. Missing marker/phase coverage fails. This avoids guessing synchronized phases from requested time or silently accepting zero contact coverage. [Godot exposes these phase parameters](https://github.com/godotengine/godot/blob/4.7-stable/scene/animation/animation_tree.cpp#L40). The checker assumes the existing setup's interpolated1D blend graph and optional OneShot wrapper, rather than supporting arbitrary graph families.

OneShot checks actual active/phase parameters, requested/default1.2s authored duration, terminal hold, actual saved clip length and fade settings. It measures final world displacement after the Shot has finished and faded, grounded root travel, simultaneous ankle-plane flight, and recovery against a separately loaded native idle clip evaluated at the actual final idle phase. A clip reaching its endpoint before fade-out is not sufficient.

Release numerical gates stay: stance slide <=min(2% leg,3cm), penetration/contact height <=1% leg, no knee pole flips/nonfinite/inert output, final horizontal endpoint error <=0.1mm, and no competing root/actor writer. Final idle recovery requires position error <=min(1% leg,1cm) and rotation error <=0.01rad. World-scaled pose differences are independent of the character's origin. Bone speed above10leg/s fails the stated default-motion heuristic; angular speed is reported separately. This is an engineering bound, not an anatomical or mathematical continuity proof. Inspect the30/60/120 traces and independent videos rather than widening it to hide a fast hand sweep.

## Checker controls and pending evidence

`tier1_setup_tree_checker.gd` creates disposable synthetic saved graphs under `user://setup_tree_checker_controls_*`; it never uses production generation. The controls test valid native base/OneShot playback, intermediate blends, exact in-place world controller movement, translated/rotated parents at scale0.5/2 including Z-up, and deliberate doubled root travel, incorrect controller distance, missing contacts and unextracted OneShot endpoint loss. The final pure run passes33 native controls across30/60/120FPS, with no engine errors (`setup-tree-controls-final.log` in the isolated worktree). This qualifies checker behavior, not production animation quality.

The first synthetic attempt retained marker timestamp collisions and a checker reference-load scene-root rename failure. The next controls exposed a synthetic fixture's Z-up hip-parent coordinate mistake; corrected only the disposable fixture. All failed attempts remain in local logs. Production source fixture files are untouched.

The narrow setup refusal and corrected transition schedule-space annotation have focused editor tests staged in `test_setup_integration.gd` and `test_motion_transform.gd`. Transition `actor_translation_keys` are a skeleton-local schedule with `actor_translation_world_scale`; transform offsets with the skeleton's global basis to obtain world displacement. Previously archived unit/identity receipts are preserved. Editor/public test execution waits for the root agent's serial capture queue.

Actual four-rig/five-style saved public scenes, public histories/save/reopen, independent visuals, released-core/platform and full exact-source gates remain required.


## Public bundle route client

`tools/mcp_setup_quality_review.py --repo <repo> --core-root <released-core> --project-root <validation-project> --output <new-directory>` is executed only by the root operator against the serial live editor. Add `--godot <console.exe>` to run the native checker after each completed four-rig route. Its default matrix is five styles, stationary extraction and in-place, forward 0.5m extraction, and both with/without the unwired turn clip: 120 independently saved bundles. `--styles responsive --turn-mode without` selects a bounded initial qualification. The unsupported forward in-place bundle remains covered by the typed atomic refusal editor test, not a success row.

No gait speed or timing is supplied. Responsive omits style as well. Setup uses `active=false` so public dry/write pose preservation remains observable; the native checker activates the saved graph. Requests, raw setup responses, public non-saving rig profiles/roles, per-clip descriptions, prior/dry/final bindings, pose snapshots, external history result, save/forced-reopen descriptions and scene hashes remain in each route. The actual bundle result is both `write` and `setup_response`; every returned clip summary and its motion metrics are preserved. Missing native metadata must fail explicitly; the native checker must never generate replacement references. No standalone-reference parity claim is made by this client.

`test_public_setup_bundle_undo_redo` is a separate external witness selected by `PublicSetupBundleHistory`. It observes the existing public transaction, removes all requested clips and the Tree in one Undo, checks prior binding and unrelated clips, then checks exact clip digests, complete clip list, graph/wiring and extraction after one Redo. It never authors another setup; the historical turn-only witness remains unchanged. Ordinary full tests skip it when no external witness exists.

Offline `python tools/test_mcp_setup_quality_review.py` passes three orchestration controls: complete default matrix, rejection of failed external history and rejection of forced-reopen clip drift. Godot 4.7.2 check-only passes the edited editor test script. Actual public calls, external Undo/Redo and saved native candidate qualification remain pending root execution. The system Python lacks FastMCP; run the public client in the existing MCP client environment.


The client also accepts `--variants extracted-stationary in-place-stationary extracted-forward` (or a subset). Each stage writes a new numbered immutable JSON snapshot under the group's `receipts/`, alongside the latest route index. `--reuse-complete <previous-output>` reuses successful individual cases, even from a failed partial group, only when exact toolkit/released-core production dependency hashes, the complete request and saved scene hash match. It records the prior route path, preserves previous receipts and never repeats completed public mutations. Dependencies are checked again at every group boundary. Native check-only replay may run on reused scenes. Offline positive control exercises full reuse with zero additional public requests and rejects changed dependency hashes before any request.


## Serialized grounding production increment (native validation pending)

`runtime/setup_grounding.gd` is a setup-owned `@tool SkeletonModifier3D`. It reads the saved interpolated Base and optional OneShot parameters every evaluation; the existing independent graph clock and single translation consumer are unchanged. It preserves the current FK foot orientation, hips/upper-body poses, rest transforms, positions and animation keys. The bounded solve rotates only the measured thigh, shin and foot chains: project penetrating ankles onto the measured rest ankle plane and hold each conservatively declared stance anchor in world space. The level-plane contract does not imply terrain collision or shoe-sole geometry.

Setup creates or reuses this helper in the same Undo transaction as clips and Tree, including relative bindings, full influence, scene ownership, modifier order and instance editability. Before writes it refuses duplicate ownership, an occupied helper/Tree name, mismatched reused helper bindings, non-direct or degenerate leg chains, a playing bound Player, a foreign active bone modifier or a competing active mixer that can write the rig. Existing foreign nodes are never disabled by setup. The return status is `configured_pending_native_playback`; it is not a playback success claim.

Call the returned helper's `reset_grounding("explicit_seek_or_new_take")` before deliberately seeking or starting a new take. Deactivation/rebind/configuration changes and large native phase discontinuities also clear anchors automatically. A forward seek smaller than the automatic discontinuity threshold is indistinguishable from ordinary manual advancement; its caller must use the explicit reset method. Keep the helper at influence1. Read its serializable `diagnostics()` for current status/error, per-evaluation residual, cumulative maximum residual/correction, unreachable targets and anchor reset reasons. A prior bad residual remains in the cumulative diagnostic but does not prevent a later valid evaluation from recovering.

`tools/check_setup_grounding_controls.py` takes an immutable fresh public setup route, project, Godot binary and new output directory. It executes serial native plays using the real saved helper: original specs; quarter/half/three-quarter inputs in both blend intervals; linear up/down ramps with exact midpoint-integrated expected world distance; a deactivate/reset/reactivate take; recovery from a prior diagnostic error; and missing/disabled/wrong-path/late-writer/partial-influence corruptions. Every negative must fail every declared cell, including exact raw gait endpoints. Scene hashes, exact `(id,spec,FPS)` identities and engine errors are checked. No source scene is written. These controls and the updated editor history/ownership tests are prepared; actual production native/public/save/reopen and visual gates remain pending the root's serial process slot and fresh public bundles.

The older33 synthetic controls above are historical evidence for the earlier checker. Their disposable fixture constructor now serializes the real owned helper and gives the synthetic hip a small downward reach margin; this does not change tracked fixtures or accepted clips. They require a fresh native rerun with the stricter ownership contract. Tiny/huge uniform scale precision limits have not been established by this source-only increment; runtime reach/residual/finite gates stay active and no broad scale qualification is claimed.

Offline orchestration controls: `python tools/test_check_setup_grounding_controls.py` passes5 tests for successful cell accounting, one negative false pass, wrong identity at the same count, engine error rejection, and original scene mutation detection. Existing output directories are refused. This tests orchestration only, not animation or GDScript parsing.

`setup-grounding-source-preservation.json` binds the isolated comparison head and exact tracked fixture/golden blobs. Only the existing motion `run` cleanup and `motion_character_setup` function bodies change; standalone `_prepare_cycle` and all other motion functions are exact against that head. Later root generator repairs are outside this isolated comparison and must be preserved during cherry-pick integration.


Post-commit parse checkpoint: all7 edited GDScript scripts passed Godot4.7.2 official `ed1daf0bf` headless check-only at source `bb8ce83`, with engine-banner-only logs retained locally under `private-setup-production-parse-r001`. This did not execute any fixtures or qualify production playback. The following remote-Tree root binding repair and its editor regression are later changes and require their own parse/native evidence.

Setup now explicitly stages the Tree's `root_node` to resolve the Player's actual animation root, even for a custom Player root and a Tree outside its parent. Detached paths are resolved from the future Tree parent before commit. Existing `root_node` is restored by the same Undo transaction; the canonical sibling `..` case remains unchanged. The editor regression covers existing and newly created remote Trees, nested Player roots, dry mutation freedom, single Undo/Redo and save to a unique disposable user scene and CACHE_MODE_IGNORE reopen of the actual relative bindings. Actual editor/public execution remains pending.


Remote-root follow-up check-only passed motion, integration test and registry at the initial root-path patch, with banner-only logs in `private-setup-production-parse-r002`. The subsequent disk-reopen assertion and explicit reset state assertions were added after that checkpoint and require their own final parse. No later test source is attributed to an earlier parse.


## Saved writer admission before playback normalization

The checker now inspects the saved mixer's active state and Player playing/autoplay state before disabling mixers or adding the scene to the SceneTree. A foreign active mixer whose resolved animation root contains the bound Skeleton3D is refused. Autoplay counts because `_ready` can start it after this inspection. The bound setup Tree is deliberately admitted, then callbacks and mixers are normalized for its isolated manual-clock measurement. This is the same conservative animation-root ownership rule used by the runtime helper, not per-track overlap analysis. An active writer whose root belongs to a genuinely unrelated rig is admitted.

The disposable corruption checker injects a same-rig active Tree and same-rig autoplay Player before this admission, and both must fail every cell. Its positive counterpart duplicates the actual track-addressable animation-root rig/library, disables copied writers/helpers, then supplies an active Tree bound solely to that unrelated rig. It must pass admission and the original setup quality cells after normalization. It never replaces the bound graph, edits source scenes or generates motion. New source is parse/native pending until the root releases the capture slot. Offline orchestration controls still pass5 tests; that does not establish these native cases.


The first integrated33-cell synthetic run failed every otherwise-valid cell on a concrete checker false refusal: Godot4.7.2 inserts an active **internal**, empty `PhysicalBoneSimulator3D` on scene entry. `find_children` exposed it while ordinary `get_children()` did not. The returned helper path resolved correctly; a one-process/one-cell enumeration repro found exactly the owned helper plus `Dummy/Skeleton3D/@PhysicalBoneSimulator3D@3`, and zero engine errors. The root's original failed log and the worker's `private-setup-production-parse-r003/repro.log` are preserved. The checker exempts only that exact inert category: internal PhysicalBoneSimulator3D, no script, no children including internal children, and not simulating. User-owned, scripted, child-bearing or simulating modifiers still fail ownership. This is not a blanket physical-modifier exemption. The fix is source-prepared; the33-cell rerun remains pending root's serial slot. [Godot documents the simulation-state query](https://docs.godotengine.org/en/4.4/classes/class_physicalbonesimulator3d.html#class-physicalbonesimulator3d-method-is-simulating-physics).


A targeted additional negative inserts an active internal PhysicalBoneSimulator3D with a child sentinel before admission. It must fail the exact empty-node exception boundary without starting physics, replacing the graph or touching any original scene. The ordinary synthetic valid cells exercise the naturally inserted empty internal node. No native pass is yet claimed for either side of this boundary.
