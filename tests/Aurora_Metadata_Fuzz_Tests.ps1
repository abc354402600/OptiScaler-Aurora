param([string]$ScratchRoot=(Join-Path $env:TEMP ('AuroraFuzz-'+[Guid]::NewGuid().ToString('N'))))
. (Join-Path $PSScriptRoot 'Aurora_Hardening_TestSupport.ps1')
$game=Join-Path $ScratchRoot 'Game'; $dir=Join-Path $game 'Win64'; $target=Join-Path $dir 'OptiScaler.ini'; Put $target 'user original'
$source=Join-Path $ScratchRoot 'OptiScaler.ini'; Put $source 'Aurora deployed'; $jp=Join-Path $dir 'OptiScaler\AuroraSetup\manifest.json'
$j=Open-AuroraJournal $jp $game $dir; Install-AuroraFile $j $jp $source $target
$valid=$j | ConvertTo-Json -Depth 12; $deployed=Get-AuroraHash $target
$outside=Join-Path $ScratchRoot 'Outside\sentinel.txt'; Put $outside 'outside sentinel'; $outsideHash=Get-AuroraHash $outside
Deny { Assert-AuroraUniqueJsonKeys '{"SchemaVersion":2,"schemaVersion":1}' } 'Case-folded duplicate JSON keys rejected by lexer'
Deny { Assert-AuroraUniqueJsonKeys '{"TargetPath":1,"Target\u0050ath":2}' } 'Escaped duplicate JSON keys rejected by lexer'
foreach ($text in @('','{','[]','null','true','{"SchemaVersion":2,"SchemaVersion":1}','{"TargetPath":1,"Target\u0050ath":2}')) {
    Put $jp $text; Deny { Open-AuroraJournal $jp $game $dir } ('Reject malformed JSON '+$text)
}
$random=New-Object Random(731)
for ($i=0; $i -lt 32; $i++) { Put $jp $valid.Substring(0,$random.Next(1,$valid.LastIndexOf('}'))); Deny { Open-AuroraJournal $jp $game $dir } "Truncation seed731 case$i" }
foreach ($field in @('SchemaVersion','InstallDir','ScanRoot','Entries')) {
    $bad=$valid | ConvertFrom-Json; $bad.PSObject.Properties.Remove($field); Write-AuroraJson $jp $bad
    Deny { Open-AuroraJournal $jp $game $dir } "Missing journal field $field"
}
foreach ($field in @('TargetPath','SourceName','BackupPath','OriginalHash','DeployedHash','Created','Status','BeforeHash')) {
    $bad=$valid | ConvertFrom-Json; $bad.Entries[0].PSObject.Properties.Remove($field); Write-AuroraJson $jp $bad
    Deny { Open-AuroraJournal $jp $game $dir } "Missing entry field $field"
}
foreach ($mutation in @('duplicate','created-with-original','not-created-without-original','boolean-version','null-entries','object-entries','invalid-hash','null-hash','numeric-created','outside-backup','outside-target','relative-target','wrong-root')) {
    $bad=$valid | ConvertFrom-Json
    switch ($mutation) {
        duplicate { $bad.Entries+=@(($valid | ConvertFrom-Json).Entries[0]); $bad.Entries[1].TargetPath=$target.ToUpperInvariant() }
        created-with-original { $bad.Entries[0].Created=$true }
        not-created-without-original { $bad.Entries[0].OriginalHash='' }
        boolean-version { $bad.SchemaVersion=$true }
        null-entries { $bad.Entries=$null }
        object-entries { $bad.Entries=$bad.Entries[0] }
        invalid-hash { $bad.Entries[0].DeployedHash='BAD' }
        null-hash { $bad.Entries[0].OriginalHash=$null }
        numeric-created { $bad.Entries[0].Created=1 }
        outside-backup { $bad.Entries[0].BackupPath=$outside }
        outside-target { $bad.Entries[0].TargetPath=$outside }
        relative-target { $bad.Entries[0].TargetPath='Win64\OptiScaler.ini' }
        wrong-root { $bad.ScanRoot=$ScratchRoot }
    }
    Write-AuroraJson $jp $bad; Deny { Open-AuroraJournal $jp $game $dir } "Corruption rejected: $mutation"
}
$bad=$valid | ConvertFrom-Json; $bad.Entries[0].TargetPath=$outside
Deny { Restore-AuroraJournal $bad $jp } 'In-memory journal cannot bypass path validation'
foreach ($field in @('OriginalHash','DeployedHash')) {
    $bad=$valid | ConvertFrom-Json; $bad.Entries[0].$field=('F'*64); Write-AuroraJson $jp $bad
    $bad=Open-AuroraJournal $jp $game $dir
    Assert ((Restore-AuroraJournal $bad $jp) -eq 1 -and (Get-AuroraHash $target) -eq $deployed) "Valid-length wrong $field preserves current file"
}
Assert ((Get-AuroraHash $outside) -eq $outsideHash -and (Get-AuroraHash $target) -eq $deployed) 'All journal fuzz leaves user and outside files unchanged'

