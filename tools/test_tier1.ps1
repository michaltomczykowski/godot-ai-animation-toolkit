# Tier-1 checks: pure addon helpers, headless, no editor needed.
#
#   ./tools/test_tier1.ps1 [-Godot C:\path\to\godot.exe]

param(
	[string]$Godot = "godot"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$project = Join-Path $root "test_project"
$scripts = @(
	"res://tests/tier1_value_codec.gd",
	"res://tests/tier1_spec_modifiers.gd",
	"res://tests/tier1_fx_specs.gd",
	"res://tests/tier1_graph_builders.gd",
	"res://tests/tier1_spec_json.gd",
	"res://tests/tier1_pose_math.gd",
	"res://tests/tier1_motion_drivers.gd",
	"res://tests/tier1_quality_modifiers.gd"
)
foreach ($script in $scripts) {
	Write-Output "== $script"
	& $Godot --headless --path $project --script $script
	if ($LASTEXITCODE -ne 0) {
		exit $LASTEXITCODE
	}
}
exit 0
