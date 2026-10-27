# Disposable setup grounding prototype

This is a controlled prototype, not production setup wiring or candidate qualification. The new `test_project/tools/setup_grounding_prototype.gd` is a runtime SkeletonModifier3D attached only by `check_setup_grounding_prototype.gd`. It holds transient native references and is not a serialized production helper. Arguments to the checker are the four-rig saved setup route and a new report path. It never generates clips or changes saved scene files.

## Bounded behavior

The original independent BlendSpace clock and exact root consumer remain unchanged. The modifier runs only while its bound Tree is active. Actual weighted clip phases/contact markers determine stance. Contact targets retain world anchors on the measured level ankle plane; swing targets are the current FK feet clamped above that plane. A measured two-bone solve changes thigh/shin rotations, then restores original global foot orientation. The current measured knee plane is retained where conditioned, with measured rig-forward fallback near straight legs. No hips/upper-body, bone-position, rest, animation-key or root-owner transform edits occur. Unreachable targets and target residuals are reported; no reach substitute is silently accepted.

The shortest-arc rotation uses `atan2(cross.length,dot)` because Godot's two-vector quaternion constructor rounded tiny corrections to identity in the initial attempt. The first120-play attempt is preserved: contact bounds already passed but its new1e-5m residual diagnostic failed on44 enabled cases, with errors up to approximately0.28mm. Stable-angle math passes the same1e-5m diagnostic without loosening a bound.

## Signal-time evidence

The checker preserves the saved Tree and original numerical gates, but takes every bone snapshot inside `modification_processed`. Contact, finite-pose, knee, velocity and final recovery reads use that captured array. Missing snapshots fail. An explicitly late corrupting SkeletonModifier3D moves a shin after grounding; the checker captures its final signal and fails, demonstrating that it does not approve an earlier intermediate pose. At120FPS a six-second blend produces720 actual signal captures. Static reference instances used for native idle recovery do not pretend to have modifier evaluations.

## Final controlled report

Raw private report `private-setup-grounding-r001/native-r003.json` SHA256:
`1019a6c431057739ad844093ccc5f78b180b295e56fa9f581a9958f51ce7927f`.
The exact private scripts and failed/earlier reports remain locally preserved. Committed scripts differ only in the helper preload filename needed for their new portable location.

| Mode | Plays | Pass | Expected counterfactual |
|---|---:|---:|---|
| Enabled |60|60|All five actual saved setup specs, four rigs,30/60/120FPS|
| Bypassed |60|24|The36 original intermediate/OneShot contact failures return|
| Wrong Tree binding |60|24|Same36 original contact failures return|
| Late bone writer |60|0|Final contact/velocity/recovery failures are observed|
| Disabled modifier |60|0|Missing signal witness and original contact failures are observed|

All300 plays have zero engine errors. Enabled maximum penetration is0.000001609325m, declared contact height0.000000923872m, stance slide0.000000976225m and IK target residual0.000001688785m. No unreachable targets occur. Maximum bone velocity is9.42306064 leg lengths/s, the same maximum as bypass. Root endpoint error is at most0.0000858306885m, exactly identical for each enabled/bypass pair; root speed/ownership was not changed.

Protected counters are exactly zero for local bone positions, rest transforms, non-leg/hips/upper-body rotations and root-owner translation. Maximum preserved global foot-orientation error is0.0000005381612rad. Largest actual target correction by rig is77.236mm dummy,32.670mm X Bot,66.372mm short and111.951mm tall Z-up. These are repairs to actual FK mixtures, not claims that the mixtures were originally valid.

## Next review boundary

Production wiring must be reviewed separately: serialize explicit paths/roles/axes/contact settings, own the helper in the same setup transaction as clips/Tree, validate foreign active modifier ordering before writes, preserve save/reopen and exact Undo/Redo, and expose correction/reach diagnostics. Add transform/style/forward-jump and wrong-path/order tests. The current prototype only proves the four saved Responsive stationary/extracted cases; it does not qualify other styles, setup variants, gameplay collision, skinned soles or visual phase coherence. Continuous native recording and independent temporal assessment remain mandatory. Do not adopt cyclic sync alone: `setup-phase-causality.md` records its speed-contract regression.
