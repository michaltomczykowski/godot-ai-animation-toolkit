param(
    [Parameter(Mandatory=$true)][string]$Route,
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$Godot,
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$Ffmpeg,
    [ValidateSet('clean','diagnostic')][string]$Mode='clean'
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'review_receipts.ps1')
$captureRoute=Read-ReviewReceipt $Route
if(-not $captureRoute.passed){throw 'Public scene route is not green'}
if($captureRoute.operation -notin @('strafe_cycle','jump')){throw 'Unsupported recording operation'}
$captureRoot=Split-Path -Parent $Route
$captureFrames=Join-Path $captureRoot ($Mode+'_frames')
if(Test-Path -LiteralPath $captureFrames){throw 'Preserve existing frames; use a fresh recording attempt'}
foreach($captureCase in $captureRoute.cases){
    $captureScene=Join-Path $ProjectRoot $captureCase.scene.Substring(6)
    if((Get-FileHash -LiteralPath $captureScene -Algorithm SHA256).Hash.ToLower() -ne $captureCase.scene_sha256){throw 'Saved public scene changed'}
}
$captureDrive=[System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($captureRoot))
if($captureDrive.AvailableFreeSpace -lt 5GB){throw 'Insufficient capture space'}
if(Get-Process -ErrorAction SilentlyContinue | Where-Object {$_.ProcessName -like 'Godot*'}){throw 'Close local Godot editor/test/render jobs before recording'}
$captureScript=if($captureRoute.operation -eq 'jump'){'res://tools/render_jump_quality.gd'}else{'res://tools/render_strafe_quality.gd'}
$captureArgs=@('--path',$ProjectRoot,'--rendering-method','gl_compatibility','--resolution','1920x1080','--disable-vsync','--script',$captureScript,'--',$Route,$captureFrames,$Mode)
$captureProgress=@{state='recording';route_sha256=(Get-FileHash -LiteralPath $Route -Algorithm SHA256).Hash.ToLower();mode=$Mode;renderer=$captureScript;pid=$null;recorder_sha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLower()}
$captureProgressPath=Join-Path $captureRoot ('recording-'+$Mode+'.json')
Save-ReviewReceipt $captureProgressPath $captureProgress
try {
    $captureProcess=Start-Process -WindowStyle Hidden -FilePath $Godot -ArgumentList $captureArgs -PassThru -RedirectStandardOutput (Join-Path $captureRoot ($Mode+'-render.log')) -RedirectStandardError (Join-Path $captureRoot ($Mode+'-errors.log'))
    $null=$captureProcess.Handle
    $captureProgress.pid=$captureProcess.Id
    $captureProgress.started_utc=$captureProcess.StartTime.ToUniversalTime().ToString('o')
    Save-ReviewReceipt $captureProgressPath $captureProgress
    $captureProcess.WaitForExit()
    if($captureProcess.ExitCode -ne 0){throw 'Native capture failed'}
    & $Python (Join-Path $PSScriptRoot 'compose_character_quality.py') $captureRoot --ffmpeg $Ffmpeg --mode $Mode
    if($LASTEXITCODE -ne 0){throw 'Encoding/independent decode failed'}
    $captureProgress.state='complete'
} catch {$captureProgress.state='failed';$captureProgress.error=$_.ToString();throw}
finally {$captureProgress.pid=$null;Save-ReviewReceipt $captureProgressPath $captureProgress}
