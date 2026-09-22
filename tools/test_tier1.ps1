# Tier-1 checks: pure addon helpers, headless, no editor needed.
#
#   ./tools/test_tier1.ps1 [-Godot C:\path\to\godot.exe]

param(
	[string]$Godot = "godot"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
& $Godot --headless --path (Join-Path $root "test_project") --script res://tests/tier1_value_codec.gd
exit $LASTEXITCODE
