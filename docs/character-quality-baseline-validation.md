# Walk baseline r001 — first human review gate

Motion source: `1389c6655e6a1fcda34ed9249b9f715f1e8e85cd` (production motion
is the previously verified `7513708` source). This checkpoint adds review tools
and documentation; it does not promote a motion profile or approve the walk.

## Actual route and native checks

The visible Godot 4.7.2 editor, Godot AI 4.1.0 and public `custom_manage` route
generate all four rigs; no direct toolkit handler constructs review animations.
Exact invocations and returned metadata are in the recovery `route.json`.
The explicit travelling-loop conditions are `root_motion=true`,
`loop_mode="linear"`; other recipe tuning, duration and sample rate stay implicit.
The initial invocation with the default nonlooping mode is preserved separately
as `default_nonloop_route.json`. Unique saved scene paths avoid resource caches.

Dry run leaves inspected output unchanged. Written clips match after save and
force reopen. All four mandatory rigs resolve reported roles and native tracks.
The X Bot FBX is a local review dependency; neither that asset nor media is
uploaded by this checkpoint.

The fresh checker imports no addon handlers/specs/pose helpers. It loads each
saved scene separately for each frame rate, disables automatic mixers/modifiers,
plays the target AnimationPlayer, advances by precisely `1/fps`, and consumes
native extracted root travel once. It reads engine bone global poses rather than
applying animation keys by hand. World up derives independently from each rest
convention; the tall rig is measured in its original Z-up coordinates.

Twelve runs (4 rigs x 30/60/120 FPS), six seconds each, pass:

- Valid path/type/count contracts; no captured engine errors or nonfinite poses.
- No detected reversal of a reachable knee pole between adjacent played frames.
- Declared-stance ankle slide <= min(2% leg length, 3 cm).
- Ankle penetration relative to the rest ankle plane <= 1% leg length.
- Full single-owner root travel, with maximum error below 0.000025 m.
- No reported generation reach clamp.
- Loop boundary pose repetition (all bones, six cycles), with maximum position
  error below 0.000000148 m and rotation error below 0.000000191 rad.

The raw traces include played contacts, ankle/hip/root positions and actual
timestamps. Step and seam displacement are reported, not treated as visual
acceptance. This initial checker does **not** prove skinned-sole contact, center
of mass, visually natural cadence or full future profile/operation acceptance.
Maximum ankle slide is about 0.000483 m, maximum rest-plane penetration about
0.002251 m. The tall Z-up arm pose is a visible outstanding concern.

## Continuous review videos

Clean and diagnostic recordings each contain 1,440 native 1920x1080 frames,
encoded as H.264 MP4 at 60 FPS. Both angles run simultaneously for six continuous
seconds per rig; no poses are reset within a segment. Chapter times in each video:

| Time | Rig |
| --- | --- |
| 00:00–00:06 | Bundled dummy |
| 00:06–00:12 | X Bot |
| 00:12–00:18 | Short synthetic |
| 00:18–00:24 | Tall Z-up synthetic |

The whole scene is normalized for display, including the Z-up rig; its bones are
never individually rotated or retuned by the renderer. Camera orientation/size
stays fixed within a rig segment and follows body translation only. The 25 cm
floor grid stays in world coordinates. Dummy and X Bot retain their skinned meshes;
synthetic cylinders/spheres connect native played bone positions with ordinary
lighting/depth tests. The visual floor uses a rest-sole display alignment, separate
from the numeric check's explicitly reported rest ankle plane.

Diagnostics: green/amber ankle markers show declared contact/swing, the green
line spans both support ankles, magenta shows hip projection and blue shows root
travel. This is not a physical support polygon or a center-of-mass calculation.

Native frame counts, capture errors, MP4 codec/dimensions/FPS, decoded frame count
and duration, media hashes and representative frame hashes are in `media.json`.
Supplemental overview images never replace video review.

## Recovery / repeat

Canonical tools:

- `tools/mcp_character_quality_baseline.py`: real editor route and progress receipt.
- `test_project/tools/character_quality_native.gd`: native playback and measurements.
- `test_project/tools/check_character_quality.gd`: fresh exact-timestep checker.
- `test_project/tools/render_character_quality.gd`: clean/diagnostic played capture.
- `tools/compose_character_quality.py`: encode and independently decode-check.
- `tools/archive_character_quality.py`: source/scene/asset archives, hashes and
  pending human review state; it never grants approval.

Local recovery root:
`F:/GODOTAITESTING/toolkit_repair_snapshot_2026-09-30/character_quality_20261008/walk-baseline-r001`.
Use a fresh output directory and route run ID when regenerating a baseline.

```powershell
# From G:/godot-ai-dev/godot-ai-animation-toolkit; Godot editor already running.
$qualityPython = 'G:/godot-ai-dev/godot-ai-v4-animation/.venv/Scripts/python.exe'
$qualityGodot = 'F:/GODOTAITESTING/Godot_v4.7.2-stable_win64/Godot_v4.7.2-stable_win64_console.exe'
$qualityOutput = '<absolute fresh recovery directory>'
& $qualityPython tools/mcp_character_quality_baseline.py --core-root G:/godot-ai-dev/godot-ai-v4-animation --project-root G:/godot-ai-dev/godot-ai-animation-toolkit/test_project --output $qualityOutput
& $qualityGodot --headless --path test_project --script res://tools/check_character_quality.gd -- "$qualityOutput/route.json" "$qualityOutput/native-check.json"
& $qualityGodot --path test_project --rendering-method gl_compatibility --resolution 1920x1080 --disable-vsync --script res://tools/render_character_quality.gd -- "$qualityOutput/route.json" "$qualityOutput/clean_frames" clean
& $qualityGodot --path test_project --rendering-method gl_compatibility --resolution 1920x1080 --disable-vsync --script res://tools/render_character_quality.gd -- "$qualityOutput/route.json" "$qualityOutput/diagnostic_frames" diagnostic
& $qualityPython tools/compose_character_quality.py $qualityOutput --ffmpeg C:/Users/mtomc/AppData/Local/Temp/opencode/ffmpeg/ffmpeg.exe
```

## Resume rule

Stop after delivering the baseline videos. Request timestamped feedback about
cadence, weight, torso/arms and foot contact; record it before implementing grounded
and responsive walk candidates. Plain “continue” is not visual approval. Later
promotion requires explicit profile/all-rig approval. Final Windows/Linux full
gates remain required for the approved motion revision, not inferred from this
baseline recording checkpoint.
