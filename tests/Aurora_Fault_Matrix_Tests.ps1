param([string]$ScratchRoot=(Join-Path $env:TEMP ('AuroraFault-'+[Guid]::NewGuid().ToString('N'))))
. (Join-Path $PSScriptRoot 'Aurora_Hardening_TestSupport.ps1')
$pkg=Join-Path $ScratchRoot 'Package'; Package $pkg
$exeFixture=Join-Path $ScratchRoot 'Fixture\Game.exe'; Binary $exeFixture
$nativeFixture=Join-Path $ScratchRoot 'Fixture\nvngx_dlss.dll'; Binary $nativeFixture '310.1.0.0'
$originalNative=Get-AuroraHash $nativeFixture
$baseCopy=${function:Copy-AuroraAtomic}; $baseHash=${function:Get-AuroraHash}; $baseJson=${function:Write-AuroraJson}
$baseRuntime=${function:Invoke-AuroraRuntimeTask}
$cases=@('preflight','backup','copy','verify','move-collision','journal-pending','journal-applied','index-pending','index-temp-only','index-applied-persistent','runtime-before-proxy','second-proxy')
$matrix=@()
foreach ($case in $cases) {
    $game=Join-Path $ScratchRoot $case; $dir=Join-Path $game 'Win64'; $second=Join-Path $game 'Win64r'
    foreach ($d in @($dir,$second)) { [IO.Directory]::CreateDirectory($d) | Out-Null; [IO.File]::Copy($exeFixture,(Join-Path $d 'Game.exe')) }
    $native=Join-Path $dir 'nvngx_dlss.dll'; [IO.File]::Copy($nativeFixture,$native)
    $report=Join-Path $ScratchRoot ($case+'.json'); $injected=$false
    if ($case -eq 'preflight') { Put (Join-Path $second 'dxgi.dll') 'other mod'; $injected=$true }
    function Copy-AuroraAtomic([string]$Source,[string]$Target,[string]$ExpectedCurrent,[string]$ExpectedSource) {
        $hit=($script:case -eq 'backup' -and $Target -like '*\backup\*') -or
             ($script:case -eq 'copy' -and $Target -eq (Join-Path $script:dir 'OptiScaler.dll')) -or
             ($script:case -eq 'runtime-before-proxy' -and $Target -eq (Join-Path $script:dir 'dxgi.dll')) -or
             ($script:case -eq 'second-proxy' -and $Target -eq (Join-Path $script:second 'dxgi.dll'))
        if ($hit) { $script:injected=$true; throw "FAULT $script:case" }
        & $script:baseCopy $Source $Target $ExpectedCurrent $ExpectedSource
    }
    function Get-AuroraHash([string]$Path) {
        if ($script:case -eq 'verify' -and $Path.EndsWith('.aurora-tmp')) { $script:injected=$true; return ('A'*64) }
        if ($script:case -eq 'move-collision' -and -not $script:injected -and $Path.EndsWith('.aurora-tmp')) { Put (Join-Path $script:dir 'OptiScaler.dll') 'concurrent user file'; $script:injected=$true }
        & $script:baseHash $Path
    }
    function Write-AuroraJson([string]$Path,$Value) {
        $isIndex=$Path.EndsWith('AuroraInstallManifest.json')
        $hit=($script:case -eq 'index-pending' -and $isIndex -and $Value.Status -eq 'Pending') -or
             ($script:case -eq 'index-applied-persistent' -and $isIndex -and $Value.Status -in @('Applied','NeedsAttention')) -or
             ($script:case -eq 'journal-pending' -and $Path.EndsWith('manifest.json') -and @($Value.Entries | Where-Object { $_.Status -eq 'Pending' }).Count) -or
             ($script:case -eq 'journal-applied' -and $Path.EndsWith('manifest.json') -and @($Value.Entries | Where-Object { $_.Status -eq 'Applied' }).Count)
        if ($script:case -eq 'index-temp-only' -and $isIndex) { Put ([IO.Path]::ChangeExtension($Path,'.tmp')) '{"SchemaVersion":3'; $hit=$true }
        if ($hit) { $script:injected=$true; throw "FAULT $script:case" }
        & $script:baseJson $Path $Value
    }
    function Invoke-AuroraRuntimeTask([string]$Mode,[string]$Root,[string]$Owner,[string]$LogPath,[string]$GameExe='',[switch]$CallerHasLock) {
        if ($script:case -eq 'backup') {
            $runtimePath=Join-Path $Owner 'OptiScaler\RuntimeSync\manifest.json'
            $runtimeJournal=Open-AuroraJournal $runtimePath $Root $Owner
            Install-AuroraFile $runtimeJournal $runtimePath (Join-Path $Owner 'OptiScaler\nvngx_dlss.dll') $script:native
        } else { & $script:baseRuntime $Mode $Root $Owner $LogPath $GameExe -CallerHasLock:$CallerHasLock }
    }
    try { Deny { Install-AuroraDeployment $game $pkg '' $report } "Failure surfaces at $case" }
    finally { Set-Item Function:Copy-AuroraAtomic $baseCopy; Set-Item Function:Get-AuroraHash $baseHash; Set-Item Function:Write-AuroraJson $baseJson; Set-Item Function:Invoke-AuroraRuntimeTask $baseRuntime }
    # Runtime runs in its own process, so backup fault is exercised below in-process.
    if ($case -eq 'backup' -and -not $injected) { throw 'Backup fault must be reached before continuing.' }
    Assert $injected "Injection site reached: $case"
    $index=Open-AuroraIndex $game
    Assert (-not $index -or $index.Status -ne 'Applied') "No success state after $case"
    if ($case -eq 'runtime-before-proxy') { Assert ((Get-AuroraHash $native) -ne $originalNative -and -not (Test-Path -LiteralPath (Join-Path $dir 'dxgi.dll'))) 'Runtime changed before first Proxy and remains recoverable' }
    if ($case -eq 'second-proxy') { Assert ((Test-Path -LiteralPath (Join-Path $dir 'dxgi.dll')) -and -not (Test-Path -LiteralPath (Join-Path $second 'dxgi.dll'))) 'First entry active, second failed: durable partial state' }
    if ($index) { $null=Remove-AuroraDeployment $index (Join-Path $ScratchRoot ($case+'-restore.json')) }
    Assert ((Get-AuroraHash $native) -eq $originalNative) "Native original recovered: $case"
    if ($case -eq 'move-collision') { Assert ([IO.File]::ReadAllText((Join-Path $dir 'OptiScaler.dll')) -eq 'concurrent user file') 'Move collision preserves newly appeared user file' }
    else { Assert (-not (Test-Path -LiteralPath (Join-Path $dir 'OptiScaler.dll'))) "Owned core recovered: $case" }
    if ($case -eq 'preflight') { Assert ([IO.File]::ReadAllText((Join-Path $second 'dxgi.dll')) -eq 'other mod') 'Preflight keeps colliding mod bytes' }
    $matrix+=@([pscustomobject]@{Stage=$case;Injected=$injected;Recovered=$true})
}

