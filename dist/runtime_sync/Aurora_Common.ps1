# Shared by Setup and Runtime Sync. Windows PowerShell 5.1 compatible.
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

function Get-AuroraPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw '路径不能为空。' }
    $p = [IO.Path]::GetFullPath($Path.Trim().Trim('"'))
    if ($p -eq [IO.Path]::GetPathRoot($p)) { return $p }
    return $p.TrimEnd('\')
}
function Test-AuroraWithin([string]$Path, [string]$Root) {
    $p = Get-AuroraPath $Path; $r = Get-AuroraPath $Root
    return $p.Equals($r, [StringComparison]::OrdinalIgnoreCase) -or
        $p.StartsWith($r.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
}
function Assert-AuroraPlainPath([string]$Path) {
    $p = Get-AuroraPath $Path
    if ($p.Substring([IO.Path]::GetPathRoot($p).Length).Contains(':')) { throw "不支持备用数据流路径：$p" }
    while ($p) {
        if (Test-Path -LiteralPath $p) {
            if ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "为避免操作其他目录，不跟随链接或目录联接：$p"
            }
        }
        $parent = [IO.Directory]::GetParent($p)
        if ($null -eq $parent) { break }
        $p = $parent.FullName
    }
}
function Assert-AuroraGameRoot([string]$Root) {
    $r = Get-AuroraPath $Root
    if (-not (Test-Path -LiteralPath $r -PathType Container)) { throw "找不到游戏目录：$r" }
    $leaf = [IO.Path]::GetFileName($r)
    if ($r -eq [IO.Path]::GetPathRoot($r) -or $leaf -match '^(common|steamapps|SteamLibrary|Epic Games|XboxGames|Program Files(?: \(x86\))?|Windows|Users|Games|HoYoPlay)$') {
        throw '请选择单个游戏的目录，不要选择磁盘、系统目录或整个游戏库。'
    }
    Assert-AuroraPlainPath $r
}
function Resolve-AuroraGameRoot([string]$InputPath) {
    $p = Get-AuroraPath $InputPath
    if (Test-Path -LiteralPath $p -PathType Leaf) { $p = [IO.Path]::GetDirectoryName($p) }
    Assert-AuroraGameRoot $p
    $cur = [IO.DirectoryInfo]$p
    # Only climb structurally known layouts, never search an arbitrary parent library.
    if ($cur.Name -match '^(NTELauncher|Launcher|Win64|Win64r|WinGDK|x64_dx12)$' -and $cur.Parent) {
        $p = $cur.Parent.FullName; $cur = $cur.Parent
    }
    if ($cur.Name -ieq 'Binaries' -and $cur.Parent) {
        $p = $cur.Parent.FullName; $cur = $cur.Parent
        if ($cur.Parent -and (Test-Path -LiteralPath (Join-Path $cur.Parent.FullName 'Engine') -PathType Container)) {
            $p = $cur.Parent.FullName
        }
    }
    Assert-AuroraGameRoot $p
    return $p
}
function Get-AuroraHash([string]$Path) {
    Assert-AuroraPlainPath $Path
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToUpperInvariant()
}
function Get-AuroraBinary([string]$Path) {
    $arch = 'Unknown'; $version = ''; $major = 0; $original = ''; $errorText = ''
    try {
        Assert-AuroraPlainPath $Path
        $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        try {
            $reader = New-Object IO.BinaryReader($stream)
            if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { throw '不是有效 PE 文件' }
            $stream.Position = 60; $offset = $reader.ReadInt32()
            if ($offset -lt 64 -or $offset -gt $stream.Length - 24) { throw 'PE 头无效' }
            $stream.Position = $offset
            if ($reader.ReadUInt32() -ne 0x4550) { throw 'PE 签名无效' }
            $machine = $reader.ReadUInt16()
            if ($machine -eq 0x8664) { $arch = 'x64' } elseif ($machine -eq 0x14c) { $arch = 'x86' }
        } finally { $stream.Dispose() }
        $v = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
        $version = [string]$v.FileVersion; $original = [string]$v.OriginalFilename
        # Conflicting file/product metadata is unknown, not a guess at SL2.
        $majors = @($v.FileMajorPart, $v.ProductMajorPart | Where-Object { $_ -gt 0 } | Sort-Object -Unique)
        if ($majors.Count -eq 1) { $major = [int]$majors[0] }
        elseif ($majors.Count -eq 0) {
            $textMajors = @(@($v.FileVersion, $v.ProductVersion) | ForEach-Object {
                if ($_ -match '^\s*(\d+)(?:[.,]\s*\d+)+\s*$') { [int]$matches[1] }
            } | Sort-Object -Unique)
            if ($textMajors.Count -eq 1) { $major = $textMajors[0] }
        }
    } catch { $errorText = $_.Exception.Message; $major = 0 }
    [pscustomobject]@{ Path=$Path; Architecture=$arch; Version=$version; Major=$major; OriginalFilename=$original; Error=$errorText }
}
function Get-AuroraScan([string]$Root, [int]$MaxDirectories=12000, [int]$MaxDepth=18, [int]$Seconds=30) {
    Assert-AuroraGameRoot $Root
    $files = New-Object 'Collections.Generic.List[object]'
    $warnings = New-Object 'Collections.Generic.List[string]'
    $queue = New-Object 'Collections.Generic.Queue[object]'
    $queue.Enqueue(@($Root, 0)); $count = 0; $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    while ($queue.Count) {
        if ($count -ge $MaxDirectories -or [DateTime]::UtcNow -gt $deadline) {
            $warnings.Add('扫描达到时间或目录数量上限，请选择更具体的游戏目录。'); break
        }
        $node = $queue.Dequeue(); $count++
        try { $children = @(Get-ChildItem -LiteralPath $node[0] -Force -ErrorAction Stop) }
        catch { $warnings.Add("无法读取目录：$($node[0])"); continue }
        foreach ($child in $children) {
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $warnings.Add("已跳过链接：$($child.FullName)"); continue
            }
            if ($child.PSIsContainer) {
                if ($child.Name -match '^(OptiScaler|\.git|\.svn|_storage.*|AuroraSetup|RuntimeSync)$') { continue }
                if ([int]$node[1] -ge $MaxDepth) { $warnings.Add("已达到深度上限：$($child.FullName)"); continue }
                $queue.Enqueue(@($child.FullName, ([int]$node[1] + 1)))
            } elseif ($child.Extension -ieq '.exe' -or $child.Name -match '^(nvngx_dlss.*|sl\..*)\.dll$') {
                $files.Add($child)
            }
        }
    }
    [pscustomobject]@{ Root=$Root; Files=@($files.ToArray()); Complete=($warnings.Count -eq 0); Warnings=@($warnings.ToArray()) }
}
function Get-AuroraCandidates($Scan) {
    $runtimes = @($Scan.Files | Where-Object { $_.Extension -ieq '.dll' })
    $candidates = @()
    foreach ($f in @($Scan.Files | Where-Object { $_.Extension -ieq '.exe' })) {
        $rel = $f.FullName.Substring($Scan.Root.Length).TrimStart('\')
        if ($rel -match '(?i)(^|\\)(Engine|[^\\]*Launcher[^\\]*|Editor|CrashReport[^\\]*|_CommonRedist)(\\|$)' -or
            $f.BaseName -match '(?i)(launcher|bootstrap|updat(er|e)|crash|unins|setup|reporter|editor|UnityCrashHandler|HYP$)') { continue }
        $pe = Get-AuroraBinary $f.FullName
        if ($pe.Architecture -ne 'x64') { continue }
        $score = 10; $reasons = @('已确认 x64 程序')
        if ($rel -match '(?i)(^|\\)Binaries\\(Win64|Win64r|WinGDK)\\') { $score += 60; $reasons += 'UE Binaries 游戏程序目录' }
        if ($rel -match '(?i)(^|\\)Win64r\\') { $score += 25; $reasons += 'Win64r 候选（仍需核对实际启动版本）' }
        if ($rel -match '(?i)(^|\\)x64_dx12\\') { $score += 30; $reasons += 'DX12 目录' }
        if ($f.BaseName -match '(?i)(shipping|^HTGame$|^wwm$|^ZenlessZoneZero$)') { $score += 20 }
        $near = @($runtimes | Where-Object { $_.DirectoryName -ieq $f.DirectoryName })
        if ($near.Count) { $score += 25; $reasons += '同目录发现 DLSS / Streamline' }
        if ($f.Length -gt 10MB) { $score += 5 }
        $candidates += [pscustomobject]@{ Path=$f.FullName; Directory=$f.DirectoryName; Score=$score; Reasons=($reasons -join '；') }
    }
    return @($candidates | Sort-Object @{Expression='Score';Descending=$true},Path)
}
function Read-AuroraChoice([string]$Title, [string[]]$Options) {
    Write-Host "`n$Title"
    for ($i=0; $i -lt $Options.Count; $i++) { Write-Host "[$($i+1)] $($Options[$i])" }
    while ($true) {
        $value = Read-Host '请输入对应的数字并按 Enter（回车）'
        $n = 0
        if ([int]::TryParse($value, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) {
            Write-Host "已选择：$($Options[$n-1])"; return $n
        }
        Write-Host '输入无效，请输入列表中的数字，然后按 Enter（回车）。' -ForegroundColor Yellow
    }
}
function Write-AuroraJson([string]$Path, $Value) {
    Assert-AuroraPlainPath $Path
    $dir = [IO.Path]::GetDirectoryName($Path)
    [IO.Directory]::CreateDirectory($dir) | Out-Null
    $tmp = Join-Path $dir ([Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($tmp, ($Value | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($tmp, $Path, [NullString]::Value) }
        else { [IO.File]::Move($tmp, $Path) }
    } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }
}
function Enter-AuroraLock([string]$InstallDir) {
    $state = Join-Path $InstallDir 'OptiScaler'
    Assert-AuroraPlainPath $state
    [IO.Directory]::CreateDirectory($state) | Out-Null
    try { return [IO.File]::Open((Join-Path $state 'Aurora.operation.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
    catch { throw '另一个安装或恢复操作正在进行，或游戏目录不可写。请关闭游戏后重试。' }
}
function Assert-AuroraGameClosed([string]$Root, [string]$GameExe='') {
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        $processPath=''
        try { $processPath=[string]$p.Path } catch { }
        if ($processPath -and (Test-AuroraWithin $processPath $Root)) { throw "游戏目录中的程序仍在运行：$processPath；请关闭后重试。" }
        if (-not $processPath -and $GameExe -and $p.ProcessName -ieq [IO.Path]::GetFileNameWithoutExtension($GameExe)) {
            throw '疑似游戏进程仍在运行且无法读取路径。请先关闭游戏。'
        }
    }
}
function Open-AuroraJournal([string]$Path, [string]$Root, [string]$InstallDir) {
    Assert-AuroraPlainPath $Path
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ SchemaVersion=2; InstallDir=$InstallDir; ScanRoot=$Root; Entries=@() }
    }
    try { $j = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "恢复清单损坏，已停止操作；请保留清单和备份：$Path" }
    if ($j.SchemaVersion -notin @(1,2) -or (Get-AuroraPath $j.InstallDir) -ine $InstallDir -or
        (Get-AuroraPath $j.ScanRoot) -ine $Root) { throw '清单版本或游戏目录不匹配，未修改文件。' }
    $seen = @{}
    foreach ($e in @($j.Entries)) {
        $t = Get-AuroraPath $e.TargetPath
        if (-not (Test-AuroraWithin $t $Root) -or $seen.ContainsKey($t) -or
            (Test-AuroraWithin $t ([IO.Path]::GetDirectoryName($Path)))) { throw '清单包含越界、重复或备份区目标。' }
        $seen[$t] = $true; Assert-AuroraPlainPath $t
        if ($e.DeployedHash -notmatch '^[0-9a-fA-F]{64}$' -or $e.OriginalHash -notmatch '^([0-9a-fA-F]{64})?$') { throw '清单哈希缺失或无效。' }
        if ($e.BackupPath) {
            if (-not (Test-AuroraWithin $e.BackupPath (Join-Path ([IO.Path]::GetDirectoryName($Path)) 'backup'))) { throw '备份路径越界。' }
            Assert-AuroraPlainPath $e.BackupPath
            if ($e.OriginalHash -notmatch '^[0-9a-fA-F]{64}$') { throw '备份缺少原始哈希，停止恢复。' }
        }
        if ($j.SchemaVersion -eq 1) {
            $e | Add-Member NoteProperty Created $false
            $e | Add-Member NoteProperty Status 'Applied'
        } elseif ($e.Status -notin @('Pending','Applied','Restored','Preserved') -or $e.Created -isnot [bool]) { throw '清单状态无效。' }
        if (-not $e.PSObject.Properties['BeforeHash']) { $e | Add-Member NoteProperty BeforeHash $e.OriginalHash }
        if ($e.BeforeHash -notmatch '^([0-9a-fA-F]{64})?$') { throw '清单操作前哈希无效。' }
        if ($Path -match '[\\/]RuntimeSync[\\/]manifest\.json$') {
            if ([IO.Path]::GetFileName($t) -notmatch '^(nvngx_dlss(?:d|g)?|sl\.[a-zA-Z0-9_.-]+)\.dll$' -or
                $e.Created -or (Test-AuroraWithin $t (Join-Path $InstallDir 'OptiScaler'))) { throw '运行库清单包含非运行库目标。' }
        }
        if (-not $e.Created -and -not $e.BackupPath -and $e.OriginalHash -ne $e.DeployedHash) { throw '清单缺少必要备份。' }
    }
    $j.SchemaVersion = 2
    return $j
}
function Copy-AuroraAtomic([string]$Source, [string]$Target, [string]$ExpectedCurrent, [string]$ExpectedSource) {
    Assert-AuroraPlainPath $Source; Assert-AuroraPlainPath $Target
    $dir = [IO.Path]::GetDirectoryName($Target); [IO.Directory]::CreateDirectory($dir) | Out-Null
    $tmp = Join-Path $dir ([Guid]::NewGuid().ToString('N') + '.aurora-tmp')
    try {
        [IO.File]::Copy($Source, $tmp, $false)
        if ((Get-AuroraHash $tmp) -ne $ExpectedSource) { throw '源文件在复制期间变化，已取消。' }
        Assert-AuroraPlainPath $Target
        if ($ExpectedCurrent) {
            if (-not (Test-Path -LiteralPath $Target -PathType Leaf) -or (Get-AuroraHash $Target) -ne $ExpectedCurrent) { throw '目标文件已变化，已取消。' }
            [IO.File]::Replace($tmp, $Target, [NullString]::Value)
        } else { [IO.File]::Move($tmp, $Target) }
        if ((Get-AuroraHash $Target) -ne $ExpectedSource) { throw '写入后的 SHA256 校验失败，请使用恢复操作。' }
    } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }
}
function Install-AuroraFile($Journal, [string]$JournalPath, [string]$Source, [string]$Target,
    [string]$ExpectedSourceHash='', [string]$ExpectedCurrentHash='') {
    if (-not (Test-AuroraWithin $Target $Journal.ScanRoot) -or
        (Test-AuroraWithin $Target ([IO.Path]::GetDirectoryName($JournalPath)))) { throw '写入目标越界。' }
    $hash = Get-AuroraHash $Source
    $current = ''; if (Test-Path -LiteralPath $Target -PathType Leaf) { $current = Get-AuroraHash $Target }
    if (($ExpectedSourceHash -and $hash -ne $ExpectedSourceHash) -or ($ExpectedCurrentHash -and $current -ne $ExpectedCurrentHash)) {
        throw '文件在扫描后发生变化，请重新检查。'
    }
    if ($current -eq $hash) { return }
    $entry = @($Journal.Entries | Where-Object { $_.TargetPath -ieq $Target } | Select-Object -First 1)
    if ($entry.Count -and $entry[0].Status -ne 'Restored') {
        $e = $entry[0]
        if ($current -ne $e.DeployedHash -and -not ($e.Status -eq 'Pending' -and $current -eq $e.BeforeHash)) {
            throw "游戏或用户已修改受管理文件，保留现状，请先处理恢复记录：$Target"
        }
        if ($e.BackupPath -and (-not (Test-Path -LiteralPath $e.BackupPath) -or (Get-AuroraHash $e.BackupPath) -ne $e.OriginalHash)) { throw '原版备份缺失或损坏，停止更新。' }
    } else {
        $backup = ''
        if ($current) {
            $backup = Join-Path ([IO.Path]::GetDirectoryName($JournalPath)) ('backup\' + [Guid]::NewGuid().ToString('N') + '\' + [IO.Path]::GetFileName($Target))
            Copy-AuroraAtomic $Target $backup '' $current
        }
        $e = [pscustomobject]@{ TargetPath=$Target; SourceName=[IO.Path]::GetFileName($Source); BackupPath=$backup; OriginalHash=$current; DeployedHash=$hash; BeforeHash=$current; Created=($current -eq ''); Status='Pending' }
        $Journal.Entries = @($Journal.Entries | Where-Object { $_.TargetPath -ine $Target }) + $e
    }
    # Write-ahead journal: a terminated process can be safely restored on the next run.
    $e.BeforeHash = $current; $e.DeployedHash = $hash; $e.Status = 'Pending'
    Write-AuroraJson $JournalPath $Journal
    Copy-AuroraAtomic $Source $Target $current $hash
    $e.Status = 'Applied'; Write-AuroraJson $JournalPath $Journal
    Write-Host "[已校验] $Target"
}
function Restore-AuroraJournal($Journal, [string]$JournalPath) {
    $failed = 0
    foreach ($e in @($Journal.Entries)) {
        if ($e.Status -in @('Restored','Preserved')) { continue }
        try {
            $target = [string]$e.TargetPath
            $current = ''; if (Test-Path -LiteralPath $target -PathType Leaf) { $current = Get-AuroraHash $target }
            if ($current -eq $e.OriginalHash) { $e.Status = 'Restored'; Write-AuroraJson $JournalPath $Journal; continue }
            if ($current -ne $e.DeployedHash -and -not ($e.Status -eq 'Pending' -and $current -eq $e.BeforeHash)) { throw '文件已被游戏更新、用户修改或删除，保留现状和备份。' }
            if ($e.Created) {
                Assert-AuroraPlainPath $target
                Remove-Item -LiteralPath $target -Force
            } else {
                if (-not $e.BackupPath -or (Get-AuroraHash $e.BackupPath) -ne $e.OriginalHash) { throw '原版备份缺失或校验失败。' }
                Copy-AuroraAtomic $e.BackupPath $target $current $e.OriginalHash
            }
            $e.Status = 'Restored'; Write-AuroraJson $JournalPath $Journal
            Write-Host "[已恢复] $target"
        } catch { $failed++; Write-Host "[未恢复] $($e.TargetPath)：$($_.Exception.Message)" -ForegroundColor Yellow }
    }
    return $failed
}
function Assert-AuroraRestoreReady($Journal) {
    # Setup must not remove its own recovery scripts before discovering a conflict.
    foreach ($e in @($Journal.Entries)) {
        if ($e.Status -in @('Restored','Preserved')) { continue }
        $current=''; if (Test-Path -LiteralPath $e.TargetPath) { $current=Get-AuroraHash $e.TargetPath }
        if ($current -eq $e.OriginalHash) { continue }
        if ($current -ne $e.DeployedHash -and -not ($e.Status -eq 'Pending' -and $current -eq $e.BeforeHash)) {
            throw "卸载前检查发现文件变化，尚未删除安装文件：$($e.TargetPath)"
        }
        if (-not $e.Created -and (-not $e.BackupPath -or (Get-AuroraHash $e.BackupPath) -ne $e.OriginalHash)) {
            throw "卸载前备份校验失败：$($e.TargetPath)"
        }
    }
}
