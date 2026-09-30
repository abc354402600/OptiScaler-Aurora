param(
    [ValidateSet("Install","Check","Restore")]
    [string]$Mode = "Check",
    [string]$InstallDir = $PSScriptRoot,
    [switch]$Rescan
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Info([string]$Text)  { Write-Host "[INFO]  $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)    { Write-Host "[OK]    $Text" -ForegroundColor Green }
function Write-Fix([string]$Text)   { Write-Host "[FIXED] $Text" -ForegroundColor Yellow }
function Write-Warn2([string]$Text) { Write-Host "[WARN]  $Text" -ForegroundColor Yellow }
function Write-Fail([string]$Text)  { Write-Host "[FAIL]  $Text" -ForegroundColor Red }

function Get-FileHashSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }
    catch { return "" }
}

function Get-FileVersionSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return "" }
    try {
        $v = (Get-Item -LiteralPath $Path).VersionInfo.FileVersion
        if ($null -eq $v) { return "" }
        return $v.Trim()
    } catch { return "" }
}

# Compare four numeric components; display labels and string order are not versions.
function Get-RuntimeVersion([string]$Path) {
    $raw = Get-FileVersionSafe $Path
    if ($raw -notmatch '^\s*(\d+)[.,]\s*(\d+)[.,]\s*(\d+)(?:[.,]\s*(\d+))?\s*$') { return $null }
    try {
        $revision = if ($Matches[4]) { [int]$Matches[4] } else { 0 }
        $version = [version]::new([int]$Matches[1], [int]$Matches[2], [int]$Matches[3], $revision)
        if ($version.Major -eq 0) { return $null }
        return $version
    } catch { return $null }
}

function Get-RuntimePreserveReason([string]$TargetPath) {
    $name = [IO.Path]::GetFileName($TargetPath).ToLowerInvariant()
    $targets = @($TargetPath)
    if ($name.StartsWith('sl.')) {
        # Keep the whole local Streamline set together if any member is newer/unknown.
        $targets = @(Get-ChildItem -LiteralPath ([IO.Path]::GetDirectoryName($TargetPath)) -Filter 'sl.*.dll' -File | ForEach-Object { $_.FullName })
    }
    foreach ($target in $targets) {
        $key = [IO.Path]::GetFileName($target).ToLowerInvariant()
        if (-not $Sources.ContainsKey($key)) { return 'Unknown' }
        $current = Get-RuntimeVersion $target
        $bundled = Get-RuntimeVersion $Sources[$key]
        if ($null -eq $current -or $null -eq $bundled) { return 'Unknown' }
        if ($current -gt $bundled) { return 'Newer' }
    }
    return ''
}

function Get-StreamlineMajorVersion([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 0 }

    $name = [System.IO.Path]::GetFileName($Path).ToLowerInvariant()

    # Only inspect Streamline DLLs.
    # 只检查 Streamline DLL。
    if (-not ($name.StartsWith("sl.") -and $name.EndsWith(".dll"))) {
        return 0
    }

    try {
        $info = (Get-Item -LiteralPath $Path).VersionInfo

        # Prefer Windows' numeric version fields.
        # 优先使用 Windows 提供的数字主版本字段，避免受到本地化版本字符串格式影响。
        foreach ($major in @($info.FileMajorPart, $info.ProductMajorPart)) {
            if ($major -eq 1 -or $major -eq 2) {
                return [int]$major
            }
        }

        # Fallback for DLLs whose numeric version metadata is incomplete.
        # 如果数字版本字段不可用，再从 FileVersion / ProductVersion 文本中识别。
        foreach ($rawVersion in @($info.FileVersion, $info.ProductVersion)) {
            if ([string]::IsNullOrWhiteSpace($rawVersion)) { continue }

            # Accept both 1.5.6.0 and localized forms such as 2,14,0,0.
            # 同时兼容点号和逗号分隔的版本号。
            $match = [regex]::Match(
                $rawVersion,
                '(?<!\d)([12])(?:[.,]\s*\d+)+'
            )

            if ($match.Success) {
                $major = 0

                if ([int]::TryParse($match.Groups[1].Value, [ref]$major)) {
                    return $major
                }
            }
        }
    }
    catch {
        return 0
    }

    # 0 = unknown / 无法判断
    return 0
}

