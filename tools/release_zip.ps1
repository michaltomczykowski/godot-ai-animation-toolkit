# Build the release / AssetLib zip from the committed tree.
#
#   ./tools/release_zip.ps1 [-Version 0.1.0]
#
# Writes dist/godot-ai-animation-toolkit-<version>.zip containing
# addons/godot_ai_animation/... (unzip into a project root). Uses `git archive`
# so only committed files are packaged (no editor-generated .import files).

param(
	[string]$Version = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

if (-not $Version) {
	$cfg = Join-Path $root "addons\godot_ai_animation\plugin.cfg"
	$match = Select-String -Path $cfg -Pattern '^version="(.*)"$'
	if (-not $match) {
		throw "Could not read version from $cfg"
	}
	$Version = $match.Matches[0].Groups[1].Value
}

$dist = Join-Path $root "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$zip = Join-Path $dist "godot-ai-animation-toolkit-$Version.zip"
if (Test-Path -LiteralPath $zip) {
	Remove-Item -LiteralPath $zip -Force
}

git -C $root archive --format=zip --output "$zip" HEAD addons/godot_ai_animation
if ($LASTEXITCODE -ne 0) {
	throw "git archive failed"
}
Write-Output "wrote $zip"
