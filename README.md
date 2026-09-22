# Godot AI Animation Toolkit

A standalone [Godot](https://godotengine.org) addon that adds one-call
**animation presets** to [Godot AI](https://github.com/hi-godot/godot-ai) as a
custom MCP tool — **no core patches**. The presets are the ones scoped out of
core during the animation PR review: a generalized `pulse` plus `bounce`,
`orbit`, `sweep`, and `drift`.

```json
{"tool": "custom_animation_presets", "params": {
  "op": "bounce",
  "player_path": "/Main/HUD",
  "target_path": "Button",
  "intensity": 0.2
}}
```

![The generated demo scene running](docs/images/presets-showcase.gif)

*`op="showcase"` builds the scene above — seven nodes, seven autoplaying clips, one undo step.*

[**Video walkthrough (2 min)**](https://github.com/michaltomczykowski/godot-ai-animation-toolkit/releases/download/v0.2.1/animation_toolkit_presets_walkthrough.mp4)
— every preset card-by-card, with the exact call and the recorded clip it builds.

## Presets

| op | What it builds | Defaults |
| --- | --- | --- |
| `pulse` | Breathing / ping-pong on any property (`scale` shortcut, or typed `from_value`/`to_value` for `modulate:a`, `position`, `modulate`, …) | `duration=0.4`, `loop_mode="none"` |
| `bounce` | Center-pivot scale overshoot with settle-back — UI press feedback | `intensity=0.15`, `duration=0.4` |
| `orbit` | Circular position orbit (XZ plane for 3D, screen space for 2D/Control) | `radius=1.0` (3D) / `100.0` (2D), `duration=2.0` |
| `sweep` | Full-turn rotation sweep — radar scans, cooldown rings | `turns=1.0`, `duration=1.0` |
| `drift` | One-axis position offset — scanlines, marquee, conveyor | `axis="x"`, `duration=1.0` |
| `spin` | 3D quaternion turn around local Y | `turns=1.0`, `duration=3.0` |
| `float` | 3D bob: rise + scale + turn through the transform | `height=0.7`, `scale=1.25`, `duration=2.4` |
| `stagger` | Reveal a list of targets one after another in **one clip** | `effect="fade_in"`, `stagger=0.06`, `duration=0.3` |
| `showcase` | Builds a runnable demo of every preset (7 nodes + 7 autoplaying clips) | `name="AnimationShowcase"` |

Every preset:

- builds **one** `Animation` clip with typed keys and named transitions
  (`linear` / `ease_in` / `ease_out` / `ease_in_out`);
- commits **one scene-pinned undo action** — a single Ctrl-Z removes the clip
  (and any auto-created library);
- recenters a Control's `pivot_offset` for `bounce`/`sweep` **inside the same
  action**, so the pop/rotation starts from the widget's middle;
- starts from the target's *current* transform (scale/rotation/position), so a
  preset never snaps the node to identity.

(`showcase` is the exception: it builds a whole demo subtree in one action
instead of a single clip.)

## Install

1. Copy `addons/godot_ai_animation/` into your project's `addons/` folder.
2. Install and enable [Godot AI](https://github.com/hi-godot/godot-ai)
   (`>= 4.1.0`) in the same project.
3. Enable **Godot AI Animation Toolkit** in *Project → Project Settings →
   Plugins* (either order works).

Agents reach the tool as `custom_animation_presets` (promoted first-class tool)
or through `custom_manage(op="list"/"invoke")`. The Godot AI dock's Tools tab
lists it with an enable/disable toggle.

## Requirements

| | |
| --- | --- |
| Godot | 4.5 – 4.7 |
| Godot AI | `>= 4.1.0` (custom-tools registry) |
| Platform | any (no OS-specific code) |

The addon is **self-contained**: it uses the Godot AI custom-tools registration
API only, never core animation-handler internals, and loads cleanly (with a
warning) when Godot AI is absent.

## Development

```powershell
# Link the core addon + this addon into the test project (Windows)
./tools/setup_dev.ps1 -GodotAiPath C:\path\to\godot-ai

# Tier 1: pure helpers, headless, no editor
./tools/test_tier1.ps1

# Tier 2: editor suite (open test_project in the editor, then)
#   godot-ai test_run suite=animation_presets
```

`test_project/` is a Godot project wired to both addons; `tests/` holds the
editor suite (27 rows) and `tests/tier1_value_codec.gd` the headless checks
(40 checks). The `demo_*.tscn` scenes are the ones recorded for the walkthrough
video — each is one preset call plus autoplay.

## Documentation

- [`docs/tool-reference.md`](docs/tool-reference.md) — every parameter.
- [`docs/recipes.md`](docs/recipes.md) — core recipes → preset calls, with the
  demo GIFs.
- [`addons/godot_ai_animation/README.md`](addons/godot_ai_animation/README.md) —
  addon-level notes.

## Licence

MIT — see [`LICENSE`](LICENSE).
