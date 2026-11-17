#!/usr/bin/env bash
set -euo pipefail

variant=$1
engine=$2
project="$RUNNER_TEMP/preview-$variant"
output="$RUNNER_TEMP/preview-results-$variant"
export XDG_CONFIG_HOME="$RUNNER_TEMP/preview-config-$variant"
export XDG_DATA_HOME="$RUNNER_TEMP/preview-data-$variant"
export XDG_CACHE_HOME="$RUNNER_TEMP/preview-cache-$variant"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

cp -a test_project "$project"
ln -s "$PWD/.ci/godot-ai/plugin/addons/godot_ai" "$project/addons/godot_ai"
ln -s "$PWD/addons/godot_ai_animation" "$project/addons/godot_ai_animation"
"$engine" --headless --path "$project" --rendering-method gl_compatibility --rendering-driver opengl3 --import
rm -f "$project/.godot/editor/editor_script_doc_cache.res"

if xvfb-run -a -s '-screen 0 1280x1024x24 +extension GLX' \
    python tools/ci_rendered_preview.py --renderer-profile linux-mesa-llvmpipe \
      --core-root .ci/godot-ai --project "$project" --output "$output" --godot "$engine"; then
  echo "EXPERIMENT_PREVIEW_PASSED variant=$variant"
else
  echo "EXPERIMENT_PREVIEW_FAILED variant=$variant"
  if test -f "$output/editor.log"; then
    cat "$output/editor.log"
  fi
  exit 1
fi
