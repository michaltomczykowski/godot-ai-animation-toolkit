# Complete setup replay and recording cleanup, 24 October 2026

## Setup: complete numerical replay

All 30 groups and 1,800 saved native plays pass on Godot 4.7.2 official
ed1daf0bf at native checker checkpoint `54744b1`. This covers five styles,
three extraction/controller/jump variants, with and without optional turn,
four rigs and 30/60/120 FPS. The exact preserved public outputs retain source
`233562a`; all 613 production dependency hashes match. No regeneration occurred.

Private evidence: `setup/native-matrix-r009/execution.json` and
`independent-validation.json` under the local release evidence directory. The
independent validator checks report/log/manifest/script hashes, exact identities,
all original contact/endpoint/ownership bounds, final modifier signals and
unreachable diagnostics. Its first attempt confused the report's public manifest
source with the separately recorded native checker source; that failed validator
and correction are retained. The native reports themselves all pass unchanged.

| Maximum across all plays | Observed |
| --- | ---: |
| Endpoint error | 0.00000190735 m |
| Stance slide | 0.00000101504 m |
| Ground penetration | 0.00000163913 m |
| Contact height error | 0.00000095368 m |
| Idle recovery position | 0.000668936 m |
| Idle recovery rotation | 0.000659314 rad |
| Competing owner displacement | 0 m |

No knee flips, nonfinite poses, unreachable solves or engine errors. These are
native numerical playback results, not a new artistic or sole collision approval.
Private X Bot data remains local.

## Saved graph/rig admission

At the same checkpoint, all 42 graph and 54 rig native positive plays pass.
Inert/no-effect, competing writer and changed scene-hash controls are rejected
as expected. All original saved scenes retain their exact hashes. The initial
four-frame GPU startup probe passes actual 1920x1080/NVIDIA OpenGL checks.

The full graph capture then correctly fails strict frame admission: 1,681 PNGs
instead of 1,680, with a blank terminal object after cleanup. Failed capture
`saved-media-candidate-r002/recording-r001` is retained; no frames were removed
or admitted into a successful video.

## Recording lifecycle correction

Godot's [main loop](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/main/main.cpp#L4689)
samples SceneTree termination during process, draws, then writes the movie frame.
Signalling quit only after drawing is too late to prevent another iteration.
Both saved renderers now signal quit during the final accepted process tick,
retain geometry through its draw, then collect the non-movie end-boundary
observation and clean up from `frame_post_draw`. Final assertion failures still
set the nonzero exit code. Animation keys, clocks and measurement bounds stay
unchanged.

A separate minimal actual GPU control reproduces four frames with a blank tail
for post-draw-only quit, versus exactly three frames retaining the final cyan
object for process-time quit plus post-draw cleanup. Evidence:
`movie-terminal-controls-r001/validation.json`. Earlier reduced-rate diagnostic
attempts remain preserved separately; they do not qualify the normal 60 FPS
capture. Full graph/rig capture and independent review remain next.

## Other CI findings

Candidate CI `40071944104` exposes two separate issues. Clean ZIP import could
activate the core before the harness starts its owned backend; import now removes
the inherited headless opt-in. Four process/environment controls pass and fresh
actual CI is required. The Linux preview native allocator abort remains unresolved;
an optional GDB path preserves the real save/rig route for diagnosis. See
`clean-zip-import-ownership-20261024.md` and
`linux-preview-native-abort-20261024.md`. No release is approved by this checkpoint.
