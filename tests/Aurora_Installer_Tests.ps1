param([string]$ScratchRoot=(Join-Path $env:TEMP ('AuroraRC3Tests-'+[Guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot; $toolsDir=Join-Path $repo 'dist\runtime_sync'
. (Join-Path $toolsDir 'Aurora_Common.ps1')
. (Join-Path $toolsDir 'Aurora_Installer.ps1')
$ScratchRoot=Get-AuroraPath $ScratchRoot
if (Test-Path -LiteralPath $ScratchRoot) { throw 'Use a new scratch directory.' }
[IO.Directory]::CreateDirectory($ScratchRoot) | Out-Null
$passed=0
function Assert($Condition,[string]$Name) { if (-not $Condition) { throw "FAIL: $Name" }; $script:passed++; Write-Host "PASS: $Name" }
function Expect-Failure([scriptblock]$Body,[string]$Name) { $failed=$false; try { & $Body | Out-Null } catch { $failed=$true }; Assert $failed $Name }
function Put([string]$Path,[string]$Text) { [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null; [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($true))) }
function Fixture([string]$Path,[string]$Version='3.0.0.0',[string]$Platform='x64') {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    $source=Join-Path $ScratchRoot ([Guid]::NewGuid().ToString('N')+'.cs')
    Put $source ('using System.Reflection; [assembly: AssemblyVersion("'+$Version+'")] [assembly: AssemblyFileVersion("'+$Version+'")] public class Fixture { public static void Main() {} }')
    $kind='library'; if ([IO.Path]::GetExtension($Path) -ieq '.exe') { $kind='exe' }
    & (Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo "/target:$kind" "/platform:$Platform" "/out:$Path" $source
    if ($LASTEXITCODE) { throw 'Fixture compiler failed.' }
}
function Run-Setup([string]$Action,[string]$Root,[string]$Package,[string]$Install='', [int]$Expected=0,[string]$Proxy='', [string]$Script=(Join-Path $toolsDir 'Aurora_Setup.ps1')) {
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$Script,'-Action',$Action,'-NonInteractive')
    if ($Root) { $args+=@('-GameRoot',$Root) }; if ($Package) { $args+=@('-PackageDir',$Package) }; if ($Install) { $args+=@('-InstallDir',$Install) }; if ($Proxy) { $args+=@('-Proxy',$Proxy) }
    $output=& powershell.exe @args 2>&1
    $script:lastOutput=$output -join "`n"
    if ($LASTEXITCODE -ne $Expected) { $output | Write-Host; throw "Setup $Action returned $LASTEXITCODE, expected $Expected" }
}

$game=Join-Path $ScratchRoot "巫师 3 [DX] ! & O'Brien"
$dx12=Join-Path $game 'bin\x64_dx12'; $dx11=Join-Path $game 'bin\x64'
Fixture (Join-Path $dx12 'witcher3.exe'); Fixture (Join-Path $dx11 'witcher3.exe')
$fixtureExe=Join-Path $dx12 'witcher3.exe'
$excluded=@('Launcher\Start.exe','NTELauncher\NTEGame.exe','Binaries\Win64\CrashReporter.exe','Binaries\Win64\UnrealEditor.exe','Binaries\Win64\EasyAntiCheat.exe','EAC\Game.exe','BattlEye\Game.exe','CEF\Game.exe','Redist\Game.exe','Prerequisites\Game.exe','Engine\Binaries\Win64\Game.exe','Tools\Win64\Game.exe','Updater\Game.exe','Binaries\Win64\Bootstrap.exe','Binaries\Win64\Uninstall.exe','Binaries\Win64\ModManager.exe','Binaries\Win64\Benchmark.exe','Binaries\Win64\Crashpad_handler.exe')
foreach ($rel in $excluded) { $p=Join-Path $game $rel; [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p)) | Out-Null; [IO.File]::Copy($fixtureExe,$p) }
Fixture (Join-Path $game 'Win64\Wrong32.exe') '1.0.0.0' 'x86'
Put (Join-Path $game 'Win64\Fake.exe') 'not PE'
Fixture (Join-Path $game 'Unknown.exe')
$scan=Get-AuroraScan $game; $c=@(Get-AuroraDeploymentCandidates $scan)
Assert ($c.Count -eq 2) 'Witcher DX11 and DX12 retained; utility, x86, invalid and weak EXEs excluded'
Assert ((Resolve-AuroraDeploymentRoot (Join-Path $dx11 'witcher3.exe')) -eq $game) 'DX11 path expands to entire game'
Assert ((Resolve-AuroraDeploymentRoot $dx12) -eq $game) 'DX12 path expands to entire game'
Assert (@(Find-AuroraGames @($dx12)).Count -eq 1) 'Extraction context auto discovery needs no manual path'
$special=Join-Path $ScratchRoot 'SpecialLayouts'
foreach ($rel in @('Client\Binaries\Win64\HTGame.exe','Win64\wwm.exe','Win64r\wwm.exe','Binaries\Win64\Crashlands.exe','Unity\Moon.exe')) {
    $p=Join-Path $special $rel; [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p)) | Out-Null; [IO.File]::Copy($fixtureExe,$p)
}
Put (Join-Path $special 'Unity\Moon_Data\data') 'Unity data'
$sc=@(Get-AuroraDeploymentCandidates (Get-AuroraScan $special))
Assert ($sc.Count -eq 5) 'HTGame, both wwm paths, Crashlands and Unity are not falsely excluded'
Assert ((Get-AuroraRecommendedProxy @($sc | Where-Object { $_.Path -like '*HTGame.exe' }) '') -eq 'winmm.dll') 'NTE automatically recommends winmm'
Assert ((Get-AuroraRecommendedProxy $c '') -eq 'dxgi.dll') 'Witcher default proxy is dxgi'
Assert ((Get-AuroraRecommendedProxy $sc 'version.dll') -eq 'version.dll') 'Advanced explicit proxy honored'
Expect-Failure { Install-AuroraDeployment $game $ScratchRoot '' (Join-Path $ScratchRoot 'bad.json') } 'Invalid package fails before writes'

$steam=Join-Path $ScratchRoot 'Steam'; $library=Join-Path $ScratchRoot 'Other Steam 库'
Put (Join-Path $steam 'steamapps\libraryfolders.vdf') ('"libraryfolders" { "1" { "path" "'+$library.Replace('\','\\')+'" } }')
Put (Join-Path $library 'steamapps\appmanifest_1.acf') '"AppState" { "installdir" "Test Game" }'
$steamGame=Join-Path $library 'steamapps\common\Test Game'
Fixture (Join-Path $steamGame 'Win64\Game.exe')
Assert (@(Get-AuroraSteamRoots @($steam)) -contains $steamGame) 'Steam additional VDF library with spaces and Chinese discovered'
Assert (@(Find-AuroraGames @($ScratchRoot+'\Missing') @($steam)) -contains $steamGame) 'Steam fallback recognizes actual game'

$pkg=Join-Path $ScratchRoot '发布包'
Fixture (Join-Path $pkg 'OptiScaler.dll')
Fixture (Join-Path $pkg 'OptiScaler\nvngx_dlss.dll') '310.9.0.0'
Put (Join-Path $pkg 'OptiScaler.ini') "[FrameGen]`nDualFeature=false`nDxgi=auto`n"
Put (Join-Path $pkg 'OptiScaler\plugins\OptiPatcher.asi') 'bundled patcher'
Put (Join-Path $pkg 'OptiScaler\plugins\OtherMod.asi') 'must not transfer'
foreach ($f in @(Get-ChildItem -LiteralPath $toolsDir -File)) { [IO.File]::Copy($f.FullName,(Join-Path $pkg $f.Name)) }
$native12=Join-Path $dx12 'nvngx_dlss.dll'; $native11=Join-Path $dx11 'nvngx_dlss.dll'
Fixture $native12 '310.8.0.0'; Fixture $native11 '310.7.0.0'
$h12=Get-AuroraHash $native12; $h11=Get-AuroraHash $native11
$sl1=Join-Path $dx12 'sl.interposer.dll'; Fixture $sl1 '1.5.6.0'; $sl1Hash=Get-AuroraHash $sl1
$sl2=Join-Path $dx11 'sl.interposer.dll'; Fixture $sl2 '2.12.0.0'; $sl2Hash=Get-AuroraHash $sl2
[IO.Directory]::CreateDirectory((Join-Path $pkg 'OptiScaler\streamline')) | Out-Null
[IO.File]::Copy((Join-Path $repo 'dist\streamline\sl.interposer.dll'),(Join-Path $pkg 'OptiScaler\streamline\sl.interposer.dll'))
$toolRuntime=Join-Path $game 'Launcher\nvngx_dlss.dll'; Fixture $toolRuntime '310.1.0.0'; $ht=Get-AuroraHash $toolRuntime
Run-Setup Install $game $pkg
Assert ($lastOutput.Contains('安装完成') -and -not ($lastOutput -match '[A-F0-9]{64}|\[已校验\]|SL1\.5')) 'Ordinary output is Chinese conclusions without hashes or per-file logs'
$index=Open-AuroraIndex $game
Assert ($index.Targets.Count -eq 2 -and $index.Status -eq 'Applied') 'One transaction covers both directories'
foreach ($dir in @($dx11,$dx12)) {
    Assert ((Get-AuroraHash (Join-Path $dir 'dxgi.dll')) -eq (Get-AuroraHash (Join-Path $pkg 'OptiScaler.dll'))) 'Each directory has its own verified Proxy'
    Assert ((Test-Path -LiteralPath (Join-Path $dir 'OptiScaler.dll')) -and (Test-Path -LiteralPath (Join-Path $dir 'OptiScaler\nvngx_dlss.dll')) -and (Test-Path -LiteralPath (Join-Path $dir 'Aurora_Installer.ps1'))) 'Each directory contains a complete standalone core and tools'
    Assert ([IO.File]::ReadAllText((Join-Path $dir 'OptiScaler.ini')).Contains('DualFeature=false')) 'Each new INI preserves DualFeature=false'
    Assert (-not (Test-Path -LiteralPath (Join-Path $dir 'OptiScaler\plugins\OtherMod.asi'))) 'Arbitrary package plugins are not propagated'
}
foreach ($rel in $excluded) { Assert (-not (Test-Path -LiteralPath (Join-Path ([IO.Path]::GetDirectoryName((Join-Path $game $rel))) 'dxgi.dll'))) ('No injection: '+$rel) }
Assert ((Get-AuroraHash $native11) -eq (Get-AuroraHash $native12) -and (Get-AuroraHash $native12) -ne $h12) 'Both native DLSS copies safely synchronized'
Assert ((Get-AuroraHash $sl1) -eq $sl1Hash -and (Get-AuroraHash $sl2) -eq $sl2Hash) 'SL1 1.5.6 and mixed native SL2 preserved by RC2 global guard'
Assert ((Get-AuroraHash $toolRuntime) -eq $ht) 'Launcher runtime is inventoried but never synchronized'
Assert ($index.RuntimeGroups.Count -eq 3) 'Multiple native Runtime groups recorded'
Assert (@($index.RuntimeGroups | Where-Object { $_.Directory -eq $dx11 -and $_.Association -eq 'SameDirectory' -and $_.CandidatePaths.Count -eq 1 }).Count -eq 1) 'Co-located Runtime group association recorded without claiming loaded evidence'
Assert (@($index.Targets | Where-Object { $_.RuntimeGroupIds.Count -gt 0 }).Count -eq 2) 'Every entry records associated group IDs'
$jp=$index.Targets[0].JournalPath; $j=Open-AuroraJournal $jp $game $index.Targets[0].Directory
Assert (@($j.Entries | Where-Object { $_.Created -and $_.DeployedHash.Length -eq 64 }).Count -gt 5) 'Manifest stores created flags and deployed SHA256'
$runtimeJp=Join-Path $index.RuntimeOwners[0] 'OptiScaler\RuntimeSync\manifest.json'; $rj=Open-AuroraJournal $runtimeJp $game $index.RuntimeOwners[0]
Assert (@($rj.Entries | Where-Object { $_.OriginalHash.Length -eq 64 -and $_.BackupPath -and (Get-AuroraHash $_.BackupPath) -eq $_.OriginalHash }).Count -eq 2) 'Runtime journal records original hashes and verified backup paths'
Run-Setup Install $game $pkg
Assert ((Open-AuroraJournal $jp $game $index.Targets[0].Directory).Entries.Count -eq $j.Entries.Count) 'Reinstall is idempotent and does not lose ownership'
Put (Join-Path $dx11 'OptiScaler.ini') 'user changed settings'
Put (Join-Path $dx12 'dxgi.dll') 'ReShade replacement by user'
Put (Join-Path $dx11 'version.dll') 'Special K unrelated'
Run-Setup Remove '' '' $dx11 0 '' (Join-Path $dx11 'Aurora_Setup.ps1')
Assert ((Get-AuroraHash $native11) -eq $h11 -and (Get-AuroraHash $native12) -eq $h12) 'Self-uninstall from either entry restores all original runtime copies'
Assert (-not (Test-Path -LiteralPath (Join-Path $dx11 'dxgi.dll')) -and -not (Test-Path -LiteralPath (Join-Path $dx12 'OptiScaler.dll')) -and -not (Test-Path -LiteralPath (Join-Path $dx12 'Aurora_Installer.ps1'))) 'Unchanged copies removed across all entries'
Assert ([IO.File]::ReadAllText((Join-Path $dx12 'dxgi.dll')) -eq 'ReShade replacement by user') 'Modified Proxy is preserved instead of deleting ReShade'
Assert ([IO.File]::ReadAllText((Join-Path $dx11 'version.dll')) -eq 'Special K unrelated') 'Untracked third party DLL is preserved'
Assert ([IO.File]::ReadAllText((Join-Path $dx11 'OptiScaler.ini')) -eq 'user changed settings') 'User configuration is preserved'
Assert ($lastOutput.Contains('用户修改文件')) 'Preserved files produce a Chinese warning'

$collision=Join-Path $ScratchRoot 'Collision'
Fixture (Join-Path $collision 'Win64\Game.exe'); Fixture (Join-Path $collision 'Win64r\Game.exe')
Put (Join-Path $collision 'Win64r\dxgi.dll') 'third party'
Run-Setup Install $collision $pkg '' 4
Assert (-not (Test-Path -LiteralPath (Join-Path $collision 'Win64\OptiScaler.dll'))) 'Collision in later entry aborts before any core write'
Assert (-not (Test-Path -LiteralPath (Get-AuroraIndexPath $collision))) 'Failed preflight does not create a deployment manifest'

$only2=Join-Path $ScratchRoot 'OnlySL2'; $onlyDir=Join-Path $only2 'Win64'
Fixture (Join-Path $onlyDir 'Game.exe'); $onlySL=Join-Path $onlyDir 'sl.interposer.dll'; Fixture $onlySL '2.12.0.0'; $oldSL=Get-AuroraHash $onlySL
Run-Setup Install $only2 $pkg
Assert ((Get-AuroraHash $onlySL) -eq (Get-AuroraHash (Join-Path $pkg 'OptiScaler\streamline\sl.interposer.dll'))) 'Recognized SL2 syncs only from pinned RC2 source hash'
$onlyIndex=Open-AuroraIndex $only2
$oj=Open-AuroraJournal (Join-Path $onlyDir 'OptiScaler\RuntimeSync\manifest.json') $only2 $onlyDir
$backup=$oj.Entries[0].BackupPath; $backupBytes=[IO.File]::ReadAllBytes($backup); Put $backup 'damaged'
Run-Setup Remove $only2 '' $onlyDir 4
Assert (Test-Path -LiteralPath (Join-Path $onlyDir 'dxgi.dll')) 'Corrupt backup stops removal before deleting recovery tools or Proxy'
[IO.File]::WriteAllBytes($backup,$backupBytes)
Run-Setup Remove $only2 '' $onlyDir
Assert ((Get-AuroraHash $onlySL) -eq $oldSL) 'Verified SL2 backup restores exact original bytes'

$unverified=Join-Path $ScratchRoot 'Unverified'; $unDir=Join-Path $unverified 'Win64'
Fixture (Join-Path $unDir 'Game.exe'); Fixture (Join-Path $unDir 'sl.interposer.dll') '2.12.0.0'
$beforeSL=Get-AuroraHash (Join-Path $unDir 'sl.interposer.dll')
$catalogSource=Join-Path $pkg 'OptiScaler\streamline\sl.interposer.dll'; [IO.File]::Delete($catalogSource); Fixture $catalogSource '2.99.0.0'
Run-Setup Install $unverified $pkg
Assert ((Get-AuroraHash (Join-Path $unDir 'sl.interposer.dll')) -eq $beforeSL) 'Unpinned x64 SL2 source fails closed even with valid version'
Run-Setup Remove $unverified '' $unDir
Put (Join-Path $unDir 'sl.interposer.dll') 'unknown Streamline'; Put (Join-Path $unDir 'nvngx_dlss.dll') 'unknown DLSS'
Run-Setup Install $unverified $pkg
Assert ([IO.File]::ReadAllText((Join-Path $unDir 'sl.interposer.dll')) -eq 'unknown Streamline' -and [IO.File]::ReadAllText((Join-Path $unDir 'nvngx_dlss.dll')) -eq 'unknown DLSS') 'Unknown native SL and DLSS remain unchanged'

$tampered=Open-AuroraIndex $unverified; $tampered.Targets[0].JournalPath=Join-Path $ScratchRoot 'outside.json'; Write-AuroraJson (Get-AuroraIndexPath $unverified) $tampered
Expect-Failure { Open-AuroraIndex $unverified } 'Tampered central journal path rejected'

# Colocation is unsafe even when the utility itself is filtered out.
$shared=Join-Path $ScratchRoot 'SharedDirectory'; Fixture (Join-Path $shared 'Win64\Game.exe'); Fixture (Join-Path $shared 'Win64\Launcher.exe')
Assert (@(Get-AuroraDeploymentCandidates (Get-AuroraScan $shared)).Count -eq 0) 'Do not inject a rendering directory shared with an x64 launcher'
$dllExe=Join-Path $ScratchRoot 'DllDisguised\Win64\Game.exe'
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dllExe)) | Out-Null
[IO.File]::Copy((Join-Path $pkg 'OptiScaler.dll'),$dllExe)
Assert (@(Get-AuroraDeploymentCandidates (Get-AuroraScan (Split-Path -Parent (Split-Path -Parent $dllExe)))).Count -eq 0) 'DLL renamed to EXE cannot be a game entry'

# Synthetic PE import descriptor exercises the actual RVA/section parser.
$pePath=Join-Path $ScratchRoot 'GraphicsImport\Renderer.exe'; $bytes=New-Object byte[] 1024
[BitConverter]::GetBytes([uint16]0x5a4d).CopyTo($bytes,0); [BitConverter]::GetBytes([int]128).CopyTo($bytes,60)
[BitConverter]::GetBytes([uint32]0x4550).CopyTo($bytes,128); [BitConverter]::GetBytes([uint16]0x8664).CopyTo($bytes,132)
[BitConverter]::GetBytes([uint16]1).CopyTo($bytes,134); [BitConverter]::GetBytes([uint16]240).CopyTo($bytes,148)
[BitConverter]::GetBytes([uint16]2).CopyTo($bytes,150); [BitConverter]::GetBytes([uint16]0x20b).CopyTo($bytes,152)
[BitConverter]::GetBytes([uint32]4096).CopyTo($bytes,272); [BitConverter]::GetBytes([uint32]40).CopyTo($bytes,276)
[BitConverter]::GetBytes([uint32]512).CopyTo($bytes,400); [BitConverter]::GetBytes([uint32]4096).CopyTo($bytes,404)
[BitConverter]::GetBytes([uint32]512).CopyTo($bytes,408); [BitConverter]::GetBytes([uint32]512).CopyTo($bytes,412)
[BitConverter]::GetBytes([uint32]4196).CopyTo($bytes,524); [Text.Encoding]::ASCII.GetBytes('d3d12.dll').CopyTo($bytes,612)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($pePath)) | Out-Null; [IO.File]::WriteAllBytes($pePath,$bytes)
Assert ((Get-AuroraExecutableEvidence $pePath).GraphicsImports -contains 'd3d12.dll') 'PE32+ import RVA maps to D3D12 DLL name'
Assert (@(Get-AuroraDeploymentCandidates (Get-AuroraScan (Split-Path -Parent $pePath))).Count -eq 1) 'Generic game root EXE qualifies through graphics imports'

$observedExe=Join-Path $dx11 'witcher3.exe'
$evidence=[pscustomobject]@{Processes=@([pscustomobject]@{Path=$observedExe;ProcessId=99});Modules=@([pscustomobject]@{Path=$native11;ProcessId=99})}
$groups=@(Get-AuroraRuntimeGroups (Get-AuroraScan $game) $c $evidence $observedExe)
Assert (@($groups | Where-Object { $_.Directory -eq $dx11 -and $_.ObservedBy.Count -eq 1 }).Count -eq 1) 'Actual module observation associates Runtime group to EXE and process ID'
$evidence.Processes[0].Path=Join-Path $dx12 'witcher3.exe'
$groups=@(Get-AuroraRuntimeGroups (Get-AuroraScan $game) $c $evidence $observedExe)
Assert (@($groups | Where-Object { $_.ObservedBy.Count }).Count -eq 0) 'Different process path cannot prove the selected EXE runtime association'

# Reuse a real RC2 v2 journal and metadata, including its user-selected Proxy.
$upgrade=Join-Path $ScratchRoot 'RC2Upgrade'; $upDir=Join-Path $upgrade 'Win64'; Fixture (Join-Path $upDir 'Game.exe')
$upJp=Join-Path $upDir 'OptiScaler\AuroraSetup\manifest.json'; $upJ=Open-AuroraJournal $upJp $upgrade $upDir
$oldCore=Join-Path $ScratchRoot 'OldRelease\OptiScaler.dll'; Fixture $oldCore '1.0.0.0'
Install-AuroraFile $upJ $upJp $oldCore (Join-Path $upDir 'winmm.dll')
$oldTool=Join-Path $ScratchRoot 'OldRelease\Aurora_Setup.ps1'; Put $oldTool '# RC2 script fixture'
Install-AuroraFile $upJ $upJp $oldTool (Join-Path $upDir 'Aurora_Setup.ps1')
Write-AuroraJson (Join-Path $upDir 'OptiScaler\AuroraSetup\installation.json') ([pscustomobject]@{GameRoot=$upgrade;GameExe=(Join-Path $upDir 'Game.exe');Proxy='winmm.dll'})
$upNative=Join-Path $upDir 'nvngx_dlss.dll'; Fixture $upNative '310.6.0.0'; $upOriginal=Get-AuroraHash $upNative
$upRjp=Join-Path $upDir 'OptiScaler\RuntimeSync\manifest.json'; $upRj=Open-AuroraJournal $upRjp $upgrade $upDir
Install-AuroraFile $upRj $upRjp (Join-Path $pkg 'OptiScaler\nvngx_dlss.dll') $upNative
Run-Setup Install $upgrade $pkg
Assert ((Open-AuroraIndex $upgrade).Targets[0].Proxy -eq 'winmm.dll' -and -not (Test-Path -LiteralPath (Join-Path $upDir 'dxgi.dll'))) 'RC2 upgrade retains prior manual Proxy automatically'
Assert ((Open-AuroraJournal $upRjp $upgrade $upDir).Entries[0].OriginalHash -eq $upOriginal) 'RC2 original runtime backup remains authoritative after upgrade'
# Recovery works even if the game EXE and optional diagnostic helper disappear.
[IO.File]::Delete((Join-Path $upDir 'Game.exe')); [IO.File]::Delete((Join-Path $upDir 'Aurora_Diagnostics.ps1'))
Run-Setup Remove '' '' $upDir 0 '' (Join-Path $upDir 'Aurora_Setup.ps1')
Assert ((Get-AuroraHash $upNative) -eq $upOriginal -and -not (Test-Path -LiteralPath (Join-Path $upDir 'winmm.dll'))) 'Installed recovery locates root and restores without EXE or diagnostic module'

# Force failure exactly before Proxy activation. All earlier writes remain recoverable.
$interrupted=Join-Path $ScratchRoot 'Interrupted'; $intDir=Join-Path $interrupted 'Win64'; Fixture (Join-Path $intDir 'Game.exe')
$baseCopy=${function:Copy-AuroraAtomic}
function Copy-AuroraAtomic([string]$Source,[string]$Target,[string]$ExpectedCurrent,[string]$ExpectedSource) {
    if ([IO.Path]::GetFileName($Target) -eq 'dxgi.dll') { throw 'Injected pre-Proxy interruption' }
    & $script:baseCopy $Source $Target $ExpectedCurrent $ExpectedSource
}
try { Expect-Failure { Install-AuroraDeployment $interrupted $pkg '' (Join-Path $ScratchRoot 'interrupted.json') } 'Failure before Proxy is journaled for recovery' }
finally { Set-Item -LiteralPath Function:Copy-AuroraAtomic -Value $baseCopy }
Assert ((Open-AuroraIndex $interrupted).Status -eq 'NeedsAttention' -and -not (Test-Path -LiteralPath (Join-Path $intDir 'dxgi.dll'))) 'Interrupted install does not leave an activated new Proxy'
Run-Setup Remove $interrupted '' $intDir
Assert (-not (Test-Path -LiteralPath (Join-Path $intDir 'OptiScaler.dll'))) 'Pending journal restores interrupted deployment'

$missing=Join-Path $ScratchRoot 'MissingJournal'; $misDir=Join-Path $missing 'Win64'; Fixture (Join-Path $misDir 'Game.exe')
Run-Setup Install $missing $pkg
[IO.File]::Delete((Join-Path $misDir 'OptiScaler\AuroraSetup\manifest.json'))
Run-Setup Remove $missing '' $misDir 4
Assert (Test-Path -LiteralPath (Join-Path $misDir 'dxgi.dll')) 'Missing applied journal fails closed instead of claiming clean uninstall'

$same=Join-Path $ScratchRoot 'SameDirectory'; $sameDir=Join-Path $same 'Win64'
Fixture (Join-Path $sameDir 'Game.exe'); Fixture (Join-Path $sameDir 'GameDX12.exe')
Run-Setup Install $same $pkg
$sameIndex=Open-AuroraIndex $same
Assert ($sameIndex.Targets.Count -eq 1 -and $sameIndex.Targets[0].Executables.Count -eq 2) 'Two rendering EXEs in one directory share exactly one payload and journal'
Run-Setup Remove $same '' $sameDir

$edited=Join-Path $ScratchRoot 'EditedRuntime'; $editDir=Join-Path $edited 'Win64'
Fixture (Join-Path $editDir 'Game.exe'); $editNative=Join-Path $editDir 'nvngx_dlss.dll'; Fixture $editNative '310.1.0.0'
Run-Setup Install $edited $pkg
Put $editNative 'game update after Aurora'
Run-Setup Remove $edited '' $editDir
Assert ([IO.File]::ReadAllText($editNative) -eq 'game update after Aurora' -and -not (Test-Path -LiteralPath (Join-Path $editDir 'dxgi.dll'))) 'Changed native Runtime retained while unchanged core is uninstalled'
$editIndex=Open-AuroraIndex $edited; $editJournal=Open-AuroraJournal (Join-Path $editDir 'OptiScaler\RuntimeSync\manifest.json') $edited $editDir
Assert ($editJournal.Entries[0].Status -eq 'Preserved' -and (Test-Path -LiteralPath $editJournal.Entries[0].BackupPath)) 'Preserved native Runtime keeps its original backup and recovery status'

# Exercise the interactive default through stdin: one Enter authorizes installation.
$ui=Join-Path $ScratchRoot 'Interactive'; $uiDir=Join-Path $ui 'Win64'; Fixture (Join-Path $uiDir 'Game.exe')
$psi=New-Object Diagnostics.ProcessStartInfo
$psi.FileName='powershell.exe'; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
$psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
$uiArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $toolsDir 'Aurora_Setup.ps1'),'-GameRoot',$ui,'-PackageDir',$pkg)
$psi.Arguments=($uiArgs | ForEach-Object { '"'+$_+'"' }) -join ' '
$proc=New-Object Diagnostics.Process; $proc.StartInfo=$psi; $null=$proc.Start()
try {
    $outTask=$proc.StandardOutput.ReadToEndAsync(); $errTask=$proc.StandardError.ReadToEndAsync()
    $proc.StandardInput.WriteLine(''); $proc.StandardInput.WriteLine(''); $proc.StandardInput.Close()
    if (-not $proc.WaitForExit(45000)) { $proc.Kill(); throw 'Interactive installer waited for unexpected extra input.' }
    $uiText=$outTask.Result+$errTask.Result
    Assert ($proc.ExitCode -eq 0 -and (Test-Path -LiteralPath (Join-Path $uiDir 'dxgi.dll'))) 'Interactive installation completes with one Enter plus exit Enter'
    Assert (-not ($uiText -match '请选择加载方式|使用什么显卡|请输入游戏目录|SHA256|sl\.interposer\.dll')) 'Default interactive UI has no path, GPU, Proxy list or runtime detail prompts'
} finally { $proc.Dispose() }
Run-Setup Remove $ui '' $uiDir
Assert (-not (Test-Path -LiteralPath (Join-Path $uiDir 'OptiScaler.dll'))) 'Interactive installation has the same precise uninstall behavior'
Write-Host "ALL PASSED: $passed RC3 assertions. Fixtures: $ScratchRoot"
