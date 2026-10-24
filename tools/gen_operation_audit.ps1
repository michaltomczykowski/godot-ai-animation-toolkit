# Export the operation inventory from the registry plus manually reviewed evidence.
param([string]$Godot = "godot")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
& $Godot --headless --path (Join-Path $root "test_project") --script res://tools/export_operation_audit.gd
exit $LASTEXITCODE
