param(
    [Parameter(Mandatory=$true)][string]$ReviewRoot,
    [Parameter(Mandatory=$true)][string]$Baseline,
    [Parameter(Mandatory=$true)][string]$Godot,
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$Ffmpeg
)
$ErrorActionPreference = 'Stop'
$reviewRepo = Split-Path -Parent $PSScriptRoot
$reviewRootPath = [IO.Path]::GetFullPath($ReviewRoot)
$reviewProgressPath = Join-Path $reviewRootPath 'recording-progress.json'
$reviewProgress = @{state='recording'; completed=@(); current=$null}
try {
    foreach ($reviewProfile in @('grounded','responsive')) {
        $reviewFolder = Join-Path $reviewRootPath $reviewProfile
        $reviewReference = if (Test-Path -LiteralPath $Baseline -PathType Container) { Join-Path $Baseline "$reviewProfile\route.json" } else { $Baseline }
        foreach ($reviewMode in @('clean','diagnostic')) {
            $reviewProgress.current = "$reviewProfile/$reviewMode"
            $reviewProgress | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reviewProgressPath -Encoding UTF8
            $reviewFrames = Join-Path $reviewFolder ($reviewMode+'_frames')
            $reviewArgs = @('--path', ('"'+(Join-Path $reviewRepo 'test_project')+'"'),
                '--rendering-method','gl_compatibility','--resolution','1920x1080','--disable-vsync',
                '--script','res://tools/render_walk_comparison.gd','--',
                ('"'+$reviewReference+'"'), ('"'+(Join-Path $reviewFolder 'route.json')+'"'),
                ('"'+$reviewFrames+'"'),$reviewMode)
            $reviewProcess = Start-Process -WindowStyle Hidden -FilePath $Godot -ArgumentList $reviewArgs -Wait -PassThru `
                -RedirectStandardOutput (Join-Path $reviewRootPath "$reviewProfile-$reviewMode-render.log") `
                -RedirectStandardError (Join-Path $reviewRootPath "$reviewProfile-$reviewMode-errors.log")
            if ($reviewProcess.ExitCode -ne 0) { throw "Native capture failed: $reviewProfile/$reviewMode" }
            & $Python (Join-Path $PSScriptRoot 'compose_character_quality.py') $reviewFolder --ffmpeg $Ffmpeg --mode $reviewMode
            if ($LASTEXITCODE -ne 0) { throw "Encode/decode check failed: $reviewProfile/$reviewMode" }
            $reviewProgress.completed += "$reviewProfile/$reviewMode"
        }
    }
    $reviewProgress.state = 'complete'
    $reviewProgress.current = $null
} catch {
    $reviewProgress.state = 'failed'
    $reviewProgress.error = $_.ToString()
    throw
} finally {
    $reviewProgress | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reviewProgressPath -Encoding UTF8
}
