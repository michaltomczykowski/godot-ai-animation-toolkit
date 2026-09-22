# Regenerate docs/op-index.md from the op registry (single source of truth).
#
#   ./tools/gen_docs.ps1 [-Godot C:\path\to\godot.exe]

param(
	[string]$Godot = "godot"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
& $Godot --headless --path (Join-Path $root "test_project") --script res://tools/gen_docs.gd
exit $LASTEXITCODE
