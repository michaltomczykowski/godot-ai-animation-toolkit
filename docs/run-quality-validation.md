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

## Remaining run gate

Implement separate ordinary run profiles without changing walk coefficients,
verify public-route Undo/Redo/reload and the 240-run native matrix, archive and
deliver ten continuous final comparison MP4s. Pause for explicit run feedback.
The historical `golden_run.json` remains immutable until that approval; intended
default-output mismatch must remain openly recorded. No release approval yet.
