# Remaining sequence, secondary and static media: bounded handoff

27 October 2026. Offline inventory/staging only. Candidate reference is
`cb70cab8a2f3d8a3f39207b119a257e3433a8e42`; historical producers below retain
their identities. No engine, media decoder, renderer or visual assessment was
run for this handoff. This does not complete Phase4 or qualify current generation.

The operation map is `docs/operation-media-coverage.json`, not a `.md` file.
The old media audit/plan predates the full sequence footage and later static
assessments. Within this assigned scope, the remaining rows are:

| Operation | Existing evidence | Bounded remaining work |
| --- | --- | --- |
| `animation_sequence.compose` | Complete clean and diagnostic 88 s movies, four saved rigs, two fresh takes each, original 24 native Player/Tree/FPS checks | Reuse after saved-input admission, full decode and independent ordered assessment. No new default capture. |
| `animation_motion.secondary_motion` | Persisted synthetic source/reference/do/undo/redo pair; old 316-frame composite is partial | Admit and capture `secondary_branches_local_60`: two fresh 6 s takes, 720 frames total at 60 FPS. |
| `animation_rig.rig_chain` | Actual public 3D create/append requests, independent effect/history checks and exact saved before/after snapshots | Admit and capture `3d_local_create` and `3d_local_append`: two fresh 4 s takes each, 480 frames/case at 60 FPS. |

Thus the minimum new queue is **three cases / 1,680 frames / 28 s**. Inline-pose
and rooted technical sequence cases are staged as optional variant inputs;
they do not silently expand that queue. Motion representative and bake captures
are owned by root and outside this inventory.

## Executable staging and receipts

`tools/prepare_remaining_sequence_static_media.py` is an exclusive-output,
offline stager. It verifies preserved archive/receipt/movie bytes, exact selected
case IDs, original public chain joins, full sequence native clock coverage and
recorded take/decode schedule. It copies only self-contained synthetic resources.
Its manifest records source Git blobs separately from current working-file SHA256
and records original rows separately from changed replay locator paths.

The actual completed stage is:

`E:/GodotAI-toolkit-release-2.0.0/20261014/sequence-secondary-static-inputs-r001/manifest.json`

SHA256 `21a299f359d98a5fb2b5ec1ab88af31a57f9e13f59ceee548e2e02f7ea2de864`.
It contains 16 `.tscn` and three `.tres` copies, no FBX or movie copies. It is an
input manifest with pending admissions, not an accepted legacy renderer input.

After integration, reproduce into a **new** directory from the primary repo:

```powershell
& 'G:/godot-ai-dev/godot-ai-v4-animation/.venv/Scripts/python.exe' tools/prepare_remaining_sequence_static_media.py --repo 'G:/godot-ai-dev/godot-ai-animation-toolkit' --output 'E:/GodotAI-toolkit-release-2.0.0/20261014/sequence-secondary-static-inputs-r002'
```

Tests, from `tools`:

```powershell
& 'G:/godot-ai-dev/godot-ai-v4-animation/.venv/Scripts/python.exe' -m unittest -v test_prepare_remaining_sequence_static_media
```

Five controls pass, including actual preserved staging and rejection of changed
bytes, duplicate IDs/clocks, native failure hidden by aggregate pass, wrong movie
route/decode/take schedule, external/skinned resources, traversal and overwrite.
Private evidence tests skip when the historical archive is unavailable.

## Full sequence footage: reuse inputs and exact limits

Base: `F:/GODOTAITESTING/toolkit_repair_snapshot_2026-09-30/release_r2_start_stop_body_20261013/closure-r002`.
The `sequence-recording-r003` producer is
`10941ba81c367fe0c753ff9086fb826d3136bbec`.

| Preserved item | SHA256 |
| --- | --- |
| `sequence-recording-r003/route.json` | `1e96b7aceabde750c3df09f1d6128fec48c159184c3ac57b9bea7febdb423bfe` |
| `sequence-recording-r003/native-check.json` | `ea2d2132ffcbda136ab6fd5c8a87c4632bf91560d4788fd1e8fbc90edad329e6` |
| `sequence-recording-r003/media.json` | `be0f33544348b8f652aeefd937fab0397995a79fb57d68fc296573d81907eb21` |
| `sequence-recording-r003/start-stop-body-sequence-r002-clean.mp4` | `24f587f9cd11f79bab37564a5cacc781d983c71fec65184dbddcd97cac27eb46` |
| `sequence-recording-r003/start-stop-body-sequence-r002-diagnostic.mp4` | `d02d172ba9e4c7520754019f9afd89c1461e4db019d9ac4ce7ef6bf1eb70029f` |
| `candidate-r002/native-scenes-and-local-rigs.zip` | `80c4330c884c42bc7e06bb5fab01fe8fd4a48717c559f9f65f4a145aaa53a6b2` |
| `candidate-r002/phase-receipts.zip` | `a607db48c6a649b0e40fb903708828226368015220d74d26aada2f58fda91a66` |

Each movie is recorded as 5,280 frames, 88 s, 60 FPS, 1920x1080. All 5,280
source PNGs currently exist for each mode. Each rig occupies 1,320 frames with
two 660-frame takes, front and side together: dummy 0–1319, XBot 1320–2639,
short 2640–3959, zup_tall 3960–5279. XBot is private: retain the movies and
assets locally, including its 22–44 s segment.

