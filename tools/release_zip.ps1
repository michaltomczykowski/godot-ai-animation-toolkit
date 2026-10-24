# Package one committed source. Qualification and publication are separate gates.
param([string]$Source = "HEAD", [string]$Version = "", [string]$OutputDirectory = "")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$sourceSha = git -C $root rev-parse --verify "$Source^{commit}"
if ($LASTEXITCODE -ne 0) { throw "Source must resolve to a committed revision" }
$cfg = git -C $root show "${sourceSha}:addons/godot_ai_animation/plugin.cfg"
if ($LASTEXITCODE -ne 0) { throw "Committed plugin.cfg missing" }
$matches = @($cfg | Select-String '^version="([0-9]+\.[0-9]+\.[0-9]+)"$')
if ($matches.Count -ne 1) { throw "Committed plugin.cfg must contain one stable version" }
$committedVersion = $matches[0].Matches[0].Groups[1].Value
if ($Version -and $Version -ne $committedVersion) { throw "Requested version differs from committed metadata" }
$Version = $committedVersion
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root "dist" }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$zip = Join-Path $OutputDirectory "godot-ai-animation-toolkit-$Version.zip"
if (Test-Path -LiteralPath $zip) { throw "Output exists; use a fresh directory: $zip" }
git -c core.autocrlf=false -C $root archive --format=zip --output "$zip" $sourceSha addons/godot_ai_animation LICENSE
if ($LASTEXITCODE -ne 0) { throw "git archive failed" }
python (Join-Path $PSScriptRoot "validate_release_package.py") --repo $root --source $sourceSha --zip $zip --version $Version
if ($LASTEXITCODE -ne 0) { throw "Package validation failed" }
Write-Output "source=$sourceSha package=$zip"
