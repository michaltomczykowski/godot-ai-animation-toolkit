# Current public effect recording checkpoint

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
