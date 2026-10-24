param(
    [Parameter(Mandatory=$true)][string]$ReviewRoot,
    [Parameter(Mandatory=$true)][string]$Matrix,
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$Godot,
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$Ffmpeg
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'review_receipts.ps1')
$candidateMatrix = Get-Content -LiteralPath $Matrix -Raw | ConvertFrom-Json
if (-not $candidateMatrix.passed -or $candidateMatrix.native_runs -ne 480 -or $candidateMatrix.rows.Count -ne 20) { throw 'Complete 480-run ordinary matrix required' }
foreach ($candidateRow in $candidateMatrix.rows) {
    if (-not $candidateRow.passed -or -not $candidateRow.complete -or $candidateRow.engine_errors.Count) { throw 'Failed native route' }
    foreach ($candidateInput in $candidateRow.input_sha256.psobject.Properties) {
        if ((Get-FileHash -LiteralPath $candidateInput.Name -Algorithm SHA256).Hash.ToLower() -ne $candidateInput.Value) { throw 'Changed native input' }
    }
}
$candidateProgressPath = Join-Path $ReviewRoot 'recording-progress.json'
if (Test-Path -LiteralPath $candidateProgressPath) {
    $candidatePrior = Get-Content -LiteralPath $candidateProgressPath -Raw | ConvertFrom-Json
    if ($candidatePrior.source_head -ne $candidateMatrix.source_head) { throw 'Previous recording source differs' }
    if ($candidatePrior.pid) {
        $candidatePriorProcess = Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$candidatePrior.pid)
        if ($candidatePriorProcess -and $candidatePriorProcess.CommandLine.Contains([IO.Path]::GetFullPath($ReviewRoot))) { throw 'Capture is already running' }
    }
}
$candidateProgress = @{state='recording'; completed=@(); current=$null; pid=$null; source_head=$candidateMatrix.source_head; matrix=$Matrix; layout='simultaneous_front_side'}
try {
    foreach ($candidateOperation in @('walk_start','walk_stop')) {
        foreach ($candidateStyle in @('responsive','grounded','relaxed','heavy','sneaky')) {
            $candidateFolder = Join-Path $ReviewRoot "$candidateOperation\$candidateStyle"
            $candidateRoutePath = Join-Path $candidateFolder 'route.json'
            $candidateRoute = Get-Content -LiteralPath $candidateRoutePath -Raw | ConvertFrom-Json
            if (-not $candidateRoute.passed -or $candidateRoute.source_head -ne $candidateMatrix.source_head -or $candidateRoute.invocation_kind -ne 'ordinary call' -or $candidateRoute.phase -ne 'candidate') { throw 'Invalid ordinary public route' }
            foreach ($candidateCase in $candidateRoute.cases) {
                $candidateScene = Join-Path $ProjectRoot $candidateCase.scene.Substring(6)
                if ((Get-FileHash -LiteralPath $candidateScene -Algorithm SHA256).Hash.ToLower() -ne $candidateCase.scene_sha256) { throw 'Changed saved scene' }
            }
            foreach ($candidateMode in @('clean','diagnostic')) {
                $candidateProgress.current = "$candidateOperation/$candidateStyle/$candidateMode"
                Save-ReviewReceipt $candidateProgressPath $candidateProgress
                $candidateMediaPath = Join-Path $candidateFolder 'media.json'
                if (Test-Path -LiteralPath $candidateMediaPath) {
                    $candidateMedia = Get-Content -LiteralPath $candidateMediaPath -Raw | ConvertFrom-Json
                    $candidateVideo = $candidateMedia.videos.$candidateMode
                    if ($candidateVideo -and (Test-Path -LiteralPath $candidateVideo.path) -and $candidateVideo.decoded_frames -eq 1440 `
                            -and $candidateVideo.render.layout -eq 'simultaneous_front_side' -and $candidateVideo.render.source_head -eq $candidateRoute.source_head `
                            -and ((Get-FileHash -LiteralPath $candidateVideo.path -Algorithm SHA256).Hash.ToLower() -eq $candidateVideo.sha256)) {
                        $candidateProgress.completed += "$candidateOperation/$candidateStyle/$candidateMode (verified prior capture)"
                        continue
                    }
                }
                $candidateFrames = Join-Path $candidateFolder ($candidateMode+'_frames')
                if (Test-Path -LiteralPath $candidateFrames) {
                    $candidateRenderPath = Join-Path $candidateFrames 'render.json'
                    if (-not (Test-Path -LiteralPath $candidateRenderPath)) { throw "Inspect preserved incomplete frames: $candidateFrames" }
                    $candidateRender = Get-Content -LiteralPath $candidateRenderPath -Raw | ConvertFrom-Json
                    if ($candidateRender.frames -ne 1440 -or $candidateRender.errors.Count -or $candidateRender.source_head -ne $candidateRoute.source_head `
                            -or $candidateRender.mode -ne $candidateMode -or $candidateRender.layout -ne 'simultaneous_front_side' -or $candidateRender.cases.Count -ne 4) { throw 'Incomplete preserved native report' }
                } else {
                    $candidateArgs = @('--path',('"'+$ProjectRoot+'"'),'--rendering-method','gl_compatibility',
                        '--resolution','1920x1080','--disable-vsync','--script','res://tools/render_start_stop_candidate.gd',
                        '--',('"'+$candidateRoutePath+'"'),('"'+$candidateFrames+'"'),$candidateMode)
                    $candidateProcess = Start-Process -WindowStyle Hidden -FilePath $Godot -ArgumentList $candidateArgs -PassThru `
                        -RedirectStandardOutput (Join-Path $ReviewRoot "$candidateOperation-$candidateStyle-$candidateMode-render.log") `
                        -RedirectStandardError (Join-Path $ReviewRoot "$candidateOperation-$candidateStyle-$candidateMode-errors.log")
                    $null = $candidateProcess.Handle
                    $candidateProgress.pid = $candidateProcess.Id
                    Save-ReviewReceipt $candidateProgressPath $candidateProgress
                    $candidateProcess.WaitForExit()
                    if ($candidateProcess.ExitCode -ne 0) { throw 'Native candidate capture failed' }
                }
                & $Python (Join-Path $PSScriptRoot 'compose_character_quality.py') $candidateFolder --ffmpeg $Ffmpeg --mode $candidateMode
                if ($LASTEXITCODE -ne 0) { throw 'Movie encode/decode failed' }
                $candidateProgress.completed += "$candidateOperation/$candidateStyle/$candidateMode"
            }
        }
    }
    $candidateProgress.state = 'complete'; $candidateProgress.current=$null; $candidateProgress.pid=$null
} catch { $candidateProgress.state='failed'; $candidateProgress.error=$_.ToString(); throw }
finally { Save-ReviewReceipt $candidateProgressPath $candidateProgress }
