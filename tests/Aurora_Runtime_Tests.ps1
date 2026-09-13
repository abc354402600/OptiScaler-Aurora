param([string]$ScratchRoot=(Join-Path $env:TEMP ('AuroraTests-'+[Guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$toolsDir=Join-Path $repo 'dist\runtime_sync'
. (Join-Path $toolsDir 'Aurora_Common.ps1')
$ScratchRoot=Get-AuroraPath $ScratchRoot
if (Test-Path -LiteralPath $ScratchRoot) { throw 'Tests require a new empty scratch path.' }
[IO.Directory]::CreateDirectory($ScratchRoot) | Out-Null
$passed=0
function Assert($Condition,[string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++; Write-Host "PASS: $Name"
}
function Expect-Failure([scriptblock]$Body,[string]$Name) {
    $threw=$false; try { & $Body } catch { $threw=$true }
    Assert $threw $Name
}
function Put([string]$Path,[string]$Text) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path,$Text)
}
function Make-Binary([string]$Path,[string]$Version,[string]$Platform='x64') {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    $src=Join-Path $ScratchRoot ([Guid]::NewGuid().ToString('N')+'.cs')
    Put $src ('using System.Reflection; [assembly: AssemblyVersion("'+$Version+'")] [assembly: AssemblyFileVersion("'+$Version+'")] public class Fixture { public static void Main() {} }')
    $kind='library'; if ([IO.Path]::GetExtension($Path) -eq '.exe') { $kind='exe' }
    & (Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo "/target:$kind" "/platform:$Platform" "/out:$Path" $src
    if ($LASTEXITCODE) { throw 'Fixture compiler failed' }
}
function Run-Runtime([string]$Mode,[string]$Game,[string]$Install,[int]$Expected=0) {
    $out=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $toolsDir 'runtime_sync.ps1') -Mode $Mode -GameRoot $Game -InstallDir $Install 2>&1
    if ($LASTEXITCODE -ne $Expected) { $out | Write-Host; throw "Runtime $Mode returned $LASTEXITCODE, expected $Expected" }
}

# Paths: Launcher -> UE, Win64/Win64r, runtime locations under Data/Assets/Engine.
$game=Join-Path $ScratchRoot "游戏 [A] ! & O'Brien"
$launch=Join-Path $game 'NTELauncher\NTEGame.exe'
$exe=Join-Path $game 'Client\WindowsNoEditor\HT\Binaries\Win64\HTGame.exe'
Make-Binary $launch '1.0.0.0'; Make-Binary $exe '1.0.0.0'
Make-Binary (Join-Path $game 'Engine\Binaries\Win64\UEEditor.exe') '1.0.0.0'
Make-Binary (Join-Path $game 'Win64\wwm.exe') '1.0.0.0'
Make-Binary (Join-Path $game 'Win64r\wwm.exe') '1.0.0.0'
Make-Binary (Join-Path $game 'Wrong32.exe') '1.0.0.0' 'x86'
Put (Join-Path $game 'Data\Assets\Plugins\nvngx_dlss.dll') 'unknown'
$scan=Get-AuroraScan $game; $c=@(Get-AuroraCandidates $scan)
Assert $scan.Complete 'Full scan including Data/Assets'
Assert (@($scan.Files | Where-Object {$_.Name -eq 'nvngx_dlss.dll'}).Count -eq 1) 'Scattered runtime inventoried'
Assert ($c.Count -eq 3) 'Reject launcher, Engine executable and x86; retain both Win64 variants'
Assert ($c[0].Path -eq $exe) 'UE HTGame preferred to bootstrap'
Assert ($c[1].Path -match 'Win64r') 'Win64r preference with both candidates retained'
Assert ((Resolve-AuroraGameRoot $launch) -eq $game) 'Launcher input expands to game directory'
Assert (-not (Get-AuroraScan $game 1).Complete) 'Scan budget truncation is visible'
Expect-Failure { Assert-AuroraGameRoot ([IO.Path]::GetPathRoot($game)) } 'Reject drive root'

# Journal: backup, idempotence, upgrades, failure before atomic replacement, conflicts.
$install=Join-Path $game 'Win64r'; $jp=Join-Path $install 'OptiScaler\AuroraSetup\manifest.json'
$j=Open-AuroraJournal $jp $game $install
$target=Join-Path $install 'test.dll'; $source=Join-Path $ScratchRoot 'source.dll'
Put $target 'original'; Put $source 'release one'; $original=Get-AuroraHash $target
Install-AuroraFile $j $jp $source $target
Assert ((Get-AuroraHash $target) -eq (Get-AuroraHash $source)) 'Install hash verified'
Assert ((Get-AuroraHash $j.Entries[0].BackupPath) -eq $original) 'Original backup verified'
Install-AuroraFile $j $jp $source $target
Assert ($j.Entries.Count -eq 1) 'Repeated install is idempotent'
Put $source 'release two'; Install-AuroraFile $j $jp $source $target
Assert ((Get-AuroraHash $j.Entries[0].BackupPath) -eq $original) 'Upgrade preserves original backup'
$j=Open-AuroraJournal $jp $game $install
Assert ((Restore-AuroraJournal $j $jp) -eq 0) 'Restore succeeds'
Assert ((Get-AuroraHash $target) -eq $original) 'Restored bytes equal original'
Install-AuroraFile $j $jp $source $target; Put $target 'game update'
Assert ((Restore-AuroraJournal $j $jp) -eq 1) 'Game update is preserved and reported as unresolved'
Assert ([IO.File]::ReadAllText($target) -eq 'game update') 'No overwrite on restore conflict'
Expect-Failure { Install-AuroraFile $j $jp $source $target } 'Repair does not silently overwrite a changed managed file'
$locked=Join-Path $install 'locked.dll'; Put $locked 'locked original'
$lock=[IO.File]::Open($locked,'Open','ReadWrite','None')
try { Expect-Failure { Install-AuroraFile $j $jp $source $locked } 'Locked target rejected' } finally {$lock.Dispose()}
Assert ([IO.File]::ReadAllText($locked) -eq 'locked original') 'Locked target unchanged'
Put $jp '{broken'
Expect-Failure { Open-AuroraJournal $jp $game $install } 'Corrupt manifest is fail-closed'

# Real PE version metadata fixtures: SL1 / unknown / mixed sets and DLSSNR untouched.
$runtimeGame=Join-Path $ScratchRoot 'RuntimeGame'; $runtimeInstall=Join-Path $runtimeGame 'bin'
$rtOpti=Join-Path $runtimeInstall 'OptiScaler'
Make-Binary (Join-Path $rtOpti 'streamline\sl.common.dll') '2.13.0.0'
Make-Binary (Join-Path $rtOpti 'nvngx_dlss.dll') '310.9.0.0'
$sl1=Join-Path $runtimeGame 'Engine\Plugins\sl.common.dll'
$sl2=Join-Path $runtimeGame 'Data\sl.interposer.dll'
$dlss=Join-Path $runtimeGame 'Assets\Plugins\nvngx_dlss.dll'
$nr=Join-Path $runtimeGame 'Data\nvngx_dlssnr.dll'
Make-Binary $sl1 '1.5.6.0'; Make-Binary $sl2 '2.12.0.0'; Make-Binary $dlss '310.8.0.0'; Put $nr 'user NR'
Make-Binary (Join-Path $rtOpti 'streamline\sl.interposer.dll') '2.13.0.0'
$h1=Get-AuroraHash $sl1; $h2=Get-AuroraHash $sl2; $hd=Get-AuroraHash $dlss
Run-Runtime Check $runtimeGame $runtimeInstall
Assert ((Get-AuroraHash $dlss) -eq $hd) 'Check never modifies game runtime'
Assert (-not (Test-Path -LiteralPath (Join-Path $rtOpti 'RuntimeSync'))) 'Check never creates manifest or backup'
Run-Runtime Install $runtimeGame $runtimeInstall
Assert ((Get-AuroraHash $sl1) -eq $h1 -and (Get-AuroraHash $sl2) -eq $h2) 'SL1 protects entire mixed native Streamline set'
Assert ((Get-AuroraHash $dlss) -eq (Get-AuroraHash (Join-Path $rtOpti 'nvngx_dlss.dll'))) 'Known DLSS sync succeeds'
Assert ([IO.File]::ReadAllText($nr) -eq 'user NR') 'DLSSNR untouched'
Run-Runtime Restore $runtimeGame $runtimeInstall
Assert ((Get-AuroraHash $dlss) -eq $hd) 'Runtime restore verifies original DLL'
Put $sl1 'unknown SL'
Run-Runtime Install $runtimeGame $runtimeInstall
Assert ((Get-AuroraHash $sl2) -eq $h2) 'Unknown SL protects otherwise recognized sibling'
Put $dlss 'unversioned DLSS'
Run-Runtime Install $runtimeGame $runtimeInstall
Assert ([IO.File]::ReadAllText($dlss) -eq 'unversioned DLSS') 'Unknown DLSS fail-closed'

# Installation from a separate package; proxy conflicts and safe manifest-only removal.
$pkg=Join-Path $ScratchRoot 'Package'
[IO.Directory]::CreateDirectory($pkg) | Out-Null
foreach ($f in Get-ChildItem -LiteralPath $toolsDir -File) { Copy-Item -LiteralPath $f.FullName -Destination $pkg }
Make-Binary (Join-Path $pkg 'OptiScaler.dll') '1.0.0.0'
Make-Binary (Join-Path $pkg 'OptiScaler\nvngx_dlss.dll') '310.9.0.0'
Put (Join-Path $pkg 'OptiScaler.ini') "[FG]`nDualFeature=false`nDxgi=auto"
$setupGame=Join-Path $ScratchRoot 'SetupGame'; $setupExe=Join-Path $setupGame 'Win64r\Game.exe'
Make-Binary $setupExe '1.0.0.0'
$setupInstall=Split-Path -Parent $setupExe
$setupScript=Join-Path $pkg 'Aurora_Setup.ps1'
$out=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setupScript -Action Install -NonInteractive -PackageDir $pkg -GameRoot $setupGame -GameExe $setupExe -Proxy winmm.dll 2>&1
if ($LASTEXITCODE) { $out | Write-Host; throw 'Setup failed' }
Assert ((Get-AuroraHash (Join-Path $setupInstall 'winmm.dll')) -eq (Get-AuroraHash (Join-Path $pkg 'OptiScaler.dll'))) 'Manual winmm choice deployed'
Put (Join-Path $setupInstall 'user-mod.txt') 'keep me'
Put (Join-Path $setupInstall 'OptiScaler.ini') 'user edited settings'
$out=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $setupInstall 'Aurora_Setup.ps1') -Action Remove -NonInteractive -InstallDir $setupInstall 2>&1
if ($LASTEXITCODE) { $out | Write-Host; throw 'Removal failed' }
Assert (-not (Test-Path -LiteralPath (Join-Path $setupInstall 'winmm.dll'))) 'Tracked proxy removed'
Assert (Test-Path -LiteralPath (Join-Path $setupInstall 'user-mod.txt')) 'Unrelated file preserved'
Assert ([IO.File]::ReadAllText((Join-Path $setupInstall 'OptiScaler.ini')) -eq 'user edited settings') 'Edited user INI preserved during self-uninstall'
Put (Join-Path $setupInstall 'dxgi.dll') 'another mod'
$out=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setupScript -Action Install -NonInteractive -PackageDir $pkg -GameRoot $setupGame -GameExe $setupExe -Proxy dxgi.dll 2>&1
Assert ($LASTEXITCODE -ne 0) 'Unknown proxy collision fails closed'
Assert ([IO.File]::ReadAllText((Join-Path $setupInstall 'dxgi.dll')) -eq 'another mod') 'Other mod proxy unchanged'
# Journal recovery after interruption, tampered backup, traversal and reparse points.
$safeGame=Join-Path $ScratchRoot 'RecoveryGame'; [IO.Directory]::CreateDirectory($safeGame) | Out-Null
$safeJp=Join-Path $safeGame 'OptiScaler\AuroraSetup\manifest.json'
$safeTarget=Join-Path $safeGame 'native.dll'; Put $safeTarget 'native'
$safeJ=Open-AuroraJournal $safeJp $safeGame $safeGame
Install-AuroraFile $safeJ $safeJp $source $safeTarget
$prior=Get-AuroraHash $safeTarget
$safeJ.Entries[0].BeforeHash=$prior; $safeJ.Entries[0].DeployedHash=('A'*64); $safeJ.Entries[0].Status='Pending'
Write-AuroraJson $safeJp $safeJ
$safeJ=Open-AuroraJournal $safeJp $safeGame $safeGame
Assert ((Restore-AuroraJournal $safeJ $safeJp) -eq 0) 'Interrupted upgrade restores from journal BeforeHash'
Assert ([IO.File]::ReadAllText($safeTarget) -eq 'native') 'Interrupted upgrade recovers original bytes'
Install-AuroraFile $safeJ $safeJp $source $safeTarget
Put $safeJ.Entries[0].BackupPath 'corrupt backup'
Assert ((Restore-AuroraJournal $safeJ $safeJp) -eq 1) 'Corrupt backup prevents restore'
Assert ((Get-AuroraHash $safeTarget) -eq (Get-AuroraHash $source)) 'Corrupt backup does not change target'
$safeJ.Entries[0].TargetPath=Join-Path $ScratchRoot 'outside.dll'; Write-AuroraJson $safeJp $safeJ
Expect-Failure { Open-AuroraJournal $safeJp $safeGame $safeGame } 'Manifest target traversal rejected'
$safeJ.Entries[0].TargetPath=$safeTarget; $safeJ.Entries[0].BackupPath=$source; Write-AuroraJson $safeJp $safeJ
Expect-Failure { Open-AuroraJournal $safeJp $safeGame $safeGame } 'Manifest backup traversal rejected'
Expect-Failure { Assert-AuroraRestoreReady $safeJ } 'Uninstall preflight detects damaged backup before deleting recovery tools'
$rootLock=Enter-AuroraLock $safeGame
try { Expect-Failure { Enter-AuroraLock $safeGame } 'Concurrent operation blocked' } finally {$rootLock.Dispose()}
$link=Join-Path $safeGame 'LinkedData'
New-Item -ItemType Junction -Path $link -Target $runtimeGame | Out-Null
Assert (-not (Get-AuroraScan $safeGame).Complete) 'Junction skipped and scan incomplete'
Expect-Failure { Assert-AuroraPlainPath (Join-Path $link 'Data\sl.interposer.dll') } 'Writing through junction rejected'

# v1 manifest migration and recovery must work even without a bundled source folder.
$legacyGame=Join-Path $ScratchRoot 'LegacyGame'; $legacyTarget=Join-Path $legacyGame 'sl.interposer.dll'
$legacyJp=Join-Path $legacyGame 'OptiScaler\RuntimeSync\manifest.json'
$legacyBackup=Join-Path $legacyGame 'OptiScaler\RuntimeSync\backup\legacy\sl.interposer.dll'
Make-Binary $legacyBackup '1.5.6.0'; Make-Binary $legacyTarget '2.13.0.0'
$legacyManifest=[pscustomobject]@{SchemaVersion=1;InstallDir=$legacyGame;ScanRoot=$legacyGame;Entries=@([pscustomobject]@{TargetPath=$legacyTarget;SourceName='sl.interposer.dll';BackupPath=$legacyBackup;OriginalHash=(Get-AuroraHash $legacyBackup);DeployedHash=(Get-AuroraHash $legacyTarget)})}
Write-AuroraJson $legacyJp $legacyManifest
Run-Runtime Restore $legacyGame $legacyGame
Assert ((Get-AuroraBinary $legacyTarget).Major -eq 1) 'v1 restore works without any bundled runtime'
Assert ((Get-Content -LiteralPath $legacyJp -Raw | ConvertFrom-Json).SchemaVersion -eq 2) 'v1 journal safely migrates to v2'
Make-Binary (Join-Path $legacyGame 'OptiScaler\streamline\sl.interposer.dll') '2.13.0.0'
[IO.File]::Copy((Join-Path $legacyGame 'OptiScaler\streamline\sl.interposer.dll'),$legacyTarget,$true)
$legacyManifest.Entries[0].DeployedHash=Get-AuroraHash $legacyTarget
Write-AuroraJson $legacyJp $legacyManifest
Run-Runtime Check $legacyGame $legacyGame
Assert ((Get-AuroraBinary $legacyTarget).Major -eq 2) 'Check does not mutate even for legacy SL1 recovery'
Run-Runtime Install $legacyGame $legacyGame
Assert ((Get-AuroraBinary $legacyTarget).Major -eq 1) 'Install recovers previously overwritten SL1 from verified v1 backup'

# SL2-only updates and unknown source cannot be mistaken for compatible upgrades.
$only2=Join-Path $ScratchRoot 'OnlySL2'; $onlyTarget=Join-Path $only2 'Data\sl.common.dll'
$onlySource=Join-Path $only2 'OptiScaler\streamline\sl.common.dll'
Make-Binary $onlySource '2.13.0.0'; Make-Binary $onlyTarget '2.12.0.0'
Run-Runtime Install $only2 $only2
Assert ((Get-AuroraHash $onlyTarget) -eq (Get-AuroraHash $onlySource)) 'Recognized SL2-only group can update'
Run-Runtime Restore $only2 $only2
$old2=Get-AuroraHash $onlyTarget; Put $onlySource 'unknown source'
Run-Runtime Install $only2 $only2
Assert ((Get-AuroraHash $onlyTarget) -eq $old2) 'Unknown source runtime cannot overwrite known SL2'
Write-Host "ALL PASSED: $passed assertions. Fixtures retained at $ScratchRoot"
