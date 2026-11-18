# Idle r002: more motion and looking around

2026-10-11. User feedback on r001: “it's very nice, but I think you can add a
little bit more motion and looking around”. This requests a revision; it does
not approve the current idle fixture or release. Work alone on Godot 4.7.2
through the separate Godot AI v4.2.1 public custom-tools route.

## Change and preserve

Preserve the delivered r001 source `8665980`, all ten video hashes, scenes,
archives and feedback. Use a new recovery folder `idle-look-r002` beneath
`release_r2_idle_20261011`. Compare r001 on the left with r002 on the right.

Retune only the idle-specific Responsive/Grounded tables, with the existing
idle style overlays. Increase look from 4/6 to 6/9 degrees; torso twist from
4/6 to 5/7.5; breathing from 1.2/1.6 to 1.4/1.8; head drift from 0.6/0.8 to
0.75/1.0; sway from 6/9 to 7.5/11 mm (before rig scaling); shift from 0.7/1.1
to 0.85/1.3 degrees; arm sway from 0.8/1.1 to 1.0/1.35 degrees. Keep the
existing phases, planted-foot solve, three-second period, hand articulation,
variation seeds and explicit caller precedence. Measure reach rather than
assuming the larger pelvis path remains feasible.

## Gates and delivery

1. Commit exact animation source, launch the isolated editor visibly with its
   existing profile, and run the focused public motion suite. Preserve the
   expected historical idle-golden failure; no fixture migration before review.
2. Generate 40 ordinary idle clips: five styles, four rigs, two requested root
   policies. Check public dry run, edited pose, actual Undo/Redo, saved/reopened
   scenes and track resolution. No private clip construction or recipe override.
3. Require the existing 240 native Player/Tree checks at 30/60/120 FPS, including
   contacts, loop continuity, knee stability, reach clamps and zero root travel.
   Measure played head/torso/pelvis ranges against r001 to document the change.
4. Check approved walk/run fixtures and exact saved playback parity after the
   idle table change, headless suites, full editor suites, reload discovery and
   source Windows/Linux CI. Only the preserved legacy idle expectation may fail.
5. Record ten new continuous 48-second 1080p60 MP4s, with matched fixed cameras,
   four rigs and front/side views. Decode and hash all videos, archive exact
   source/scenes/receipts, push and verify the remote branch. Open PC Explorer
   with r002 Responsive clean selected, then pause for feedback again.

No tolerance relaxation, approval reset, merge, tag or fixture promotion in
this revision. Follow `idle-golden-migration-plan.md` only after explicit
approval of the revised videos.
