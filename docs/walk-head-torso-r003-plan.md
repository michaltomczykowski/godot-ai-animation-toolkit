# Walk head and torso revision r003

## Human input and scope

2026-10-09: “it looks better but the torso and head is still too stiff, the head
needs a small bob while walking just like real human”. The user viewed r002.
This requests another revision; neither profile has visual approval.

1. Preserve r002 clips, recipes and videos as the comparison reference. Extend
   the engine-only checker to measure played head/chest position and orientation
   in the rig frame, at 30/60/120 FPS. Separate inherited vertical bob from local
   head articulation. Record those measurements before changing generation.
2. Add opt-in torso flex/roll and head nod/roll with explicit amplitudes and gait
   phase delay. Distribute torso flex across the actual hips-to-head hierarchy,
   excluding pelvis and cervical joints; carry each rotation through its animated
   parent. Counter a portion of incoming torso motion at the cervical chain and
   layer a restrained two-per-stride nod. Retain inherited vertical bob and bone
   lengths; do not translate the head joint to fake a bounce.
3. Reject nonzero controls without usable roles/connected rest hierarchy and
   reject excessive amplitudes/delay. Keep existing default clips and goldens
   unchanged pending human review. New controls must be reachable through the
   public Godot AI custom-tools schema and shared gait generator.
4. Add native playback regressions for articulated torso/head, orientation,
   periodicity, parent-frame conversion, missing roles, dry run and history.
   Generate/save/reopen all eight candidates through Godot AI in a fresh visible
   Godot 4.7.2 editor. Check contacts, reach, root travel, loops and joint steps
   at actual 30/60/120 FPS; verify access before/after core reload and Windows/Linux CI.
5. Record continuous matched front/side comparisons: r002 same-profile left,
   r003 right, all four rigs, grounded/responsive, clean/diagnostic. Decode-verify
   each 48-second 1080p60 MP4; archive exact sources/scenes/recipes/logs/receipts
   and push an unreleased review checkpoint.
6. Open PC Explorer with the new videos, ask for head/torso and overall walking
   feedback, and stop. Defaults/profile approval remain a manual gate.

## Reference and limits

[Hirasaki et al.](https://pubmed.ncbi.nlm.nih.gov/10442403/) studied coordinated
vertical head movement and pitch during walking. This informs periodic,
restrained articulation; our preview coefficients are authored candidates,
not a fit to their subjects or a claim of biomechanical validity.
[Skeleton3D](https://docs.godotengine.org/en/4.7/classes/class_skeleton3d.html)
defines bone-global poses in skeleton space. Convert using measured rig axes
and the incoming animated parent rather than fixed world Y or guessed bone axes.
Ankle contact checks do not establish natural movement or skin-sole/COM accuracy.
