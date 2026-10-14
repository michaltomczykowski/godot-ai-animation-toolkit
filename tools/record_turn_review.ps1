param(
    [Parameter(Mandatory=$true)][string]$ReviewRoot,
    [Parameter(Mandatory=$true)][string]$ProjectRoot,
    [Parameter(Mandatory=$true)][string]$Godot,
    [Parameter(Mandatory=$true)][string]$Python,
    [Parameter(Mandatory=$true)][string]$Ffmpeg,
    [string[]]$Styles=@('responsive'),
    [string[]]$Modes=@('clean','diagnostic'),
    [string]$Matrix,
    [switch]$Baseline
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'review_receipts.ps1')
if(-not $Baseline){
    if(-not $Matrix){throw 'Candidate recordings require native matrix'}
    $turnMatrix=Read-ReviewReceipt $Matrix
    if(-not $turnMatrix.passed){throw 'Candidate native matrix is not green'}
}
$turnProgressPath=Join-Path $ReviewRoot 'recording-progress.json'
if(Test-Path -LiteralPath $turnProgressPath){throw 'Preserve the previous recording attempt and its progress receipt'}
$turnProgress=@{state='recording';completed=@();current=$null;pid=$null;baseline=[bool]$Baseline}
try {
    foreach($turnVariant in @('left90','right90','left180','right180')){
        foreach($turnStyle in $Styles){
            $turnFolder=Join-Path $ReviewRoot "$turnVariant/$turnStyle"
            $turnRoutePath=Join-Path $turnFolder 'route.json'
            $turnRoute=Read-ReviewReceipt $turnRoutePath
            if(-not $turnRoute.passed -or $turnRoute.operation -ne 'turn_cycle' -or $turnRoute.cases.Count -ne 4){throw 'Invalid public turn route'}
            if($Baseline -and $turnRoute.phase -ne 'baseline'){throw 'Expected original baseline'}
            if(-not $Baseline -and $turnRoute.source_head -ne $turnMatrix.source_head){throw 'Candidate source differs from played matrix'}
            if(-not $Baseline){
                $turnCovered=@($turnMatrix.rows | Where-Object {$_.name -eq "$turnVariant-$turnStyle" -and $_.passed})
                if($turnCovered.Count -ne 1){throw 'Recording route is absent from the passing native matrix'}
                if((Get-FileHash -LiteralPath $turnCovered[0].route -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $turnRoutePath -Algorithm SHA256).Hash){throw 'Recording route differs from its measured receipt'}
            }
            foreach($turnCase in $turnRoute.cases){
                $turnScene=Join-Path $ProjectRoot $turnCase.scene.Substring(6)
                if((Get-FileHash -LiteralPath $turnScene -Algorithm SHA256).Hash.ToLower() -ne $turnCase.scene_sha256){throw 'Saved turn scene changed'}
            }
            foreach($turnMode in $Modes){
                $turnDrive=[System.IO.DriveInfo]::new([System.IO.Path]::GetPathRoot($ReviewRoot))
                if($turnDrive.AvailableFreeSpace -lt 1.5GB){throw 'Insufficient capture space; preserve frames and use a fresh recording attempt'}
                $turnProgress.current="$turnVariant/$turnStyle/$turnMode"
                Save-ReviewReceipt $turnProgressPath $turnProgress
                $turnFrames=Join-Path $turnFolder ($turnMode+'_frames')
                if(Test-Path -LiteralPath $turnFrames){throw "Preserve existing frames; inspect receipt before retry: $turnFrames"}
                $turnArgs=@('--path',('"'+$ProjectRoot+'"'),'--rendering-method','gl_compatibility','--resolution','1920x1080','--disable-vsync','--script','res://tools/render_turn_quality.gd','--',('"'+$turnRoutePath+'"'),('"'+$turnFrames+'"'),$turnMode)
                $turnProcess=Start-Process -WindowStyle Hidden -FilePath $Godot -ArgumentList $turnArgs -PassThru -RedirectStandardOutput (Join-Path $ReviewRoot "$turnVariant-$turnStyle-$turnMode-render.log") -RedirectStandardError (Join-Path $ReviewRoot "$turnVariant-$turnStyle-$turnMode-errors.log")
                $null=$turnProcess.Handle
                $turnProgress.pid=$turnProcess.Id
                Save-ReviewReceipt $turnProgressPath $turnProgress
                $turnProcess.WaitForExit()
                if($turnProcess.ExitCode -ne 0){throw 'Native turn capture failed'}
                & $Python (Join-Path $PSScriptRoot 'compose_character_quality.py') $turnFolder --ffmpeg $Ffmpeg --mode $turnMode
                if($LASTEXITCODE -ne 0){throw 'Turn encode/decode failed'}
                $turnProgress.completed+=$turnProgress.current
            }
        }
    }
    $turnProgress.state='complete'; $turnProgress.current=$null; $turnProgress.pid=$null
} catch {$turnProgress.state='failed';$turnProgress.error=$_.ToString();throw}
finally {Save-ReviewReceipt $turnProgressPath $turnProgress}
