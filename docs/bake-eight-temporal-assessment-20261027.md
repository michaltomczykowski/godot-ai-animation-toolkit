# Saved bake eight-case film: independent temporal assessment

27 October 2026. Accept the exact film below for **technical, unskinned
source-versus-redo coverage** of its eight cases. No blocking visible defect was
found. This is an independent sampled temporal assessment, not human or release
approval, natural character motion assessment, or skin assessment.

The immutable private record is
`E:/GodotAI-toolkit-release-2.0.0/20261014/bake-eight-video-assessment-r001/review/assessment.json`,
SHA256 `fd63284c9b07c2622f27115e0cc9d7c34f64f2d34836a0f0657cd314e396b2ad`.
It records `human_approved=false`, `release_approved=false` and
`full_speed_watch_performed=false`.

## Exact evidence and method

Film: `bake-eight-pair-media-r001/saved-bake-eight-source-redo.mp4`, SHA256
`d1a8f1d05cb480a485b51489f03aea2aa9dc768562a546cab95cc765e548a658`:
2,808 frames / 46.8 s / 1920x1080 / 60 FPS. Public producer
`b5928a083b40dffa5e8d90969907a6bd8bd2464f` and capture source
`b5c4c945db45f8632a9c4765d6acfb6a7257e423` remain separate identities.

All 27 ordered contact sheets were inspected: all 214 actual encoded-video
decoded observations, both fixed views, source and redo, and both fresh takes
for every case. Eight decoded PNGs were also inspected at original resolution,
one per case. Endpoints and event changes are included. This worker launched no
engine, renderer, decoder or media composer.

The read-only input verification checked 4,277 unique files and recomputed the
existing capture admission. All 776 render samples exactly join native traces;
all 16 source/redo comparisons and 16 fresh-take checks pass their original
position/rotation/scale limits. The maximum errors are 5.37e-7 m, 9.09e-7 rad
and 2.39e-7 respectively. The movie, frozen inputs, native/render PNGs, paired
PNGs, presentation frames, extracted PNGs, sheets, receipts and full-decode log
are hash-bound. The decoder's final counters are 2,808 frames and 46.8 s.

| Private record | SHA256 |
| --- | --- |
| extraction `manifest.json` | `eba22b72f1dac7a5055829c5e1bb81399dada6e0044706082966504f8188c665` |
| `review/verification.json` | `a9c2ad6d9c58330b3139eea6537c98ec2a85ded151ffa7217c5dc325c1c0e05e` |
| media `media.json` | `1bb36d508c057ca55d3ed5e3520bffed94d7f3ef2cf1a7f8336fc6ca50457f0d` |

## Findings

| Case | Observed result in both views and takes |
| --- | --- |
| `graph_state_60` | Initial pose, travel event, response and endpoint agree. |
| `graph_oneshot_60` | Event response and return agree. The sharp transient at native 0.116667 s is shared by source and redo in both takes. |
| `modifier_spring_1_60` | Connected chain, bends, per-bone axes and endpoints agree; no broken connection or clipping. |
| `modifier_ordered_spring_look_1_60` | Coherent connected chain and small changes agree through the endpoint. |
| `modifier_retarget_1_60` | Both complete chains remain visible; their relative placement, bends and axes agree. |
| `root_preserve_true_true_true_60` | Translation and endpoints agree and stay framed; small axes remain readable at full resolution. |
| `root_pose_only_true_true_true_60` | Both sides remain spatially steady, without observed drift. |
| `root_apply_true_true_true_60` | Translation agrees without doubled or one-sided displacement; fresh starts and endpoints agree. |

Each evaluated native sample repeats for six presentation frames; the final
sample holds for 30 extra frames, without simulation advances. Native intervals
can be unequal near events. This paced comparison does not establish natural
real-time motion. Every graph/modifier native sample was observed; root cases
use selected indices including both endpoints. Hold tails were not separately
watched in full. A sampled review cannot exclude every single-frame artifact.
Camera scale differs between cases; apparent size is not an inter-case measure.

The original render-r002 `execution.json` remains **failed**, SHA256
`5a0f0ffec02880ff0d2504f8355301a4dd4da56d0840d7549948c4ec0f7758ff`:
Python postprocessing called `read_bytes` on a string. Existing read-only
`admit()` verifies actual child exit 0, cleanup, logs, frozen inputs and native
traces; it does not relabel that original failure. The earlier wrong-axis
render-r001 rejection also remains preserved. Neither failure is visual approval.
