# R2 idle: baseline and repair evidence

## r002 feedback revision (2026-10-11)

The user described r001 as very nice and requested a little more motion and
looking around. Preserve that feedback without claiming individual style/rig
approval. The complete r001 review record is in `idle_revision_history`;
all r001 media and archives remain intact. Plan: `idle-look-r002-plan.md`.

Animation change `1b79378`, capture source `9188ffa`, public UUID
`12f39e415f3b4ee19128d7b7737e0eba`. Godot 4.7.2 was launched visibly in the
isolated released-core project with the correct authenticated backend profile.
Only the two idle-specific profile tables changed; existing planted reach
planning, loop timing, seeded hand motion and caller controls are retained.

- **40/40** ordinary public idle writes pass actual Undo/Redo, dry/edited-pose
  preservation, save/force-reopen and track inspection. No recipe/timing override.
- **240/240** native Player/Tree checks pass on four rigs, both requested root
  policies and 30/60/120 FPS. Forty before/after-core-reload dry calls and complete
  ten-family/eight-promoted-tool discovery also pass.
- **60/60** independent played range comparisons show increased head yaw, chest
  yaw and pelvis sway versus r001. At 60 FPS Responsive dummy head sweep grows
  from 17.26 to 23.79 degrees; torso sweep 5.59 to 6.98 degrees; lateral pelvis
  sweep 11.28 to 14.10 mm. These are measured world-space ranges, not raw control
  amplitudes. X Bot, short and tall Z-up measurements pass at all three FPS.
- **120/120** fresh ordinary walk/run comparisons remain exactly identical to
  approved saved clips; 80 reference/candidate scenes are archived separately.
- Focused public motion remains **63/64**, with only preserved legacy idle golden
  failing; approved walk/run fixture drift is zero. Headless **14/14**, no engine
  errors. Full local editor passes **388/389** in 32 suites, zero skips,
  engine/discovery/route errors, both 103-operation registration probes pass.
- Source Actions **38141249398** checks the exact `9188ffa` tracked tree through
  merge `1ea717e`. All 28 Windows/Linux headless jobs and both live MCP jobs pass
  (118 pass / zero fail markers each). Four editor jobs have only the preserved
  old idle expectation and the two explicitly named private-X-Bot skips.
  This remains expected-failing pre-review CI, not green release approval.
- All 240 native runs have zero reach clamps, knee flips and actor/extracted
  root travel. Worst rigid ankle slide is **0.000879 mm**, height/penetration
  **0.001133 mm**. These are ankle-bone/rest-plane checks, not sole collision.

Full checks are complete. The isolated
visible editor quit normally through public `editor_manage(op="quit")` after
all saved-scene and reload work. Native recording continues from saved clips.

Recovery: `release_r2_idle_20261011/idle-look-r002`. All ten continuous MP4s are
complete and independently decoded: 48s/1080p60, 2,880 frames each. Videos compare
r001 left / r002 right, with six seconds front and side per rig. Strict archive
passes: exact source, 68 saved idle scenes, local/private rigs, current tooling,
source CI/local/native/history receipts and preserved reference receipts. All
three archive SHA-256/ZIP CRC checks and ten copied-video hashes independently
pass. The earlier 48 prototype runs are retained from their original source,
explicitly identified in the receipt; r002's 60 played range checks are separate.

PC Explorer is observed on the new `candidate/review-videos` with r002 Responsive
clean selected. Receipt: `candidate/pc-review-delivery.json`. r001 feedback and
delivery remain intact; r002 has five null approvals and awaits video feedback.
**Pause now.** The existing idle golden cannot migrate until revised footage is
explicitly approved; no start/stop phase or release action is authorized by the
numerical checks. Updated closure notes/state will be pushed as the final
delivery checkpoint, preserving the exact animation source separately.

## Preserved r001 evidence

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

## C — additive control checkpoint

