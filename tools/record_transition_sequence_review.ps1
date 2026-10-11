param(
    [Parameter(Mandatory=$true)][string]$ReviewRoot,
    [Parameter(Mandatory=$true)][string]$TransitionRoot,
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$Godot,
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$Ffmpeg
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'review_receipts.ps1')
$sequenceNative = Get-Content -LiteralPath (Join-Path $ReviewRoot 'native-check.json') -Raw | ConvertFrom-Json
$sequenceRoute = Get-Content -LiteralPath (Join-Path $ReviewRoot 'route.json') -Raw | ConvertFrom-Json
if (-not $sequenceNative.passed -or $sequenceNative.runs.Count -ne 24 -or -not $sequenceRoute.passed) { throw 'Complete sequence public/native gates required' }
$sequenceProgressPath = Join-Path $ReviewRoot 'recording-progress.json'
if (Test-Path -LiteralPath $sequenceProgressPath) { throw 'Inspect the prior sequence recording before starting another' }
$sequenceProgress = @{state='waiting_for_transition_recordings'; orchestrator_pid=$PID; renderer_pid=$null; completed=@(); current=$null; source_head=$sequenceRoute.source_head}
try {
    Save-ReviewReceipt $sequenceProgressPath $sequenceProgress
    do {
        $sequenceTransitionProgress = Get-Content -LiteralPath (Join-Path $TransitionRoot 'recording-progress.json') -Raw | ConvertFrom-Json
        if ($sequenceTransitionProgress.state -eq 'failed') { throw 'Transition recording failed; preserve partial captures' }
        if ($sequenceTransitionProgress.state -ne 'complete') { Start-Sleep -Seconds 5 }
    } while ($sequenceTransitionProgress.state -ne 'complete')
    foreach ($sequenceCase in $sequenceRoute.cases) {
        $sequenceScene = Join-Path $ProjectRoot $sequenceCase.scene.Substring(6)
        if ((Get-FileHash -LiteralPath $sequenceScene -Algorithm SHA256).Hash.ToLower() -ne $sequenceCase.scene_sha256) { throw 'Changed saved sequence scene' }
    }
    foreach ($sequenceMode in @('clean','diagnostic')) {
        $sequenceFrames = Join-Path $ReviewRoot ($sequenceMode+'_frames')
        if (Test-Path -LiteralPath $sequenceFrames) { throw 'Preserve existing sequence frames' }
        $sequenceProgress.state = 'recording'
        $sequenceProgress.current = $sequenceMode
        $sequenceArgs = @('--path',('"'+$ProjectRoot+'"'),'--rendering-method','gl_compatibility',
            '--resolution','1920x1080','--disable-vsync','--script','res://tools/render_transition_sequence_review.gd',
            '--',('"'+(Join-Path $ReviewRoot 'route.json')+'"'),('"'+$sequenceFrames+'"'),$sequenceMode)
        $sequenceProcess = Start-Process -WindowStyle Hidden -FilePath $Godot -ArgumentList $sequenceArgs -PassThru `
            -RedirectStandardOutput (Join-Path $ReviewRoot ($sequenceMode+'-render.log')) `
            -RedirectStandardError (Join-Path $ReviewRoot ($sequenceMode+'-errors.log'))
        $null = $sequenceProcess.Handle
        $sequenceProgress.renderer_pid = $sequenceProcess.Id
        Save-ReviewReceipt $sequenceProgressPath $sequenceProgress
        $sequenceProcess.WaitForExit()
        if ($sequenceProcess.ExitCode -ne 0) { throw 'Sequence native capture failed' }
        & $Python (Join-Path $PSScriptRoot 'compose_transition_sequence_review.py') $ReviewRoot --mode $sequenceMode --ffmpeg $Ffmpeg
        if ($LASTEXITCODE -ne 0) { throw 'Sequence movie encode/decode failed' }
        $sequenceProgress.completed += $sequenceMode
    }
    $sequenceProgress.state = 'complete'; $sequenceProgress.current = $null; $sequenceProgress.renderer_pid = $null
} catch { $sequenceProgress.state = 'failed'; $sequenceProgress.error = $_.ToString(); throw }
finally { Save-ReviewReceipt $sequenceProgressPath $sequenceProgress }