# Real read-only and cross-process sharing failures use the file journal primitive.
$lockedGame=Join-Path $ScratchRoot 'FileFailures'; $target=Join-Path $lockedGame 'nvngx_dlss.dll'; Put $target 'original'
$jp=Join-Path $lockedGame 'OptiScaler\RuntimeSync\manifest.json'; $j=Open-AuroraJournal $jp $lockedGame $lockedGame
$source=Join-Path $pkg 'OptiScaler\nvngx_dlss.dll'
[IO.File]::SetAttributes($target,[IO.FileAttributes]::ReadOnly)
try { Deny { Install-AuroraFile $j $jp $source $target } 'Readonly original cannot be overwritten' } finally { [IO.File]::SetAttributes($target,[IO.FileAttributes]::Normal) }
$lockScript='$h=[IO.File]::Open('''+$target.Replace("'","''")+''',''Open'',''ReadWrite'',''None''); Write-Output READY; try { Start-Sleep 50 } finally {$h.Dispose()}'
$psi=New-Object Diagnostics.ProcessStartInfo; $psi.FileName='powershell.exe'; $psi.Arguments='-NoProfile -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($lockScript)); $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true; $psi.RedirectStandardOutput=$true
$process=[Diagnostics.Process]::Start($psi)
try { Assert ($process.StandardOutput.ReadLine() -eq 'READY') 'Separate process owns exclusive DLL handle'; Deny { Install-AuroraFile $j $jp $source $target } 'Exclusive external process blocks deployment' }
finally { if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }; $process.Dispose() }
Assert ([IO.File]::ReadAllText($target) -eq 'original') 'Locked/readonly failures preserve original bytes'
$new=Join-Path $lockedGame 'created.dll'; $coreJp=Join-Path $lockedGame 'OptiScaler\AuroraSetup\manifest.json'; $core=Open-AuroraJournal $coreJp $lockedGame $lockedGame
Install-AuroraFile $core $coreJp $source $new
[IO.File]::SetAttributes($new,[IO.FileAttributes]::ReadOnly)
try { Assert ((Restore-AuroraJournal $core $coreJp) -eq 1 -and (Test-Path -LiteralPath $new)) 'Remove does not force-delete a readonly owned file' } finally { [IO.File]::SetAttributes($new,[IO.FileAttributes]::Normal) }
Assert ((Restore-AuroraJournal $core $coreJp) -eq 0) 'Readonly failure is recoverable after access restored'
Write-AuroraJson (Join-Path $ScratchRoot 'fault-matrix.json') $matrix
Finish 'FAULT MATRIX'
