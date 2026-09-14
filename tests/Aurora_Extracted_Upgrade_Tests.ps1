param([string]$ScratchRoot=(Join-Path $env:TEMP ('AuroraExtracted-'+[Guid]::NewGuid().ToString('N'))))
. (Join-Path $PSScriptRoot 'Aurora_Hardening_TestSupport.ps1')
$pkg=Join-Path $ScratchRoot '新版包'; Package $pkg
$game=Join-Path $ScratchRoot '巫师 [3] 空格'; $dx11=Join-Path $game 'bin\x64'; $dx12=Join-Path $game 'bin\x64_dx12'
Binary (Join-Path $dx11 'witcher3.exe'); Binary (Join-Path $dx12 'witcher3.exe')
# Previously extracted source is deliberately not owned by the first install.
Package $dx12
$old=Get-AuroraHash (Join-Path $dx12 'OptiScaler.dll')
Binary (Join-Path $dx12 'sl.interposer.dll') '1.5.6.0'; $sl1=Get-AuroraHash (Join-Path $dx12 'sl.interposer.dll')
Put (Join-Path $dx12 'OptiScaler.ini') "[FrameGen]`nDualFeature=false`n; user configuration"
$config=Get-AuroraHash (Join-Path $dx12 'OptiScaler.ini')
$index=Install-AuroraDeployment $game $dx12 '' (Join-Path $ScratchRoot 'first.json')
$null=Remove-AuroraDeployment $index (Join-Path $ScratchRoot 'remove.json')
Assert ((Get-AuroraHash (Join-Path $dx12 'OptiScaler.dll')) -eq $old) 'Remove leaves unowned extracted source intact'
$indexHash=Get-AuroraHash (Get-AuroraIndexPath $game)
Deny { Install-AuroraDeployment $game $pkg '' (Join-Path $ScratchRoot 'blocked.json') } 'Unattended upgrade cannot silently take over extracted files'
Assert ((Get-AuroraHash (Get-AuroraIndexPath $game)) -eq $indexHash -and -not (Test-Path -LiteralPath (Join-Path $dx11 'dxgi.dll'))) 'Second-entry conflict is found before writing either entry or retiring the old index'
$review=Read-AuroraJson (Join-Path $ScratchRoot 'blocked.json')
Assert ($review.Status -eq 'AwaitingConflictConsent' -and $review.Conflicts.Count -ge 2) 'Conflict report includes core and bundled Runtime with exact hashes'
Deny { Install-AuroraDeployment $game $pkg '' (Join-Path $ScratchRoot 'cancel.json') -ConfirmConflicts {param($files) return $false} } 'Cancel preserves everything'
Deny { Install-AuroraDeployment $game $pkg '' (Join-Path $ScratchRoot 'ambiguous.json') -ConfirmConflicts {param($files) return 'yes'} } 'Only explicit boolean approval is accepted'
$script:reviewed=@()
$index=Install-AuroraDeployment $game $pkg '' (Join-Path $ScratchRoot 'upgrade.json') -ConfirmConflicts {param($files) $script:reviewed=@($files); return $true}
Assert ($index.Status -eq 'Applied' -and $index.Targets.Count -eq 2 -and $script:reviewed.Count -eq $review.Conflicts.Count) 'One reviewed consent covers the exact conflict set and both entries complete'
foreach($dir in @($dx11,$dx12)) { Assert ((Get-AuroraHash (Join-Path $dir 'dxgi.dll')) -eq (Get-AuroraHash (Join-Path $pkg 'OptiScaler.dll'))) 'Both proxies use the new core' }
$j=Open-AuroraJournal (Join-Path $dx12 'OptiScaler\AuroraSetup\manifest.json') $game $dx12
$e=@($j.Entries | Where-Object {$_.TargetPath -eq (Join-Path $dx12 'OptiScaler.dll')})[0]
Assert (-not $e.Created -and $e.OriginalHash -eq $old -and (Get-AuroraHash $e.BackupPath) -eq $old) 'Reviewed takeover records and verifies the original backup'
Assert ((Get-AuroraHash (Join-Path $dx12 'sl.interposer.dll')) -eq $sl1 -and (Get-AuroraHash (Join-Path $dx12 'OptiScaler.ini')) -eq $config) 'SL1 and user configuration stay intact'
$null=Remove-AuroraDeployment $index (Join-Path $ScratchRoot 'restore-extracted.json')
Assert ((Get-AuroraHash (Join-Path $dx12 'OptiScaler.dll')) -eq $old -and -not (Test-Path -LiteralPath (Join-Path $dx11 'dxgi.dll'))) 'Remove restores old extracted source and removes newly created proxies'
# Consent is not permission for files changed during review.
Deny { Install-AuroraDeployment $game $pkg '' (Join-Path $ScratchRoot 'race.json') -ConfirmConflicts {param($files) Put $files[0].Path 'changed during review'; return $true} } 'Changed reviewed file aborts before any new transaction'
Assert (-not (Test-Path -LiteralPath (Join-Path $dx11 'dxgi.dll'))) 'Review race cannot partially activate the first entry'
# Proxy conflicts are never offered for takeover, even with a plausible PE identity.
$proxy=Join-Path $dx11 'dxgi.dll'; Copy-Item -LiteralPath (Join-Path $dx12 'OptiScaler.dll') -Destination $proxy
$script:called=$false
Deny { Install-AuroraDeployment $game $pkg '' (Join-Path $ScratchRoot 'proxy-blocked.json') -ConfirmConflicts {$script:called=$true; return $true} } 'Unowned Proxy collision stays blocked'
Assert (-not $script:called) 'Payload consent cannot bypass Proxy ownership protection'
Remove-Item -LiteralPath $proxy
# Real CMD interaction, including decline and B approval, in a separate fresh game.
$ui=Join-Path $ScratchRoot '交互 巫师3'; Package $ui
$uiDir=Join-Path $ui 'bin\x64_dx12'; Binary (Join-Path $uiDir 'witcher3.exe'); Binary (Join-Path $uiDir 'OptiScaler.dll') '2.0.0.0'
function Entry([string]$InputText) {
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$env:ComSpec; $psi.Arguments='/d /c ""'+(Join-Path $ui 'Aurora_Setup.bat')+'""'
    $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $psi.EnvironmentVariables['LOCALAPPDATA']=Join-Path $ScratchRoot 'UserLocal'
    $process=[Diagnostics.Process]::Start($psi); $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
    $process.StandardInput.Write($InputText); $process.StandardInput.Close()
    if(-not $process.WaitForExit(60000)){ $process.Kill(); throw 'Entry timeout' }
    $result=[pscustomobject]@{ExitCode=$process.ExitCode;Output=$stdout.Result+$stderr.Result}; $process.Dispose(); return $result
}
$cancel=Entry "`r`n`r`n`r`n"; Put (Join-Path $ScratchRoot 'ui-cancel.txt') $cancel.Output
Assert ($cancel.ExitCode -ne 0 -and -not (Test-Path -LiteralPath (Join-Path $uiDir 'dxgi.dll'))) 'Real wrapper Enter cancels conflict without writing Proxy'
$accepted=Entry "`r`nD`r`nB`r`n`r`n"; Put (Join-Path $ScratchRoot 'ui-accept.txt') $accepted.Output
Assert ($accepted.ExitCode -eq 0 -and $accepted.Output -match '选择备份更新将先保存原文件' -and $accepted.Output -match '部署完成') 'Real wrapper D then B reviews and completes deployment'
# New user edits still prevent Remove from deleting or overwriting their file.
$installed=Open-AuroraIndex $ui; Put (Join-Path $uiDir 'OptiScaler.dll') 'user mod after upgrade'
$preserved=@(Remove-AuroraDeployment $installed (Join-Path $ScratchRoot 'preserved.json'))
Assert ($preserved -contains (Join-Path $uiDir 'OptiScaler.dll') -and [IO.File]::ReadAllText((Join-Path $uiDir 'OptiScaler.dll')) -eq 'user mod after upgrade') 'User modifications after approved upgrade remain untouched by Remove'
$baseCopy=${function:Copy-AuroraAtomic}
foreach ($phase in @('backup','core-copy')) {
    $faultGame=Join-Path $ScratchRoot ('fault-'+$phase); $faultDir=Join-Path $faultGame 'Win64'
    Binary (Join-Path $faultDir 'Game.exe'); Binary (Join-Path $faultDir 'OptiScaler.dll') '2.0.0.0'
    $original=Get-AuroraHash (Join-Path $faultDir 'OptiScaler.dll'); $script:faultHit=$false
    function Copy-AuroraAtomic([string]$Source,[string]$Target,[string]$ExpectedCurrent,[string]$ExpectedSource) {
        if (($script:phase -eq 'backup' -and $Target -like '*\backup\*') -or ($script:phase -eq 'core-copy' -and $Target -eq (Join-Path $script:faultDir 'OptiScaler.dll'))) {
            $script:faultHit=$true; throw 'Injected reviewed takeover failure'
        }
        & $script:baseCopy $Source $Target $ExpectedCurrent $ExpectedSource
    }
    Deny { Install-AuroraDeployment $faultGame $pkg '' (Join-Path $ScratchRoot ($phase+'.json')) -ConfirmConflicts {return $true} } "Reviewed takeover stops on $phase failure"
    Set-Item Function:Copy-AuroraAtomic $baseCopy
    $failed=Open-AuroraIndex $faultGame
    Assert ($script:faultHit -and $failed.Status -eq 'NeedsAttention' -and -not (Test-Path -LiteralPath (Join-Path $faultDir 'dxgi.dll'))) "Failure at $phase is not reported as success and activates no Proxy"
    $null=Remove-AuroraDeployment $failed (Join-Path $ScratchRoot ($phase+'-remove.json'))
    Assert ((Get-AuroraHash (Join-Path $faultDir 'OptiScaler.dll')) -eq $original) "Remove after $phase failure preserves the original extracted core"
}
Finish 'EXTRACTED UPGRADE'
