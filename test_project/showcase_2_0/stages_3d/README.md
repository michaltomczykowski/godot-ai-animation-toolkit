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
| Zombie | Bone rotation, hips translation and a single performer position track on a synthetic humanoid |

## Locomotion styles

Open `motion_stage.tscn` and choose a clip in AnimationPlayer. The eight families are `idle`, `walk`, `run`, `strafe`, `jump`, `turn`, `walk_start` and `walk_stop`. Under each base name, Responsive uses the unsuffixed clip. Grounded, Relaxed, Heavy and Sneaky use their respective lowercase suffixes. Default and Responsive have identical saved track paths, key values and times, interpolation, clip duration, loop mode and markers in all eight families. Grounded and Responsive also match in Turn. The locomotion comparisons use in-place motion.

## Zombie Shuffle

`zombie.tscn` uses an original human-proportioned mannequin built from native primitive meshes and bone attachments. The base gait was generated with `animation_motion.walk_cycle` on `Performer/Skeleton3D` using `style: grounded`, `duration: 3.0`, `samples: 60`, `speed: 0.25`, `root_motion: true`, `set_root_motion: false` and `loop_mode: none`. The main style overrides are a 70% stance, 16° forward lean, 3.6 cm crouch, 9° arm swing and delayed wrist follow-through.

The six-second `zombie_shuffle` take retimes pose and travel together across two cycles. The baked clip adds asymmetric arm and head poses and fits the visible soles to the deck. Its single `Performer:position` track moves the mannequin 1.5 m. The gallery uses the three-quarter `Camera3D`. The `SideCamera` provides a profile view of the contacts.

The earlier exhibit’s `characterMedium.fbx` and `zombieMaleA.png` are retained in `kenney/` alongside the CC0 license for Kenney’s **Animated Characters Retro 1.1**.