The four saved scenes are exact archive members under
`project/repair_transition_sequence/1f2b266250884903841a30442228ee41/`.
The manifest carries every scene hash. Dummy is
`6ed78577d4e58662b07ae62802530dc7513454cf52b7c6b8ece09ea06b1025d2`.
The original project also exists under
`G:/godot-ai-dev/godot-ai-animation-toolkit/test_project/repair_r1_validation_20261010`;
the current E: validation project lacks those scene paths. Use the archive bytes
and bind their original local model/import dependencies before any replay.

`check_transition_sequence_review.gd` already reads saved source clips and checks
contact, pose and root behavior, but hardcodes four rigs / 24 clocks. Retain those
checks for admission. Record exact checker/helpers/scene/model identities and
zero errors in the copied replay project. Then root must full-decode the current
movie bytes and provide ordered actual-video frames, including both resets,
endpoints and all four rig spans, for independent review. Historical recorded
decode counts and existing PNG counts are not fresh decode or visual approval.
Recapture only for a concrete failed admission or visible defect.

## Secondary and optional technical pairs

Base: `F:/GODOTAITESTING/toolkit_repair_snapshot_2026-09-30/motion_sequence_history_20261008`.
Producer is `751370894a2959ade6278ad972623e45813aa066`.
`final-native-scenes.zip` SHA256 is
`a4acf84f79bc21346ce387c8477b449fa0b227c17f75ba163dd45df0a71c6002`.
The stage retains exact original manifest rows and all five resource hashes per
selected case. `secondary_branches_local_60` uses native hand_L/hand_R spring
branches, stiffness 120/damping 12, one-second existing animation and 60 samples.
Its do/redo SHA256 is
`fe5a73c283ba2632ed5ee1b63369fd2acb5cba1d0e82045eff68ce5285d3ea3f`;
persisted reference is
`5b29cf29133c62156daaee3c0842476bf026e1cb4345f57b03d4d11a86068c99`.

The old `media/motion_sequence_history.mp4` is only 316 frames / 5.2667 s
(`98903e880e29e8a32b40ffe06191fdfaf65f5e0fa8d2b6ae1b14636b5c28eaeb`).
It is partial technical evidence with floor occlusion, never full approval.

Before recording, narrowly adapt `render_motion_sequence_history.gd` to consume
the staged existing resources. Its legacy `Reference.build` replaces the
reference-side animation library and is unsuitable for immutable saved replay.
Load the persisted `.tres`; retain every existing native channel/root predicate,
one clock/writer owner, a complete finite action followed by held endpoint, fresh
reset before each take, full body and header framing. The legacy checker also
hardcodes the full 273-case manifest; do not invoke it as a three-case checker
without an explicit bounded selector. No new clip/reference generation is needed.

## Static chain pairs

Base: `E:/GodotAI-toolkit-release-2.0.0/20261014/setup-public-history-witness-r002`.
Producer is `3d91adef459558f28a76b9537dfb4b6b5205d9bd`; operation-context SHA256
is `51cbda30de52942905ff13ddcc9a30ca128e82dc09a6e53231a01974617c0c63`.
The stager re-verifies all seven existing public/history/effect checks and copies
the exact `persist_undo` / `persist_redo` bytes from this receipt's private
`appdata/Godot/app_userdata/Toolkit R2 Turn Validation` directory. Default roaming
userdata has since changed and is not the historical source.

| Case | Before SHA256 | After SHA256 |
| --- | --- | --- |
| `3d_local_create` | `bb67f30ced39127f6155e09fb09b159bf1f8892765c73d19d9595b7ed7a9cd43` | `889343e7c5c7e894a3f566618deeb09430bb88ad448e403617cbb98d0e4c9beb` |
| `3d_local_append` | `434fb75c2317be6eb4721f929babe13d52f1aefff11d976bbfb16a5eb4436b0e` | `63e245a6067839a1aee4cb0e473a705e45269388cb91b0dafe01faebf79dac0e` |

The manifest retains raw event path/hash/ID, fixed request, actual native snapshot
and effect checks for both states. Render all original and new skeletons and show
the added bone/rest/parent/name/scale. Use zero animation writers, two fresh
comparisons, two seconds before and two after. No skin or animation claim follows.
`render_saved_rig_effects.gd` currently hardcodes nine other operations, constant
bone counts and pose_apply untouched-bone logic: chain topology changes require
the bound snapshot oracle, rather than that unchanged renderer.

## Source boundaries and already covered static effects

The stager discloses whole-file differences instead of calling historical scenes
current-source generation. For the full sequence, composition helpers and spec
math match; `sequence.gd` adds registry preflight. `bone_animation.gd` changed
procedural root-carrier conversion, outside the sequence commit path; preserve
the saved source clips rather than regenerate their gaits. Against earlier751,
sequence marker grouping also changed and the procedural translation tail grew
from `1/30 + .001` to `2/30 + .001`; old clips do not establish current marker or
tail behavior. Secondary's operative `motion_secondary` function and its sampler,
sandbox and driver dependencies match; whole motion/bone handler files differ.
The four selected chain production dependencies match 3d91 exactly. These are
bounded source comparisons, with current saved replay still pending.

Existing independent assessments already cover pose_apply in the 72 s / 4,320
frame rig film and inspect.preview's eight discrete Linux421/430 PNGs. See
`rig-visual-assessment-r004-r001` and
`docs/preview-static-assessment-checkpoint-20261026.md`. Existing graph7 and
modifier5 full films also remain assessed. Resource/read operations
pose_blend/save/list/rig_get retain their file/read contracts: `_blend_redo.tscn`
is pose_apply at 0.5, not an invented direct pose_blend scene operation. Optional
2D chain coverage is not claimed by these two selected 3D cases.
