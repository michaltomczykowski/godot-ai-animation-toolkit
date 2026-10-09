# Walk upper-body r002 — feedback received, revised in r003

On 2026-10-09 the user viewed r002 and requested a less stiff torso/head with
a small walking head bob. No profile approval was granted. The next candidate
and current review gate are in `walk-head-torso-r003-validation.md`; the r002
receipts/media below remain the preserved comparison reference.

Candidate animation source: `671a2fff8acaaf6c0410c756cebec61da687d47a`.
Final API refusal follow-up: `1ec8348` (requires upper-arm roles for nonzero
wrist swing; valid candidate key generation is unchanged).
Baseline source remains `1389c6655e6a1fcda34ed9249b9f715f1e8e85cd`.
Branch: `repair/toolkit-quality`, unreleased. No profile approval, default
promotion, reference-file regeneration or media upload is part of this checkpoint.

## User feedback and changes

The user viewed r001 through File Explorer remotely on the PC and reported stiff,
strange hand/arm movement and a stiff pelvis. Exact feedback remains in
`character-quality-review.json`; the focused implementation/review plan is
`walk-upper-body-revision-plan.md`.

Native r001 playback confirms zero local wrist articulation on all four rigs.
The original lowering assumed world Y and bone-local Y, and kept the Z-up arms
raised. The candidate measures arm-to-elbow rest geometry and rig up, carries
the elbow hinge through incoming torso/clavicle animation, delays elbow flexion,
and adds restrained periodic wrist follow-through. No noise or finger-axis
guessing is used. Synthetic hand segments now show played hand orientation on
both sides of the comparison; their original recorded clips remain unchanged.

New opt-in controls: `elbow_lag`, `wrist_swing`, `wrist_lag`, `torso_twist`.
They enable the measured arm controller; requests without these controls retain
existing default motion and goldens pending review. The old `chest_yaw` weight
multiplier cancels during normalization; `torso_twist` supplies a shared amplitude
independently. Legacy default repair/promotion remains an explicit later gate.
Nonzero wrist swing requires arm, forearm and hand roles on both sides. Delay/amplitude limits and
missing roles return typed errors without committing output.

The first attempt (`9fbbae3`) exposed wrong torso handedness in an added independent
played-pose check. It was retained under `attempt-9fbbae3`, not delivered for
approval. Corrected source applies the rig's yaw sign to torso twist and adds an
editor regression. Final candidates use new scene UUIDs.

## Actual Godot AI route

Godot 4.7.2 visible editor, Godot AI 4.1.0. All eight candidate clips are generated
by public `custom_manage` invocation of `animation_motion`; the renderer and
checker generate no animations. The two JSON recipes in `docs/` contain the
exact preview coefficients. These are named candidate recipes, not promoted
public style presets.

Baseline ground speed per rig is passed explicitly to both candidates. Duration
remains one second; root extraction and linear looping are explicit. Candidate
sampling is explicitly 60 keys/s (baseline retains 24). Foot-distance defaults
remain rig-scaled. Dry-run invariance, resolved tracks/counts, save and force
reopen all pass. Exact calls, responses and scene hashes are in each `route.json`.

Final grounded scene UUID: `2fe5864ed2254d5c82d3e940dd579355`.
Final responsive scene UUID: `bbd6e3b291da4e6e9b11066c80f77e3e`.

All eight candidate recipes also pass public-route overwrite dry runs before
and after a Godot AI core-plugin reload (16 invocations). Inspected saved clips
stay unchanged; the new controls remain accessible after toolkit re-registration.
Exact calls and session identities are in `core-reload.json`.

## Native checks and regressions

Each candidate has twelve engine-only six-second runs: four rigs at actual
30/60/120 FPS, plus twelve upper-body traces. The engine plays each original saved
clip and consumes extracted root motion exactly once. No hand-applied key pose
is used as playback evidence.

