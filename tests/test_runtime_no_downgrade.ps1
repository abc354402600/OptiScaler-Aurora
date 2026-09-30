$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$source = Join-Path $PSScriptRoot '../dist/runtime_sync/runtime_sync.ps1'
$ast = [Management.Automation.Language.Parser]::ParseFile((Resolve-Path $source), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Get-RuntimeVersion','Get-RuntimePreserveReason','Sync-One')) {
    $definition = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name}, $true)
    . ([scriptblock]::Create($definition.Extent.Text))
}
$versions = @{}
function Get-FileVersionSafe($Path) { return $versions[$Path] }
function Get-FileHashSafe($Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Get-StreamlineMajorVersion($Path) { return 2 }
function Find-Entry($Entries,$Path) { return $null }
function Write-Warn2($Text) {}
function Save-TargetBackup { throw 'Unexpected backup/write path' }
function Write-Fail { throw 'Unexpected failure/write path' }
$script:checks = 0
function Assert($Condition) { if (-not $Condition) { throw "Runtime check $($script:checks+1) failed" }; $script:checks++ }
$root = Join-Path ([IO.Path]::GetTempPath()) ('aurora-version-' + [guid]::NewGuid().ToString('N'))
try {
    $game = New-Item -ItemType Directory -Path (Join-Path $root 'game space') -Force
    $bundle = New-Item -ItemType Directory -Path (Join-Path $root 'bundle') -Force
    $Sources = @{}
    foreach ($name in @('nvngx_dlss.dll','sl.common.dll','sl.reflex.dll')) {
        $src = Join-Path $bundle.FullName $name; $dst = Join-Path $game.FullName $name
        [IO.File]::WriteAllText($src,'bundle'); [IO.File]::WriteAllText($dst,'game')
        $Sources[$name] = $src
        $versions[$src] = '2,14,0,0'; $versions[$dst] = '2.14.0.0'
    }
    $dlss = Join-Path $game.FullName 'nvngx_dlss.dll'
    $versions[$Sources['nvngx_dlss.dll']] = '310,9,0,0'
    foreach ($case in @(@('310.9.1.0','Newer'),@('310.10.0.0','Newer'),@('310.9.0.0',''),@('310.8.0.0',''),@('','Unknown'),@('0.0.0.0','Unknown'),@('broken','Unknown'),@('310,9,1,0','Newer'))) {
        $versions[$dlss]=$case[0]; Assert ((Get-RuntimePreserveReason $dlss) -eq $case[1])
    }
    $versions[$dlss]='310.9.1.0'
    $before=Get-FileHashSafe $dlss; $result=Sync-One @() $dlss $true
    Assert ($result.Status -eq 'Preserved'); Assert ((Get-FileHashSafe $dlss) -eq $before); Assert (@($result.Entries).Count -eq 0)
    $common=Join-Path $game.FullName 'sl.common.dll'; $reflex=Join-Path $game.FullName 'sl.reflex.dll'
    $versions[$reflex]='2.14.1.0'
    Assert ((Get-RuntimePreserveReason $common) -eq 'Newer')
    $before=Get-FileHashSafe $common; $result=Sync-One @() $common $true
    Assert ($result.Status -eq 'Preserved'); Assert ((Get-FileHashSafe $common) -eq $before)
    $versions[$reflex]='unknown'; Assert ((Get-RuntimePreserveReason $common) -eq 'Unknown')
    $versions[$reflex]='2.14.0.0'; Assert ((Get-RuntimePreserveReason $common) -eq '')
    $versions[$Sources['sl.common.dll']]='unknown'; Assert ((Get-RuntimePreserveReason $common) -eq 'Unknown')
    Write-Output "PASS: $script:checks runtime no-downgrade checks"
} finally {
    $absolute=[IO.Path]::GetFullPath($root)
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if (-not $absolute.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($absolute) -notlike 'aurora-version-*') { throw 'Unsafe test cleanup path' }
    if (Test-Path -LiteralPath $absolute) { Remove-Item -LiteralPath $absolute -Recurse -Force }
}
