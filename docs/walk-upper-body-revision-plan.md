# Walk upper-body revision r002

## Review input

On 2026-10-08 the user viewed the baseline videos remotely on the PC: walking
looks better, but hands/arms move stiffly and strangely, and the hip feels stiff.
This authorizes a walk revision. It does not approve either quality profile.

## Investigation and implementation

1. Preserve r001 source, saved clips and videos. Measure actual played upper-body
   motion and inspect imported rest axes before choosing new controls.
2. Replace the candidate's world-Y arm lowering with the measured rig up
   and the arm-to-elbow rest direction. Test different bone axes and Z-up rigs.
   Keep explicit arm-down requests meaningful.
3. Add opt-in elbow delay and restrained wrist follow-through to the shared walk
   generator, with measured joint axes and periodic curves. Use explicit tuning
   for pelvis roll/yaw/sway and torso counterrotation. Do not promote unreviewed
   style defaults, guess finger axes, or add arbitrary motion noise. Explicit
   follow-through controls enable the corrected arm geometry and parent-frame
   handling. Legacy default clips remain unchanged until video approval. The
   existing chest_yaw multiplier cancels during weight normalization; the new
   torso_twist control provides an explicit total without changing legacy clips.
4. Generate all four rigs via the connected Godot AI custom-tools API. Save,
   reopen and play the clips in Godot 4.7.2 at actual 30/60/120 FPS. Check contact,
   reach, loops, joint continuity and non-inert wrist/forearm output. Add focused
   regressions for coordinate conversion and missing optional hand roles.
5. Record continuous 1080p60 baseline/candidate comparisons with matched front
   and side views. Archive exact source, parameters, scenes and receipts; push
   the unreleased branch checkpoint.
6. Open File Explorer on the PC with the new video selected. Ask the user to
   judge arms/hands, pelvis/torso and the whole walk; stop until feedback arrives.

## Limits and reference contracts

These are authored gait candidates, not a dynamics simulation or motion-capture
fit. Contact checks are ankle/marker checks, not skinned sole or COM proof.
Finger articulation requires validated finger chains and is a separate decision
if wrist/forearm correction still leaves the hand silhouette too rigid.

Godot's [Skeleton3D contract](https://docs.godotengine.org/en/4.7/classes/class_skeleton3d.html)
defines bone-global transforms relative to the skeleton. The arm controller must
use this space and actual rest geometry, independent of world Y or bone-local Y.
[Collins et al.](https://pmc.ncbi.nlm.nih.gov/articles/PMC2817299/) studied the
mechanical role of arm swing and its phase relationship to gait. This supports
coordinated swing as a design direction; it does not validate our coefficients.
