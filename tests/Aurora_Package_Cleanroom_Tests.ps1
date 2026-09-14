param([string]$ScratchRoot=(Join-Path $env:TEMP ('AuroraPackage-'+[Guid]::NewGuid().ToString('N'))))
. (Join-Path $PSScriptRoot 'Aurora_Hardening_TestSupport.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$clean=Join-Path $ScratchRoot '源码 clean [中文]'; $src=Join-Path $clean 'x64\Release\a'
foreach ($relative in @('package_release.ps1','setup_windows.bat','OptiScaler.ini','scripts\stage_aurora_package.ps1')) {
    $dest=Join-Path $clean $relative; [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest)) | Out-Null
    [IO.File]::Copy((Join-Path $repo $relative),$dest)
}
[IO.Directory]::CreateDirectory((Join-Path $clean 'dist')) | Out-Null
Copy-Item -LiteralPath $toolsDir -Destination (Join-Path $clean 'dist\runtime_sync') -Recurse
Copy-Item -LiteralPath (Join-Path $repo 'dist\streamline') -Destination (Join-Path $clean 'dist\streamline') -Recurse
# Reproduce a git archive / replacement ZIP with LF-only batch source files.
foreach ($bat in @((Join-Path $clean 'setup_windows.bat'))+@(Get-ChildItem -LiteralPath (Join-Path $clean 'dist\runtime_sync') -Filter '*.bat' | ForEach-Object { $_.FullName })) {
    [IO.File]::WriteAllText($bat,[IO.File]::ReadAllText($bat).Replace("`r`n","`n"),(New-Object Text.UTF8Encoding($false)))
}
Package $src
foreach ($name in @('nvngx_dlss.dll','nvngx_dlssg.dll','nvngx_dlssd.dll','dlssg_to_fsr3_amd_is_better.dll')) { Binary (Join-Path $clean ('dist\nvngx\'+$name)) '310.9.0.0' }
Put (Join-Path $src 'Licenses\fixture.txt') 'Synthetic fixtures; not playable GPU binaries.'
Put (Join-Path $src 'nvngx.dll_dlssnr.dll') 'Synthetic forwarder: dlssnr_call_create dlssnr_call_evaluate dlssnr_call_set_extras'
Put (Join-Path $src 'OptiScaler\AuroraSetup\should-not-ship.json') 'user recovery metadata'
Put (Join-Path $src 'OptiScaler\RuntimeSync\backup\user.dll') 'user backup'
Put (Join-Path $src 'OptiScaler\plugins\ThirdParty.asi') 'third party plugin'
Put (Join-Path $src 'OptiScaler\debug.pdb') 'debug symbols'
Put (Join-Path $src 'Aurora_Installer.ps1') 'stale build output helper'
$packager=Join-Path $clean 'package_release.ps1'; $zip=Join-Path $clean 'release\OptiScaler-DLSSNR-cleanroom.zip'
function Run-Package([string]$Version='cleanroom',[switch]$Fail) {
    $ErrorActionPreference='Continue'
    $output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:packager -SkipBuild -Version $Version 2>&1
    $ErrorActionPreference='Stop'
    $code=$LASTEXITCODE; $output | Out-File -LiteralPath (Join-Path $ScratchRoot 'package.log.txt') -Encoding UTF8 -Append
    if ($Fail) { Assert ($code -ne 0) "Invalid package rejected: $Version" } else { Assert ($code -eq 0) 'Clean-room package command succeeded' }
}
function Run-Batch([string]$Path,[string]$InputText) {
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$env:ComSpec; $psi.Arguments='/d /c ""'+$Path+'""'; $psi.WorkingDirectory=[IO.Path]::GetDirectoryName($Path)
    $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $process=[Diagnostics.Process]::Start($psi)
    $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
    $process.StandardInput.Write($InputText); $process.StandardInput.Close()
    if (-not $process.WaitForExit(120000)) { $process.Kill(); throw 'Packaged wrapper timed out.' }
    $code=$process.ExitCode
    ($stdout.Result+$stderr.Result) | Out-File -LiteralPath (Join-Path $ScratchRoot 'wrappers.log.txt') -Append -Encoding UTF8
    $process.Dispose(); Assert ($code -eq 0) ('Packaged wrapper succeeded: '+[IO.Path]::GetFileName($Path))
}
Run-Package
$zipHash=Get-AuroraHash $zip
foreach ($badVersion in @('..\escape','C:\escape','\\server\share','bad/part')) { Run-Package $badVersion -Fail }
Assert ((Get-AuroraHash $zip) -eq $zipHash) 'Invalid versions do not alter last good archive'
$missing=Join-Path $clean 'dist\runtime_sync\Aurora_Installer.ps1'; $saved=[IO.File]::ReadAllBytes($missing); [IO.File]::Delete($missing)
Run-Package -Fail; [IO.File]::WriteAllBytes($missing,$saved)
Assert ((Get-AuroraHash $zip) -eq $zipHash) 'Missing required helper cannot publish partial archive'
$missing=Join-Path $src 'OptiScaler.dll'; $saved=[IO.File]::ReadAllBytes($missing); [IO.File]::Delete($missing)
Run-Package -Fail; [IO.File]::WriteAllBytes($missing,$saved)
Assert ((Get-AuroraHash $zip) -eq $zipHash) 'Missing core cannot replace good archive'
$badSl=Join-Path $clean 'dist\streamline\sl.common.dll'; $saved=[IO.File]::ReadAllBytes($badSl); Put $badSl 'unverified SL2'
Run-Package -Fail; [IO.File]::WriteAllBytes($badSl,$saved)
Assert ((Get-AuroraHash $zip) -eq $zipHash) 'Catalog mismatch cannot replace good archive'

$game=Join-Path $ScratchRoot '游戏 clean [中文]'; $a=Join-Path $game 'bin\x64_dx12'; $b=Join-Path $game 'bin\x64'
foreach ($dir in @($a,$b)) { Binary (Join-Path $dir 'witcher3.exe'); Binary (Join-Path $dir 'nvngx_dlss.dll') '310.1.0.0' }
$originals=@{}; foreach ($dir in @($a,$b)) { $originals[$dir]=Get-AuroraHash (Join-Path $dir 'nvngx_dlss.dll') }
$package=Join-Path $game 'Aurora package [中文]'; [IO.Compression.ZipFile]::ExtractToDirectory($zip,$package)
$helpers=@(Get-ChildItem -LiteralPath $toolsDir -File | Where-Object { $_.Extension -in @('.ps1','.bat') })
foreach ($file in $helpers) { Assert ((Get-AuroraHash (Join-Path $package $file.Name)) -eq (Get-AuroraHash $file.FullName)) ('Archive helper matches source: '+$file.Name) }
Assert ((Get-AuroraHash (Join-Path $package 'setup_windows.bat')) -eq (Get-AuroraHash (Join-Path $repo 'setup_windows.bat'))) 'Archive entry wrapper matches source'
foreach ($rel in @('OptiScaler\AuroraSetup','OptiScaler\RuntimeSync','OptiScaler\plugins\ThirdParty.asi','OptiScaler\debug.pdb')) { Assert (-not (Test-Path -LiteralPath (Join-Path $package $rel))) ('No build/user residue: '+$rel) }
Run-Batch (Join-Path $package 'setup_windows.bat') "`r`n`r`n"
$index=Open-AuroraIndex $game
Assert ($index.Status -eq 'Applied' -and $index.Targets.Count -eq 2) 'One-Enter wrapper auto-discovers and installs both Witcher entry directories'
foreach ($dir in @($a,$b)) {
    Assert ((Get-AuroraHash (Join-Path $dir 'dxgi.dll')) -eq (Get-AuroraHash (Join-Path $package 'OptiScaler.dll'))) 'Each entry has self-contained matching Proxy'
    Assert ((Get-AuroraHash (Join-Path $dir 'nvngx_dlss.dll')) -eq (Get-AuroraHash (Join-Path $package 'OptiScaler\nvngx_dlss.dll'))) 'Separate native Runtime group updated'
    foreach ($file in $helpers) { Assert (Test-Path -LiteralPath (Join-Path $dir $file.Name)) ('Deployed recovery dependency: '+$file.Name) }
}
Put (Join-Path $a 'OptiScaler.ini') "[FrameGen]`nDualFeature=false`n; user configuration after install`n"
$userConfig=Get-AuroraHash (Join-Path $a 'OptiScaler.ini')
Binary (Join-Path $src 'OptiScaler.dll') '4.0.0.0'
Run-Package
$update=Join-Path $game 'Aurora update'; [IO.Compression.ZipFile]::ExtractToDirectory($zip,$update)
Run-Batch (Join-Path $update 'setup_windows.bat') "`r`n`r`n"
foreach ($dir in @($a,$b)) { Assert ((Get-AuroraHash (Join-Path $dir 'dxgi.dll')) -eq (Get-AuroraHash (Join-Path $update 'OptiScaler.dll'))) 'Both Proxies updated from repackaged core' }
Assert ((Get-AuroraHash (Join-Path $a 'OptiScaler.ini')) -eq $userConfig) 'Update preserves user-edited config'

# New remove fault: final state writes fail persistently after files were restored.
$baseJson=${function:Write-AuroraJson}; $injected=$false
function Write-AuroraJson([string]$Path,$Value) {
    if ($Path.EndsWith('AuroraInstallManifest.json') -and $Value.Status -in @('Removed','NeedsAttention')) { $script:injected=$true; throw 'Injected final removal index failure' }
    & $script:baseJson $Path $Value
}
Deny { Remove-AuroraDeployment (Open-AuroraIndex $game) (Join-Path $ScratchRoot 'failed-remove.json') } 'Removal final index failure is reported'
Set-Item Function:\Write-AuroraJson $baseJson
Assert ($injected -and (Open-AuroraIndex $game).Status -eq 'Pending') 'Partial remove remains Pending even if NeedsAttention cannot be written'
# Recovery can run from the extracted package after all local helpers were already removed.
$output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $update 'Aurora_Setup.ps1') -Action Remove -GameRoot $game -NonInteractive 2>&1
$output | Out-File -LiteralPath (Join-Path $ScratchRoot 'retry-remove.log.txt') -Encoding UTF8
Assert ($LASTEXITCODE -eq 0) 'Packaged recovery retries incomplete removal'
foreach ($dir in @($a,$b)) {
    Assert ((Get-AuroraHash (Join-Path $dir 'nvngx_dlss.dll')) -eq $originals[$dir]) 'Remove restores original Runtime bytes in both groups'
    Assert (-not (Test-Path -LiteralPath (Join-Path $dir 'dxgi.dll'))) 'Remove cleans redundant Proxy'
}
Assert ((Get-AuroraHash (Join-Path $a 'OptiScaler.ini')) -eq $userConfig) 'Remove preserves modified user config'

# A second real wrapper pipeline with native SL1; DLLs are test fixtures, not GPU tests.
$slGame=Join-Path $ScratchRoot 'SL1 game'; $slDir=Join-Path $slGame 'bin\x64_dx12'
Binary (Join-Path $slDir 'witcher3.exe'); Binary (Join-Path $slDir 'sl.interposer.dll') '1.5.6.0'
$slHash=Get-AuroraHash (Join-Path $slDir 'sl.interposer.dll')
$slPackage=Join-Path $slGame 'Aurora package'; [IO.Compression.ZipFile]::ExtractToDirectory($zip,$slPackage)
Run-Batch (Join-Path $slPackage 'setup_windows.bat') "`r`n`r`n"
Assert ((Get-AuroraHash (Join-Path $slDir 'sl.interposer.dll')) -eq $slHash) 'Clean-room bundled SL2 does not replace native SL1'
Run-Batch (Join-Path $slDir 'Remove_Aurora.bat') "`r`n"
Assert (-not (Test-Path -LiteralPath (Join-Path $slDir 'dxgi.dll')) -and (Get-AuroraHash (Join-Path $slDir 'sl.interposer.dll')) -eq $slHash) 'Deployed Remove wrapper restores clean SL1 game'
Assert ((Get-AuroraHash (Join-Path $slPackage 'OptiScaler.dll')) -eq (Get-AuroraHash (Join-Path $src 'OptiScaler.dll'))) 'Uninstall preserves extracted source package'

foreach ($workflow in @('build.yml','just_build.yml','just_build_no_signature.yml','release_debug.yml')) {
    $text=Get-Content -LiteralPath (Join-Path $repo ('.github\workflows\'+$workflow)) -Raw
    Assert ($text.IndexOf('stage_aurora_package.ps1') -gt 0 -and $text.IndexOf('stage_aurora_package.ps1') -lt $text.IndexOf('7z a')) ('Actions gates archive on current RC3 files: '+$workflow)
}
Finish 'PACKAGE CLEANROOM'
