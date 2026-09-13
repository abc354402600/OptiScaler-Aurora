$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$toolsDir=Join-Path $repo 'dist\runtime_sync'
. (Join-Path $toolsDir 'Aurora_Common.ps1')
. (Join-Path $toolsDir 'Aurora_Installer.ps1')
$ScratchRoot=Get-AuroraPath $ScratchRoot
if (Test-Path -LiteralPath $ScratchRoot) { throw 'Hardening tests require a fresh scratch directory.' }
[IO.Directory]::CreateDirectory($ScratchRoot) | Out-Null
$passed=0; $skipped=@()
function Assert($Condition,[string]$Name) { if (-not $Condition) { throw "FAIL: $Name" }; $script:passed++; Write-Host "PASS: $Name" }
function Deny([scriptblock]$Body,[string]$Name) { $denied=$false; try { & $Body | Out-Null } catch { $denied=$true }; Assert $denied $Name }
function Put([string]$Path,[string]$Text) { [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null; [IO.File]::WriteAllText($Path,$Text,(New-Object Text.UTF8Encoding($true))) }
function Binary([string]$Path,[string]$Version='3.0.0.0') {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    $cs=Join-Path $ScratchRoot ([Guid]::NewGuid().ToString('N')+'.cs')
    Put $cs ('using System.Reflection; [assembly:AssemblyFileVersion("'+$Version+'")] public class Fixture { public static void Main() {} }')
    $kind='library'; if ($Path.EndsWith('.exe')) { $kind='exe' }
    & (Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /platform:x64 "/target:$kind" "/out:$Path" $cs
    if ($LASTEXITCODE) { throw 'Fixture compile failed.' }
}
function Package([string]$Path) {
    Binary (Join-Path $Path 'OptiScaler.dll')
    Binary (Join-Path $Path 'OptiScaler\nvngx_dlss.dll') '310.9.0.0'
    Put (Join-Path $Path 'OptiScaler.ini') "[FrameGen]`nDualFeature=false`nLogToFile=auto`nLogLevel=auto`n"
    foreach ($file in @(Get-ChildItem -LiteralPath $toolsDir -File)) { [IO.File]::Copy($file.FullName,(Join-Path $Path $file.Name)) }
}
function Finish([string]$Phase) { Write-Host "ALL PASSED: $passed $Phase assertions; skipped=$($skipped.Count). Scratch: $ScratchRoot" }
