param([string]$ScratchRoot=(Join-Path $env:TEMP ('AuroraDiagnostics-'+[Guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$toolsDir=Join-Path $repo 'dist\runtime_sync'
. (Join-Path $toolsDir 'Aurora_Common.ps1')
. (Join-Path $toolsDir 'Aurora_Diagnostics.ps1')
$ScratchRoot=Get-AuroraPath $ScratchRoot
if (Test-Path -LiteralPath $ScratchRoot) { throw 'Tests require a new scratch directory.' }
[IO.Directory]::CreateDirectory($ScratchRoot) | Out-Null
$passed=0
function Assert($Condition,[string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++; Write-Host "PASS: $Name"
}
function Put([string]$Path,[string]$Text) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($true)))
}
function Fixture([string]$Path,[string]$Version='3.0.0.0',[switch]$Wait) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    $source=Join-Path $ScratchRoot ([Guid]::NewGuid().ToString('N')+'.cs')
    $body=''; if ($Wait) { $body='System.Threading.Thread.Sleep(120000);' }
    Put $source ('using System.Reflection; [assembly: AssemblyFileVersion("'+$Version+'")] public class Fixture { public static void Main() { '+$body+' } }')
    $kind='library'; if ([IO.Path]::GetExtension($Path) -ieq '.exe') { $kind='exe' }
    & (Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo "/target:$kind" /platform:x64 "/out:$Path" $source
    if ($LASTEXITCODE) { throw 'Fixture compilation failed.' }
}
function InventoryItem([string]$Path,[int]$Major=3) {
    [pscustomobject]@{ Path=$Path; Name=[IO.Path]::GetFileName($Path); Major=$Major; Architecture='x64'; SHA256='abc'; Version="$Major.0"; Action='保留'; Reason='测试'; SourceHash=''; SourceVersion='' }
}
function Module([string]$Path,[bool]$Aurora=$false,[int]$ProcessId=41) {
    [pscustomobject]@{Path=$Path;Name=[IO.Path]::GetFileName($Path);Aurora=$Aurora;ProcessId=$ProcessId;Version='3.0';DiskSHA256='abc'}
}
$game=Join-Path $ScratchRoot "游戏 [A] ! & O'Brien"
$install=Join-Path $game 'Client\Binaries\Win64'
$exe=Join-Path $install 'AuroraDiagFixture.exe'
$native=Join-Path $install 'nvngx_dlssg.dll'
$other=Join-Path $game 'Assets\Plugin\nvngx_dlssg.dll'
$bundle=Join-Path $install 'OptiScaler\nvngx_dlssg.dll'
$process=[pscustomobject]@{ProcessId=41;Path=$exe;State='Observed';ModulesComplete=$true}
$evidence=[pscustomobject]@{State='Observed';Processes=@($process);Modules=@()}
$argsForFinding=@{InstallDir=$install;GameRoot=$game;GameExe=$exe;Candidates=@([pscustomobject]@{Path=$exe;Directory=$install});Inventory=@();Proxies=@();ProcessEvidence=$evidence;Entries=@();ScanComplete=$true}
function Findings { @(Get-AuroraDiagnosticFindings @argsForFinding) }
function Has([object[]]$Items,[string]$Code) { @($Items | Where-Object { $_.Code -eq $Code }).Count -gt 0 }

Assert (Has (Findings) 'AuroraNotObserved') 'Complete module snapshot can report Aurora not observed'
$process.ModulesComplete=$false; $process.State='ModulesUnavailable'
$f=Findings
Assert ((Has $f 'ModuleObservationIncomplete') -and -not (Has $f 'AuroraNotObserved')) 'Restricted snapshot never asserts Aurora absent'
$process.State='Exited'
Assert (-not (Has (Findings) 'AuroraNotObserved')) 'Exited process never asserts Aurora absent'
$process.State='OtherExecutable'; $process.Path=Join-Path $game 'Win64r\AuroraDiagFixture.exe'
Assert (Has (Findings) 'OtherRunningExecutable') 'Same name at another executable path is distinguished'
$process.State='Observed'; $process.ModulesComplete=$true; $process.Path=$exe
$evidence.Modules=@((Module (Join-Path $install 'winmm.dll') $true))
$f=Findings
Assert ((Has $f 'AuroraObserved') -and -not (Has $f 'AuroraNotObserved')) 'Recognized Aurora only claims module presence'
$evidence.Modules=@((Module (Join-Path $game 'Another\winmm.dll') $true))
Assert (Has (Findings) 'OtherAuroraLocation') 'Aurora from another install is identified'
$evidence.Processes=@($process,[pscustomobject]@{ProcessId=42;Path=$exe;State='Observed';ModulesComplete=$true})
$f=Findings
Assert ((Has $f 'AuroraObserved') -and (Has $f 'AuroraNotObserved')) 'Module presence is evaluated per process ID'
$evidence.Processes=@($process)
$argsForFinding.Inventory=@((InventoryItem $native),(InventoryItem $other))
$argsForFinding.Entries=@([pscustomobject]@{SourceName='nvngx_dlssg.dll';TargetPath=$native;Status='Applied';DeployedHash='abc'})
$evidence.Modules=@((Module $other))
$f=Findings
Assert ((Has $f 'RuntimeCopies') -and (Has $f 'LoadedDifferentRuntimeCopy')) 'Multiple copies and different loaded target have distinct evidence'
$evidence.Modules=@((Module $native))
Assert (-not (Has (Findings) 'LoadedDifferentRuntimeCopy')) 'Correct synchronized target is not flagged as different copy'
$evidence.Modules[0].DiskSHA256='changed'
Assert (Has (Findings) 'RuntimeChangedSinceSync') 'Changed disk hash is reported without claiming memory hash'
$evidence.Modules[0].DiskSHA256=''
Assert (-not (Has (Findings) 'RuntimeChangedSinceSync')) 'Unavailable disk hash is not treated as mismatch'
$evidence.Modules=@((Module $bundle))
$f=Findings
Assert (-not ((Has $f 'LoadedDifferentRuntimeCopy') -or (Has $f 'LoadedRuntimeNotInventoried'))) 'Aurora bundled runtime is not mistaken for unsynchronized native copy'
$evidence.Modules=@((Module (Join-Path $ScratchRoot 'External\nvngx_dlssg.dll')))
Assert (Has (Findings) 'RuntimeOutsideScan') 'Outside-root loaded module is reported without scanning it'
$evidence.Modules=@((Module (Join-Path $game 'Skipped\nvngx_dlssg.dll')))
Assert (Has (Findings) 'LoadedRuntimeNotInventoried') 'Uninventoried loaded path is reported'
$argsForFinding.Inventory=@((InventoryItem (Join-Path $install 'sl.interposer.dll') 1),(InventoryItem $native 0))
$f=Findings
Assert ((Has $f 'SL1Protected') -and (Has $f 'UnknownRuntime')) 'SL1 and unknown-runtime protection explained separately'
$argsForFinding.ScanComplete=$false
Assert (Has (Findings) 'ScanIncomplete') 'Incomplete scan recommends no synchronization'
$argsForFinding.ScanComplete=$true; $argsForFinding.GameExe=Join-Path $game 'Win64r\Game.exe'
Assert (Has (Findings) 'ExecutableDirectoryMismatch') 'Launcher/install versus selected executable mismatch is surfaced'
$argsForFinding.GameExe=''; $argsForFinding.Candidates=@([pscustomobject]@{Path=$exe;Directory=$install},[pscustomobject]@{Path=(Join-Path $install 'Other.exe');Directory=$install})
Assert (Has (Findings) 'MultipleExecutables') 'Multiple direct executables require explicit selection'
$argsForFinding.Candidates=@([pscustomobject]@{Path=$exe;Directory=(Join-Path $game 'Win64r')})
Assert (Has (Findings) 'OtherExecutableCandidates') 'Candidate outside install directory supplies a path clue'
$evidence.State='NotRunning'; $evidence.Processes=@(); $evidence.Modules=@()
Assert (Has (Findings) 'GameNotRunning') 'Stopped game remains unknown rather than load failure'
$evidence.State='Unselected'
Assert (Has (Findings) 'ProcessUnselected') 'No selected executable remains unknown'
Assert (Has (Findings) 'ExternalSettingsUnknown') 'NVIDIA and game settings explicitly remain unobserved'
$argsForFinding.Proxies=@([pscustomobject]@{Recognized=$true;IsProxy=$false;Path=(Join-Path $install 'OptiScaler.dll')})
Assert (Has (Findings) 'ProxyNotFound') 'Raw OptiScaler DLL does not prove a Proxy was installed'
$argsForFinding.Proxies=@([pscustomobject]@{Recognized=$true;IsProxy=$true;Path=(Join-Path $install 'dxgi.dll')},[pscustomobject]@{Recognized=$true;IsProxy=$true;Path=(Join-Path $install 'winmm.dll')})
Assert (Has (Findings) 'MultipleProxies') 'Multiple recognized loaders are surfaced'
Assert (@(Get-AuroraGameHints '').Count -eq 0) 'Empty executable is valid for hints'
$hint=@(Get-AuroraGameHints (Join-Path $install 'HTGame.exe') 'dxgi.dll') -join ' '
Assert ($hint.Contains('winmm.dll') -and $hint.Contains('手动') -and $hint.Contains('当前仍选择 dxgi.dll')) 'NTE warning preserves the user-selected Proxy'

# Actual script invocation: unique EXE inference, scattered runtime paths, read-only JSON/TXT.
Fixture $exe -Wait
Fixture $native
Fixture $other
Fixture (Join-Path $game 'Engine\Plugins\sl.interposer.dll') '1.5.6.0'
Put (Join-Path $game 'Data\nvngx_dlss.dll') 'unknown fixture'
$before=@(Get-ChildItem -LiteralPath $game -Recurse -File | ForEach-Object { $_.FullName+'|'+(Get-AuroraHash $_.FullName) })
$reportPath=Join-Path $ScratchRoot '诊断 [A] & 报告.json'
$output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $toolsDir 'runtime_sync.ps1') -Mode Check -InstallDir $install -GameRoot $game -ReportPath $reportPath 2>&1
if ($LASTEXITCODE) { $output | Write-Host; throw 'Read-only diagnostic invocation failed.' }
$report=Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
$textPath=[IO.Path]::ChangeExtension($reportPath,'.txt')
$txt=[IO.File]::ReadAllText($textPath)
Assert ($report.GameExe -ieq $exe) 'Only direct candidate inferred for read-only process observation'
Assert ($report.Inventory.Count -eq 4 -and (Has $report.Findings 'SL1Protected') -and (Has $report.Findings 'UnknownRuntime')) 'Integrated report keeps scattered inventory and protection findings'
Assert ($txt.Contains('发现：') -and $txt.Contains('可能原因：') -and $txt.Contains('操作：') -and $txt.Contains($other)) 'Chinese TXT contains actionable findings and full Unicode paths'
Assert ([IO.File]::ReadAllBytes($textPath)[0] -eq 239) 'Chinese TXT is UTF-8 with BOM for Windows editors'
$after=@(Get-ChildItem -LiteralPath $game -Recurse -File | ForEach-Object { $_.FullName+'|'+(Get-AuroraHash $_.FullName) })
Assert (-not (Compare-Object $before $after)) 'Read-only diagnostics do not change game files or create manifests'
Put $textPath '用户已有文本'
$output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $toolsDir 'runtime_sync.ps1') -Mode Check -InstallDir $install -GameRoot $game -ReportPath $reportPath 2>&1
Assert ($LASTEXITCODE -eq 0 -and [IO.File]::ReadAllText($textPath) -eq '用户已有文本') 'Existing TXT is preserved while JSON can be refreshed'
Assert ((Get-AuroraProcessEvidence '').State -eq 'Unselected') 'Collector handles no selected executable'
$spawned=$null
try {
    $spawned=Start-Process -FilePath $exe -WindowStyle Hidden -PassThru
    $live=Get-AuroraProcessEvidence $exe
    Assert (@($live.Processes | Where-Object { $_.ProcessId -eq $spawned.Id -and $_.ModulesComplete }).Count -eq 1) 'Live x64 fixture module snapshot is observed on Windows PowerShell 5.1'
    $alternate=Get-AuroraProcessEvidence (Join-Path $game 'Another\AuroraDiagFixture.exe')
    Assert (@($alternate.Processes | Where-Object { $_.ProcessId -eq $spawned.Id -and $_.State -eq 'OtherExecutable' }).Count -eq 1) 'Collector distinguishes same process name at different path'
} finally { if ($null -ne $spawned -and -not $spawned.HasExited) { Stop-Process -Id $spawned.Id -Force } }

