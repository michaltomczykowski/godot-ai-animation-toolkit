# Human Character Dummy (test asset)

A rigged humanoid pair used by the rig tests and demos (Phase 6). Provided by
the project owner from the *Human Character Dummy* pack; the archive contained
no licence file, so treat it as project-local test data.

| File | Notes |
| --- | --- |
| `HumanCharacterDummy_F.fbx` | 56-bone humanoid, female body mesh, scale 1.0 |
| `HumanCharacterDummy_M.fbx` | same skeleton, male body mesh |
| `HumanCharacterDummy_ColorPalette.png` | shared palette texture |

Verified import shape (Godot 4.7):

```
HumanCharacterDummy_F (Node3D)
  Rig (Node3D)
  Skeleton3D (56 bones)
    HumanF_BodyMesh (MeshInstance3D, skinned)
  AnimationPlayer            # one static "Untitled" clip (23 tracks, rest pose)
```

Bone names are human-readable and side-suffixed, which the rig tooling relies
on: `B-root`, `B-hips`, `B-spine`, `B-chest`, `B-shoulder.L/.R`,
`B-upperArm.L/.R`, `B-forearm.L/.R`, `B-hand.L/.R`, fingers, `B-neck`,
`B-head`, `B-jaw`, `B-thigh.L/.R`, `B-shin.L/.R`, `B-foot.L/.R`, `B-toe.L/.R`,
`B-spineProxy`.

Animation track paths on this rig look like `Skeleton3D:B-thigh.R`, using
`TYPE_ROTATION_3D` (quaternions) and `TYPE_SCALE_3D` tracks - the format the
toolkit's clip specs already read and write.
