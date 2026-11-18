param(
    [Parameter(Mandatory=$true)][string]$ReviewRoot,
    [Parameter(Mandatory=$true)][string]$BaselineRoot,
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$Godot,
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$Ffmpeg
)
$ErrorActionPreference = 'Stop'
$runProgressPath = Join-Path $ReviewRoot 'recording-progress.json'
$runProgress = @{state='recording'; completed=@(); current=$null}
try {
    foreach ($runStyle in @('responsive','grounded','relaxed','heavy','sneaky')) {
        $runFolder = Join-Path $ReviewRoot $runStyle
        $runReference = Join-Path $BaselineRoot ($runStyle+'\route.json')
        $runRoute = Get-Content -LiteralPath (Join-Path $runFolder 'route.json') -Raw | ConvertFrom-Json
        $runNative = Get-Content -LiteralPath (Join-Path $runFolder 'native-check.json') -Raw | ConvertFrom-Json
        if (-not $runRoute.passed -or -not $runNative.passed) { throw "Failed route/native gate: $runStyle" }
        foreach ($runMode in @('clean','diagnostic')) {
            $runProgress.current = "$runStyle/$runMode"
            $runProgress | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $runProgressPath -Encoding UTF8
            $runMediaPath = Join-Path $runFolder 'media.json'
            if (Test-Path -LiteralPath $runMediaPath) {
                $runMedia = Get-Content -LiteralPath $runMediaPath -Raw | ConvertFrom-Json
                $runVideo = $runMedia.videos.$runMode
                if ($runVideo -and (Test-Path -LiteralPath $runVideo.path) -and $runVideo.decoded_frames -eq 2880 `
                        -and $runVideo.render.source_head -eq $runRoute.source_head `
                        -and ((Get-FileHash -LiteralPath $runVideo.path -Algorithm SHA256).Hash.ToLower() -eq $runVideo.sha256)) {
                    $runProgress.completed += "$runStyle/$runMode (previous verified recording)"
                    continue
                }
            }
            $runFrames = Join-Path $runFolder ($runMode+'_frames')
            $runArgs = @('--path', ('"'+$ProjectRoot+'"'), '--rendering-method','gl_compatibility',
                '--resolution','1920x1080','--disable-vsync','--script','res://tools/render_run_comparison.gd',
                '--',('"'+$runReference+'"'),('"'+(Join-Path $runFolder 'route.json')+'"'),('"'+$runFrames+'"'),$runMode)
            $runProcess = Start-Process -WindowStyle Hidden -FilePath $Godot -ArgumentList $runArgs -Wait -PassThru `
                -RedirectStandardOutput (Join-Path $ReviewRoot "$runStyle-$runMode-render.log") `
                -RedirectStandardError (Join-Path $ReviewRoot "$runStyle-$runMode-errors.log")
            if ($runProcess.ExitCode -ne 0) { throw "Native capture failed: $runStyle/$runMode" }
            & $Python (Join-Path $PSScriptRoot 'compose_character_quality.py') $runFolder --ffmpeg $Ffmpeg --mode $runMode
            if ($LASTEXITCODE -ne 0) { throw "Encode/decode check failed: $runStyle/$runMode" }
            $runProgress.completed += "$runStyle/$runMode"
        }
    }
    $runProgress.state = 'complete'
    $runProgress.current = $null
} catch {
    $runProgress.state = 'failed'
    $runProgress.error = $_.ToString()
    throw
} finally {
    $runProgress | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $runProgressPath -Encoding UTF8
}
