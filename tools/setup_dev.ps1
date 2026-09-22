# Link the core Godot AI addon and this addon into test_project/addons.
#
#   ./tools/setup_dev.ps1 -GodotAiPath C:\path\to\godot-ai
#
# Re-running replaces existing links. On Linux/macOS use a symlink instead:
#   ln -s "$GODOT_AI/plugin/addons/godot_ai" test_project/addons/godot_ai
#   ln -s "$PWD/addons/godot_ai_animation" test_project/addons/godot_ai_animation

param(
	[Parameter(Mandatory = $true)]
	[string]$GodotAiPath
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$addons = Join-Path $root "test_project\addons"
New-Item -ItemType Directory -Force -Path $addons | Out-Null

$links = @(
	@{ Name = "godot_ai"; Target = Join-Path $GodotAiPath "plugin\addons\godot_ai" },
	@{ Name = "godot_ai_animation"; Target = Join-Path $root "addons\godot_ai_animation" }
)

foreach ($link in $links) {
	$path = Join-Path $addons $link.Name
	if (-not (Test-Path -LiteralPath $link.Target)) {
		throw "Target does not exist: $($link.Target)"
	}
	if (Test-Path -LiteralPath $path) {
		(Get-Item -LiteralPath $path).Delete()
	}
	cmd /c mklink /J "$path" "$($link.Target)" | Out-Null
	Write-Output "linked $($link.Name) -> $($link.Target)"
}

Write-Output ""
Write-Output "Next: open test_project in Godot (both plugins enable automatically),"
Write-Output "then run the tier-1 checks:  ./tools/test_tier1.ps1"