Idle now evaluates opt-in `elbow_swing`, `elbow_lag`, `wrist_swing`,
`wrist_lag`, `forearm_twist`, `wrist_sway`, `arm_variation`, `variation_seed`
and `hand_relax`. They use measured rig geometry/coordinated parents, the same
typed hand/finger anatomy validation as gait, and bounded periodic baked curves.
The original default config is unchanged. Reach metadata now carries actual
solve clamps/shortfall, clamped leg-sample count, `reach_evaluated`, and truthful
bilateral versus caller-authored support. No gait generation function changed.

Source `e181dd8`: fresh visible editor PID 17180, public motion suite **62/62**,
no skips/errors; all **14/14** canonical headless suites pass. Existing idle and
approved walk/run golden drift remains zero. The added test covers played hand
motion, seeds, typed refusals, dry-run nonmutation, explicit zero elbow swing
and `planted: false`.

Twenty fresh ordinary public clips (UUID `903351fb38f842808e94066dcec06ecb`)
pass save/reopen; **60/60** independent played baseline comparisons have exactly
zero pose/root differences. Receipts are in `additive-controls/ordinary-parity`.
All twenty now truthfully report clamping; maximum shortfall is 8.769 mm
(heavy/tall Z-up). Maximum played ankle height error is 8.763 mm.
The original numerical baseline allowed up to 1% leg-length contact-band height;
that included small ankle lift from clamping. This explains why low planar slide
and penetration did not detect unreachable targets. Default candidate clamps
must be fixed; these ordinary clips are preserved diagnostic output.

Both representative baseline MP4s are complete: 24 s/1080p60, 1,440 independently
decoded frames each, no render errors. `baseline/preserved-baseline/manifest.json`
hashes the exact baseline source ZIP, twenty scene copies and both videos. The
full candidate/private-rig archive is a later gate. Still no idle approval.

`idle-hand-prototypes.json` adds modest evaluated hand controls to the supported
three-second recipes. Compare their actual public saved playback before choosing
profiles. A reach-planned pelvis path is needed separately to remove clamping;
the additive checkpoint deliberately retained baseline animation bytes.

### C2 — reach planning before profile selection

The baseline foot lift is consistent with solver shortfall, not hidden actor
drift: the standing contact band accepted it, while generation had not reported
it. Preserve the failing output. For planted idle, precompute the complete
authored pelvis rotation/offset path; find one shared constant downward stance
offset that keeps both rest ankle targets reachable throughout. This preserves
smooth periodic breathing/weight shifts, rather than adding per-frame corrective
dips. Use measured lengths and a margin beyond the two-bone solver's 1 mm limit.
Refuse malformed leg hierarchies, degenerate geometry or a correction over 8%
of measured leg length before mutation. Check the minimum reach as well.
Unplanted idle retains its documented caller-owned feet and unsolved metadata.

This intentionally changes planted idle output and its historical golden must
remain a failing expectation until idle video approval/versioned migration.
Walk/run generation is untouched. First measure the two explicit three-second
hand prototypes and a reach-planned rerun; then decide implicit profiles/timing.

Source `57eb376`: eight public saved/reopened prototypes, **48/48** Player/Tree
runs at 30/60/120 FPS pass. Zero clamps, shortfall, knee flips, root drift or
engine errors. Maximum slide 0.000848 mm, ankle height/penetration 0.000924 mm;
fractional repeat error 0.000339 mm/0.000000578 rad. Planned stance drop is
3.61–6.81 mm across these prototypes. These very small numbers describe rigid
bone ankle positions; they still do not certify skinned sole collision.
Receipt: `reach-plan/reach-plan-summary.json`. Headless **14/14**; fresh focused
motion **61/62**, only `test_the_idle_matches_its_golden` fails (162 units).
Approved walk/run goldens still match, no load/engine errors or skips.

Responsive's continuous legacy/prototype comparison is complete under
`reach-plan/prototype-3s/responsive-in-place`: 48 s/1080p60, 2,880 independently
decoded frames, no render errors. The saved source comparison shows the Z-up
arm correction and relaxed fingers. This is an internal prototype, not an
ordinary five-style candidate or user approval; preserve its media receipt.

### C3 — profile/default integration (fresh verification pending)

