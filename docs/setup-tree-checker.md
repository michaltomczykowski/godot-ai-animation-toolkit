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

The existing saved Tree must bind the requested player and have the same resolved `root_node`. The saved root-motion bindings must agree. All other mixers and modifiers are disabled, and exactly one active Tree is required. Each run reloads the saved scene and verifies its hash.

Contact declarations use the actual read-only Godot `current_position` parameters of contributing animation nodes. A blend declares contact only when all nonzero-weight contributing clips declare it; idle is treated as planted. Missing marker/phase coverage fails. This avoids guessing synchronized phases from requested time or silently accepting zero contact coverage. [Godot exposes these phase parameters](https://github.com/godotengine/godot/blob/4.7-stable/scene/animation/animation_tree.cpp#L40). The checker assumes the existing setup's interpolated1D blend graph and optional OneShot wrapper, rather than supporting arbitrary graph families.

OneShot checks actual active/phase parameters, requested/default1.2s authored duration, terminal hold, actual saved clip length and fade settings. It measures final world displacement after the Shot has finished and faded, grounded root travel, simultaneous ankle-plane flight, and recovery against a separately loaded native idle clip evaluated at the actual final idle phase. A clip reaching its endpoint before fade-out is not sufficient.

Release numerical gates stay: stance slide <=min(2% leg,3cm), penetration/contact height <=1% leg, no knee pole flips/nonfinite/inert output, final horizontal endpoint error <=0.1mm, and no competing root/actor writer. Final idle recovery requires position error <=min(1% leg,1cm) and rotation error <=0.01rad. World-scaled pose differences are independent of the character's origin. Bone speed above10leg/s fails the stated default-motion heuristic; angular speed is reported separately. This is an engineering bound, not an anatomical or mathematical continuity proof. Inspect the30/60/120 traces and independent videos rather than widening it to hide a fast hand sweep.

## Checker controls and pending evidence

`tier1_setup_tree_checker.gd` creates disposable synthetic saved graphs under `user://setup_tree_checker_controls_*`; it never uses production generation. The controls test valid native base/OneShot playback, intermediate blends, exact in-place world controller movement, translated/rotated parents at scale0.5/2 including Z-up, and deliberate doubled root travel, incorrect controller distance, missing contacts and unextracted OneShot endpoint loss. The final pure run passes33 native controls across30/60/120FPS, with no engine errors (`setup-tree-controls-final.log` in the isolated worktree). This qualifies checker behavior, not production animation quality.

The first synthetic attempt retained marker timestamp collisions and a checker reference-load scene-root rename failure. The next controls exposed a synthetic fixture's Z-up hip-parent coordinate mistake; corrected only the disposable fixture. All failed attempts remain in local logs. Production source fixture files are untouched.

The narrow setup refusal and corrected transition schedule-space annotation have focused editor tests staged in `test_setup_integration.gd` and `test_motion_transform.gd`. Transition `actor_translation_keys` are a skeleton-local schedule with `actor_translation_world_scale`; transform offsets with the skeleton's global basis to obtain world displacement. Previously archived unit/identity receipts are preserved. Editor/public test execution waits for the root agent's serial capture queue.

Actual four-rig/five-style saved public scenes, public histories/save/reopen, independent visuals, released-core/platform and full exact-source gates remain required.
