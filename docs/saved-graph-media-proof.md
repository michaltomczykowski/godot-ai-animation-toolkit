# Preserved graph native effect proof

The graph media path uses new dedicated files; it does not share or modify the generic saved-effects renderer.

1. Prepare immutable byte copies and a scene/control manifest:
   `python tools/prepare_graph_media.py --output <new-directory>`
2. Run native proof and corruption controls without rendering:
   `python tools/check_graph_media.py --manifest <directory>/manifest.json --project-root <project> --godot <console.exe> --output <new-controls-directory>`
3. Only when root schedules GPU capture, use Godot Movie Maker with the fixed clock:
   `godot --path <project> --resolution 1920x1080 --fixed-fps 60 --write-movie <new-frames-directory>/frame.png --script res://tools/render_saved_graph_effects.gd -- <manifest.json> <new-render-report.json>`

The intended continuous recording is28s/1680 frames: seven operations, each with two fresh-instance two-second takes. Independently decode and verify actual frame count after capture; the script's intended frame count is not a media verification. No GPU capture or image approval has occurred during implementation.

## Exact saved ownership and controls

The preparer selects self-contained `graph_history_<op>_new_redo.tscn` files from the preserved coverage inventory, verifies their original hashes and copies their bytes exactly. External-resource scenes are refused. `wire_new_redo` has no graph root, so the wire demonstration instead uses the preserved sibling `wire_replace_redo`: an existing saved idle AnimationNode whose player binding was written by wire. It is explicitly a binding/neutral-hold demonstration. It does not claim that wire generated movement. The original covered scene record, alternate source path and exact actual copied hash are retained.

Exactly one original saved Tree is activated. All Players and other mixers are stopped/disabled before the scene enters the tree. Saved player binding and graph-root identity are checked; every sampled frame checks ownership and finite output. Scene hashes and clip-key fingerprints are checked again at the end. The graph is never replaced, and no animations, target poses or target transform keys are synthesized.

Controls use native state-machine playback,1D blend position, Blend2 amount, OneShot request and Add2 amount. The manifest records each control contract. The preserved state machine automatically advances idle to walk; its native output can continue despite the playback stop flag. The caption therefore says automatic transition, and its reset proof is a fresh hashed scene instance, not a claimed neutral tail. Other graphs return to saved idle/zero amount and must recover the original baseline. Two fresh takes must have identical full native traces.

The fixed camera has position(100,-40), zoom(3,3). The invisible saved Node2D target receives only a cyan display polygon child. A stationary floor/grid and origin ghost provide a reference. Captions explicitly identify display-only geometry; its transform inherits the saved animated target. No display proxy determines the checked position or rotation.

## Native expectations

At the played checkpoint, moving graphs must produce lateral motion, the state machine must be in walk, OneShot must lift the target at least20 units, and Add2 must produce at least0.05 radians. The1D blend scenes must show native walk/run positive segment velocities100/200 units/s within0.01, excluding the parameter-switch sample and loop-wrap jumps. This avoids judging an arbitrary looping endpoint as distance. A fresh neutral initial pose, native return to idle where supported, and repeat-take equality are mandatory.

## Validation at this increment

Godot4.7.2 check-only passes. Headless saved-scene native proof passes42 runs (seven operations × two takes ×30/60/120FPS), with zero engine errors. The no-effect control fails all36 moving-operation runs while the six wire neutral-hold runs correctly pass. Competing-player control fails all42 ownership checks. A wrong saved-scene hash refuses the six affected loads; all36 unaffected runs pass. Original source and copied scene hashes remain exact. Three pure Python controls pass for exact copying/immutable output, changed preserved hashes and refused external dependencies.

Private evidence is under the isolated worktree's `private-graph-media-r001` and `private-graph-media-controls-r002`. Initial attempts are retained: creating scenes too early in SceneTree initialization produced inert output; deferring execution fixed initialization. The first checkpoint scheme assumed arbitrary looping endpoints and a neutral state-machine tail; saved sync/automatic-transition behavior disproved those assumptions. The final method uses actual segment velocity and honest fresh-instance reset semantics. GPU rendering, full media decoding, independent image/temporal assessment and candidate-source linkage remain root qualification steps. Historical saved scenes establish representative operation effects; they do not prove current candidate public writes.


Movie Maker viewport guard: the renderer uses1920x1080 `CONTENT_SCALE_MODE_VIEWPORT` with aspect KEEP, independent of desktop-clamped physical window bounds. Every rendered process frame checks both root texture and logical visible rectangle dimensions; a mismatch is fatal. Reports record physical, logical and render texture sizes. Root must still inspect actual encoded/PNG dimensions after scheduled GPU capture; no viewport correctness is inferred from native-only tests.
