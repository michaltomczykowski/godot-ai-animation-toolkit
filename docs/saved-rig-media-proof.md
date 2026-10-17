# Preserved rig native media path

This bounded path covers eight saved3D rig clips and one exact static pose_apply before/after pair. It never calls a generator, creates target keys, applies a pose, replaces a graph or evaluates live modifiers. The static pair represents the original saved Undo/Redo states, shown sequentially; it is not a newly executed pose_apply call. pose_blend remains a JSON/file effect without asserted downstream scene linkage. See `preserved-rig-media-scope.md`.

Prepare a fresh immutable manifest and byte copies:

`python tools/prepare_rig_media.py --output <new-directory>`

After root ends the low-RAM/editor generation pause, run native positive/negative controls:

`python tools/check_rig_media.py --manifest <directory>/manifest.json --project-root <project> --godot <console.exe> --output <new-controls-directory>`

Scheduled capture only:

`godot --path <project> --fixed-fps 60 --resolution 1920x1080 --write-movie <new-frame-directory>/frame.png --script res://tools/render_saved_rig_effects.gd -- <manifest.json> <new-render-report.json>`

Intended continuous movie:72s/4320 frames, nine outputs with two fresh four-second takes each. Static pose_apply shows the original before scene for2s and after scene for2s, with no interpolation between them. Clip cases preserve the saved Player speed, root_node and original clip. Every authored position/rotation/scale channel is compared with native interpolation at the actual played phase; tolerance1e-5 in the appropriate units. Unsupported tracks, extraction or modifier-bearing scenes refuse explicitly. Only one Player writes during clips; the static pair has zero writers. All competing Trees/Players are disabled. Pose_apply must change the saved pose and preserve the fixture's untouched bone. Clip cases must show native temporal change. Fresh takes must repeat exact traces and initial pose digests. Scene and clip data remain hash-bound.

The display uses clearly labeled unskinned spheres, parent lines and local-axis rods, including scale inheritance for blink channels. These are display-only geometry driven from observed native bone transforms. They do not replace skeleton data or skinned meshes and cannot establish skinned anatomical quality. A stable world grid and fixed orthographic camera per case provide spatial reference. Camera values are recorded. The1920x1080 logical viewport uses VIEWPORT/KEEP; each rendered process frame must have the exact logical and texture dimensions regardless of desktop window clamping. Physical/logical/texture sizes are reported. Independently verify actual PNG/movie dimensions and frame counts after capture; intended counts are not media proof.

Validation now: exact-source planner construction succeeded on the preserved local scenes. Three pure Python controls pass (exact immutable copies/resource applicability; changed source hash refusal; missing static-before pair refusal). Python compilation passes. Initial Godot check-only exposed one dynamic type inference, corrected; check-only then passed. Subsequent numerical/render helper refinements have not been parsed or run because root requested no additional Godot processes during low physical RAM and active public generation. All54 native positive runs, inert/competing-writer/hash controls, GPU capture, decoding and image assessment are pending. No candidate quality or image approval is claimed. Private staged inputs remain under `private-rig-media-r001` in the isolated worktree.
