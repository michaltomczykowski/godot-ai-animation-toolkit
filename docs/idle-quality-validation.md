# R2 idle: baseline and repair evidence

2026-10-11. Follow [idle-quality-review-plan.md](idle-quality-review-plan.md).
Run is closed; idle has not been tuned or approved. Work alone, Godot 4.7.2,
released separate Godot AI v4.2.1 (`bfc264200584ea5823f18356acb164781f57796d`).

## A — preserved public baseline

Animation/source checkpoint `f44f23685e839a4da21400a549fc91c65d1015dc`.
Fresh visible isolated editor PID 364, correct APPDATA profile, authenticated
Godot AI backend 8000/9500. The user's older editor/core remains open separately.
UUID `f853d458c87f4ce78c9a1c81850579ee`. All 20 ordinary clips pass the public
route, dry/pose preservation, write, save, force reopen and resolved-track checks.
Five styles, four rigs, in-place; duration/sampling/recipe overrides omitted.
Responsive omits style. Baseline writes are not history acceptance witnesses.

Recovery: `release_r2_idle_20261011/baseline` beneath the persistent snapshot.
Five `*-in-place/route.json` reports retain exact inputs/fixture hashes and scene
paths. The complete attempt report and baseline editor logs are preserved.

## B — independent standing checks

`check_idle_quality.gd` loads those saved scenes and advances one real mixer.
It requires bilateral standing support against each foot's rest ankle target;
it does not request running contact/toe-off/flight markers. Measured contacts
remain distinct from expected support. It checks paths/counts, finite poses,
foot slide/height/penetration, knee poles, zero actor/extracted root drift,
fractional reference poses and crossed loop seams. A fixed fractional played
probe measures incoming/outgoing positional and angular step direction at the
seam, preserving established 5 mm positional and relative angular step gates.

All **60/60** baseline Player checks at 30/60/120 FPS pass numerical measurement.
Report: `baseline/native-01f1d72dfe5c43ca9081169d8f7f7f0b/matrix.json`.
Each report records exact checker hashes and the public source. No engine errors.
All periods are 1.0 s. Maximum slide 0.332 mm, penetration 0.104 mm, fractional
reference position error 0.000497 mm and rotation error 0.000000748 rad.
Zero knee flips and zero actor/extracted translation.

**Generation clamps remain unknown:** every baseline reply omits `clamped`.
The checker stores null and `generation_clamp_metadata_known: false`, never
substitutes zero, and rejects a candidate missing that metadata. Baseline
measurement passes are not complete quality passes or visual approval.

Negative playback (`negative-actor-drift.json/.log`) translates a temporary
unanimated parent while playing the original clip; no bone pose is edited.
All twelve runs fail root drift and standing slide, exit 1, zero engine errors.
This verifies that numeric failures affect process status rather than relying
only on structural checks.

Observed upper body: wrists have zero local excursion on every rig. Maximum
upper-arm direction dot rig-up is +0.079 on the tall Z-up rig, versus -0.969 or
lower on the other fixtures: its arms remain close to horizontal. This is a
measured direction, not a visual acceptance criterion. Preserve representative
continuous front/side playback before changing any coefficients.

Limitations: rest ankle targets do not prove skinned sole collision; hip
projection is not center of mass. The current baseline covers Player/in-place;
the final candidate still requires 240 Player/Tree/root-policy checks and
actual public Undo/Redo, aliases/setup/optional-anatomy/config-isolation tests.

## Next gate

## C — additive control checkpoint (verification pending)

Idle now evaluates opt-in `elbow_swing`, `elbow_lag`, `wrist_swing`,
`wrist_lag`, `forearm_twist`, `wrist_sway`, `arm_variation`, `variation_seed`
and `hand_relax`. They use measured rig geometry/coordinated parents, the same
typed hand/finger anatomy validation as gait, and bounded periodic baked curves.
The original default config is unchanged. Reach metadata now carries actual
solve clamps/shortfall, clamped leg-sample count, `reach_evaluated`, and truthful
bilateral versus caller-authored support. No gait generation function changed.

Fresh editor/public verification is still required: ordinary saved baseline
parity, actual controls in played clips, old idle golden and approved walk/run
goldens. The added test covers played motion, seeds, typed refusals, dry-run
nonmutation, explicit zero elbow swing and `planted: false`. Do not promote a
profile until this additive checkpoint passes.

### Next measurement

Supported prototype inputs are saved in `idle-supported-prototypes.json`:
quieter existing breath/look/twist/weight-shift controls and explicit 3.0 s
duration, matching setup's existing idle timing. These are hypotheses to measure,
not promoted profiles. No wrist/finger control is claimed by these recipes.
The route helper accepts explicit prototype duration and refuses it for an
ordinary baseline/candidate call. Native baseline capture uses the preserved
public clips and a standing-specific renderer; walk/run renderer defaults are
unchanged behind virtual contact/status/footer hooks.

Capture and independently decode representative continuous baseline video,
then compare supported explicit timing/recipe prototypes through Godot AI.
New idle controls require actual evaluation and typed validation before use.
Approved walk/run output and all historical fixtures remain unchanged. Final
ordinary idle clips need ten continuous review videos and a manual user pause;
the idle golden cannot migrate before that feedback.