$pkg=Join-Path $ScratchRoot 'Package'; Package $pkg
$realGame=Join-Path $ScratchRoot 'IndexGame'; $a=Join-Path $realGame 'Win64'; $b=Join-Path $realGame 'Win64r'
Binary (Join-Path $a 'Game.exe'); Binary (Join-Path $b 'Game.exe'); Binary (Join-Path $a 'nvngx_dlss.dll') '310.1.0.0'
$index=Install-AuroraDeployment $realGame $pkg '' (Join-Path $ScratchRoot 'install.json')
$indexPath=Get-AuroraIndexPath $realGame; $validIndex=$index | ConvertTo-Json -Depth 12
foreach ($field in @('SchemaVersion','GameRoot','Status','Targets','RuntimeOwners','RuntimeGroups')) {
    $bad=$validIndex | ConvertFrom-Json; $bad.PSObject.Properties.Remove($field); Write-AuroraJson $indexPath $bad
    Deny { Open-AuroraIndex $realGame } "Missing index field $field"
}
foreach ($mutation in @('duplicate-target','duplicate-owner','empty-targets','scalar-exes','escaped-journal','stale-root','bad-status','boolean-version')) {
    $bad=$validIndex | ConvertFrom-Json
    switch ($mutation) {
        duplicate-target { $bad.Targets+=@(($validIndex | ConvertFrom-Json).Targets[0]) }
        duplicate-owner { $bad.RuntimeOwners+=@($bad.RuntimeOwners[0]) }
        empty-targets { $bad.Targets=@() }
        scalar-exes { $bad.Targets[0].Executables=$bad.Targets[0].Executables[0] }
        escaped-journal { $bad.Targets[0].JournalPath=$outside }
        stale-root { $bad.GameRoot=$game }
        bad-status { $bad.Status='SuccessMaybe' }
        boolean-version { $bad.SchemaVersion=$true }
    }
    Write-AuroraJson $indexPath $bad; Deny { Open-AuroraIndex $realGame } "Index mutation $mutation rejected"
}
Write-AuroraJson $indexPath ($validIndex | ConvertFrom-Json)
$runtimePath=Join-Path $a 'OptiScaler\RuntimeSync\manifest.json'; $runtime=Open-AuroraJournal $runtimePath $realGame $a
$runtimeSaved=$runtime | ConvertTo-Json -Depth 12
$otherRuntime=$runtimeSaved | ConvertFrom-Json; $otherRuntime.InstallDir=$b
$otherPath=Join-Path $b 'OptiScaler\RuntimeSync\manifest.json'
$otherBackup=Join-Path $b 'OptiScaler\RuntimeSync\backup\conflict\nvngx_dlss.dll'
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($otherBackup)) | Out-Null; [IO.File]::Copy($runtime.Entries[0].BackupPath,$otherBackup)
$otherRuntime.Entries[0].BackupPath=$otherBackup; Write-AuroraJson $otherPath $otherRuntime
$index=$validIndex | ConvertFrom-Json; $index.RuntimeOwners=@($a,$b); Write-AuroraJson $indexPath $index
Deny { Remove-AuroraDeployment (Open-AuroraIndex $realGame) (Join-Path $ScratchRoot 'conflict.json') } 'Cross-journal conflict rejected before any restore'
Assert ((Test-Path -LiteralPath (Join-Path $a 'dxgi.dll')) -and (Test-Path -LiteralPath (Join-Path $b 'dxgi.dll'))) 'Both entries retained on conflicting ownership'
Write-AuroraJson $indexPath ($validIndex | ConvertFrom-Json)
# A missing registered Runtime journal is not equivalent to an empty journal.
[IO.File]::Delete($runtimePath)
Deny { Remove-AuroraDeployment (Open-AuroraIndex $realGame) (Join-Path $ScratchRoot 'missing.json') } 'Missing registered Runtime journal prevents false clean uninstall'
Write-AuroraJson $runtimePath ($runtimeSaved | ConvertFrom-Json)
$corePath=Join-Path $a 'OptiScaler\AuroraSetup\manifest.json'; $core=Open-AuroraJournal $corePath $realGame $a; $coreSaved=$core | ConvertTo-Json -Depth 12
$userFile=Join-Path $a 'savegame.dat'; Put $userFile 'user save'; $core.Entries[0].TargetPath=$userFile; $core.Entries[0].DeployedHash=Get-AuroraHash $userFile
Write-AuroraJson $corePath $core
Deny { Remove-AuroraDeployment (Open-AuroraIndex $realGame) (Join-Path $ScratchRoot 'forged-scope.json') } 'Core manifest cannot claim arbitrary game saves even with matching hash'
Assert ([IO.File]::ReadAllText($userFile) -eq 'user save') 'Forged save ownership did not delete user data'
Write-AuroraJson $corePath ($coreSaved | ConvertFrom-Json)
[IO.File]::Delete($indexPath)
$result=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $toolsDir 'Aurora_Setup.ps1') -Action Remove -GameRoot $realGame -InstallDir $a -NonInteractive 2>&1
Assert ($LASTEXITCODE -eq 4) 'Missing RC3 index cannot fall through to legacy single-entry removal'
Assert ((Test-Path -LiteralPath (Join-Path $a 'dxgi.dll')) -and (Test-Path -LiteralPath (Join-Path $b 'dxgi.dll'))) 'Missing index retains both installed entries'
Write-AuroraJson $indexPath ($validIndex | ConvertFrom-Json)
$null=Remove-AuroraDeployment (Open-AuroraIndex $realGame) (Join-Path $ScratchRoot 'valid-remove.json')
Assert (-not (Test-Path -LiteralPath (Join-Path $a 'dxgi.dll'))) 'Valid registered journals still restore after corruption is repaired'
Finish 'METADATA FUZZ'
