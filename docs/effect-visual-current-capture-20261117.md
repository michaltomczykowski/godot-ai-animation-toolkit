# Current public effect recording checkpoint

## Completed batch and sampled visual review

All **47 of 47** pre-draw captures now have native playback receipts and
720-frame, 12-second full decodes. The combined receipt follows the
preserved six-case prefix into the resumed 41-case queue. It verifies
every MP4 and native report against the same original plan and case order.
The two corrected pilots also pass, for 49 representatives of 47 operations.

The overview samples from both takes of every video were reviewed. The
clips show the expected changed behavior, or intentionally preserve their
reference behavior for edits such as resample, cleanup, and reduce. The
nearest-interpolation representative holds the initial value because its
only other key sits at the loop boundary. Its reference moves and the
native trace verifies the interpolation and hold. The audio cue also
passes checks on the native WAV and on audio decoded from the final MP4.

Two pairs needed clearer presentation. Stagger's saved controls overlap.
Separately spaced display markers show a 12-frame (0.2 s) fade delay in
both takes. Retarget's original and destination use identical geometry.
Colored display markers show the original moving in undo and the
destination moving in redo. The observed displacement agrees with the
native trace within 0.34 px. Both follow-ups use the original saved
scene bytes and tracks, and each video passes full decode.

| Private receipt | SHA-256 |
| --- | --- |
| `effect-predraw-remaining-resume-r003/combined-capture-binding-r001.json` | `a1233d3218d891dc17c01cd1634d8c13447c57a4e623e8ac0b81fe625013d1ac` |
| `effect-review-notes-through46-r001.json` (initial presentation) | `951895bbee4563dd3ebd04e0b669df1636b8da3bd59976e43829c38dbb62272d` |
| `effect-stagger-visibility-r001/decoded-stagger-delay-r001.json` | `1e6fd00a6a5b2cb9d71f3ad37a17f564085d6524d2bca55213a0a850a9318cf1` |
| `effect-retarget-visibility-r001/decoded-retarget-ownership-r001.json` | `b24d927c59b39838709736098945e82dd25d6b7bb347cb7e5471da4eb6dbbd8a` |

These are sampled visual findings bound to the full recorded clips. The
independent release assessment and final audit receipt are still required.
The current effect batch targets 47 of 82 visual operation bindings. The
other 35 lie in graph, preview, motion, rig, modifier, and sequence work.

## Resume after Windows checkpoint contention

The 47-case queue completed and fully decoded six videos. Case 06 also
captured all 720 frames and removed its owned viewport override. Windows
denied the atomic checkpoint replacement before encoding case 06.
The queue now uses the shared durable JSON writer, which retries bounded
Windows sharing violations. `--resume-from` starts a fresh output,
revalidates the completed prefix against the same plan, and preserves the
original case indices and evidence. The temporal review planner can read
the resumed entries, including native observations from a reused capture.

Read `effect-predraw-remaining-resume-r003/queue.json` for the final
status. It revalidated the six original receipts and encoded and decoded
the saved case 06 without rerendering. The original failed checkpoint and
all source frames are retained under `effect-predraw-remaining-r002`.

The first four corrected videos yielded 230 selected decoded frames.
Both takes' overview samples show the shake offset and recovery, the zoom
accent and settling grid, the hit flash contrast and restoration, and the
typewriter reset and progressive reveal. These are observations from
encoded frames. Full temporal review and the operation audit remain open.

## Viewport pre-draw observation

The reset-aligned batch reached 17 completed cases. Decoded comparisons
showed that SpriteFrames still advanced during the nodes' idle processing
after the SceneTree sample. The old sprite report disagrees with the
actual captured image at 144 of 720 frame indices, including frames 4,
359, and 719. Stop receipt:
`effect-reset-aligned-remaining-r001/capture-stopped-for-predraw-alignment.json`.
The old batch was stopped after the owned override was removed; prior
recordings and the just-captured case remain diagnostic evidence.

