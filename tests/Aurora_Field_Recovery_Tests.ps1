param([string]$ScratchRoot=(Join-Path $env:TEMP ('AuroraFieldRecovery-'+[Guid]::NewGuid().ToString('N'))))
. (Join-Path $PSScriptRoot 'Aurora_Hardening_TestSupport.ps1')
$pkg=Join-Path $ScratchRoot 'Package'; Package $pkg
$exe=Join-Path $ScratchRoot 'Fixture\Game.exe'; Binary $exe
function Exe([string]$Path) { [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null; [IO.File]::Copy($exe,$Path,$true) }

$cp=Join-Path $ScratchRoot '中文 空格 Cyberpunk 2077'; $bin=Join-Path $cp 'bin\x64'
$game=Join-Path $bin 'Cyberpunk2077.exe'; $helper=Join-Path $bin 'REDEngineErrorReporter.exe'
Exe $game; Exe $helper
Assert (-not (Test-AuroraCyberpunkCrashCompanion $helper)) 'Unknown reporter bytes are not trusted by name'
$scan=Get-AuroraScan $cp
Assert (@(Get-AuroraDeploymentCandidates $scan).Count -eq 0) 'Unknown colocated reporter still blocks deployment'
Assert ($scan.CandidateRejections.Count -eq 1 -and $scan.CandidateRejections[0].Companion -eq $helper) 'Report identifies the blocking helper instead of saying EXE absent'
$policy=${function:Test-AuroraCyberpunkCrashCompanion}; $fixtureHash=Get-AuroraHash $exe
function Test-AuroraCyberpunkCrashCompanion([string]$Path) { return ([IO.Path]::GetFileName($Path) -ieq 'REDEngineErrorReporter.exe' -and (Get-AuroraHash $Path) -eq $script:fixtureHash) }
$c=@(Get-AuroraDeploymentCandidates (Get-AuroraScan $cp))
Assert ($c.Count -eq 1 -and $c[0].Path -eq $game) 'Pinned reporter permits only Cyberpunk2077'
foreach ($proxy in @('version.dll','dbghelp.dll','winmm.dll')) { Assert (-not (Test-AuroraCandidateDirectory $cp $game $proxy)) "Reporter exception does not authorize $proxy" }
Assert (Test-AuroraCandidateDirectory $cp $game 'dxgi.dll') 'Reviewed Cyberpunk dxgi pair is admitted'
Exe (Join-Path $bin 'OtherGame.exe')
Assert (@(Get-AuroraDeploymentCandidates (Get-AuroraScan $cp)).Count -eq 1) 'Directory cache cannot share the exception with another EXE'
Exe (Join-Path $bin 'Updater.exe')
Assert (@(Get-AuroraDeploymentCandidates (Get-AuroraScan $cp)).Count -eq 0) 'Extra updater blocks even the pinned game profile'
Remove-Item -LiteralPath (Join-Path $bin 'Updater.exe')
Remove-Item -LiteralPath (Join-Path $bin 'OtherGame.exe')
$cpIndex=Install-AuroraDeployment $cp $pkg '' (Join-Path $ScratchRoot 'cp-install.json')
Assert ($cpIndex.Status -eq 'Applied' -and $cpIndex.Targets.Count -eq 1 -and $cpIndex.Targets[0].Proxy -eq 'dxgi.dll') 'Full synthetic Cyberpunk deployment selects one dxgi target'
Assert ((Get-AuroraHash $helper) -eq $fixtureHash) 'Reporter bytes remain unchanged'
$null=Remove-AuroraDeployment $cpIndex (Join-Path $ScratchRoot 'cp-remove.json')
Assert (-not (Test-Path -LiteralPath (Join-Path $bin 'dxgi.dll'))) 'Remove deletes the owned Cyberpunk proxy'
Set-Item Function:Test-AuroraCyberpunkCrashCompanion $policy

# Reproduce an external restoration of an already managed native runtime.
$root=Join-Path $ScratchRoot '游戏 恢复'; $win=Join-Path $root 'Win64'; Exe (Join-Path $win 'Game.exe')
$native=Join-Path $root 'Engine\Plugins\Runtime\Nvidia\DLSS\Binaries\ThirdParty\Win64\nvngx_dlss.dll'
Binary $native '310.5.0.0'; $original=Get-AuroraHash $native
$index=Install-AuroraDeployment $root $pkg '' (Join-Path $ScratchRoot 'first.json')
$jp=Join-Path $win 'OptiScaler\RuntimeSync\manifest.json'
$j=Open-AuroraJournal $jp $root $win; $backup=$j.Entries[0].BackupPath
foreach ($status in @('Applied','Preserved','Pending')) {
    [IO.File]::Copy($backup,$native,$true)
    $j=Open-AuroraJournal $jp $root $win; $j.Entries[0].Status=$status
    Write-AuroraJson $jp $j
    $index=Install-AuroraDeployment $root $pkg '' (Join-Path $ScratchRoot ($status+'.json'))
    $j=Open-AuroraJournal $jp $root $win
    Assert ($index.Status -eq 'Applied' -and $j.Entries[0].Status -eq 'Applied') "Update resumes externally restored $status runtime"
    Assert ($j.Entries[0].BackupPath -eq $backup -and (Get-AuroraHash $backup) -eq $original) "Original backup retained across $status resume"
}
[IO.File]::Copy($backup,$native,$true); $backupBytes=[IO.File]::ReadAllBytes($backup)
Put $backup 'damaged'
Deny { Install-AuroraFile $j $jp (Join-Path $pkg 'OptiScaler\nvngx_dlss.dll') $native } 'Corrupted original backup blocks resume'
Assert ((Get-AuroraHash $native) -eq $original) 'Backup rejection leaves original untouched'
[IO.File]::WriteAllBytes($backup,$backupBytes)
Remove-Item -LiteralPath $backup
Deny { Install-AuroraFile $j $jp (Join-Path $pkg 'OptiScaler\nvngx_dlss.dll') $native } 'Missing backup blocks resume'
[IO.File]::WriteAllBytes($backup,$backupBytes)
Put $native 'user-modified-runtime'; $changed=Get-AuroraHash $native
Deny { Install-AuroraFile $j $jp (Join-Path $pkg 'OptiScaler\nvngx_dlss.dll') $native } 'Unknown changed bytes cannot be adopted'
Assert ((Get-AuroraHash $native) -eq $changed) 'User runtime preserved after rejection'

# A preserved record must settle after a launcher restores the exact original;
# otherwise Remove remains NeedsAttention forever and blocks a clean reinstall.
$j=Open-AuroraJournal $jp $root $win; $j.Entries[0].Status='Preserved'; Write-AuroraJson $jp $j
[IO.File]::Copy($backup,$native,$true)
$kept=@(Remove-AuroraDeployment $index (Join-Path $ScratchRoot 'remove-settled.json'))
Assert ($kept.Count -eq 0 -and (Open-AuroraIndex $root).Status -eq 'Removed') 'Exact original settles previously Preserved record on Remove'
Assert ((Get-AuroraHash $native) -eq $original) 'Settlement performs no runtime replacement'
$again=Install-AuroraDeployment $root $pkg '' (Join-Path $ScratchRoot 'clean-reinstall.json')
Assert ($again.Status -eq 'Applied') 'Install after settled Remove succeeds'
$j=Open-AuroraJournal $jp $root $win; $j.Entries[0].Status='Preserved'; Write-AuroraJson $jp $j
Put $native 'still-user-modified'
$kept=@(Remove-AuroraDeployment $again (Join-Path $ScratchRoot 'remove-kept.json'))
Assert ($kept -contains $native -and (Open-AuroraIndex $root).Status -eq 'NeedsAttention') 'Unknown preserved runtime still needs attention'

# The runtime exception must not extend to core/Proxy ownership.
$coreRoot=Join-Path $ScratchRoot 'CoreBoundary'; [IO.Directory]::CreateDirectory($coreRoot) | Out-Null
$coreJournal=Join-Path $coreRoot 'OptiScaler\AuroraSetup\manifest.json'; $target=Join-Path $coreRoot 'dxgi.dll'
Put $target 'third-party-original'; $j=Open-AuroraJournal $coreJournal $coreRoot $coreRoot
Install-AuroraFile $j $coreJournal (Join-Path $pkg 'OptiScaler.dll') $target
[IO.File]::Copy($j.Entries[0].BackupPath,$target,$true)
Deny { Install-AuroraFile $j $coreJournal (Join-Path $pkg 'OptiScaler.dll') $target } 'Restored core/Proxy cannot use runtime-only exception'
Finish 'field recovery'
