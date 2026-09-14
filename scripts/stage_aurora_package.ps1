param(
    [string]$RepositoryRoot,
    [Parameter(Mandatory=$true)][string]$Destination,
    [switch]$VerifyOnly
)
$ErrorActionPreference='Stop'
if (-not $RepositoryRoot) { $RepositoryRoot=Split-Path -Parent $PSScriptRoot }
. (Join-Path $RepositoryRoot 'dist\runtime_sync\Aurora_Common.ps1')
. (Join-Path $RepositoryRoot 'dist\runtime_sync\Aurora_RuntimeCatalog.ps1')
$RepositoryRoot=Get-AuroraPath $RepositoryRoot; $Destination=Get-AuroraPath $Destination
if (-not (Test-AuroraWithin $Destination $RepositoryRoot) -or $Destination -ieq $RepositoryRoot) { throw 'Package destination must be inside this checkout.' }
$guard=Enter-AuroraPathGuard $Destination -Directory -Create
try {
    $files=@()
    $required=@('Aurora_Common.ps1','Aurora_Installer.ps1','Aurora_RuntimeCatalog.ps1','Aurora_Setup_Legacy.ps1','Aurora_Diagnostics.ps1','Aurora_Setup.ps1','runtime_sync.ps1','Aurora_Setup.bat','Check_DLSS_Runtime.bat','Remove_Aurora.bat')
    foreach ($name in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $RepositoryRoot ('dist\runtime_sync\'+$name)) -PathType Leaf)) { throw "Missing Aurora helper: $name" }
    }
    # Include future helper additions automatically, while requiring today's complete set.
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'dist\runtime_sync') -File)) {
        if ($file.Extension -in @('.ps1','.bat')) { $files+=@([pscustomobject]@{Source=$file.FullName;Relative=$file.Name}) }
    }
    $files+=@([pscustomobject]@{Source=(Join-Path $RepositoryRoot 'setup_windows.bat');Relative='setup_windows.bat'})
    foreach ($name in @('nvngx_dlss.dll','nvngx_dlssg.dll','nvngx_dlssd.dll','dlssg_to_fsr3_amd_is_better.dll')) {
        $files+=@([pscustomobject]@{Source=(Join-Path $RepositoryRoot ('dist\nvngx\'+$name));Relative=('OptiScaler\'+$name)})
    }
    foreach ($name in $AuroraVerifiedSL2.Keys) {
        $source=Join-Path $RepositoryRoot ('dist\streamline\'+$name)
        if ((Get-AuroraHash $source) -ne $AuroraVerifiedSL2[$name]) { throw "Unverified Streamline package source: $name" }
        $files+=@([pscustomobject]@{Source=$source;Relative=('OptiScaler\streamline\'+$name)})
    }
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'dist\streamline') -File -Filter '*.txt')) {
        $files+=@([pscustomobject]@{Source=$file.FullName;Relative=('OptiScaler\streamline\'+$file.Name)})
    }
    foreach ($file in $files) {
        $hash=Get-AuroraHash $file.Source
        $bytes=$null
        if ([IO.Path]::GetExtension($file.Source) -ieq '.bat') {
            # git archive stores LF even with eol=crlf; CMD requires CRLF here.
            $content=[IO.File]::ReadAllText($file.Source).Replace("`r`n","`n").Replace("`n","`r`n")
            $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($content)
            $sha=[Security.Cryptography.SHA256]::Create()
            try { $hash=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','') } finally { $sha.Dispose() }
        }
        $file | Add-Member NoteProperty Hash $hash
        $file | Add-Member NoteProperty Bytes $bytes
    }
    if (-not $VerifyOnly) {
        foreach ($file in $files) {
            $target=Join-Path $Destination $file.Relative; $current=''
            if (Test-Path -LiteralPath $target) { $current=Get-AuroraHash $target }
            if ($null -ne $file.Bytes) {
                $temporary=Join-Path $Destination ([Guid]::NewGuid().ToString('N')+'.aurora-bat-tmp')
                try {
                    [IO.File]::WriteAllBytes($temporary,$file.Bytes)
                    Copy-AuroraAtomic $temporary $target $current $file.Hash
                } finally { if (Test-Path -LiteralPath $temporary) { [IO.File]::Delete($temporary) } }
            } else { Copy-AuroraAtomic $file.Source $target $current $file.Hash }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $Destination 'OptiScaler.ini'))) {
            $ini=Join-Path $RepositoryRoot 'OptiScaler.ini'
            Copy-AuroraAtomic $ini (Join-Path $Destination 'OptiScaler.ini') '' (Get-AuroraHash $ini)
        }
    }
    foreach ($file in $files) {
        if ((Get-AuroraHash (Join-Path $Destination $file.Relative)) -ne $file.Hash) { throw "Stale/missing packaged file: $($file.Relative)" }
    }
    $null=Get-AuroraHash (Join-Path $Destination 'OptiScaler.dll')
    $ini=Get-Content -LiteralPath (Join-Path $Destination 'OptiScaler.ini') -Raw -Encoding UTF8
    if ($ini -notmatch '(?m)^DualFeature=false\s*$') { throw 'Package must preserve DualFeature=false.' }
    Write-Host "Aurora package verified: $($files.Count) current helpers/runtime files and core/config."
} finally { $guard.Dispose() }
