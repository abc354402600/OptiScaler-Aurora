param([string]$ScratchRoot=(Join-Path $env:TEMP ('AuroraIncident-'+[Guid]::NewGuid().ToString('N'))))
. (Join-Path $PSScriptRoot 'Aurora_Hardening_TestSupport.ps1')
$pkg=Join-Path $ScratchRoot 'Package'; Package $pkg
$fixture=Join-Path $ScratchRoot 'Fixture\Game.exe'; Binary $fixture
function Exe([string]$Path) { [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null; [IO.File]::Copy($fixture,$Path,$true) }
function EraseFixture([string]$Path) {
    $full=Get-AuroraPath $Path
    if ($full -eq $ScratchRoot -or -not (Test-AuroraWithin $full $ScratchRoot)) { throw 'Unsafe test cleanup.' }
    Assert-AuroraPlainPath $full
    Remove-Item -LiteralPath $full -Recurse -Force
}
$nte=Join-Path $ScratchRoot '异环 空格\Client\WindowsNoEditor'
$win=Join-Path $nte 'HT\Binaries\Win64'; $ace=Join-Path $win 'AntiCheatExpert'
Exe (Join-Path $win 'HTGame.exe')
foreach ($name in @('ACE-Service64.exe','ACE-Setup64.exe','ACE-Tray.exe','Game.exe')) { Exe (Join-Path $ace $name) }
Exe (Join-Path $win 'CrashCapture.exe'); Exe (Join-Path $win 'CrashClientReporter.exe')
foreach ($rel in @('AntiCheatExpert\Game.exe','Win64\ACE-Service64.exe','ACE\Game.exe','ACe_Setup64.exe','CrashCapture.exe','CrashClientReporter.exe','BattlEye\Game.exe','EasyAntiCheat\Game.exe')) {
    Assert (Test-AuroraUtilityPath $rel) "Utility excluded: $rel"
}
Assert (-not (Test-AuroraUtilityPath 'Crashlands.exe')) 'Legitimate Crashlands is not a crash utility'
Assert (-not (Test-AuroraNteCrashCompanion (Join-Path $win 'CrashCapture.exe'))) 'A matching helper name with unknown bytes is not trusted'
Assert (@(Get-AuroraDeploymentCandidates (Get-AuroraScan $nte)).Count -eq 0) 'Unknown colocated helpers block auto-deployment; ACE is never the fallback'

# Synthetic stand-in for the two pinned companions. Only the hash lookup is
# substituted; names, path, Proxy policy, transaction and subprocesses stay real.
$companionPolicy=${function:Test-AuroraNteCrashCompanion}
$fixtureHash=Get-AuroraHash $fixture
function Test-AuroraNteCrashCompanion([string]$Path) {
    return ([IO.Path]::GetFileName($Path) -in @('CrashCapture.exe','CrashClientReporter.exe') -and (Get-AuroraHash $Path) -eq $script:fixtureHash)
}
$found=@(Get-AuroraDeploymentCandidates (Get-AuroraScan $nte))
Assert ($found.Count -eq 1 -and $found[0].Path -eq (Join-Path $win 'HTGame.exe')) 'The actual NTE directory shape selects HTGame only'
Assert ((Get-AuroraRecommendedProxy $found '') -eq 'winmm.dll') 'HTGame selects winmm'
Assert (-not (Test-AuroraCandidateDirectory $nte $found[0].Path 'dxgi.dll')) 'NTE dxgi override is blocked before deployment'
Exe (Join-Path $win 'Updater.exe')
Assert (@(Get-AuroraDeploymentCandidates (Get-AuroraScan $nte)).Count -eq 0) 'NTE exception never permits another unknown colocated utility'
Remove-Item -LiteralPath (Join-Path $win 'Updater.exe')
$ue=Join-Path $nte 'Engine\Plugins\Runtime\Nvidia\DLSS\Binaries\ThirdParty\Win64\nvngx_dlss.dll'
Binary $ue '310.1.0.0'; $before=Get-AuroraHash $ue
$acRuntime=Join-Path $ace 'nvngx_dlss.dll'; [IO.File]::Copy($ue,$acRuntime); $acHash=Get-AuroraHash $acRuntime
Assert (-not (Test-AuroraUtilityPath $ue.Substring($nte.Length).TrimStart('\') -Runtime)) 'UE ThirdParty native Runtime is eligible for normal version checks'
Assert (Test-AuroraUtilityPath 'Engine\Tools\ThirdParty\nvngx_dlss.dll' -Runtime) 'Engine Tools Runtime stays excluded'
Assert (Test-AuroraUtilityPath 'ThirdParty\Game.exe') 'ThirdParty executables remain excluded'
Deny { Install-AuroraDeployment $nte $pkg 'dxgi.dll' (Join-Path $ScratchRoot 'bad-proxy.json') } 'NTE explicit dxgi install cannot bypass the profile'
Assert (-not (Test-Path -LiteralPath (Join-Path $win 'dxgi.dll'))) 'Rejected override writes no Proxy'
$index=Install-AuroraDeployment $nte $pkg '' (Join-Path $ScratchRoot 'nte.json')
Assert ($index.Status -eq 'Applied' -and $index.Targets.Count -eq 1 -and $index.Targets[0].Directory -eq $win) 'Only the real NTE main directory is deployed'
Assert ((Get-AuroraHash (Join-Path $win 'winmm.dll')) -eq (Get-AuroraHash (Join-Path $win 'OptiScaler.dll')) -and -not (Test-Path -LiteralPath (Join-Path $win 'dxgi.dll'))) 'Complete core and winmm exist; no dxgi'
Assert (-not (Test-Path -LiteralPath (Join-Path $ace 'OptiScaler')) -and -not (Test-Path -LiteralPath (Join-Path $ace 'dxgi.dll')) -and -not (Test-Path -LiteralPath (Join-Path $ace 'OptiScaler.dll')) -and (Get-AuroraHash $acRuntime) -eq $acHash) 'No core, Proxy, metadata or Runtime changes in ACE'
Assert ((Get-AuroraHash $ue) -eq (Get-AuroraHash (Join-Path $pkg 'OptiScaler\nvngx_dlss.dll'))) 'UE native Runtime synchronized with a backup'
Assert ($index.RuntimeSummary.Synchronized -eq 1 -and $index.Verification[0].DiskVerified -and $index.Verification[0].GameLoaded -eq '未验证') 'Summary distinguishes verified disk state from untested game loading'
$rj=Join-Path $win 'OptiScaler\RuntimeSync\manifest.json'; $rjBytes=[IO.File]::ReadAllBytes($rj); Remove-Item -LiteralPath $rj
Deny { Install-AuroraDeployment $nte $pkg '' (Join-Path $ScratchRoot 'missing-runtime.json') } 'An active install cannot recreate a lost Runtime journal and orphan the original backup'
[IO.File]::WriteAllBytes($rj,$rjBytes)
$null=Remove-AuroraDeployment $index (Join-Path $ScratchRoot 'nte-remove.json')
Assert ((Get-AuroraHash $ue) -eq $before -and -not (Test-Path -LiteralPath (Join-Path $win 'winmm.dll'))) 'Remove restores the UE original and removes owned winmm'
# Reproduce the old build's completed-but-wrong ACE deployment index. All its
# files/journals disappear when the launcher rebuilds Win64 below.
$old=Open-AuroraIndex $nte; $old.Targets[0].Directory=$ace
$old.Targets[0].Executables=@((Join-Path $ace 'ACE-Service64.exe'))
$old.Targets[0].Proxy='dxgi.dll'; $old.Targets[0].JournalPath=Join-Path $ace 'OptiScaler\AuroraSetup\manifest.json'
$old.RuntimeOwners=@($ace); Write-AuroraJson (Get-AuroraIndexPath $nte) $old
EraseFixture $win
Exe (Join-Path $win 'HTGame.exe')
Deny { Open-AuroraIndex $nte } 'Strict ownership reader still rejects absent journals'
$completed=Open-AuroraIndex $nte -ForNewInstall
Assert ($completed.Status -eq 'Removed') 'New-install reader accepts a completed uninstall after launcher rebuild'
Deny { Remove-AuroraDeployment $completed (Join-Path $ScratchRoot 'unsafe-remove.json') } 'The new-install exception never authorizes Remove without journals'
$second=Install-AuroraDeployment $nte $pkg '' (Join-Path $ScratchRoot 'nte-rebuilt.json')
Assert ($second.Status -eq 'Applied' -and (Test-Path -LiteralPath (Join-Path $win 'winmm.dll'))) 'Reinstall after entire Win64 rebuild succeeds'
Assert ($second.Targets.Count -eq 1 -and $second.Targets[0].Directory -eq $win -and -not (Test-Path -LiteralPath $ace)) 'Completed legacy ACE target is retired, not carried into the new install'
Assert (@(Get-ChildItem -LiteralPath (Join-Path $nte 'OptiScaler\AuroraSetup\history') -File).Count -eq 1) 'Completed index is archived before the new transaction'
$missing=$second.Targets[0].JournalPath; $saved=[IO.File]::ReadAllBytes($missing); Remove-Item -LiteralPath $missing
Deny { Open-AuroraIndex $nte -ForNewInstall } 'Applied plus missing journal still fails closed even for install'
[IO.File]::WriteAllBytes($missing,$saved)
Set-Item Function:Test-AuroraNteCrashCompanion $companionPolicy

$generic=Join-Path $ScratchRoot 'Generic'; Exe (Join-Path $generic 'Win64\Game.exe'); Exe (Join-Path $generic 'Win64\CrashCapture.exe')
Assert (@(Get-AuroraDeploymentCandidates (Get-AuroraScan $generic)).Count -eq 0) 'Generic shared crash-helper directory is still blocked'
$steam=Join-Path $ScratchRoot 'Steam'; $otherGame=Join-Path $steam 'steamapps\common\OtherGame'
Exe (Join-Path $otherGame 'Win64\Game.exe'); Put (Join-Path $steam 'steamapps\appmanifest_1.acf') '"installdir" "OtherGame"'
$roots=@(Find-AuroraGames @($generic) @($steam))
Assert ($roots.Count -eq 1 -and $roots[0] -eq $generic) 'A blocked current game never silently falls back to an unrelated Steam game'
$nested=Join-Path $ScratchRoot 'Nested'; Exe (Join-Path $nested 'Binaries\Win64\Other\Unrelated.exe')
Assert (@(Get-AuroraDeploymentCandidates (Get-AuroraScan $nested)).Count -eq 0) 'Arbitrary children do not inherit Win64 rendering evidence'

$witcher=Join-Path $ScratchRoot '巫师 3'; $dx12=Join-Path $witcher 'bin\x64_dx12'; $dx11=Join-Path $witcher 'bin\x64'
Exe (Join-Path $dx12 'witcher3.exe'); Exe (Join-Path $dx11 'witcher3.exe')
Binary (Join-Path $dx12 'sl.interposer.dll') '1.5.6.0'; $sl1=Get-AuroraHash (Join-Path $dx12 'sl.interposer.dll')
Binary (Join-Path $dx12 'nvngx_dlss.dll') '3.1.1.0'
$w=Install-AuroraDeployment $witcher $pkg '' (Join-Path $ScratchRoot 'witcher.json')
Assert ($w.Targets.Count -eq 2 -and $w.Verification.Count -eq 2 -and $w.RuntimeSummary.SL1Preserved -eq 1) 'Both Witcher entries verified with SL1 protection visible'
Assert ((Get-AuroraHash (Join-Path $dx12 'sl.interposer.dll')) -eq $sl1) 'SL1 1.5.6 bytes unchanged'
foreach ($dir in @($dx11,$dx12)) { Assert ((Get-AuroraHash (Join-Path $dir 'dxgi.dll')) -eq (Get-AuroraHash (Join-Path $dir 'OptiScaler.dll'))) "Self-contained core and Proxy: $dir" }

# New late failure: a first target changes after its individual copy has passed.
$late=Join-Path $ScratchRoot 'Late'; $la=Join-Path $late 'Win64'; $lb=Join-Path $late 'Win64r'
Exe (Join-Path $la 'Game.exe'); Exe (Join-Path $lb 'Game.exe')
$installFile=${function:Install-AuroraFile}; $injected=$false
function Install-AuroraFile($Journal,[string]$JournalPath,[string]$Source,[string]$Target,[string]$ExpectedSourceHash,[string]$ExpectedTargetHash) {
    & $script:installFile $Journal $JournalPath $Source $Target $ExpectedSourceHash $ExpectedTargetHash
    if ($Target -eq (Join-Path $script:lb 'dxgi.dll')) { Put (Join-Path $script:la 'dxgi.dll') 'late external modification'; $script:injected=$true }
}
try { Deny { Install-AuroraDeployment $late $pkg '' (Join-Path $ScratchRoot 'late.json') } 'Final whole-install verification rejects a late change' }
finally { Set-Item Function:Install-AuroraFile $installFile }
$lateIndex=Open-AuroraIndex $late
Assert ($injected -and $lateIndex.Status -eq 'NeedsAttention') 'Late failure cannot persist an Applied state'
$kept=@(Remove-AuroraDeployment $lateIndex (Join-Path $ScratchRoot 'late-remove.json'))
Assert ($kept -contains (Join-Path $la 'dxgi.dll') -and [IO.File]::ReadAllText((Join-Path $la 'dxgi.dll')) -eq 'late external modification') 'Remove preserves the changed Proxy after final verification failure'

$logs=Join-Path $ScratchRoot 'Logs'
$active=New-AuroraReportSession $logs 3
$unknown=New-AuroraReportSession $logs 3; Put (Join-Path ([IO.Path]::GetDirectoryName($unknown.ReportPath)) 'user-notes.txt') 'keep'; $unknown.Lease.Dispose()
for ($i=0; $i -lt 7; $i++) { $s=New-AuroraReportSession $logs 3; Write-AuroraJson $s.ReportPath @{Test=$i}; $s.Lease.Dispose() }
Assert (Test-Path -LiteralPath ([IO.Path]::GetDirectoryName($active.ReportPath))) 'Retention preserves a locked active session'
Assert (Test-Path -LiteralPath (Join-Path ([IO.Path]::GetDirectoryName($unknown.ReportPath)) 'user-notes.txt')) 'Retention preserves an unknown user file and its session'
Assert (@(Get-ChildItem -LiteralPath $logs -Directory).Count -eq 5) 'Retention keeps three recent sessions plus active and unknown sessions'
$active.Lease.Dispose()
$outside=Join-Path $ScratchRoot 'OutsideLogs'; Put (Join-Path $outside 'session.json') '{"Kind":"AuroraReports","Version":1}'; Put (Join-Path $outside 'report.json') 'outside sentinel'
$link=Join-Path $logs ('a'*32); New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
$last=New-AuroraReportSession $logs 1; $last.Lease.Dispose()
Assert ([IO.File]::ReadAllText((Join-Path $outside 'report.json')) -eq 'outside sentinel') 'Log retention never follows a session junction'
$linkedGame=Join-Path $ScratchRoot 'LinkedGame'; [IO.Directory]::CreateDirectory($linkedGame) | Out-Null
New-Item -ItemType Junction -Path (Join-Path $linkedGame 'Win64') -Target $outside | Out-Null
Deny { Test-AuroraCandidateDirectory $linkedGame (Join-Path $linkedGame 'Win64\Game.exe') } 'Shared-directory safety check cannot enumerate outside through a junction'
Finish 'INSTALL INCIDENT'
