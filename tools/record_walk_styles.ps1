param(
    [Parameter(Mandatory=$true)][string]$ReviewRoot,
    [Parameter(Mandatory=$true)][string]$ReferenceRoot,
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$Godot,
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$Ffmpeg
)
$ErrorActionPreference = 'Stop'
$r1ProgressPath = Join-Path $ReviewRoot 'recording-progress.json'
$r1Progress = @{state='recording'; completed=@(); current=$null}
try {
    foreach ($r1Style in @('responsive','grounded','relaxed','heavy','sneaky')) {
        $r1Folder = Join-Path $ReviewRoot $r1Style
        $r1ReferenceStyle = if ($r1Style -eq 'grounded') { 'grounded' } else { 'responsive' }
        $r1Reference = Join-Path $ReferenceRoot ($r1ReferenceStyle+'\route.json')
        foreach ($r1Mode in @('clean','diagnostic')) {
            $r1Progress.current = "$r1Style/$r1Mode"
            $r1Progress | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $r1ProgressPath -Encoding UTF8
            $r1MediaPath = Join-Path $r1Folder 'media.json'
            if (Test-Path -LiteralPath $r1MediaPath) {
                $r1Media = Get-Content -LiteralPath $r1MediaPath -Raw | ConvertFrom-Json
                if ($r1Media.videos.$r1Mode -and (Test-Path -LiteralPath $r1Media.videos.$r1Mode.path) `
                        -and $r1Media.videos.$r1Mode.decoded_frames -eq 2880 `
                        -and ((Get-FileHash -LiteralPath $r1Media.videos.$r1Mode.path -Algorithm SHA256).Hash.ToLower() -eq $r1Media.videos.$r1Mode.sha256)) {
                    $r1Progress.completed += "$r1Style/$r1Mode (previous verified recording)"
                    continue
                }
            }
            $r1Frames = Join-Path $r1Folder ($r1Mode+'_frames')
            $r1Args = @('--path', ('"'+$ProjectRoot+'"'), '--rendering-method','gl_compatibility',
                '--resolution','1920x1080','--disable-vsync','--script','res://tools/render_walk_comparison.gd',
                '--',('"'+$r1Reference+'"'),('"'+(Join-Path $r1Folder 'route.json')+'"'),('"'+$r1Frames+'"'),$r1Mode)
            $r1Process = Start-Process -WindowStyle Hidden -FilePath $Godot -ArgumentList $r1Args -Wait -PassThru `
                -RedirectStandardOutput (Join-Path $ReviewRoot "$r1Style-$r1Mode-render.log") `
                -RedirectStandardError (Join-Path $ReviewRoot "$r1Style-$r1Mode-errors.log")
            if ($r1Process.ExitCode -ne 0) { throw "Native capture failed: $r1Style/$r1Mode" }
            & $Python (Join-Path $PSScriptRoot 'compose_character_quality.py') $r1Folder --ffmpeg $Ffmpeg --mode $r1Mode
            if ($LASTEXITCODE -ne 0) { throw "Encode/decode check failed: $r1Style/$r1Mode" }
            $r1Progress.completed += "$r1Style/$r1Mode"
        }
    }
    $r1Progress.state = 'complete'
    $r1Progress.current = $null
} catch {
    $r1Progress.state = 'failed'
    $r1Progress.error = $_.ToString()
    throw
} finally {
    $r1Progress | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $r1ProgressPath -Encoding UTF8
}