function Get-StringSha256([string]$Text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text.ToLowerInvariant())
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace "-", "").Substring(0, 20)
    } finally {
        $sha.Dispose()
    }
}

function Normalize-FullPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    $clean = $Path.Trim().Trim('"')
    return [System.IO.Path]::GetFullPath($clean).TrimEnd([char]'\')
}

$InstallDir = Normalize-FullPath $InstallDir
$OptiDir = Join-Path $InstallDir "OptiScaler"
$StreamlineDir = Join-Path $OptiDir "streamline"
$StateDir = Join-Path $OptiDir "RuntimeSync"
$BackupRoot = Join-Path $StateDir "backup"
$ManifestPath = Join-Path $StateDir "manifest.json"

if (-not (Test-Path -LiteralPath $OptiDir -PathType Container)) {
    Write-Fail "OptiScaler folder was not found: $OptiDir"
    exit 2
}

# Only files that ship in our validated runtime bundle are candidates.
# nvngx_dlssnr.dll is intentionally NOT touched.
$Sources = @{}
foreach ($name in @("nvngx_dlss.dll", "nvngx_dlssd.dll", "nvngx_dlssg.dll")) {
    $p = Join-Path $OptiDir $name
    if (Test-Path -LiteralPath $p -PathType Leaf) { $Sources[$name] = $p }
}
if (Test-Path -LiteralPath $StreamlineDir -PathType Container) {
    Get-ChildItem -LiteralPath $StreamlineDir -File -Filter "sl.*.dll" -ErrorAction SilentlyContinue |
        ForEach-Object { $Sources[$_.Name.ToLowerInvariant()] = $_.FullName }
}

if ($Sources.Count -eq 0) {
    Write-Fail "No bundled DLSS / Streamline runtime files were found under OptiScaler."
    exit 3
}

function Resolve-ScanRoot([string]$StartDir) {
    $cur = New-Object System.IO.DirectoryInfo($StartDir)
    for ($i = 0; $i -lt 6 -and $null -ne $cur; $i++) {
        $engine = Join-Path $cur.FullName "Engine"
        if (Test-Path -LiteralPath $engine -PathType Container) {
            return $cur.FullName
        }
        if ($null -eq $cur.Parent) { break }
        # Never deliberately climb into a Steam/common-style shared game container.
        if ($cur.Parent.Name -ieq "common") { break }
        $cur = $cur.Parent
    }
    return $StartDir
}

$ScanRoot = Normalize-FullPath (Resolve-ScanRoot $InstallDir)

function Is-SkippedDirectory([System.IO.DirectoryInfo]$Dir) {
    $n = $Dir.Name.ToLowerInvariant()
    if ($n -eq "optiscaler") { return $true }
    if ($n -like "_storage*") { return $true }
    if ($n.StartsWith(".")) { return $true }

    $skip = @(
        "content","paks","saved","logs","movies","sounds","music","videos",
        "localization","shadercache","derivedcache","cache","textures","maps",
        "levels","audio","data","assets","mods","screenshots","redist",
        "_commonredist","crashreport","crashreports"
    )
    return $skip -contains $n
}

