param([Parameter(Mandatory=$true)][string]$Archive)
$ErrorActionPreference = 'Stop'

# Only the explicit formal tag can publish; branch/manual builds remain artifacts.
$tag = 'aurora-v1.1'
$repo = 'abc354402600/OptiScaler-Aurora'
if ($env:GITHUB_REF -ne "refs/tags/$tag" -or $env:GITHUB_REPOSITORY -ne $repo) {
    throw 'Formal release requires the Aurora v1.1 tag in the expected repository.'
}
$head = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE) { throw 'Cannot resolve build commit.' }
$mainRef = & git ls-remote origin refs/heads/aurora
if ($LASTEXITCODE -or -not $mainRef) { throw 'Cannot verify aurora head.' }
if (($mainRef -split '\s+')[0] -ne $head -or $env:GITHUB_SHA -ne $head) {
    throw 'Release build must match the current aurora head and tag event commit.'
}
$resource = Get-Content -LiteralPath 'OptiScaler/resource.h' -Raw
if ($resource -notmatch '(?m)^#define VER_AURORA_VERSION "1\.1"\s*$') {
    throw 'Resource version does not match the release tag.'
}
if (-not (Test-Path -LiteralPath $Archive -PathType Leaf) -or (Get-Item -LiteralPath $Archive).Length -eq 0) {
    throw 'Release archive missing or empty.'
}
$hash = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant()
$assetName = [IO.Path]::GetFileName($Archive)
"$hash  $assetName" | Set-Content -LiteralPath 'SHA256SUMS.txt' -Encoding ascii

# Never replace published assets. A failed upload can resume its draft only.
$releaseList = & gh api "repos/$repo/releases?per_page=100"
if ($LASTEXITCODE) { throw 'Cannot inspect existing releases.' }
$existing = @($releaseList | ConvertFrom-Json | Where-Object { $_.tag_name -eq $tag })
if ($existing.Count -gt 0) {
    if ($existing.Count -ne 1 -or -not $existing[0].draft) { throw 'Release already published; refusing asset replacement.' }
    & gh release edit $tag --repo $repo --title 'OptiScaler Aurora v1.1' --notes-file docs/RELEASE_NOTES_AURORA_V1_1.md
    if ($LASTEXITCODE) { throw 'Draft notes update failed.' }
} else {
    & gh release create $tag --repo $repo --verify-tag --draft --title 'OptiScaler Aurora v1.1' --notes-file docs/RELEASE_NOTES_AURORA_V1_1.md
    if ($LASTEXITCODE) { throw 'Draft release creation failed.' }
}
& gh release upload $tag $Archive 'SHA256SUMS.txt' --repo $repo --clobber
if ($LASTEXITCODE) { throw 'Release upload failed; draft retained.' }
$assetsJson = & gh release view $tag --repo $repo --json assets
if ($LASTEXITCODE) { throw 'Cannot verify uploaded assets.' }
$assets = ($assetsJson | ConvertFrom-Json).assets
$uploaded = @($assets | Where-Object { $_.name -eq $assetName })
if ($uploaded.Count -ne 1 -or $uploaded[0].size -ne (Get-Item -LiteralPath $Archive).Length) {
    throw 'Uploaded archive size mismatch; draft retained.'
}
if (@($assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' }).Count -ne 1) {
    throw 'Checksum asset missing; draft retained.'
}
& gh release edit $tag --repo $repo --draft=false --latest
if ($LASTEXITCODE) { throw 'Final publication failed; check draft state.' }
Write-Output "Published $tag at $head with SHA256 $hash"
