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
$transitionMatrix = Get-Content -LiteralPath $Matrix -Raw | ConvertFrom-Json
if (-not $transitionMatrix.passed -or $transitionMatrix.native_runs -ne 480 -or $transitionMatrix.rows.Count -ne 20) {
    throw 'Complete 480-run transition matrix required'
}
foreach ($transitionRow in $transitionMatrix.rows) {
    if (-not $transitionRow.passed -or -not $transitionRow.complete -or $transitionRow.engine_errors.Count) { throw 'Failed native route' }
    foreach ($transitionInput in $transitionRow.input_sha256.psobject.Properties) {
        if ((Get-FileHash -LiteralPath $transitionInput.Name -Algorithm SHA256).Hash.ToLower() -ne $transitionInput.Value) { throw 'Changed native input' }
    }
}
$transitionProgressPath = Join-Path $ReviewRoot 'recording-progress.json'
if (Test-Path -LiteralPath $transitionProgressPath) {
    $transitionPrevious = Get-Content -LiteralPath $transitionProgressPath -Raw | ConvertFrom-Json
    if ($transitionPrevious.pid) {
        $transitionPriorProcess = Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$transitionPrevious.pid)
        if ($transitionPriorProcess -and $transitionPriorProcess.CommandLine.Contains([IO.Path]::GetFullPath($ReviewRoot))) { throw 'Capture is already running' }
    }
}
$transitionProgress = @{state='recording'; completed=@(); current=$null; pid=$null; source_head=$transitionMatrix.source_head; matrix=$Matrix}
try {
    foreach ($transitionOp in @('walk_start','walk_stop')) {
        foreach ($transitionStyle in @('responsive','grounded','relaxed','heavy','sneaky')) {
            $transitionFolder = Join-Path $ReviewRoot "$transitionOp\$transitionStyle"
            $transitionReference = Join-Path $BaselineRoot "$transitionOp\$transitionStyle\route.json"
            $transitionRoutePath = Join-Path $transitionFolder 'route.json'
            $transitionRoute = Get-Content -LiteralPath $transitionRoutePath -Raw | ConvertFrom-Json
            $transitionBaseline = Get-Content -LiteralPath $transitionReference -Raw | ConvertFrom-Json
            if (-not $transitionRoute.passed -or -not $transitionBaseline.passed -or $transitionRoute.operation -ne $transitionOp `
                    -or $transitionRoute.phase -ne 'candidate' -or $transitionRoute.invocation_kind -ne 'ordinary call' `
                    -or $transitionRoute.source_head -ne $transitionMatrix.source_head) { throw 'Invalid ordinary route' }
            foreach ($transitionManifest in @($transitionRoute,$transitionBaseline)) {
                foreach ($transitionCase in $transitionManifest.cases) {
                    $transitionScenePath = Join-Path $ProjectRoot $transitionCase.scene.Substring(6)
                    if ((Get-FileHash -LiteralPath $transitionScenePath -Algorithm SHA256).Hash.ToLower() -ne $transitionCase.scene_sha256) { throw 'Changed saved scene' }
                }
            }
            foreach ($transitionMode in @('clean','diagnostic')) {
                $transitionProgress.current = "$transitionOp/$transitionStyle/$transitionMode"
                $transitionProgress | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $transitionProgressPath -Encoding UTF8
                $transitionMediaPath = Join-Path $transitionFolder 'media.json'
                if (Test-Path -LiteralPath $transitionMediaPath) {
                    $transitionMedia = Get-Content -LiteralPath $transitionMediaPath -Raw | ConvertFrom-Json
                    $transitionVideo = $transitionMedia.videos.$transitionMode
                    if ($transitionVideo -and (Test-Path -LiteralPath $transitionVideo.path) -and $transitionVideo.decoded_frames -eq 2880 `
                            -and $transitionVideo.render.source_head -eq $transitionRoute.source_head `
                            -and ((Get-FileHash -LiteralPath $transitionVideo.path -Algorithm SHA256).Hash.ToLower() -eq $transitionVideo.sha256)) {
                        $transitionProgress.completed += "$transitionOp/$transitionStyle/$transitionMode (verified prior capture)"
                        continue
                    }
                }
                $transitionFrames = Join-Path $transitionFolder ($transitionMode+'_frames')
                if (Test-Path -LiteralPath $transitionFrames) {
                    $transitionRenderPath = Join-Path $transitionFrames 'render.json'
                    if (-not (Test-Path -LiteralPath $transitionRenderPath)) { throw "Inspect preserved incomplete capture: $transitionFrames" }
                    $transitionRender = Get-Content -LiteralPath $transitionRenderPath -Raw | ConvertFrom-Json
                    if ($transitionRender.frames -ne 2880 -or $transitionRender.errors.Count -or $transitionRender.source_head -ne $transitionRoute.source_head `
                            -or $transitionRender.mode -ne $transitionMode -or $transitionRender.cases.Count -ne 8) { throw 'Incomplete preserved native report' }
                    & $Python (Join-Path $PSScriptRoot 'compose_character_quality.py') $transitionFolder --ffmpeg $Ffmpeg --mode $transitionMode
                    if ($LASTEXITCODE -ne 0) { throw 'Preserved frame encode/decode check failed' }
                    $transitionProgress.completed += "$transitionOp/$transitionStyle/$transitionMode (complete native report recovered)"
                    continue
                }
                $transitionArgs = @('--path',('"'+$ProjectRoot+'"'),'--rendering-method','gl_compatibility',
                    '--resolution','1920x1080','--disable-vsync','--script','res://tools/render_start_stop_comparison.gd',
                    '--',('"'+$transitionReference+'"'),('"'+$transitionRoutePath+'"'),('"'+$transitionFrames+'"'),$transitionMode)
                $transitionProcess = Start-Process -WindowStyle Hidden -FilePath $Godot -ArgumentList $transitionArgs -PassThru `
                    -RedirectStandardOutput (Join-Path $ReviewRoot "$transitionOp-$transitionStyle-$transitionMode-render.log") `
                    -RedirectStandardError (Join-Path $ReviewRoot "$transitionOp-$transitionStyle-$transitionMode-errors.log")
                $transitionProgress.pid = $transitionProcess.Id
                # Cache the handle before the process exits. Windows PowerShell
                # otherwise can expose a null ExitCode after WaitForExit.
                $null = $transitionProcess.Handle
                $transitionProgress | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $transitionProgressPath -Encoding UTF8
                $transitionProcess.WaitForExit()
                if ($transitionProcess.ExitCode -ne 0) { throw "Native capture failed: $transitionOp/$transitionStyle/$transitionMode" }
                & $Python (Join-Path $PSScriptRoot 'compose_character_quality.py') $transitionFolder --ffmpeg $Ffmpeg --mode $transitionMode
                if ($LASTEXITCODE -ne 0) { throw 'Encode/decode check failed' }
                $transitionProgress.completed += "$transitionOp/$transitionStyle/$transitionMode"
            }
        }
    }
    $transitionProgress.state = 'complete'
    $transitionProgress.current = $null
    $transitionProgress.pid = $null
} catch {
    $transitionProgress.state = 'failed'
    $transitionProgress.error = $_.ToString()
    throw
} finally {
    $transitionProgress | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $transitionProgressPath -Encoding UTF8
}