The renderer now observes via [RenderingServer.frame_pre_draw](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html#class-renderingserver-signal-frame-pre-draw),
after node processing and before viewport update. It keeps a static
in-video heading and stores exact frame/state alignment in the receipt.
The first probe logged 721 frames because requesting exit from pre-draw
was too late for Movie Maker. That failure is preserved. The correction
requests exit from SceneTree on the final iteration while still sampling
and drawing that iteration.

Fresh `effect-predraw-probe-r002` damage bar and SpriteFrames each pass
720-frame capture and full decode. The independent palette oracle maps a
pixel from each source PNG and decoded MP4 frame to its saved sprite
cell: 144 mismatches for the prior renderer, **zero across all 720
corrected frames**. Proof SHA-256:
`2b7a129a6938732d28b32c504cc3bbb55473bdd0e277add72b0db4c5f0ff4a35`.
The generator and original saved outputs were unchanged.

The new 47-case queue is `effect-predraw-remaining-r002`, with
`capture-plan-predraw-remaining-r002.json` from
`effect-public-a0acf2d-r002`. Both strict observation flags are enabled.
The renderer source for these captures is `014f362`. Read its queue
checkpoint before starting another renderer. Image review remains separate.

The mid-stage review has 698 decoded frames for 12 operations. It is
retained as review/diagnosis of the old capture path. Separately, the
start-of-take audio cue passes both raw PCM and audio decoded from the
previous batch's actual MP4, at 0.020 s and 6.025 s. The first decoded WAV
format was WAVE_FORMAT_EXTENSIBLE and rejected by Python 3.11's built-in
parser; the saved 16-bit PCM decode passes unchanged waveform, timing,
duration, sound-level and clipping limits. No listening approval claimed.
Receipts: `case12/audio-native-verify-r001.json` and
`case12/audio-decoded-verify-r002.json` in the reset-aligned queue.

Latest archived CI preview checkout `a8c3157`: both ordinary Linux
preview bundles pass the exact dependency gate and both postmortem jobs
report no crash. That does not close the intermittent native abort.

Private `linux-doc-queue-source-control-r001` contains a synchronization
experiment against exact Godot source `ed1daf0bf001b61586d9930840f2f1394092c079`.
Its queue lock covers pending document add/remove mutations, reset, drain,
and readiness publication. Script loads, documentation retrieval and
thread joins run outside the lock. The patch applies cleanly. Compiler
and runtime results remain pending under the separate engine identity.
Patch SHA-256:
`0378c9c898b32606d19547cd076a63b2800763ac4ff3c7e74fb0f7a717c71001`.

[Paired Linux run 44126929152](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/44126929152)
builds the exact same engine revision before and after applying the patch,
then exercises the public preview in separate cold-start projects. It is
outside the repair branch and leaves the official binary gate intact.
[Official Linux CI run 44121185902](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/44121185902)
passed clean install on both cores and enable orders. The extracted ZIP,
source and log hashes matched. The allocation checks returned in
3.84–4.39 seconds without reproducing the earlier timeout.

## Corrected take boundary

The ordered review of the first five clips found a one-frame mismatch in
the old Movie Maker renderer. On zero-based frame 360, the damage bar
video had already reset to 80%, while the native row and caption still
described the prior 30% hold. The progress bar showed the same mismatch.
The callback sampled and captioned the current take, then rebuilt the
clones before Movie Maker drew that frame.

Commit `2de9823` resets the clones at an integer frame boundary before
sampling and drawing the new take. The checker requires the explicit reset
metadata and exact first/second take frame counts for new capture plans.
The review planner marks older traces as having an unbound reset frame.
Seventeen focused unit controls pass.

The old queue was stopped after the owned viewport override was cleaned
up; nine encoded cases and one unfinished case are retained with a stop
receipt. Corrected damage/progress bar probes each pass 720-frame capture
and full 12-second decode. The actual decoded body is held at frame 359
and reset at frame 360, matching the fixed trace. The old and new videos
were each checked against independent baseline/held image observations.
Verification SHA-256:
`8c938d07aff46843c5314a3c96e8513213835e78d6fb4c23f0637cd555c1742c`.

The replacement queue is `effect-reset-aligned-remaining-r001` with
47 additional cases. Its plan under `effect-public-a0acf2d-r002` is
`capture-plan-reset-aligned-remaining-r001.json`, SHA-256
`3a67c982d02001a2a19ef0410b3101c79fe8181d64121104f6c6d1e026461967`.
The saved producer remains `a0acf2d`; only the capture source changed.
Use the replacement queue for review. The old files below are diagnostic
history and have not been overwritten.

## Original intake and pilot

The exact audited checkout `a0acf2d26449cefb8e8e831bfd8248d048604a26`
ran the actual Godot AI 4.2.1 editor route in a fresh isolated Windows project
on Godot 4.7.2. Edit, FX, and preset/library history passed. The first attempt
retains both passing editor suites and a driver-side error: the FX expectation
is a set, whereas the shared suite verifier takes a count map. Fresh attempt
`effect-public-a0acf2d-r002` uses the matching name/count contract and exits
after all three suites and strict collection succeed.

The intake joins each saved undo/redo file to its history event, its outer
public test run and its forced persistence checks. It hashes every scene and
referenced asset and binds the capture tools. All 49 representatives for
47 operations were admitted without missing or ambiguous cases. No source
fixture or interactive editor was modified.

| Private receipt | SHA-256 |
| --- | --- |
| Fresh operation report | `850bc8953c5944762d23dc3d9d3f134946066c3e55c5fc1da0efabfc7977f50f` |
| Fresh 49-case plan | `020951f270bdc158105ecc47f64442f212bb6dd4f3e571150d192f15c5261ba4` |
| Two-case pilot queue | `282c84ea92c78608c8db61f2ed6f1edf7aed941b7cb8d994e86847a813d38b9d` |
| Pilot ordered decode manifest | `fe823210770f43dDBa554fe255e868f19bab988643957d986a3f7bddf36ea0f` |
| Remaining 47-case plan | `099b6f0481bb4220e3434fd91fa1b3546542e7290ca3bf82ef81a2b89f91f77d` |

The two pilot films (hit flash and reverse) each pass native observation,
720 frame validation and full 12-second decode. Twenty-four ordered samples
from the encoded copies show the hit flash contrast and restoration and the
opposing directions of the reverse comparison in both takes. This is a
technical first look, not independent review or release qualification.

The other 47 recordings run serially in private
`effect-exact-remaining-a0acf2d-r001`. Read its `queue.json` before launching
another Godot or FFmpeg job. Preserve any failed case and its complete logs.
Do not treat a passing native/encode run as a visual pass.

For possible archival reuse, 21 older clip edit captures covering 20
operations also passed read-only admission. Their scenes are self-contained;
the historical renderer is found at exact Git bytes; all 15,120 original
frame hashes, startup logs, native witnesses and retained movies match.
Private `edit-visual-capture-admission-r001.json` SHA-256
`f60ad2afcf8b4fc3fc4e8e13995daffa00e9c05d8e782804f27f4885cdf2c44d`.
Old/new serialized scene pairs still differ. These archive checks do not
promote the old recordings into current evidence.

Official Godot source records the documentation-load benchmark after
loader join and postponed queue processing. The engine dumps the benchmark
only in startup/shutdown, however. A running editor cannot use it as a
reliable readiness barrier. The earlier Linux abort remains unresolved.
No merge, tag, publication or confirmation prompt before qualification.
