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

Movie Maker chooses its writer dimensions before the script starts. Runtime
Window settings alone cannot repair a writer initialized at 1152×648. Launch
through `tools/movie_capture_startup.py --project PROJECT --width 1400 --height
800 --receipt NEW.json -- GODOT --path PROJECT ...`. It exclusively creates
`override.cfg` with viewport dimensions and `viewport`/`keep` stretch settings
before launching, plus a half-size physical window. An existing override is
preserved and blocks launch. The helper removes only its unchanged owned
override in `finally`; an override changed by another process is preserved and
the job fails. The receipt records command/config hashes, exit status, cleanup
and unchanged project.godot identity. Use one capture per project at a time.

The renderer refuses immediately unless effective startup ProjectSettings
match that contract. The engine's [Movie Maker resolution documentation](https://docs.godotengine.org/en/stable/tutorials/animation/creating_movies.html#rendering-at-a-higher-resolution-than-the-screen-resolution)
requires viewport stretch and startup viewport dimensions for captures larger
than the screen. The runtime extent checks and every-PNG checks remain required.

Fixed comparison framing is applied after saved Camera2D nodes are disabled,
including both newly instanced takes. Camera shake/zoom keep their native camera
presentation. Every frame records the actual canvas transform and pane bounds;
the checker independently rejects an identity/reset offset in fixed-frame cases.
The bounded header occupies y8–178; both body panes occupy y190–800, so captions
cannot cover effects. These are presentation transforms only; animated target
keys, poses and local transforms are not rewritten. Fresh pixel inspection and
continuous review remain required even when these placement checks pass.
