# Four saved motion movies: independent temporal assessment

27 October 2026. **Accept the four exact films for scoped technical temporal
coverage.** No blocking visible defect was found in the reviewed observations.
`human_approved` and `release_approved` remain false.

Private immutable assessment:
`E:/GodotAI-toolkit-release-2.0.0/20261014/motion-representatives-assessment-r003/review/assessment.json`

SHA256 `9cd9efe81da333d503e4d9fa96d3c93167941c7c11b68dc8ed8a0478312ba9a0`.
The original extraction manifest is unchanged, SHA256
`e97d01b0d083eb34ca10050c7b9cc3b9582409e8d7860552dabca257a1283eee`.
`review/verification.json` SHA256 is
`0743eb63393ab5b55f42964fd85cfe023e4b0e209d9b983da0673d85a78fe77f`.

## Reviewed evidence

All 66 ordered sheets were viewed: 520 observations decoded from the actual
encoded movies, both simultaneous front/side cameras, all four rigs and every
recorded take and endpoint. Nine decoded PNGs were additionally inspected at
their original 1920x1080 resolution. Each movie is 1,440 frames / 24 s / 60 FPS.

| Movie under `motion-representatives-r005` | SHA256 | Scoped result |
| --- | --- | --- |
| `right-clean-r001/strafe-candidate-r001-right-responsive-clean.mp4` | `bb6fb2fb1411cd47054b80c8410954fa02dcbf1fecf45378006669d2f7886244` | Accept |
| `right-diagnostic-r001/strafe-candidate-r001-right-responsive-diagnostic.mp4` | `1c4a6a12999783c250227a101d8e9cfb3c4f12646480d75cdc65e8e740bb6b9e` | Accept |
| `jump-clean-r001/jump-candidate-r002-stationary-responsive-clean.mp4` | `f249487ccd260ddd8bfb52ec438c3220b2f617136b8d65f14bc97824cfe77a22` | Accept |
| `jump-diagnostic-r001/jump-candidate-r002-stationary-responsive-diagnostic.mp4` | `1a3a7dd20444ebce605fc11072f86f92dbde41bfbd422dfc94e0d7a81ca94e19` | Accept |

Read-only byte verification covered 6,422 unique files, including all four
movies/executions, capture bindings, original/copied routes, scenes, helpers,
models/imports, 5,760 original capture PNGs, 520 decoded review PNGs and 66 sheets.
Existing strict validators rechecked all 2,880 frame/view witnesses per film and
24 Player/Tree 30/60/120 native runs plus ten admission controls per operation.
Clean/diagnostic native poses and clocks match at all 2,880 rows per pair. Jump
take2 matches take1 pose/origin at every 180-frame phase in both views, for all
four rigs. These numerical checks support, rather than substitute for, the
authored visual findings in the JSON.

## Findings and boundaries

Jump shows anticipation, a visible airborne arc, landing compression and recovery
in both fresh three-second takes for dummy, XBot, short and tall Z-up rigs. The
short rig returns sooner and the tall rig later, consistently across the two
takes. Body, hands and feet remain framed; no accumulated reset offset or mesh
collapse was observed. `JUMP 0.00m` labels horizontal distance, not height; the
bound native dummy 60 FPS apex is about 0.4698 m.

Strafe shows repeated open/gather side steps, changing support, modest hip/knee
weight and sustained anatomical-right travel against the fixed front grid. No
visible leg crossing, pole reversal, loss of framing or abrupt body collapse was
observed. **Each strafe rig has one continuous six-second take. A claim of two
fresh strafe takes is not supported by these films.**

This is ordered sampled review, not an uninterrupted human full-speed watch or
inspection of every encoded frame. Root's full decode/extraction receipts were
byte-bound; the worker did not rerun FFmpeg. Side-view foot overlap and synthetic
pointed feet limit sole/contact interpretation. The restrained technical motion
does not establish polished acting or shoe collision. Private XBot media stays
local; no model/frame/movie bytes are committed or uploaded.

Capture source `cb70cab8a2f3d8a3f39207b119a257e3433a8e42` remains separate from
the original strafe producer `44089be24168f2387f00544aacc7776d46a6b8e4` and jump
producer `f5da034ba49964e4855945398ef388fe1032d3b2`. Other profiles, directions,
parameters, generation and platform qualification are outside this assessment.
Failed extraction attempts r001/r002 remain preserved; only r003 is assessed.
