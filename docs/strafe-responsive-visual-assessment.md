# Responsive left strafe representative visual assessment

Independent agent recommendation: **pass for the recorded Responsive left/extracted default on the four recorded rigs**, within the sampled method below. This is not human approval. Other styles, right strafe, in-place playback, jump and setup transitions remain outside this assessment.

## Bound recordings

- Candidate clean MP4 SHA256: `b3cf9382232d850c122ce07b1543a9de6c77cfb5c3c64154402c6ce825057558` (source overlay `44089be`).
- Baseline clean MP4 SHA256: `aab743d5956f63adf8e48055bbf3975e269a9681a212999bb3c791874c30331f`.
- Private method/findings JSON SHA256: `523659fe0357a650c4ca4c345a8ca606c32883bb727b510b873db7563f2f55d9`.

The movies are the preserved `strafe/{candidate-r001,baseline-r001}/left/responsive/*clean.mp4` recordings. Private images and JSON remain locally in `toolkit-release-checkers-20261015/private-strafe-assessment-r001`; no private rig images or media are committed or uploaded.

## Actual method

Both movies independently decoded completely with ffmpeg to null: exit0,1440 frames,24.00s,1920x1080,60FPS. Eight ordered timeline grids were inspected: candidate and baseline each at8 sampled frames/s across every six-second rig segment (dummy0-6s, X Bot6-12s, short12-18s, tall Z-up18-24s),48 samples per rig/movie. Timeline labels are nominal fps-filter output times, not exact source-frame timestamps.

Larger candidate front/side crop grids were additionally inspected for every rig at exact local source frames `[0,8,15,23,30,38,45,53,60,300,330,359]`, offset by `[0,360,720,1080]` for each segment. Exact time is source frame/60. This covers each first complete cycle, the next-cycle boundary, later fifth/sixth-cycle positions and each final recorded frame. The equivalent baseline Z-up detail grid was inspected. The private receipt hashes every viewed grid and records the extraction method. Full decoding is distinct from visual inspection: this was ordered temporal sampling of actual continuous recordings, without real-time playback or an all-frame visual claim.

## Findings

The baseline Z-up arms remain held horizontally forward at shoulder level. Candidate Z-up arms are lowered beside the hips with modest phase-linked arm/wrist changes, including the later loops and23.9833s endpoint. This fixes the conspicuous baseline arm defect.

Front samples show a readable leading lateral step and trailing-foot stance recovery on all four rigs. No obvious sampled leg crossing, knee inversion, collapse, accumulating pose failure or loss of framing is visible. The torso/head stay upright with restrained sway/bob. Candidate arms stay lowered; X Bot hands remain close to the thighs without gross sampled interpenetration. Later cycles retain the same movement character and the last sampled frames remain coherent.

The movement reads as a crouched procedural side shuffle. Knees remain bent; head/torso motion is restrained and hands are open/neutral, particularly on the synthetic rigs. These are aesthetic limits, not a newly demonstrated blocker for this representative default. The videos contain no commanded stop, so only cyclic stance recovery is assessed.

Front-panel characters are considerably smaller than side-panel characters; side knees/feet overlap in projection. Crops help gross reading but cannot restore source detail. Fine finger articulation, subtle sole sliding and short transients cannot be fully judged with this method. Numerical contact/continuity checks and broader style/direction recordings retain their separate roles. Root reports80 clips/480 native plays and168 corruption detections; those numbers were not rerun by this visual assessment.

The first extraction attempt used an unsupported ffmpeg `-vsync` option and failed before extraction; its script is retained. A separate retry removed that option and completed. Original recordings were never modified.
