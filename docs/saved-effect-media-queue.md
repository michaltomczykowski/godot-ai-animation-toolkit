# Serial saved-effect media queue

`tools/saved_effect_media_queue.py` consumes the immutable JSON emitted by
`tools/plan_saved_effects.py`. It verifies every planned tool, source scene and
resource hash before starting and before each case. No generation or MCP calls
occur. Only one case captures, encodes and decodes at a time.

Example (private paths are supplied locally):

```powershell
python tools/saved_effect_media_queue.py --plan PLAN.json --project PROJECT `
  --output NEW_QUEUE_ROOT --godot GODOT --ffmpeg FFMPEG --ffprobe FFPROBE `
  --reuse 3=EXACT_CAPTURE_CASE03 --reuse 15=EXACT_CAPTURE_CASE15
```

Reuse is explicit. Existing captures must identify the exact plan hash, saved
dependencies and successful startup cleanup; actual complete PNGs are decoded
and checked at 1400×800, logs are checked for engine/script errors, and the
current strict saved-effect checker reruns. An older plan with a changed
renderer or dependency is refused, even if its earlier observations passed.
Thus plan-r005 captures remain historical evidence when an audio repair creates
plan-r006; they are not relabeled as exact-plan-r006 captures.

Fresh captures use `movie_capture_startup.py` for the owned startup override.
An fsynced queue checkpoint identifies each stage/command before launch. Failed
outputs, logs and error details remain in place and stop the entire queue.
Use a fresh output root for a failed retry, with explicit valid capture reuse.
An exclusive queue lock prevents concurrent users of the same output root; the
startup override independently prevents concurrent captures in the same project.
A crash-preserved lock requires inspection before manual recovery.

Encoding preserves source PNGs and the actual `frame.wav` for audio-required
cases. Only that captured WAV is muxed; no synthetic soundtrack is supplied.
Other cases have no audio stream. Every MP4 is fully decoded independently with
strict decoder error handling; decoded frame count/duration and independently
probed dimensions/FPS/audio ownership must match. Complete media receipts bind
all frame hashes, native report/checks, logs, startup receipt, actual WAV hash,
producer dependencies, encode/decode commands and output hash. Completed media
can be resumed only with identical identities, and is decoded again on reuse.

Media completion keeps visual, audio-output review and qualification pending.
A WAV's existence or an audio-playing flag does not prove nonzero PCM or correct
audible output; the native audio checker and independent listening remain gates.
