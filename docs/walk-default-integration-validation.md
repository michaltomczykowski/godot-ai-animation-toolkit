# R1: accepted walk default integration

2026-10-10. Responsive/default use the exact r004 recipe through one resolver.
Grounded uses its separate recipe; relaxed/heavy/sneaky now decorate Responsive.
Configuration is resolved before measured arm axes. Missing implicit head/hand/
finger features are omitted with reasons; explicit unsupported controls still
fail before writes. Setup returns per-clip style/capability/sampling metadata.

Default density is 60/s. Jump, turn and start/stop report their authored 120/s
minimum and enforce the real interval budget. Cycles now default to linear loops
as documented (previously the inherited bone handler chose none and appended a
terminal hold to a normal rooted walk). Explicit loop/root flags remain honored.

## Fresh supported-core checks

The counts below preserve the initial pre-review run. Post-approval fixture and
regression results are recorded in the closing section; the initial failures
were not hidden or replaced.

Separate released Godot AI v4.2.1 checkout:
`bfc264200584ea5823f18356acb164781f57796d`, original custom 4.1.0 untouched.
Fresh visible Godot 4.7.2 runs the isolated project
`test_project/repair_r1_validation_20261010` on ports 8000/9500, with isolated
APPDATA under the recovery folder. Public authenticated attach/MCP probe finds
all ten families/eight promoted tools, typed family errors and no missing schemas.

Fresh motion suite: **57/58 passed, zero skips**. New checks cover four-rig
default/explicit/alias/setup equivalence, optional anatomy, explicit typed
refusals, precedence/metre preservation and actual one-shot density/budget.
All existing contact, hand variation, articulation, history, and run/idle goldens
in this suite pass. The one failure is the intentionally preserved pre-v2 walk
golden (20 tracks, versus 38 with the accepted hands/fingers). A separate pure
proportions golden also differs after the intended profile change. Do not hide
these failures or overwrite either historical fixture before review. Final
green regression remains an R1 exit gate after visual approval.

First attempts are archived: a missing test-local type annotation, old sample
expectation and test anatomy aliases were corrected. Test-renamed skin bones are
restored before teardown; the fresh second run has no engine errors.

## Public routes and native playback

Saved public routes now pass for **20 normal style clips** plus eight matched-
input clips. Sixty four-rig contact/loop runs pass at 30/60/120 FPS. Twenty-four
native matched-input comparisons pass against the original saved r004 output
(position/root <=10 micrometres, rotation <=0.0001 rad). Forty style dry calls
before/after core reload preserve inspected clips. All ten families remain
registered on the released core. The fresh headless check is **13/14 suites**;
only the preserved pre-v2 proportions golden differs. A docs-root failure in
the isolated fixture was corrected by running that filesystem-specific suite
from the canonical test project, where it passes 2012 checks.

Animation source `056cc8d19d9821086346816345e1c4feab0041dd` is pushed. Later
checkpoints change documentation and review tooling; addon animation code is
unchanged from that exact source. All ten captures are complete.

Across each style's twelve native runs, the measured maxima are:

| Style | Declared stance slide (mm) | Rest ankle plane penetration (mm) | Knee flips | Generation reach clamps |
| --- | ---: | ---: | ---: | ---: |
| Responsive/default | 0.115 | 0.689 | 0 | 0 |
| Grounded | 0.115 | 0.599 | 0 | 0 |
| Relaxed | 0.080 | 0.393 | 0 | 0 |
| Heavy | 0.107 | 0.513 | 0 | 0 |
| Sneaky | 0.057 | 0.191 | 0 | 0 |

These are independent played world-space ankle measurements with declared contact
markers. They do not establish skinned sole collision or a center of mass, and
do not grant visual approval.

## Continuous review delivery

All five styles have clean and diagnostic **48s 1080p60 H.264 MP4s**, independently
decoded to 2,880 frames each. All ten render error logs are empty. Each video has
six continuous seconds front and six side for dummy, X Bot, short and tall Z-up.
The original accepted r004 Responsive clip is on the left (r004 Grounded for
Grounded); the actual normal-call candidate is on the right. Style-selected
implicit speeds differ, so captions report ground travel rather than claiming
matched speeds. The default candidate uses no style, recipe or sampling override.

The strict R1 archive checks all public/native/reload/media receipts, original
r004 comparison provenance, scene hashes and single-owner travel. It preserves
28 new scenes plus eight reference scenes, local rig assets, animation source,
current documentation/tooling, ten review copies and SHA256 receipts. Private
media/assets remain local. Rerunning the archive retains previous delivery
history and Explorer metadata; recorded feedback cannot be reset by rerunning it.

PC File Explorer is open to `review-videos` with
`walk-default-responsive-r005-clean.mp4` selected; the folder and selection were
verified through Windows Shell. `START-HERE.txt` describes the chapters and review
checklist. Playback by the user has **not** been inferred from opening Explorer.
At delivery, state was `awaiting_promoted_walk_styles_feedback` and five approval
fields were null. Top-level baseline fields preserve history; current walk
source/evidence/media are in `promoted_walk_review`.

