param([string]$ScratchRoot=(Join-Path $env:TEMP ('AuroraEntryIncident-'+[Guid]::NewGuid().ToString('N'))))
. (Join-Path $PSScriptRoot 'Aurora_Hardening_TestSupport.ps1')
$game=Join-Path $ScratchRoot '异环 [中文] 空格\Client\WindowsNoEditor'; $win=Join-Path $game 'HT\Binaries\Win64'
Package $win
Binary (Join-Path $win 'HTGame.exe'); Binary (Join-Path $win 'CrashCapture.exe'); Binary (Join-Path $win 'CrashClientReporter.exe')
Binary (Join-Path $win 'AntiCheatExpert\ACE-Service64.exe')
Binary (Join-Path $game 'Engine\Plugins\Runtime\Nvidia\DLSS\Binaries\ThirdParty\Win64\nvngx_dlss.dll') '310.1.0.0'
$installer=Join-Path $win 'Aurora_Installer.ps1'
$text=[IO.File]::ReadAllText($installer)
# The real product pins game companion bytes, not synthetic executables. Substitute
# only those two fingerprints in this isolated package; no helper-policy stubs.
$text=$text.Replace('1C909503EC05A58552F244654D62105BDA92B16D90F66C6E87B5F69944CA3FB5',(Get-AuroraHash (Join-Path $win 'CrashCapture.exe')))
$text=$text.Replace('FC334948C58161D706035A17C72DAFABC1BBF309A0EB1AE853EFFE11A25FBD26',(Get-AuroraHash (Join-Path $win 'CrashClientReporter.exe')))
Put $installer $text
$sourceHash=Get-AuroraHash (Join-Path $win 'OptiScaler.dll')
function RunEntry([string]$Wrapper,[string]$InputText) {
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$env:ComSpec; $psi.Arguments='/d /c ""'+(Join-Path $script:win $Wrapper)+'""'
    $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    # Keep fixture sessions out of the user's real log directory.
    $psi.EnvironmentVariables['LOCALAPPDATA']=Join-Path $script:ScratchRoot 'UserLocal'
    $process=[Diagnostics.Process]::Start($psi)
    $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
    $process.StandardInput.Write($InputText); $process.StandardInput.Close()
    if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'Entry timed out.' }
    $result=[pscustomobject]@{ExitCode=$process.ExitCode;Output=$stdout.Result;Error=$stderr.Result}
    $process.Dispose(); return $result
}
$first=RunEntry 'Aurora_Setup.bat' "`r`n`r`n"
Put (Join-Path $ScratchRoot 'install-output.txt') ($first.Output+$first.Error)
Assert ($first.ExitCode -eq 0) 'Real CMD wrapper accepts one Enter to install from an extracted package inside Win64'
Assert ($first.Output -match 'HTGame.exe' -and $first.Output -match 'winmm.dll' -and $first.Output -notmatch 'ACE-Service64.exe') 'Normal UI names HTGame and winmm without listing ACE as an entry'
Assert ($first.Output -match '已同步 1 项' -and $first.Output -match '实际加载') 'Normal UI reports actual Runtime outcome and requests in-game verification'
$index=Open-AuroraIndex $game
Assert ($index.Status -eq 'Applied' -and $index.Targets[0].Directory -eq $win -and $index.Targets[0].Proxy -eq 'winmm.dll') 'Automatic root resolution and disk deployment agree'
Assert ((Get-AuroraHash (Join-Path $win 'OptiScaler.dll')) -eq $sourceHash -and (Get-AuroraHash (Join-Path $win 'winmm.dll')) -eq $sourceHash) 'Extracted core stays intact while a real Proxy is created'
$journal=Open-AuroraJournal $index.Targets[0].JournalPath $game $win
Assert (-not @($journal.Entries | Where-Object { $_.TargetPath -eq (Join-Path $win 'OptiScaler.dll') }).Count) 'Source extraction alone does not grant installer ownership of OptiScaler.dll'
$again=RunEntry 'Aurora_Setup.bat' "`r`n`r`n"
Assert ($again.ExitCode -eq 0 -and $again.Output -match '已同步 0 项，已是包内版本 1 项') 'Update runs the complete chain and reports an already-current Runtime'
$remove=RunEntry 'Remove_Aurora.bat' "`r`n"
Assert ($remove.ExitCode -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $win 'winmm.dll')) -and (Test-Path -LiteralPath (Join-Path $win 'OptiScaler.dll'))) 'Actual Remove entry deletes owned Proxy and retains extracted source core'
$sessions=@(Get-ChildItem -LiteralPath (Join-Path $ScratchRoot 'UserLocal\Aurora\Logs') -Directory)
Assert ($sessions.Count -eq 3 -and @(Get-ChildItem -LiteralPath $sessions[0].FullName -File).Count -gt 1) 'Each real wrapper operation keeps its files in one managed log session'
Finish 'INSTALL ENTRY'