Use the measured three-second quiet and grounded recipes as separate idle-only
tables. Default/Responsive aliases match; Grounded differs. Keep duration=3 s
for all five implicit styles so each six-second review chapter covers two
periods. Preserve explicit timing and 60/s density; setup's matched three-second
idle must have identical tracks. Distances in implicit profiles scale to the
rig; the exploratory recipe's explicit meter values remain recorded inputs.

Retune variants with idle-only multipliers; leave walk/run/shared multipliers
unchanged. Handle missing head/breathing chains explicitly (implicit omissions
with reason, nonzero explicit impossible controls refused). Hand/finger anatomy
uses the tested omission/refusal path and measured axes even after omission.
Require deterministic variation, alias/setup/precedence/config isolation tests,
actual public idle Undo/Redo witnesses, saved playback and complete 240 matrix
before final continuous review media. A history marker only observes the public
write; it never authors another animation in that branch.

The tables and three-second implicit period are implemented, with existing
explicit timing/sampling precedence. Idle head/breath controls now report
missing connected chain geometry and refuse explicit impossible requests.
New profile and public-history tests are implemented; next restart the isolated
editor before using their results. Historical idle fixture remains unchanged.

First integration check on `aa08459`: headless 14/14; focused 62/64. The preserved
idle golden fails as expected. The older breathing test also assumed pronounced
default head/torso sweeps; retain its numerical thresholds and give it explicit
look=18/twist=22 inputs so it tests the authored controls. Ordinary quieter
profiles have separate alias/setup and native motion coverage. Preserve this
first report in `candidate-gates/motion-suite.json`; rerun with a fresh editor
into a distinct final-source report. No old fixtures were rewritten.

Source `757dd26`, fresh visible editor PID 26536: focused **63/64**, no skips/load
errors, only preserved `test_the_idle_matches_its_golden` fails. New idle profiles,
head/hand omissions/refusals, aliases, setup parity, seeded playback and history
tests pass; approved walk/run golden drift remains zero. Final ordinary public
40-clip capture and 240-run matrix are next. Candidate videos use a separate
standing renderer, gated recorder and exact ten verified outputs; archives and
manual review remain pending. No phase is approved by prototype footage.

Candidate source `8665980`, UUID `111fa689c5184c1ca20c41b0ef52141f`: **40/40**
ordinary public clips across all five styles/four rigs/two requested root modes
pass actual external Undo/Redo, dry nonmutation, pose preservation, save/reopen
and track inspection. Responsive omits style; all omit timing/sampling/recipe
overrides. The reply's `root_motion` echoes the requested mode; its empty
`root_motion_track` reports no newly owned actor track. Native playback confirms
zero actor/extracted translation under both requests. The native 240 matrix and
forty reload dry calls are running; source Actions `38124952893` is pending.
Do not infer completion from the previous 48 explicit prototype checks.

### D — final native/reload and protected gait regression

Ordinary candidate native matrix **240/240** passes, including Player/Tree,
30/60/120 FPS and both requested root policies. Zero reach clamps, knee flips,
actor travel or extracted root travel. Maximum rigid ankle slide 0.000891 mm,
height/penetration 0.001014 mm; upper-arm up dot <= -0.97294 on every rig/style.
These are bone-position measurements, not skinned sole collision certification.
Receipts: `candidate/native-matrix.json`, `candidate/native-metrics-summary.json`.

All **40/40** reload dry routes pass, with all ten families/eight promoted tools
in each ready session and unchanged saved inspection. Fresh full local editor
**388/389**, 32 suites, no skips/discovery/route/engine errors; only preserved
legacy idle golden fails. Two complete registry-route probes pass. Results:
`candidate/core-reload.json`, `candidate-gates/editor-full.json` and raw log.

Shared-context changes additionally require exact saved walk/run regression.
Use fresh ordinary public baseline writes for all five styles/four rigs, then
`tools/check_idle_protected_gaits.py` against their accepted saved scenes: 120
six-second native comparisons at 30/60/120 FPS, exactly zero bone/root drift.
The helper's walk mode is restricted to baseline regression; it cannot create
a new walk review candidate. Preserve sources/scenes/receipts in protected-gaits.
Final continuous idle recording and source Actions `38124952893` are pending.
The following closing checkpoint supersedes that pending source-CI wording.

