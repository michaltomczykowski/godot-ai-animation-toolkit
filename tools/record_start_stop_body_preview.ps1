param(
    [Parameter(Mandatory=$true)][string]$ReviewRoot,
    [Parameter(Mandatory=$true)][string]$BaselineRoot,
    [Parameter(Mandatory=$true)][string]$Matrix,
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$Godot,
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$Ffmpeg
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'review_receipts.ps1')
$bodyMatrix = Get-Content -LiteralPath $Matrix -Raw | ConvertFrom-Json
if (-not $bodyMatrix.passed -or $bodyMatrix.native_runs -ne 96 -or $bodyMatrix.body_runs -ne 16 -or $bodyMatrix.rows.Count -ne 4) {
    throw 'Complete Responsive played quality/body checkpoint required'
}
foreach ($bodyRow in $bodyMatrix.rows) {
    foreach ($bodyInput in $bodyRow.inputs_sha256.psobject.Properties) {
        if ((Get-FileHash -LiteralPath $bodyInput.Name -Algorithm SHA256).Hash.ToLower() -ne $bodyInput.Value) { throw 'Changed checkpoint input' }
    }
}
$bodyProgressPath = Join-Path $ReviewRoot 'recording-progress.json'
if (Test-Path -LiteralPath $bodyProgressPath) { throw 'Preserve existing recording attempt' }
$bodyProgress = @{state='recording'; completed=@(); current=$null; pid=$null; source_head=$bodyMatrix.source_head; matrix=$Matrix; scope='Responsive body feedback only'}
try {
    foreach ($bodyOperation in @('walk_start','walk_stop')) {
        $bodyFolder = Join-Path $ReviewRoot "$bodyOperation\responsive"
        $bodyRoutePath = Join-Path $bodyFolder 'route.json'
        $bodyBaselinePath = Join-Path $BaselineRoot "$bodyOperation\responsive\route.json"
        $bodyRoute = Get-Content -LiteralPath $bodyRoutePath -Raw | ConvertFrom-Json
        $bodyBaseline = Get-Content -LiteralPath $bodyBaselinePath -Raw | ConvertFrom-Json
        if (-not $bodyRoute.passed -or -not $bodyBaseline.passed -or $bodyRoute.source_head -ne $bodyMatrix.source_head -or $bodyRoute.invocation_kind -ne 'ordinary call') { throw 'Invalid public route' }
        foreach ($bodyManifest in @($bodyRoute,$bodyBaseline)) {
            foreach ($bodyCase in $bodyManifest.cases) {
                $bodyScene = Join-Path $ProjectRoot $bodyCase.scene.Substring(6)
                if ((Get-FileHash -LiteralPath $bodyScene -Algorithm SHA256).Hash.ToLower() -ne $bodyCase.scene_sha256) { throw 'Changed saved scene' }
            }
        }
        $bodyFrames = Join-Path $bodyFolder 'clean_frames'
        if (Test-Path -LiteralPath $bodyFrames) { throw 'Preserve previous frames' }
        $bodyProgress.current = $bodyOperation
        Save-ReviewReceipt $bodyProgressPath $bodyProgress
        $bodyArgs = @('--path',('"'+$ProjectRoot+'"'),'--rendering-method','gl_compatibility',
            '--resolution','1920x1080','--disable-vsync','--script','res://tools/render_start_stop_comparison.gd',
            '--',('"'+$bodyBaselinePath+'"'),('"'+$bodyRoutePath+'"'),('"'+$bodyFrames+'"'),'clean')
        $bodyProcess = Start-Process -WindowStyle Hidden -FilePath $Godot -ArgumentList $bodyArgs -PassThru `
            -RedirectStandardOutput (Join-Path $ReviewRoot "$bodyOperation-clean-render.log") `
            -RedirectStandardError (Join-Path $ReviewRoot "$bodyOperation-clean-errors.log")
        $bodyProgress.pid = $bodyProcess.Id
        $null = $bodyProcess.Handle
        Save-ReviewReceipt $bodyProgressPath $bodyProgress
        $bodyProcess.WaitForExit()
        if ($bodyProcess.ExitCode -ne 0) { throw "Native capture failed: $bodyOperation" }
        & $Python (Join-Path $PSScriptRoot 'compose_character_quality.py') $bodyFolder --ffmpeg $Ffmpeg --mode clean
        if ($LASTEXITCODE -ne 0) { throw 'Movie integrity check failed' }
        $bodyProgress.completed += "$bodyOperation/clean"
    }
    $bodyProgress.state = 'complete'
    $bodyProgress.current = $null
    $bodyProgress.pid = $null
} catch {
    $bodyProgress.state = 'failed'
    $bodyProgress.error = $_.ToString()
    throw
} finally {
    Save-ReviewReceipt $bodyProgressPath $bodyProgress
}
