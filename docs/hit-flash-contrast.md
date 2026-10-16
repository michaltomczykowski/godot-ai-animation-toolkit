# Hit flash contrast and restoration

`animation_fx.hit_flash` animates `CanvasItem.modulate`. An omitted `color`
selects a contrasting pulse from the actual baseline: RGB darker than 0.5 in
every channel pulses toward white; otherwise RGB pulses at one quarter of the
baseline. The original alpha is retained when positive. A fully transparent
baseline pulses at alpha 1, then returns to its original transparent state.
The response reports resolved `color`, restoration `base_color`, and
`color_mode` (`automatic_contrast` or `explicit`).

An explicit color retains its exact meaning. If it approximately equals the
baseline, the call returns typed `OPERATION_UNAVAILABLE` before creating a
clip/library or undo action, including dry runs. Two transparent endpoints are
also refused. Duration/count validation remains unchanged.

This replaces the inert white-on-white default; existing saved clips are
unchanged. The failed historical three-white-key capture remains failed evidence.
Regenerate through the public route and record fresh native/visual proof.

[Godot's CanvasItem modulation](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html#class-canvasitem-property-modulate)
affects the item and its children. The [canvas shader COLOR contract](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html#color-and-texture)
multiplies incoming color/modulation. A modulation pulse cannot guarantee white
emission from intrinsically black pixels, visibility through hidden ancestors,
or output from an undrawn target. No intrinsic ColorRect color, material, pose
or target transform is rewritten.

## Other defaults reviewed

Shake/wave use nonzero amplitudes, zoom punch a nonzero ratio, pendulum a nonzero
angle, dialog pop a scale excursion, typewriter 0→1, and counter 0→100. Spring,
path follow, flipbook, sprite frames and audio require caller/target resources;
their resource shape and audible/visual output still need case qualification.
Damage bar defaults from the current value to 0; progress fill defaults from
the current value to 1. Either can be numerically constant when already at its
destination. Those separate baseline-dependent contracts merit a narrow
no-change decision; this repair does not alter them or classify inert output
as a passing effect. Explicit zero spring offsets and single-cell frame ranges
also require contract-specific review rather than a family-wide disable.

Focused editor tests cover white, dark, transparent and explicit distinct
colors, native midpoint/end playback, resource save/reload, Undo/Redo, and
atomic dry/write refusal. Pure builder checks cover contrast and restoration.
Execution on the integrated candidate remains required.