On 2026-10-10 the user replied, **“they look very good.”** This approves the
presented five-style/four-rig walk set against source `056cc8d` and the archived
video hashes. Individual files watched were not enumerated. No other motion or
release is approved by this feedback.

## Post-approval fixture migration and local regression

Separate `golden_walk_responsive_v2.json` (38 tracks, 61 keys) and
`golden_spec_walk_responsive_v2.json` (ten tracks, 13 keys) guard the approved
default. The original four walk/spec/run/idle fixtures are unchanged. Scale 2048
and tolerance 2 are unchanged. The editor fixture omits style/sampling overrides;
the synthetic arithmetic fixture retains 12/s. Fixture provenance and hashes
are in `test_project/tests/fixtures/golden_walk_v2_provenance.json`.

Missing goldens now fail normal tests. Deliberate local recording requires
`ANIMATION_TOOLKIT_RECORD_GOLDENS=1`; CI refuses recording even with that flag.
A regression test verifies both refusals and absence of writes. The recording
run is preserved separately from comparison evidence.

Fresh Godot 4.7.2 on released core v4.2.1, with recording unset:

- Focused suite through authenticated public MCP: **59/59**, zero skips.
- All **14/14** pure headless suites pass.
- Full editor CI harness: **384/384** across **32** suites, zero skips,
  discovery errors, engine errors or route errors.
- Registration/operation probes before and after reload: **ten families and
  103 operation dry routes** each. These probes are discovery/refusal coverage,
  not visual approval of all 103 operations.

The full harness records one expected invalid-NaN fixture warning and four
existing Bone2D child-length warnings. After the successful result, shutdown
records three ObjectDB leaks and a backend keepalive disconnect; neither is
counted as a new animation assertion failure. The visible editor is restored
without recording/CI flags (PID 28336 at this checkpoint).

Logs/reports are under `release_r1_20261010/accepted-r005-regression`.
State is `approved_walk_styles_pending_ci`. Windows/Linux source CI remains the
R1 exit gate. R2-R5 and final release review remain pending.

## Source CI and recording-guard follow-up

Fixture candidate `9a350637c44e46cd56db203f3f7f2f984f835646` passes
[Actions 38056657619](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/38056657619):
all 32 required source jobs and both advisory core-main jobs. Both platforms'
full live MCP routes record 118 passing contract markers and zero failure markers.
Each editor job has 382/384 passing tests, no failures/errors, and exactly two
private-X-Bot skips; locally all 384 pass with the asset installed. The skipped
tests are `test_responsive_default_aliases_and_setup_use_identical_walks` and
`test_xbot_rooted_walk_and_run_play_with_contact`, both reporting the missing
local FBX. They are not a blanket skip allowance for future failures.

CI tests synthetic PR merge `2a2fa0a5dd2ec735b37a132f25121fe54370566c`, whose
tracked tree exactly matches the candidate. Released core is `bfc264200...`;
advisory main is `b82b5c519b1b17228f70d8effce1626f391bd1dd`. Tag-only version/
release jobs correctly skip. Raw jobs/logs and parsed receipts are preserved in
the accepted-regression folder.

The guard now also recognizes standard `CI=true/1`, used by pure headless jobs.
The fresh public motion suite passes 59/59 including that additional refusal.
This small test-helper follow-up needs its own full source CI before final R1
closure. Animation generation and approved video output remain unchanged.
The next operation's detailed plan is `docs/run-quality-review-plan.md`; baseline
measurement can use the verified fixture source while this guard CI completes,
but run generation-code changes wait for the R1 exit gate.

These are candidate defaults on the review branch, not a release or approval of
other motions. Non-walk profile tables still have their own previous baselines;
R2 authors/reviews them separately rather than copying walk controls into them.

Recovery root:
`F:\GODOTAITESTING\toolkit_repair_snapshot_2026-09-30\release_r1_20261010`.

## R1 final closure — 2026-10-10

Final standard-CI guard source `8f7b6e78b25204b8298bbdd135a725524b104f0c`
passes [Actions 38057817851](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/38057817851):
32 required source jobs and two advisory core-main jobs. Four editor jobs each
record 382/384 passing tests, the same two private-X-Bot skips, zero failures
and engine/route/discovery errors. Both live MCP jobs record 118 passing
markers and zero failing markers. Tag-only jobs skip. Released core is
`bfc264200584ea5823f18356acb164781f57796d`; advisory main is
`b82b5c519b1b17228f70d8effce1626f391bd1dd`. Synthetic merge
`d16d5999120399ba9e54ad568635abe82c364c09` has the same tracked tree.

Raw logs, parsed editor results and `ci-8f7b6e7-receipt.json` are archived in
accepted-r005-regression. State is `approved_walk_styles_regression_complete`.
R1 is complete; R2 run and subsequent release gates remain open. Historical
pending/failure paragraphs above describe the preserved earlier checkpoints.
