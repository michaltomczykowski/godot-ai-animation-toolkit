# Rendered preview CI

The separate `Rendered preview` workflow runs Godot 4.7.2's actual editor
under Xvfb with Mesa llvmpipe and `gl_compatibility`, for the exact released
Godot AI 4.2.1 and 4.3.0 commits. The editor command has no `--headless`.
Headless import only prepares resources before this rendered process starts.

`tools/ci_rendered_preview.py` owns an isolated backend/editor, generates a
walk on the public bundled dummy through Godot AI, then calls the public
`animation_inspect.preview` route at four distinct clip times. It requires four
320×240 PNG files, decoded nonuniform pixels and differing frames. Dry run,
missing animation and overwrite refusals must return typed errors. Dry run
must create no output, and overwrite refusal must preserve all PNG hashes.

The saved scene bytes (including live serialized skeleton poses) and complete
clip timeline must match before and after all preview/error calls. This does
not independently inspect transient player playback state or constitute visual
quality approval. No headless refusal is counted as rendered success.

Artifacts contain collector context and exact public-call traces, response
paths, PNG pixel metrics/hashes, before/after scene and timeline snapshots, and
the renderer startup log. `rendered-preview.json` schema version 1 binds its
successful `public_case_id`, `context_sha256`, operation, actual editor command,
images, restoration snapshots and logs. All referenced files reside beneath
the artifact root. The operation collector must be committed in the candidate
before running; a pending job or partial trace does not qualify the operation.
CI calls this reusable workflow on the same candidate and waits for both
released-core jobs. Main/tag gates download only artifacts from that workflow
run and verify them through the strict preview adapter, exact source SHA and
full canonical Git dependency set. No latest-workflow lookup is used. Windows
GPU proof and independent visual assessment remain separate required evidence.

Immediate serialized scene and timeline checkpoints bracket the successful
preview; additional checkpoints follow dry/missing-clip/overwrite refusals.
Each checkpoint binds its actual timeline public call ID, raw snapshots and
hashes. The complete editor log is checked after process termination, including
shutdown, and any engine or script error rejects the run.
