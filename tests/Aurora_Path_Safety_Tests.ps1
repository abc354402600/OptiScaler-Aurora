param([string]$ScratchRoot=(Join-Path $env:TEMP ('AuroraPath-'+[Guid]::NewGuid().ToString('N'))))
. (Join-Path $PSScriptRoot 'Aurora_Hardening_TestSupport.ps1')
$game=Join-Path $ScratchRoot '游戏 Root'; $dir=Join-Path $game 'Win64'; $outside=Join-Path $ScratchRoot 'Outside'
Put (Join-Path $outside 'sentinel.dll') 'never change'; Put (Join-Path $dir 'file.dll') 'original'
$sentinel=Get-AuroraHash (Join-Path $outside 'sentinel.dll')
foreach ($p in @('\\server\share\file.dll','\\?\C:\Windows\file','C:relative','\\.\C:\file','C:\Game\NUL','C:\Game\trailing.\file','C:\Game\file.dll:stream')) { Deny { Get-AuroraPath $p } "Reject ambiguous/network/device path: $p" }
foreach ($p in @('..\Outside\sentinel.dll','Win64\file.dll',($game+'\..\Outside\sentinel.dll'),($game+'\Win64\..\Win64\file.dll'))) { Deny { Get-AuroraMetadataPath $p } "Reject metadata relative component: $p" }
Assert (Test-AuroraWithin ($dir.ToUpperInvariant()+'\') ($game+'\')) 'Case and trailing separator normalization retains scope'
Assert (-not (Test-AuroraWithin (Join-Path $outside 'sentinel.dll') $game)) 'Absolute outside path does not belong to game'
Assert (-not (Test-AuroraWithin ($game+'2\file.dll') $game)) 'Prefix sibling is not a child'
$jp=Join-Path $dir 'OptiScaler\AuroraSetup\manifest.json'; $source=Join-Path $ScratchRoot 'source.dll'; Put $source 'new'
$j=Open-AuroraJournal $jp $game $dir; Install-AuroraFile $j $jp $source (Join-Path $dir 'file.dll')
$saved=$j | ConvertTo-Json -Depth 12
Assert ((Open-AuroraJournal $jp ($game.ToUpperInvariant()+'\') ($dir+'\')).Entries.Count -eq 1) 'Journal opens across case and trailing separators'
foreach ($field in @('TargetPath','BackupPath')) {
    $j=$saved | ConvertFrom-Json; $j.Entries[0].$field=Join-Path $outside 'sentinel.dll'; Write-AuroraJson $jp $j
    Deny { Open-AuroraJournal $jp $game $dir } "Outside $field rejected before restore"
}
$j=$saved | ConvertFrom-Json; $j.InstallDir=$outside; Write-AuroraJson $jp $j
Deny { Open-AuroraJournal $jp $game $dir } 'Root/install/journal mismatch rejected'
Write-AuroraJson $jp ($saved | ConvertFrom-Json)
$link=Join-Path $game 'Junction'; New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
$scan=Get-AuroraScan $game
Assert (-not $scan.Complete -and -not @($scan.Files | Where-Object { $_.FullName -like '*sentinel*' }).Count) 'Junction not traversed; scan marked incomplete'
Deny { Get-AuroraHash (Join-Path $link 'sentinel.dll') } 'Hash cannot follow junction'
Deny { Copy-AuroraAtomic $source (Join-Path $link 'new.dll') '' (Get-AuroraHash $source) } 'Copy cannot write through junction'
Deny { Write-AuroraJson (Join-Path $link 'state.json') @{x=1} } 'JSON cannot write through junction'
Deny { Get-AuroraScan $link } 'Junction cannot become game root'
$symbol=Join-Path $game 'Symbolic'
try { New-Item -ItemType SymbolicLink -Path $symbol -Target $outside | Out-Null; $symbolAvailable=$true } catch { $symbolAvailable=$false; $skipped+='SymbolicLink unavailable'; Write-Host 'SKIP: symbolic link creation unavailable' }
if ($symbolAvailable) { Deny { Get-AuroraHash (Join-Path $symbol 'sentinel.dll') } 'Symbolic directory cannot escape'; Assert (-not (Get-AuroraScan $game).Complete) 'Symbolic link makes scan incomplete' }
$guard=Enter-AuroraPathGuard $dir -Directory
try { Deny { [IO.Directory]::Move($dir,(Join-Path $game 'Moved')) } 'Directory cannot be swapped after validation while guard is held' } finally { $guard.Dispose() }
$fileLink=Join-Path $game 'file-link.dll'
if ($symbolAvailable) {
    New-Item -ItemType SymbolicLink -Path $fileLink -Target (Join-Path $outside 'sentinel.dll') | Out-Null
    Deny { Get-AuroraHash $fileLink } 'Leaf file symbolic link cannot be read as owned file'
}
Assert ((Get-AuroraHash (Join-Path $outside 'sentinel.dll')) -eq $sentinel -and @(Get-ChildItem -LiteralPath $outside).Count -eq 1) 'Outside sentinel bytes and directory inventory unchanged'
Finish 'PATH SAFETY'
