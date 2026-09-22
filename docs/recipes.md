# Recipes and presets

![The generated demo scene running: bounce button, orbiting dot, sweeping bar, drifting line, pulsing label](images/presets-showcase.gif)

*`animation_presets(op="showcase")` builds the scene above in one call — five
nodes and five autoplaying clips, one undo step. Run the current scene (F6) to
watch it.*

## Recipe → preset

The core Godot AI docs describe four motion **recipes** built from
`animation_create` + `add_property_track`. The toolkit turns each into a
one-call preset:

| Recipe (core docs) | Preset call |
| --- | --- |
| Bounce — press feedback | `{"op": "bounce", "player_path": "...", "target_path": "Button", "intensity": 0.2}` |
| Orbit — circular position | `{"op": "orbit", "player_path": "...", "target_path": "Marker", "radius": 1.5, "loop_mode": "linear"}` |
| Sweep — radar / cooldown ring | `{"op": "sweep", "player_path": "...", "target_path": "RadarPivot", "loop_mode": "linear"}` |
| Drift — scanline / marquee | `{"op": "drift", "player_path": "...", "target_path": "Scanline", "axis": "x", "distance": 480.0, "loop_mode": "pingpong"}` |

Two more presets cover the typed-track demos from the core showcase:

| Effect | Preset call |
| --- | --- |
| Quaternion spin (3D) | `{"op": "spin", "player_path": "...", "target_path": "Cube", "loop_mode": "linear"}` |
| Breathing / hover pulse | `{"op": "pulse", "player_path": "...", "target_path": "Label", "property": "modulate:a", "from_value": 0.2, "to_value": 1.0, "loop_mode": "pingpong"}` |

## Why a preset instead of raw keyframes

![Left: hand-written per-frame driver. Right: the same motion from animation tracks](images/recipes-before-after.gif)

*Same motion either way — the difference is what it takes to author it.*

The core animation tooling can express all of this with
`animation_create` + `add_property_track`, and a hand-written `_process`
driver can too. The presets exist so an agent (or a person) does not have to:

- pick the right keyframe times and transition names per effect
  (`ease_out` / `ease_in_out` curves, 16-segment circle sampling, ping-pong
  phases);
- remember that a Control scales/rotates around `pivot_offset` — and recenter
  it in the same undo step;
- start from the target's **current** transform instead of snapping it to
  identity;
- get the typed key shapes right (`Vector2` vs `Vector3` vs `float` vs
  `Quaternion`).

## The showcase op

```json
{"op": "showcase", "params": {"op": "showcase", "name": "Presets"}}
```

Builds under the edited scene root (or `parent_path`):

- `BounceButton` — Control, `bounce` clip, pivot recentered
- `OrbitDot` — ColorRect, `orbit` clip (radius 60 px)
- `SweepPivot`/`SweepBar` — `sweep` clip (linear loop)
- `DriftLine` — `drift` clip (ping-pong, x axis)
- `PulseLabel` — `pulse` clip on `modulate:a` (ping-pong)

All five `AnimationPlayer`s autoplay, the whole subtree is one undo step, and
`test_project/showcase.tscn` in this repository is exactly this output.
