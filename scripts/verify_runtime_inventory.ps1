param([string]$Root = (Split-Path -Parent $PSScriptRoot), [string]$PackageRoot)
$ErrorActionPreference = 'Stop'
$inventory = Get-Content -Raw -LiteralPath (Join-Path $Root 'dist/runtime_versions.json') | ConvertFrom-Json
foreach ($entry in $inventory.Files) {
    $file = Join-Path $Root $entry.Path
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing runtime: $($entry.Path)" }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ine $entry.SHA256) { throw "Runtime hash mismatch: $($entry.Path)" }
    if ((Get-Item -LiteralPath $file).Length -ne $entry.Bytes) { throw "Runtime size mismatch: $($entry.Path)" }
    if ($PackageRoot) {
        $relative = $entry.Path -replace '^dist/nvngx/', 'OptiScaler/' -replace '^dist/streamline/', 'OptiScaler/streamline/'
        $packed = Join-Path $PackageRoot $relative
        if (-not (Test-Path -LiteralPath $packed -PathType Leaf)) { throw "Missing packaged runtime: $relative" }
        if ((Get-FileHash -LiteralPath $packed -Algorithm SHA256).Hash -ine $entry.SHA256) { throw "Packaged runtime hash mismatch: $relative" }
    }
}
Write-Output "PASS: $($inventory.Files.Count) official runtime hashes verified"
