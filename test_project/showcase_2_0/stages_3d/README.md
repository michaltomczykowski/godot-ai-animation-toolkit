# 3D stage fixtures

The kinetic props are ordinary Node3D scenes with saved AnimationPlayer clips. The playback script plays the stored clip on entry and repeats one-shots after a short hold. Each stage has its own camera and lighting. Use a viewport with its own World3D when embedding more than one stage on screen.

| Scene | Native animation track |
| --- | --- |
| Pulse | Vector3 scale |
| Bounce | Vector3 scale with overshoot and settle |
| Orbit | Position on the XZ plane |
| Sweep | Euler rotation around local Y |
| Drift | X translation with ping-pong playback |
| Spin | Quaternion rotation around local Y |
| Float | Transform3D combining lift, scale, and turn |
| Stagger | Position on five independently timed Node3D targets |
| Blink | Scale on two Skeleton3D eye bones |
| Zombie | Bone rotation and hips translation on an imported skeleton |

## Locomotion styles

Open `motion_stage.tscn` and choose a clip in AnimationPlayer. The eight families are `idle`, `walk`, `run`, `strafe`, `jump`, `turn`, `walk_start` and `walk_stop`. Under each base name, Responsive uses the unsuffixed clip. Grounded, Relaxed, Heavy and Sneaky use their respective lowercase suffixes. Default and Responsive have identical saved track paths, key values and times, interpolation, clip duration, loop mode and markers in all eight families. Grounded and Responsive also match in Turn. The locomotion comparisons use in-place motion.

## Kenney character

The imported `characterMedium.fbx` and `zombieMaleA.png` are unmodified files from Kenney's **Animated Characters Retro 1.1**. The accompanying CC0 license is in `kenney/License.txt`. The original toolkit-generated `zombie_walk` uses the Godot AI `animation_rig.walk_cycle` recipe on `Performer/Root/Skeleton3D`.

| Roles | Imported bones |
| --- | --- |
| hips, spine, chest, neck, head | Hips, Spine, UpperChest, Neck, Head |
| thigh_l, shin_l, foot_l, toe_l | LeftUpLeg, LeftLeg, LeftFoot, LeftToes |
| thigh_r, shin_r, foot_r, toe_r | RightUpLeg, RightLeg, RightFoot, RightToes |
| arm_l, forearm_l, hand_l | LeftArm, LeftForeArm, LeftHand |
| arm_r, forearm_r, hand_r | RightArm, RightForeArm, RightHand |

The FBX import converts the Z-up bind pose through the model's Root node. On this skeleton, the recipe's `arm_down` setting points the arms forward in the Godot scene. The authored cycle uses an 86° reach, 12° arm swing, 22° stride, and 17° knee bend.
