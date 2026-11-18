param(
    [Parameter(Mandatory=$true)][string]$ReviewRoot,
    [Parameter(Mandatory=$true)][string]$BaselineRoot,
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$Godot,
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$Ffmpeg
)
$ErrorActionPreference = 'Stop'
$idleMatrix = Get-Content -LiteralPath (Join-Path $ReviewRoot 'native-matrix.json') -Raw | ConvertFrom-Json
if (-not $idleMatrix.passed -or $idleMatrix.native_runs -ne 240) { throw 'Complete 240-run idle matrix required' }
$idleProgressPath = Join-Path $ReviewRoot 'recording-progress.json'
if (Test-Path -LiteralPath $idleProgressPath) {
    $idlePrevious = Get-Content -LiteralPath $idleProgressPath -Raw | ConvertFrom-Json
    if ($idlePrevious.pid) {
        $idlePriorProcess = Get-CimInstance Win32_Process -Filter ("ProcessId="+[int]$idlePrevious.pid)
        if ($idlePriorProcess -and $idlePriorProcess.ExecutablePath -eq [IO.Path]::GetFullPath($Godot) `
                -and $idlePriorProcess.CommandLine.Contains([IO.Path]::GetFullPath($ReviewRoot))) {
            throw 'This idle capture is still running; inspect progress instead of starting a duplicate'
        }
    }
}
$idleProgress = @{state='recording'; completed=@(); current=$null; pid=$null; source_head=$idleMatrix.source_head}
try {
    foreach ($idleStyle in @('responsive','grounded','relaxed','heavy','sneaky')) {
        $idleFolder = Join-Path $ReviewRoot $idleStyle
        $idleReference = Join-Path $BaselineRoot ($idleStyle+'-in-place\route.json')
        $idleRoute = Get-Content -LiteralPath (Join-Path $idleFolder 'route.json') -Raw | ConvertFrom-Json
        $idleNative = Get-Content -LiteralPath (Join-Path $idleFolder 'native-check.json') -Raw | ConvertFrom-Json
        if (-not $idleRoute.passed -or -not $idleNative.passed -or $idleRoute.operation -ne 'idle_cycle' `
                -or $idleRoute.phase -ne 'candidate' -or $idleRoute.source_head -ne $idleMatrix.source_head) {
            throw "Failed ordinary idle route/native gate: $idleStyle"
        }
        if (@($idleRoute.cases | Where-Object { $_.write.length -gt 3.0 }).Count -ne 0) {
            throw 'Six-second chapters require idle periods <= 3 s; extend capture/composer before using longer output'
        }
        foreach ($idleMode in @('clean','diagnostic')) {
            $idleProgress.current = "$idleStyle/$idleMode"
            $idleProgress | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $idleProgressPath -Encoding UTF8
            $idleMediaPath = Join-Path $idleFolder 'media.json'
            if (Test-Path -LiteralPath $idleMediaPath) {
                $idleMedia = Get-Content -LiteralPath $idleMediaPath -Raw | ConvertFrom-Json
                $idleVideo = $idleMedia.videos.$idleMode
                if ($idleVideo -and (Test-Path -LiteralPath $idleVideo.path) -and $idleVideo.decoded_frames -eq 2880 `
                        -and $idleVideo.render.source_head -eq $idleRoute.source_head `
                        -and ((Get-FileHash -LiteralPath $idleVideo.path -Algorithm SHA256).Hash.ToLower() -eq $idleVideo.sha256)) {
                    $idleProgress.completed += "$idleStyle/$idleMode (previous verified recording)"
                    continue
                }
            }
            $idleFrames = Join-Path $idleFolder ($idleMode+'_frames')
            if (Test-Path -LiteralPath $idleFrames) { throw "Inspect preserved incomplete frames before resuming: $idleFrames" }
            $idleArgs = @('--path', ('"'+$ProjectRoot+'"'), '--rendering-method','gl_compatibility',
                '--resolution','1920x1080','--disable-vsync','--script','res://tools/render_idle_comparison.gd',
                '--',('"'+$idleReference+'"'),('"'+(Join-Path $idleFolder 'route.json')+'"'),('"'+$idleFrames+'"'),$idleMode)
            $idleProcess = Start-Process -WindowStyle Hidden -FilePath $Godot -ArgumentList $idleArgs -PassThru `
                -RedirectStandardOutput (Join-Path $ReviewRoot "$idleStyle-$idleMode-render.log") `
                -RedirectStandardError (Join-Path $ReviewRoot "$idleStyle-$idleMode-errors.log")
            $idleProgress.pid = $idleProcess.Id
            $idleProgress | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $idleProgressPath -Encoding UTF8
            $idleProcess.WaitForExit()
            if ($idleProcess.ExitCode -ne 0) { throw "Native capture failed: $idleStyle/$idleMode" }
            & $Python (Join-Path $PSScriptRoot 'compose_character_quality.py') $idleFolder --ffmpeg $Ffmpeg --mode $idleMode
            if ($LASTEXITCODE -ne 0) { throw "Encode/decode check failed: $idleStyle/$idleMode" }
            $idleProgress.completed += "$idleStyle/$idleMode"
        }
    }
    $idleProgress.state = 'complete'
    $idleProgress.current = $null
    $idleProgress.pid = $null
} catch {
    $idleProgress.state = 'failed'
    $idleProgress.error = $_.ToString()
    throw
} finally {
    $idleProgress | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $idleProgressPath -Encoding UTF8
}