Protected gait regression completed on `adca5c9`: **40/40** new ordinary public
save/reopens, then **120/120** independent native comparisons with exactly zero
world-space bone position/rotation or actor-root differences. All five styles,
four rigs and 30/60/120 FPS included. Reference walk source `056cc8d` and run
`97f17ce`; current addon is byte-identical to idle candidate `8665980`.
Receipt: `protected-gaits/parity-summary.json`; 80 saved reference/candidate
scenes are preserved in `protected-gaits/protected-scenes.zip`. Ordinary calls
omit timing/sampling/overrides; these gait clips are regression evidence.

Four source CI editor jobs are complete: **386/389**, one legacy idle golden
failure and exactly two named private-X-Bot skips, no engine/discovery/route
errors. Each performs both ten-family/103-operation route probes. The synthetic
merge `361d11d994a6a7a6e063a3ad285eada08988facd` has the same tracked tree as
candidate source `8665980`. Pinned core is `bfc2642`, engine 4.7.2. All completed
Tier-1 jobs and Linux live MCP pass; Windows live MCP remains pending. Preserve
the raw logs and parsed receipts in candidate-gates; do not call this CI green.

Source Actions `38124952893` is now complete: all **28** Windows/Linux headless
jobs and **both** live MCP jobs pass, each live route has **118 pass / zero fail**
markers. All four editor jobs fail solely the old idle golden as detailed above.
Tag-only version/release jobs are skipped. Exact source/tree/log hashes and
named private-rig skips are preserved in `candidate-gates/ci-8665980-receipt.json`.
This is an expected pre-review failure, not green release CI. The future
`idle-golden-migration-plan.md` preserves the manual gate and separate fixture;
no selector or expectation has changed during recording.

Final archive preflight caught an incorrect documentation/archiver assumption:
the reply's `root_motion` is the requested context flag, not an actual-travel
boolean (`handlers/motion.gd` assigns it from the prepared context). All twenty
true requests echo true with an empty `root_motion_track`; twenty false requests
echo false with the same empty track. The 240 native runs independently require
no active root position track and zero actor/extracted travel. Preserve this
failed preflight in `candidate-gates/archive-first-failure.json`. Correct the
reference and archive to require the echoed request, empty new track and existing
native ownership/travel checks; no addon, saved clip or media changes are needed.

### E — complete media, archive and PC review delivery

All ten final ordinary comparisons are complete: five clean/diagnostic pairs,
48 continuous seconds each, 1080p60 H.264, **2,880 independently decoded frames**
per video. Every rig has six seconds front and six side, covering two new idle
periods per view. Original legacy left/new ordinary candidate right, matching
fixed cameras and actual period/support/drift labels; no recipe/timing/sampling
overrides were used for candidate generation. Render errors are zero.

Strict archive passes after the requested/owned-root contract correction. It
requires all public/history/native/prototype/reload/local/source-CI/media gates
and exact protected gait regression. Source remains byte-identical to `8665980`.
Archive: **68 idle scenes**, both local FBX rigs, exact animation source, current
tooling/docs and phase receipts; protected gait proof adds **80 saved scenes**.
All ten review copies match their original video hashes. Receipt:
`candidate/review-delivery.json`; source/scene/tooling ZIP hashes are recorded.

PC File Explorer is observed on `candidate/review-videos`, with all ten MP4s
plus START-HERE and **idle-review-r001-responsive-clean.mp4 selected**. Delivery
observation is saved in `candidate/pc-review-delivery.json`. This is delivery,
not human motion approval. State: `awaiting_idle_styles_feedback`, all five idle
approvals null. Pause here for explicit five-style/four-rig idle video feedback.
Historical idle fixture is unchanged. `idle-golden-migration-plan.md` is the
next regression step; `start-stop-quality-review-plan.md` is prepared for
execution only after idle approval and independent green closure.

### Historical next measurement (before prototypes)

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