| Check | Grounded | Responsive |
| --- | --- | --- |
| Maximum declared-stance ankle slide | 0.000115 m | 0.000115 m |
| Maximum penetration below rest ankle plane | 0.000600 m | 0.000690 m |
| Maximum loop bone position error | 0.000000062 m | 0.000000022 m |
| Maximum loop rotation error | 0.000000151 rad | 0.000000120 rad |
| Maximum played wrist step, including 30 FPS | 0.837 degrees | 0.732 degrees |
| Initial torso counterrotation against hips | 12/12 | 12/12 |
| Engine/path/count/nonfinite errors, reach clamps, knee flips | 0 | 0 |

All existing ankle/marker thresholds and full root travel pass. Wrist articulation
is non-inert and repeats at the loop boundary. This validates neither natural
walking nor skinned-sole collision, physical COM, finger posing or arbitrary
terrain. The intrinsic torso-sign check concerns the posed counterrotation at
the initial sample, not full-body angular momentum.

The fresh visible editor passes **51/51** motion tests, zero skips, including
walk/run/idle goldens, native wrist playback, typed refusals and the new torso-sign
regression. Fourteen local headless suites pass; measured lowering regressions
include Z-up, rotated rigs, independent bone axes and explicit degree requests.
The animation source passes all 34 validation jobs in
[Actions run 37844680472](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/37844680472):
28 headless jobs, four editor/core combinations and both complete live MCP routes
on Windows/Linux. The later missing-arm refusal guard passes the same fresh
51-test local suite, including a partial rig with forearm/hand roles but no arm
role; all sixteen before/after-reload candidate dry invocations are repeated
against that guard. The final approved revision still requires closing full CI
after human review and promotion. Current CI approves contracts, not visual quality.

## Continuous comparison and manual gate

Each required MP4 has 2,880 native frames, 1920x1080 H.264 at 60 FPS, 48 seconds.
Left is the original r001 clip; right is one candidate. Each rig has six seconds
from the front followed by six seconds from the side. Cameras match and follow
translation only; the world grid is stationary. Both profiles require clean and
diagnostic versions. The encoder independently decodes and counts every result.

| Time in either candidate video | Rig / view |
| --- | --- |
| 00:00–00:06 / 00:06–00:12 | Dummy / front then side |
| 00:12–00:18 / 00:18–00:24 | X Bot / front then side |
| 00:24–00:30 / 00:30–00:36 | Short synthetic / front then side |
| 00:36–00:42 / 00:42–00:48 | Tall Z-up synthetic / front then side |

Diagnostic markers retain the r001 meanings: declared ankle contact/swing,
hip projection (not COM), support-ankle line and root travel. Human review must
assess arm timing, hand stiffness, pelvis/torso coordination and the whole walk.
Finger pose remains the imported rest pose; neither preview claims relaxed fingers.

Recovery root:
`F:/GODOTAITESTING/toolkit_repair_snapshot_2026-09-30/character_quality_20261008/walk-review-r002`.
The archive gate requires both complete profiles, unchanged scene/media hashes,
all numeric/upper-body checks and the fresh editor result. It preserves the exact
source, twelve scenes, local FBX dependencies, tooling/docs and SHA-256 receipts.

Tools: `mcp_character_quality_baseline.py` (explicit recipe/baseline-speed args),
`check_walk_upper_body.gd`, `render_walk_comparison.gd`,
`record_walk_review.ps1`, `compose_character_quality.py`,
`archive_walk_revision.py`.

**Stop after opening File Explorer with these videos selected on the PC.**
Ask for feedback on both candidates and all four rigs. The user must explicitly
approve before profile/default promotion; “continue” alone grants no approval.

All four MP4s are verified and copied with matching hashes to `review-videos`.
Explorer's folder window was confirmed with the grounded clean MP4 selected.
Playback was subsequently confirmed by the 2026-10-09 feedback; no profile
visual approval was granted. r003 is the current pending review.