function Add-TargetIfMatch(
    [string]$FilePath,
    [System.Collections.Generic.HashSet[string]]$Found
) {
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { return }
    $name = [System.IO.Path]::GetFileName($FilePath).ToLowerInvariant()
    if (-not $Sources.ContainsKey($name)) { return }

    $full = Normalize-FullPath $FilePath
    # Never sync the package's own runtime copies.
    if ($full.StartsWith($OptiDir + "\", [System.StringComparison]::OrdinalIgnoreCase)) { return }
    [void]$Found.Add($full)
}

function Find-GameRuntimeTargets([string]$Root) {
    $found = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    # 1) Files beside the game executable / setup.
    foreach ($name in $Sources.Keys) {
        Add-TargetIfMatch (Join-Path $InstallDir $name) $found
    }

    # 2) Common Unreal Engine NVIDIA runtime locations: hit these before walking.
    $knownDirs = @(
        "Engine\Plugins\Runtime\Nvidia\DLSS\Binaries\ThirdParty\Win64",
        "Engine\Plugins\Runtime\Nvidia\StreamlineCore\Binaries\ThirdParty\Win64",
        "Engine\Plugins\Runtime\Nvidia\Streamline\Binaries\ThirdParty\Win64"
    )
    foreach ($rel in $knownDirs) {
        $d = Join-Path $Root $rel
        if (Test-Path -LiteralPath $d -PathType Container) {
            foreach ($name in $Sources.Keys) {
                Add-TargetIfMatch (Join-Path $d $name) $found
            }
        }
    }

    # 3) Bounded walk for project plugins, RE Engine layouts, CryEngine layouts, etc.
    $queue = New-Object 'System.Collections.Generic.Queue[object]'
    $queue.Enqueue([pscustomobject]@{ Path = $Root; Depth = 0 })
    $maxDepth = 9
    $maxDirs = 7000
    $seenDirs = 0
    $deadline = [DateTime]::UtcNow.AddSeconds(10)

    while ($queue.Count -gt 0) {
        if ($seenDirs -ge $maxDirs -or [DateTime]::UtcNow -gt $deadline) {
            Write-Warn2 "Runtime scan budget reached. Existing matches will still be used."
            break
        }

        $item = $queue.Dequeue()
        $dirPath = [string]$item.Path
        $depth = [int]$item.Depth
        $seenDirs++

        try {
            $items = Get-ChildItem -LiteralPath $dirPath -Force -ErrorAction Stop
        } catch {
            continue
        }

        foreach ($child in $items) {
            if ($child.PSIsContainer) {
                if ($depth -lt $maxDepth -and -not (Is-SkippedDirectory $child)) {
                    $queue.Enqueue([pscustomobject]@{ Path = $child.FullName; Depth = $depth + 1 })
                }
            } else {
                $lname = $child.Name.ToLowerInvariant()
                if ($Sources.ContainsKey($lname)) {
                    Add-TargetIfMatch $child.FullName $found
                }
            }
        }
    }

    return @($found)
}

function Load-Manifest {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { return $null }
    try {
        return (Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        Write-Warn2 "Manifest is unreadable; a new one will be created."
        return $null
    }
}

function Save-Manifest($Entries) {
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    $obj = [pscustomobject]@{
        SchemaVersion = 1
        InstallDir = $InstallDir
        ScanRoot = $ScanRoot
        UpdatedAt = (Get-Date).ToString("o")
        Entries = @($Entries)
    }
    $json = $obj | ConvertTo-Json -Depth 7
    [System.IO.File]::WriteAllText($ManifestPath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Find-Entry($Entries, [string]$TargetPath) {
    return @($Entries | Where-Object { $_.TargetPath -ieq $TargetPath }) | Select-Object -First 1
}

function Save-TargetBackup([string]$TargetPath, [string]$ExpectedHash) {
    $id = Get-StringSha256 $TargetPath
    $backupDir = Join-Path $BackupRoot $id
    New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
    $backupPath = Join-Path $backupDir ([System.IO.Path]::GetFileName($TargetPath))
    $tempPath = $backupPath + ".tmp"

    try {
        Copy-Item -LiteralPath $TargetPath -Destination $tempPath -Force
        $backupHash = Get-FileHashSafe $tempPath
        if ([string]::IsNullOrWhiteSpace($backupHash) -or $backupHash -ne $ExpectedHash) {
            throw "Backup verification failed: $TargetPath"
        }
        Move-Item -LiteralPath $tempPath -Destination $backupPath -Force
    } finally {
        if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }

    return $backupPath
}

function Sync-One($Entries, [string]$TargetPath, [bool]$AllowBackup) {
    $name = [System.IO.Path]::GetFileName($TargetPath).ToLowerInvariant()
    if (-not $Sources.ContainsKey($name)) {
        Write-Warn2 "No bundled source for $name"
        return [pscustomobject]@{ Entries=$Entries; Status="Skip" }
    }
	    # Recover legacy Streamline 1.x files that an older Aurora Runtime Sync
    # may already have replaced with the bundled Streamline 2.x runtime.
    # 如果旧版 Aurora 已经把游戏原生 SL1 替换成 SL2，则优先从已验证备份自动恢复。
    if ($name.StartsWith("sl.") -and $name.EndsWith(".dll") -and
        (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {

        $existingEntry = Find-Entry $Entries $TargetPath

        if ($null -ne $existingEntry) {
            $backupPath = [string]$existingEntry.BackupPath

            if (-not [string]::IsNullOrWhiteSpace($backupPath) -and
                (Test-Path -LiteralPath $backupPath -PathType Leaf)) {

                $backupMajor = Get-StreamlineMajorVersion $backupPath

                if ($backupMajor -eq 1) {
                    $backupHash = Get-FileHashSafe $backupPath
                    $expectedOriginalHash = [string]$existingEntry.OriginalHash
                    $currentHashEarly = Get-FileHashSafe $TargetPath
                    $previousDeployedHash = [string]$existingEntry.DeployedHash
                    $currentMajorEarly = Get-StreamlineMajorVersion $TargetPath

                    # Never restore from an unverified backup.
                    # 未通过哈希校验的备份绝不自动恢复。
                    if ([string]::IsNullOrWhiteSpace($backupHash) -or
                        (-not [string]::IsNullOrWhiteSpace($expectedOriginalHash) -and
                         $backupHash -ne $expectedOriginalHash)) {

                        Write-Fail "Legacy Streamline backup verification failed: $backupPath"
                        Write-Fail "旧版 Streamline 备份校验失败，未修改游戏文件。"

                        return [pscustomobject]@{
                            Entries = $Entries
                            Status  = "Fail"
                        }
                    }

                    # The launcher or Steam may already have restored SL1 itself.
                    # If so, remove the stale Aurora management entry.
                    # 如果游戏/启动器已经自行恢复 SL1，只清理旧管理记录，不再修改 DLL。
                    if ($currentMajorEarly -eq 1) {
                        Write-Info "Game-native Streamline 1.x is already restored: $name"
                        Write-Info "检测到游戏原生 Streamline 1.x 已恢复，清理旧 Runtime Sync 记录。"

                        $Entries = @(
                            $Entries | Where-Object {
                                ([string]$_.TargetPath) -ine $TargetPath
                            }
                        )
                    }
                    elseif (-not [string]::IsNullOrWhiteSpace($previousDeployedHash) -and
                            $currentHashEarly -eq $previousDeployedHash) {

                        try {
                            Copy-Item -LiteralPath $backupPath -Destination $TargetPath -Force

                            $afterHash = Get-FileHashSafe $TargetPath
                            if ($afterHash -ne $backupHash) {
                                throw "Restored file hash does not match the verified backup."
                            }

                            $Entries = @(
                                $Entries | Where-Object {
                                    ([string]$_.TargetPath) -ine $TargetPath
                                }
                            )

                            Write-Fix "Restored game-native Streamline 1.x: $name"
                            Write-Fix "已自动恢复游戏原生 Streamline 1.x：$name"

                            return [pscustomobject]@{
                                Entries = $Entries
                                Status  = "Fixed"
                            }
                        }
                        catch {
                            Write-Fail "Could not restore legacy Streamline backup: $TargetPath"
                            Write-Fail "旧版 Streamline 自动恢复失败，目标文件保持现状。"

                            return [pscustomobject]@{
                                Entries = $Entries
                                Status  = "Fail"
                            }
                        }
                    }
                    else {
                        # The managed target changed after Aurora installed it.
                        # Do not overwrite an unknown user/game state.
                        # 当前文件已被其他程序或用户修改，不擅自覆盖。
                        Write-Warn2 "Legacy SL1 backup exists, but the current target no longer matches Aurora's deployed copy."
                        Write-Warn2 "Keeping the current file untouched for safety."
                        Write-Warn2 "存在 SL1 原版备份，但当前文件已发生变化；为安全起见不自动覆盖。"

                        return [pscustomobject]@{
                            Entries = $Entries
                            Status  = "LegacySL1"
                        }
                    }
                }
            }
        }
    }
    # Legacy Streamline 1.x is ABI-incompatible with the bundled Streamline 2.x runtime.
    # Never replace a game-native SL1 DLL with Aurora's SL2 runtime.
    # 旧版 Streamline 1.x 与 Aurora 集成的 Streamline 2.x 并非普通的小版本升级，
    # 检测到游戏原生 SL1 时必须保留游戏自己的 DLL。
    if ($name.StartsWith("sl.") -and $name.EndsWith(".dll")) {
        $slMajor = Get-StreamlineMajorVersion $TargetPath
        if ($slMajor -eq 1) {
            $version = Get-FileVersionSafe $TargetPath
            $label = if ($version) { "$name [$version]" } else { $name }
            Write-Warn2 "Legacy Streamline 1.x detected: $label"
            Write-Warn2 "Keeping the game-native Streamline runtime unchanged."
            Write-Warn2 "检测到 Streamline 1.x：保留游戏原生运行库，不进行替换。"
            return [pscustomobject]@{
                Entries = $Entries
                Status  = "LegacySL1"
            }
        }
		        elseif ($slMajor -eq 0) {
            $version = Get-FileVersionSafe $TargetPath
            $label = if ($version) { "$name [$version]" } else { $name }

            Write-Warn2 "Unknown Streamline generation: $label"
            Write-Warn2 "Keeping the game-native Streamline runtime unchanged for safety."
            Write-Warn2 "无法确认 Streamline 版本代际：为避免兼容性问题，保留游戏原生运行库。"

            return [pscustomobject]@{
                Entries = $Entries
                Status  = "UnknownSL"
            }
        }
    }
    $source = $Sources[$name]
    $sourceHash = Get-FileHashSafe $source
    $sourceVer = Get-FileVersionSafe $source

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) {
        Write-Warn2 "Missing target, left untouched: $TargetPath"
        return [pscustomobject]@{ Entries=$Entries; Status="Missing" }
    }

    $currentHash = Get-FileHashSafe $TargetPath
    $currentVer = Get-FileVersionSafe $TargetPath
    $preserve = Get-RuntimePreserveReason $TargetPath
    if ($preserve) {
        Write-Warn2 "保留游戏原有 Runtime（版本较新或无法安全比较），不降级、不混换 Streamline 组件：$TargetPath"
        return [pscustomobject]@{ Entries=$Entries; Status='Preserved' }
    }
    $entry = Find-Entry $Entries $TargetPath

    if ($null -eq $entry) {
        $backupPath = ""
        if ($AllowBackup -and $currentHash -ne $sourceHash) {
            try {
                $backupPath = Save-TargetBackup $TargetPath $currentHash
            } catch {
                Write-Fail "Could not create a verified backup; target left untouched: $TargetPath"
                return [pscustomobject]@{ Entries=$Entries; Status="Fail" }
            }
        }

        $entry = [pscustomobject]@{
            TargetPath = $TargetPath
            SourceName = $name
            BackupPath = $backupPath
            OriginalHash = $currentHash
            OriginalVersion = $currentVer
            DeployedHash = $sourceHash
            DeployedVersion = $sourceVer
        }
        $Entries = @($Entries) + $entry
    } else {
        $previousDeployedHash = [string]$entry.DeployedHash
        $currentIsPreviousAurora = (-not [string]::IsNullOrWhiteSpace($previousDeployedHash)) -and ($currentHash -eq $previousDeployedHash)

        # If the launcher/game changed a managed file after Aurora was installed,
        # preserve that newer game-owned state before repairing it again.
        if ($AllowBackup -and $currentHash -ne $sourceHash -and -not $currentIsPreviousAurora) {
            try {
                $entry.BackupPath = Save-TargetBackup $TargetPath $currentHash
                $entry.OriginalHash = $currentHash
                $entry.OriginalVersion = $currentVer
                Write-Info "Refreshed restore backup for $name"
            } catch {
                Write-Fail "Could not refresh the restore backup; target left untouched: $TargetPath"
                return [pscustomobject]@{ Entries=$Entries; Status="Fail" }
            }
        }

        # If the original game file happened to equal Aurora's previous runtime, there
        # was no backup to create at first install. Preserve it before a future Aurora
        # runtime upgrade changes the deployed hash.
        if ($AllowBackup -and $currentHash -ne $sourceHash -and $currentIsPreviousAurora -and
            [string]::IsNullOrWhiteSpace([string]$entry.BackupPath) -and
            [string]$entry.OriginalHash -eq $previousDeployedHash) {
            try {
                $entry.BackupPath = Save-TargetBackup $TargetPath $currentHash
            } catch {
                Write-Fail "Could not preserve the previous runtime before upgrade; target left untouched: $TargetPath"
                return [pscustomobject]@{ Entries=$Entries; Status="Fail" }
            }
        }

        $entry.DeployedHash = $sourceHash
        $entry.DeployedVersion = $sourceVer
        $entry.SourceName = $name
    }

    if ($currentHash -eq $sourceHash) {
        $label = $name
        if ($sourceVer) { $label += " [$sourceVer]" }
        Write-Ok $label
        return [pscustomobject]@{ Entries=$Entries; Status="OK" }
    }

    try {
        Copy-Item -LiteralPath $source -Destination $TargetPath -Force
        $afterHash = Get-FileHashSafe $TargetPath
        if ($afterHash -ne $sourceHash) {
            Write-Fail "Verification failed after replacing: $TargetPath"
            return [pscustomobject]@{ Entries=$Entries; Status="Fail" }
        }

        $from = if ($currentVer) { $currentVer } else { "different build" }
        $to = if ($sourceVer) { $sourceVer } else { "bundled build" }
        Write-Fix "$name : $from -> $to"
        return [pscustomobject]@{ Entries=$Entries; Status="Fixed" }
    } catch {
        Write-Fail "$name could not be replaced. Close the game first. $($_.Exception.Message)"
        return [pscustomobject]@{ Entries=$Entries; Status="Fail" }
    }
}

function Restore-All($Manifest) {
    if ($null -eq $Manifest -or @($Manifest.Entries).Count -eq 0) {
        Write-Info "No managed game runtime files were recorded."
        return 0
    }

    $restored = 0
    $kept = 0
    $failed = 0
    foreach ($entry in @($Manifest.Entries)) {
        $target = [string]$entry.TargetPath
        $backup = [string]$entry.BackupPath
        if ([string]::IsNullOrWhiteSpace($backup) -or -not (Test-Path -LiteralPath $backup -PathType Leaf)) {
            $kept++
            continue
        }

        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            Write-Warn2 "Target is gone; not restoring an old game file: $target"
            $kept++
            continue
        }

        $backupHash = Get-FileHashSafe $backup
        $expectedBackupHash = [string]$entry.OriginalHash
        if ([string]::IsNullOrWhiteSpace($backupHash) -or
            (-not [string]::IsNullOrWhiteSpace($expectedBackupHash) -and $backupHash -ne $expectedBackupHash)) {
            Write-Fail "Backup verification failed; target left untouched: $target"
            $failed++
            continue
        }

        $currentHash = Get-FileHashSafe $target
        if ($currentHash -ne [string]$entry.DeployedHash) {
            Write-Warn2 "Game/launcher changed this file after install; leaving it untouched: $target"
            $kept++
            continue
        }

        try {
            Copy-Item -LiteralPath $backup -Destination $target -Force
            Write-Ok "Restored $([System.IO.Path]::GetFileName($target))"
            $restored++
        } catch {
            Write-Fail "Could not restore: $target"
            $failed++
        }
    }

    Write-Host ""
    Write-Info "Restore complete. Restored: $restored  Left untouched: $kept  Failed: $failed"
    return $failed
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor DarkGray
Write-Host " OptiScaler Aurora DLSS / Streamline Runtime Sync v1.3 / 运行库同步 v1.3" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor DarkGray
Write-Info "Install folder: $InstallDir"
Write-Info "Scan root:      $ScanRoot"
Write-Host ""

$manifest = Load-Manifest

if ($Mode -eq "Restore") {
    $restoreFailed = Restore-All $manifest
    if ([int]$restoreFailed -gt 0) { exit 5 }
    exit 0
}

$entries = @()
if ($null -ne $manifest) { $entries = @($manifest.Entries) }

$targets = @()
$useFastCheck = ($Mode -eq "Check" -and -not $Rescan -and $entries.Count -gt 0)

if ($useFastCheck) {
    Write-Info "Using saved manifest for a fast self-check."
    $targets = @($entries | ForEach-Object { [string]$_.TargetPath } | Sort-Object -Unique)
} else {
    Write-Info "Scanning this game for its own DLSS / Streamline runtime files..."
    $targets = @(Find-GameRuntimeTargets $ScanRoot | Sort-Object -Unique)
}

if ($targets.Count -eq 0) {
    Write-Warn2 "No game-owned matching runtime files were found."
    Write-Info "Nothing was changed."
    exit 0
}

Write-Info "Targets: $($targets.Count)"
Write-Host ""

$ok = 0
$fixed = 0
$failed = 0
$missing = 0
$legacySL1 = 0
$unknownSL = 0
$preserved = 0

foreach ($target in $targets) {
    $r = Sync-One $entries $target $true
    $entries = @($r.Entries)
    switch ($r.Status) {
    "OK"        { $ok++ }
    "Fixed"     { $fixed++ }
    "Fail"      { $failed++ }
    "Missing"   { $missing++ }
    "LegacySL1" { $legacySL1++ }
    "UnknownSL" { $unknownSL++ }
    "Preserved" { $preserved++ }
	}
}

Save-Manifest $entries

Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
Write-Info "Checked: $($targets.Count)  Already correct: $ok  Repaired: $fixed  Failed: $failed  Missing: $missing"
if ($legacySL1 -gt 0) {
    Write-Ok "Protected legacy Streamline 1.x files: $legacySL1"
}
if ($unknownSL -gt 0) {
    Write-Warn2 "Protected Streamline files with unknown generation: $unknownSL"
}
if ($failed -eq 0 -and $preserved -gt 0) {
    Write-Warn2 "已保留 $preserved 个游戏 Runtime；未降级，保留版本的 Aurora 兼容性尚待确认。"
} elseif ($failed -eq 0) {
    Write-Ok "Runtime set is ready."
    Write-Host "        If this game uses a launcher, you can now click Start Game." -ForegroundColor Green
} else {
    Write-Warn2 "Some files could not be repaired. Close the game and retry."
}
Write-Host ""

if ($failed -gt 0) { exit 4 }
exit 0
