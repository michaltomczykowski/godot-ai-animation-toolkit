# Complete saved-effect capture

The comparison layout occupies 1400×800 logical pixels. The renderer sets the
root Window's `content_scale_size` to that size, selects
`CONTENT_SCALE_MODE_VIEWPORT` and `CONTENT_SCALE_ASPECT_KEEP`, and requests a
matching physical window. A smaller desktop may clamp the physical window;
the complete layout still renders at the fixed logical resolution and scales
to fit the display. This follows the [Godot Window content scaling contract](https://docs.godotengine.org/en/stable/classes/class_window.html#enum-window-contentscalemode).

Each native process frame checks the actual root texture size and rejects a
logical/render extent other than 1400×800. The receipt records logical,
render and physical window dimensions plus scaling mode/aspect. The physical
window may be smaller; the render texture and every captured PNG may not.

Run `tools/check_saved_effects.py` with the existing arguments plus
`--frames-dir <actual Movie Maker PNG folder>`. It verifies the expected frame
count and every PNG's IHDR dimensions, in addition to all existing semantic,
clock, engine-error and visibility checks. This dimension check does not
replace image decoding, encoder preflight or continuous visual assessment.
Earlier 1152×648 cropped attempts remain failed evidence. Regenerate a plan
with the new renderer hash, then make a fresh capture; do not relabel old PNGs.