# New dependency must be shipped, journaled and removable by the installed tools.
$package=Join-Path $ScratchRoot '发布包'
Fixture (Join-Path $package 'OptiScaler.dll')
Fixture (Join-Path $package 'OptiScaler\nvngx_dlssg.dll')
Put (Join-Path $package 'OptiScaler.ini') "[FrameGen]`nDualFeature=false`n"
$output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $toolsDir 'Aurora_Setup.ps1') -Action Install -PackageDir $package -GameRoot $game -GameExe $exe -Proxy winmm.dll -NonInteractive 2>&1
if ($LASTEXITCODE) { $output | Write-Host; throw 'Setup with diagnostic dependency failed.' }
Assert ((Get-AuroraHash (Join-Path $install 'Aurora_Diagnostics.ps1')) -eq (Get-AuroraHash (Join-Path $toolsDir 'Aurora_Diagnostics.ps1'))) 'Installer deploys exact diagnostic helper bytes'
Assert ((Test-Path -LiteralPath (Join-Path $install 'winmm.dll')) -and -not (Test-Path -LiteralPath (Join-Path $install 'dxgi.dll'))) 'Integration preserves explicit winmm Proxy choice'
$output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $install 'Aurora_Setup.ps1') -Action Check -InstallDir $install -NonInteractive 2>&1
if ($LASTEXITCODE) { $output | Write-Host; throw 'Installed diagnostic invocation failed.' }
Assert ($LASTEXITCODE -eq 0) 'Installed helpers run diagnostics without source package path'
$installedDiagnostic=Join-Path $install 'Aurora_Diagnostics.ps1'
$savedDiagnostic=Join-Path $ScratchRoot 'diagnostic-helper.saved'
Move-Item -LiteralPath $installedDiagnostic -Destination $savedDiagnostic
try {
    $output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $install 'Aurora_Setup.ps1') -Action Restore -InstallDir $install -NonInteractive 2>&1
    if ($LASTEXITCODE) { $output | Write-Host; throw 'Missing diagnostic helper blocked recovery.' }
    Assert ($LASTEXITCODE -eq 0) 'Recovery does not depend on diagnostic helper availability'
} finally { Move-Item -LiteralPath $savedDiagnostic -Destination $installedDiagnostic }
$output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $install 'Aurora_Setup.ps1') -Action Remove -InstallDir $install -NonInteractive 2>&1
if ($LASTEXITCODE) { $output | Write-Host; throw 'Installed helper removal failed.' }
Assert (-not (Test-Path -LiteralPath (Join-Path $install 'Aurora_Diagnostics.ps1'))) 'Installed diagnostic helper is removed through its journal'
Assert ((Get-AuroraHash $native) -eq (($before | Where-Object { $_.StartsWith($native+'|') }) -split '\|')[-1]) 'Native runtime survives diagnostic install and uninstall'
Write-Host "ALL $passed DIAGNOSTIC CHECKS PASSED; scratch: $ScratchRoot"
