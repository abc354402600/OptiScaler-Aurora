param([string]$ScratchRoot=(Join-Path $env:TEMP ('AuroraPerf-'+[Guid]::NewGuid().ToString('N'))))
. (Join-Path $PSScriptRoot 'Aurora_Hardening_TestSupport.ps1')
function Reference-Scan([string]$Root) {
    $queue=New-Object 'Collections.Generic.Queue[string]'; $queue.Enqueue($Root)
    $files=New-Object 'Collections.Generic.List[object]'; $entries=0; $dirs=0
    while ($queue.Count) {
        $dir=$queue.Dequeue(); $dirs++; $guard=Enter-AuroraPathGuard $dir -Directory
        try { $children=@(Get-ChildItem -LiteralPath $dir -Force); $entries+=$children.Count } finally { $guard.Dispose() }
        foreach ($child in $children) {
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reference fixture unexpectedly contains a link' }
            if ($child.PSIsContainer) { if ($child.Name -notmatch '^(OptiScaler|\.git|\.svn|_storage.*|AuroraSetup|RuntimeSync)$') { $queue.Enqueue($child.FullName) } }
            elseif ($child.Extension -ieq '.exe' -or $child.Name -match '^(nvngx_dlss.*|sl\..*)\.dll$') { $files.Add($child) }
        }
    }
    [pscustomobject]@{Root=$Root;Files=@($files.ToArray());Complete=$true;Warnings=@();EntriesMaterialized=$entries;DirectoriesVisited=$dirs}
}
$fixture=Join-Path $ScratchRoot 'Fixture\Game.exe'; Binary $fixture
$results=@()
foreach ($scale in @(1000,10000,50000)) {
    $root=Join-Path $ScratchRoot ('Scale'+$scale)
    foreach ($rel in @('Win64\Game.exe','Win64r\Game.exe','Launcher\Start.exe','Content\HiddenGame\Binaries\Win64\Alternate.exe','Engine\Binaries\Tool.exe')) {
        $p=Join-Path $root $rel; [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p)) | Out-Null; [IO.File]::Copy($fixture,$p)
    }
    Put (Join-Path $root 'Content\Assets\Plugins\nvngx_dlss.dll') 'unversioned native runtime'
    Put (Join-Path $root 'Engine\Plugins\sl.common.dll') 'unversioned native runtime'
    for ($i=0; $i -lt $scale; $i++) {
        $dir=Join-Path $root ('Content\Resources\chunk'+[Math]::Floor($i/1000))
        if ($i%1000 -eq 0) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
        [IO.File]::WriteAllBytes((Join-Path $dir ('asset'+$i+'.pak')),[byte[]]@())
    }
    $timer=[Diagnostics.Stopwatch]::StartNew(); $reference=Reference-Scan $root; $expected=@(Get-AuroraDeploymentCandidates $reference); $timer.Stop(); $oldMs=$timer.Elapsed.TotalMilliseconds
    $timer.Restart(); $scan=Get-AuroraScan $root; $actual=@(Get-AuroraDeploymentCandidates $scan); $timer.Stop(); $newMs=$timer.Elapsed.TotalMilliseconds
    Assert $scan.Complete "Complete $scale-file discovery"
    Assert (-not (Compare-Object @($reference.Files.FullName | Sort-Object) @($scan.Files.FullName | Sort-Object))) "Same EXE/runtime inventory at $scale files"
    Assert ($actual.Count -eq 3 -and -not (Compare-Object @($expected.Path | Sort-Object) @($actual.Path | Sort-Object))) "Security filters and hidden Content entry preserved at $scale files"
    Assert ($scan.Stats.EntriesMaterialized -lt $reference.EntriesMaterialized/5) "Irrelevant asset object creation reduced at $scale files"
    $results+=@([pscustomobject]@{AssetFiles=$scale;ReferenceTotalMs=[Math]::Round($oldMs,2);FilteredTotalMs=[Math]::Round($newMs,2);ReferenceMaterialized=$reference.EntriesMaterialized;FilteredMaterialized=$scan.Stats.EntriesMaterialized;DirectoriesVisited=$scan.Stats.DirectoriesVisited;Candidates=$actual.Count})
    Write-Host ($results[-1] | ConvertTo-Json -Compress)
}
# Changing the tree is observed on a new scan; no stale cross-operation cache.
$root=Join-Path $ScratchRoot 'Scale1000'; $newPath=Join-Path $root 'Win64\Launcher.exe'; [IO.File]::Copy($fixture,$newPath)
Assert (@(Get-AuroraDeploymentCandidates (Get-AuroraScan $root)).Count -eq 2) 'Newly added colocated Launcher immediately removes unsafe entry'
$external=Join-Path $ScratchRoot 'External'; Put (Join-Path $external 'outside.exe') 'sentinel'
New-Item -ItemType Junction -Path (Join-Path $root 'Content\Linked') -Target $external | Out-Null
$linked=Get-AuroraScan $root
Assert (-not $linked.Complete -and -not @($linked.Files | Where-Object { $_.Name -eq 'outside.exe' }).Count) 'Filtered enumeration still refuses directory junctions'
Write-AuroraJson (Join-Path $ScratchRoot 'scan-performance.json') $results
Finish 'SCAN PERFORMANCE'
