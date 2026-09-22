# Publishing

## Release zip

`tools/release_zip.ps1` (and the CI `release` job) writes
`dist/godot-ai-animation-toolkit-<version>.zip` containing
`addons/godot_ai_animation/...`. Users unzip it into their project root.

The zip is built from the committed tree with `git archive`, so no
editor-generated `.import` files are packaged.

## Versioning

`plugin.cfg`'s `version` must match the release tag (`v0.1.0` → `0.1.0`). CI's
`version-check` job enforces this before the release job runs.

## Godot AssetLib

Submissions go through the AssetLib web form (human-reviewed), so the final
step is manual:

1. Run the release workflow (or `tools/release_zip.ps1`) and download the zip
   from the GitHub release.
2. Submit at <https://godotengine.org/asset-library/asset> → *Upload*:
   - **Category**: Tools
   - **Godot version**: 4.5+ (developed and tested on 4.7)
   - **Licence**: MIT
   - **Repository**: <https://github.com/michaltomczykowski/godot-ai-animation-toolkit>
   - **Description**: state up front that the addon **requires Godot AI**
     (`>= 4.1.0`) in the same project, then list the preset ops
     (`pulse`, `bounce`, `orbit`, `sweep`, `drift`, `spin`, `showcase`).
3. Keep the AssetLib version in sync with the tag; re-upload for each release.

The store page renders the repository README, so the demo GIF and the install
steps come along automatically.
