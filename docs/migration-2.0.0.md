# Migrating to 2.0.0

## Upgrade and enable

Use Godot 4.7.2 and a stable Godot AI release 4.4.2 or later.
The release qualification covers Windows and Linux on Godot AI 4.4.2.
Missing, unreadable, malformed, prerelease, or older core metadata prevents
tool registration and produces a dependency diagnostic.

1. Back up your project and your current addon directory.
2. Install Godot AI separately. Verify the toolkit ZIP against the SHA-256
   file on the release page and extract it into your project root. The ZIP
   contains `addons/godot_ai_animation/` and the MIT license.
3. Enable both plugins in **Project → Project Settings → Plugins**. Either
   enable order works.
4. In the Godot AI dock, open **Tools → Custom tools (addon-registered)**.
   Each family checkbox applies immediately and persists in the project.
   The built-in animation domain toggle controls Godot AI's core tools.

Eight families have promoted `custom_*` tools. Discover the catalog with
`custom_manage` using `{"op":"list"}`. Invoke `animation_sequence` and
`animation_rig_modifiers` through `custom_manage` with the family name and
nested operation arguments. The [README's agent guide](../README.md#agent-workflow)
shows complete requests.

## Regenerating motion

Omitted or default style now resolves to **Responsive**. Select `grounded`
explicitly for that variant, or choose `relaxed`, `heavy`, or `sneaky`.
Existing Animation resources and saved clips remain intact. Work on a
separate clip or scene copy when regenerating, then compare movement, timing,
root extraction, and playback before replacing a clip.

Procedural locomotion targets humanoid rigs on level surfaces. Game code
handles collision and actor movement. Assign exactly one translation
owner when consuming root motion. Motion and sequence writes and dry runs
require a stopped or paused destination player and inactive linked
AnimationTrees.

## Known issues and limitations

- An intermittent scene-save crash was observed in stock Godot 4.7.2 on
  Linux. The Windows and Linux clean-install checks and the official
  Linux rendered-preview check passed. The crash remains unresolved.
  Save incremental checkpoints.
- Rendered inspection needs a rendering-capable editor. Headless preview
  can return a typed refusal when rendering is unavailable.
- Scene Undo/Redo covers supported scene mutations. Disk effects such as
  exports and scene saves need separate file-level recovery.

See [the operation reference](op-index.md) for supported inputs and
[the operation inventory](operation-audit.json) for contextual refusals.
