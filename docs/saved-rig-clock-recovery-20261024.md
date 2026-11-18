# Saved rig clock revalidation, 24 October 2026

The normal 60 FPS capture at `a9dc865` produced exactly 4,320 rig PNGs with
all 18 native runs passing, no engine errors, fresh unskinned bone transforms,
valid framing and original authored channel checks. The independent clock
admission refused the result because it assumed unit playback speed and a
zero phase after natural finite playback ends.

The exact saved target AnimationPlayer instead has `speed_scale = 0.8`, retained
from the original history fixture. Its observed first phase is
0.0133333335320155 at 1/60 second, matching the native float32 speed
0.800000011920929. Natural finite playback retains phase1.0 after stopping;
the loader does not call stop after starting this clip. No playback or fixture
change is needed.

The admission now resolves the exact manifest player path and its speed from
the hashed saved scene, separately from peer players. It applies the unchanged
10 microsecond clock tolerance to the resulting scaled schedule, loop convention
and retained finite endpoint. Missing/ambiguous/wrong player nodes, unsupported
speed, stopped/lagged/skipped phases and changed clips still refuse admission.
Eleven controls pass, including actual captured values and a differently paced
peer. Rechecking the unchanged actual report passes all4,320movie samples and
18non-movie boundary samples.

Private failed receipt and images remain unchanged at
`saved-media-candidate-r004/recording-r001/rig`. Re-admission, full image hashing,
encoding, independent MP4 decode and visual assessment must use a separate new
receipt identifying the original capture source and corrected validator source.
Do not overwrite the failed receipt or label the images as a fresh generation.
