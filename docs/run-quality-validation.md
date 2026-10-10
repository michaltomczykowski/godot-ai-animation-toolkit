# Run quality — R2 working evidence

2026-10-10. Godot 4.7.2, official separate Godot AI v4.2.1
`bfc264200584ea5823f18356acb164781f57796d`, public authenticated MCP.
Recovery: `F:\GODOTAITESTING\toolkit_repair_snapshot_2026-09-30\release_r2_run_20261010`.
Plan: [run-quality-review-plan.md](run-quality-review-plan.md).

## Preserved baseline and measured prototypes

Baseline source `8f7b6e7` retains animation source `056cc8d`. Twenty ordinary
run calls (five styles/four rigs) pass dry-run nonmutation, pose preservation,
save/reopen, inspection and resolved tracks. UUID:
`904e00f9aeeb4b7f8038374470167000`. Sixty rooted AnimationPlayer runs at
30/60/120 FPS pass. Responsive additionally passes 24 player/tree native runs.
Maximum measured stance slide is 0.184 mm, penetration 0.283 mm; no default
reach clamps or knee flips. A deliberately wrong reported speed fails all
twelve checks and exits 1, proving numeric failures affect the checker result.

Continuous baseline output identifies raised arms on the tall Z-up fixture,
rigid wrists and excessive legacy torso counter rotation. This is not a
lower-body failure. Explicit angular-only prototypes use existing public
overrides, preserving cadence, speed, reach, pelvis and foot targets. Twenty
prototype routes and 120 native player/tree runs pass. Parameters and profile
tables are preserved locally. UUID: `6c1bf50ae49246f4804710d0ea2fe01c`.

Responsive baseline is a decoded 24s 1080p60 MP4; prototype comparison is 48s,
2,880 independently decoded frames. Supplemental overview and raw comparison
frame 000030 both show the baseline/candidate correctly. A temporary camera
diagnostic was archived locally; no renderer defect was found. Prototype
footage is diagnostic, not the final ordinary-call review or human approval.

## Checker contract

`check_run_quality.gd` loads saved clips, evaluates real mixers, uses an
independent played reference, and measures crossed fractional loop seams.
AnimationTree disables competing player evaluation. One consumer owns extracted
root travel. In-place testing explicitly identifies a separate gameplay actor
driver; the clip itself must have zero extraction/translation. A retained player
binding for another clip is permitted when the current clip contains no matching
track. Native checks preserve the planned tolerances and fail numeric violations.

## Ordinary profile implementation checkpoint

Separate Responsive/Grounded run tables and run-only variant overlays now
enable measured arm axes, bent running elbows, torso/head follow-through,
periodic seeded wrists/forearms and relaxed fingers. Lower-body formulas and
walk tables are unchanged. A pure config-isolation check and accepted synthetic
walk golden pass (103 checks, zero walk drift).

Fresh public motion suite initially passes 59/61. One failure is the deliberately
preserved run golden (38 new tracks versus 20 legacy tracks). The other was a
new precedence test requesting an unreachable 1s run on the short fixture;
use reachable explicit 0.6s / 1.1 m/s inputs to test precedence without bypassing
reach refusal. The corrected focused test passes 17 assertions. Record a fresh
full candidate result after restart; do not count this corrected subset as it.

Optional anatomy tests now exercise both walk and run. New alias/setup checks
cover three public rigs. A history witness tests the actual external MCP run
write when a plain scene marker is present; otherwise it creates a local unit
fixture. It requires removal on Undo and exact clip/contacts/root binding on
Redo. Final ordinary route capture must invoke this witness for every clip.

## Ordinary route and native matrix

Animation source `97f17ce579510fe5b784c1edd84a845eb164c199` is pushed. Actual
MCP writes **40/40** ordinary clips (five styles/four rigs/two root modes), each
with successful Undo/Redo of that same public write, dry nonmutation, pose
preservation, save/reopen and inspection. UUID:
`6bcece032a55484297d9d5b113f6af8d`. Responsive omits style and all recipes omit
duration/speed/sampling/loop/overrides. **40/40** dry calls preserve inspection
before/after a core reload; ten families/eight promoted tools and a new ready
session are verified in both phases.

The complete **240/240** native matrix passes, as do **60/60** played comparisons
between ordinary defaults and explicit angular prototypes. Fresh public motion
suite is **60/61**, zero skips: only the preserved legacy run golden fails.
All **14/14** local headless suites pass. Four Windows/Linux editor CI jobs on
the animation candidate each record **383/386**, two private-X-Bot skips and
one legacy run-golden failure, zero engine/route/discovery errors. Those CI
failures remain visible; they are not a release-ready result.

### Playback-checker failures and ownership correction

The first in-place attempt failed because the old native helper resolved an
empty extraction path as a child node. The next attempt exposed both a Godot
empty-NodePath accessor error and X Bot's tree resetting the driver placed on
its animated visual child. Both failed attempts are preserved locally. Empty
paths are now checked before access and missing actors return a failed result.
Checker subprocesses have a timeout so a script error cannot hang indefinitely.

For in-place clips, the explicit gameplay driver is an unanimated parent outside
the visual mixer's subtree. This keeps one translation owner and leaves the
original animation library/bindings intact. The linked tree stays deterministic;
no baseline tracks are removed to make the check pass. This follows the engine's
[missing-track/reset blending contract](https://docs.godotengine.org/en/4.7/classes/class_animationmixer.html#class-animationmixer-property-deterministic).
The corrected matrix has zero engine errors. These are checker corrections;
they do not change the accepted walk or the candidate run animation source.
The 240-run aggregate includes maximum stance slide 15.416 mm (caller-driven
in-place cases included), ankle-plane penetration 0.283 mm, root travel error
0.089 mm, zero knee flips/default clamps and zero fractional repeat-pose error.
Both in-place extraction and clip-owned actor translation measure zero.

[Actions 38060543584](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/actions/runs/38060543584)
is complete: all non-editor source jobs pass, including both full live MCP
jobs with 118 pass markers and zero fail markers each. The four editor jobs
fail only the preserved run golden; tag-only jobs skip. Exact source, core
checkout SHAs, raw logs and `ci-97f17ce-review-receipt.json` are archived locally.

## Remaining review gate

Archive and deliver ten continuous final comparison MP4s. Pause for explicit
run feedback. Captures use same-style ordinary legacy output left and candidate
right; declared flight/contact, speed, loop duration and travel are captioned.
Media/measurement limitations remain the rest ankle plane and hip projection,
not skin collision or center of mass. Numerical passes do not approve aesthetics.
Documentation debt for R4: generator/test comments currently label the relative
speed `v/sqrt(gL)` as Froude number. The conventional locomotion definition is
`v²/(gL)`; these are different quantities ([primary research](https://pmc.ncbi.nlm.nih.gov/articles/PMC3639764/)).
Correct labels, physical-band claims and citations without silently changing
reviewed authoring coefficients. No physiological validity is established by
the current arithmetic proportion checks or video approval.
The historical `golden_run.json` remains immutable until that approval; intended
default-output mismatch must remain openly recorded. No release approval yet.
