param([string]$ScratchRoot=(Join-Path $env:TEMP ('AuroraPackageBoundary-'+[Guid]::NewGuid().ToString('N'))))
. (Join-Path $PSScriptRoot 'Aurora_Hardening_TestSupport.ps1')
$clean=Join-Path $ScratchRoot 'checkout'; [IO.Directory]::CreateDirectory((Join-Path $clean 'dist')) | Out-Null
Copy-Item -LiteralPath $toolsDir -Destination (Join-Path $clean 'dist\runtime_sync') -Recurse
foreach ($relative in @('package_release.ps1','setup_windows.bat','OptiScaler.ini','scripts\stage_aurora_package.ps1')) {
    $dest=Join-Path $clean $relative; [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest)) | Out-Null
    [IO.File]::Copy((Join-Path $repo $relative),$dest)
}
$outside=Join-Path $ScratchRoot 'outside'; Put (Join-Path $outside 'sentinel.txt') 'outside untouched'
$sentinel=Get-AuroraHash (Join-Path $outside 'sentinel.txt')
function Rejected([string[]]$Arguments,[string]$Name,[string]$ExpectedMessage) {
    $ErrorActionPreference='Continue'
    $result=& powershell.exe -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1
    $code=$LASTEXITCODE; $ErrorActionPreference='Stop'
    $text=$result | Out-String
    Assert ($code -ne 0 -and $text -match $ExpectedMessage) $Name
}
$link=Join-Path $clean 'release'; New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
Rejected @('-File',(Join-Path $clean 'package_release.ps1'),'-SkipBuild','-Version','test') 'Package rejects release junction before output mutation' '重解析|联接|reparse|链接'
$stage=Join-Path $clean 'scripts\stage_aurora_package.ps1'
Rejected @('-File',$stage,'-Destination',$outside) 'Actions staging rejects destination outside checkout' 'inside this checkout'
Rejected @('-File',$stage,'-Destination',(Join-Path $link 'artifact')) 'Actions staging rejects child of destination junction' '重解析|联接|reparse|链接'
$sourceLink=Join-Path $clean 'dist\streamline'; New-Item -ItemType Junction -Path $sourceLink -Target $outside | Out-Null
Rejected @('-File',$stage,'-Destination',(Join-Path $clean 'artifact')) 'Actions staging rejects linked Runtime sources' '重解析|联接|reparse|链接'
Assert ((Get-AuroraHash (Join-Path $outside 'sentinel.txt')) -eq $sentinel) 'Outside sentinel unchanged by all packaging failures'
Assert (@(Get-ChildItem -LiteralPath $outside -Force).Count -eq 1) 'No output file or directory created through junction'
Finish 'PACKAGE BOUNDARY'
