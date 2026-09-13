param(
    [ValidateSet('Install','Check','Restore')][string]$Mode = 'Check',
    [string]$InstallDir = $PSScriptRoot, [string]$GameRoot, [string]$GameExe,
    [string]$ReportPath, [switch]$Rescan, [switch]$CallerHasLock, [switch]$RC3Safety
)
# Check never repairs. Rescan remains accepted for v1 callers; v2 always inventories.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Aurora_Common.ps1')
$opLock = $null
try {
    $InstallDir = Get-AuroraPath $InstallDir
    $opti = Join-Path $InstallDir 'OptiScaler'
    $manifestPath = Join-Path $opti 'RuntimeSync\manifest.json'
    Assert-AuroraPlainPath $manifestPath
    if (-not $GameRoot -and (Test-Path -LiteralPath $manifestPath)) {
        $saved = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $GameRoot = [string]$saved.ScanRoot
    }
    if (-not $GameRoot) { $GameRoot = Resolve-AuroraGameRoot $InstallDir }
    $GameRoot = Get-AuroraPath $GameRoot; Assert-AuroraGameRoot $GameRoot
    if (-not (Test-AuroraWithin $InstallDir $GameRoot)) { throw '安装目录不在所选游戏目录内。' }
    Assert-AuroraPlainPath $InstallDir
    if ($Mode -ne 'Check') {
        Assert-AuroraGameClosed $GameRoot $GameExe
        if (-not $CallerHasLock) { $opLock = Enter-AuroraLock $GameRoot }
    }
    $journal = Open-AuroraJournal $manifestPath $GameRoot $InstallDir
    $modeLabel=@{Check='只读检查';Install='备份后同步';Restore='恢复原版'}[$Mode]
    Write-Host "`nAurora 运行库同步 v2 / $modeLabel`n游戏目录：$GameRoot`n安装目录：$InstallDir"
    if ($Mode -eq 'Restore') {
        $failures = Restore-AuroraJournal $journal $manifestPath
        if ($failures) { throw "有 $failures 项未恢复；清单和备份已保留，请勿删除 OptiScaler 文件夹。" }
        Write-Host '恢复校验完成，备份仍保留。'; exit 0
    }
    # Recovery must remain available even if the optional diagnostic helper is missing.
    . (Join-Path $PSScriptRoot 'Aurora_Diagnostics.ps1')
    if ($RC3Safety) {
        . (Join-Path $PSScriptRoot 'Aurora_Installer.ps1')
        . (Join-Path $PSScriptRoot 'Aurora_RuntimeCatalog.ps1')
    }
    $scan = Get-AuroraScan $GameRoot
    foreach ($w in $scan.Warnings) { Write-Host "[扫描不完整] $w" -ForegroundColor Yellow }
    $sources = @{}
    foreach ($name in @('nvngx_dlss.dll','nvngx_dlssd.dll','nvngx_dlssg.dll')) {
        $p = Join-Path $opti $name
        if (Test-Path -LiteralPath $p -PathType Leaf) { $sources[$name] = $p }
    }
    $slDir = Join-Path $opti 'streamline'
    if (Test-Path -LiteralPath $slDir) {
        Assert-AuroraPlainPath $slDir
        foreach ($f in @(Get-ChildItem -LiteralPath $slDir -File -Filter 'sl.*.dll')) { $sources[$f.Name.ToLowerInvariant()] = $f.FullName }
    }
    $inventory = @()
    foreach ($f in @($scan.Files | Where-Object { $_.Extension -ieq '.dll' })) {
        $info = Get-AuroraBinary $f.FullName
        $hash = ''; try { $hash = Get-AuroraHash $f.FullName } catch { }
        $inventory += [pscustomobject]@{ Path=$f.FullName; Name=$f.Name.ToLowerInvariant(); Version=$info.Version; Major=$info.Major; Architecture=$info.Architecture; SHA256=$hash; Action='保留'; Reason='未包含对应源文件'; SourceHash=''; SourceVersion='' }
    }
    $sl = @($inventory | Where-Object { $_.Name -like 'sl.*.dll' })
    # Protect the entire native SL set, including DLLs missing from the source bundle.
    $slBlocked = @($sl | Where-Object { $_.Major -ne 2 -or $_.Architecture -ne 'x64' -or -not $_.SHA256 }).Count -gt 0
    $legacyEntries = @()
    foreach ($e in @($journal.Entries)) {
        if ($e.SourceName -like 'sl.*.dll' -and $e.BackupPath -and (Test-Path -LiteralPath $e.BackupPath)) {
            if ((Get-AuroraBinary $e.BackupPath).Major -eq 1) { $legacyEntries += $e; $slBlocked = $true }
        }
    }
    $sourceSlBlocked = $false
    foreach ($name in @($sources.Keys | Where-Object { $_ -like 'sl.*.dll' })) {
        $info = Get-AuroraBinary $sources[$name]
        if ($info.Major -ne 2 -or $info.Architecture -ne 'x64') { $sourceSlBlocked = $true }
        if ($RC3Safety -and (-not $AuroraVerifiedSL2.ContainsKey($name) -or (Get-AuroraHash $sources[$name]) -ne $AuroraVerifiedSL2[$name])) { $sourceSlBlocked = $true }
    }
    foreach ($item in $inventory) {
        if ($RC3Safety -and (Test-AuroraUtilityPath $item.Path.Substring($GameRoot.Length).TrimStart('\') -Runtime)) {
            $item.Reason = '启动器 / 工具 / 反作弊目录的 Runtime 仅记录，不替换'; continue
        }
        if ($item.Name -eq 'nvngx_dlssnr.dll') { $item.Reason = 'DLSSNR 仅记录，不同步、不覆盖'; continue }
        if (-not $sources.ContainsKey($item.Name)) { continue }
        $source = Get-AuroraBinary $sources[$item.Name]; $item.SourceVersion = $source.Version
        if ($item.Architecture -ne 'x64' -or $source.Architecture -ne 'x64' -or
            $item.Major -le 0 -or $source.Major -le 0 -or -not $item.SHA256) {
            $item.Reason = '版本、架构或哈希无法确认；保留原文件'; continue
        }
        if ($item.Name -like 'sl.*.dll' -and ($slBlocked -or $sourceSlBlocked)) {
            $item.Reason = '游戏或源包存在 SL1 / 未知代际，或 RC3 源哈希未经确认；保护整组 Streamline'; continue
        }
        $item.SourceHash = Get-AuroraHash $sources[$item.Name]
        if ($item.SourceHash -eq $item.SHA256) { $item.Reason = '与包内版本相同'; continue }
        $item.Action = '可同步'; $item.Reason = '已识别版本和 x64 架构，执行前备份并校验'
    }
    $candidates=@(Get-AuroraCandidates $scan)
    $observations=@()
    if (-not $GameExe) {
        $direct=@($candidates | Where-Object { $_.Directory -ieq $InstallDir })
        if ($direct.Count -eq 1) {
            $GameExe=$direct[0].Path
            $observations += '未保存游戏选择；仅将安装目录内唯一候选用于本次只读进程观察，未更改安装配置。'
        }
    }
    if ($GameExe) {
        $GameExe=Get-AuroraPath $GameExe
        if (-not (Test-AuroraWithin $GameExe $GameRoot)) { throw '诊断程序不在游戏目录内。' }
    }
    $processEvidence=Get-AuroraProcessEvidence $GameExe
    $loaded=@($processEvidence.Modules)
    $proxies=@(Get-AuroraProxyInventory $InstallDir)
    $findings=@(Get-AuroraDiagnosticFindings -InstallDir $InstallDir -GameRoot $GameRoot -GameExe $GameExe -Candidates $candidates -Inventory $inventory -Proxies $proxies -ProcessEvidence $processEvidence -Entries @($journal.Entries) -ScanComplete $scan.Complete)
    $notes = @(
        '磁盘文件存在或版本一致不等于 Aurora 已加载，也不能证明可用 6X。',
        '本工具不能读取 NVIDIA App 覆盖设置或当前 MFG 倍率；以下是排查建议，不是检测结论。',
        '只有 2X 时：核对 NVIDIA App 的 AI 插帧/帧生成覆盖，尝试交由游戏控制 DLSS，重启后对比。',
        '游戏原生 DLSSG 输入：按游戏教程开启游戏帧生成；OptiFG 输入不能套用同一开关规则。',
        '巫师3：保留 SL1.5.6；游戏原生帧生成关闭，使用 OptiFG (Upscaler) → DLSSG → None (Real DLSSG)，DualFeature=false。'
    )
    $report = [pscustomobject]@{ SchemaVersion=2; DiagnosticVersion='2.1'; Timestamp=[DateTime]::UtcNow.ToString('o'); Mode=$Mode; Phase='PreOperation'; GameRoot=$GameRoot; GameExe=$GameExe; InstallDir=$InstallDir; ScanComplete=$scan.Complete; ScanWarnings=$scan.Warnings; Inventory=$inventory; LoadedModules=$loaded; Processes=@($processEvidence.Processes); Findings=$findings; Observations=$observations; Notes=$notes }
    if ($RC3Safety) {
        $report | Add-Member NoteProperty RuntimeGroups @(Get-AuroraRuntimeGroups $scan @(Get-AuroraDeploymentCandidates $scan))
    }
    $reportText=Format-AuroraDiagnosticText $report
    Write-Host $reportText
    if ($ReportPath) {
        $ReportPath = Get-AuroraPath $ReportPath
        if ([IO.Path]::GetExtension($ReportPath) -ine '.json' -or (Test-AuroraWithin $ReportPath $GameRoot)) { throw '诊断报告请选择游戏目录外的 .json 路径，避免覆盖游戏或恢复记录。' }
        Write-AuroraJson $ReportPath $report; Write-Host "结构化报告已保存：$ReportPath"
        $textPath=[IO.Path]::ChangeExtension($ReportPath,'.txt')
        try {
            Write-AuroraDiagnosticText $textPath $reportText
            Write-Host "中文报告已保存：$textPath"
        } catch { Write-Host "中文报告未另存（文件已存在或路径不可写）；JSON 报告已保留：$($_.Exception.Message)" }
    }
    if ($Mode -eq 'Check') {
        Write-Host '只读检查完成，未替换游戏运行库。需要修复时选择安装/修复操作。'
        if (-not $scan.Complete) { exit 6 }; exit 0
    }
    if (-not $scan.Complete) { throw '扫描不完整，已停止同步。请缩小游戏目录后重试。' }
    if (-not $sources.Count) { throw '缺少包内 DLSS / Streamline 文件；未执行同步。' }
    foreach ($e in $legacyEntries) {
        $current = Get-AuroraHash $e.TargetPath
        if ((Get-AuroraHash $e.BackupPath) -ne $e.OriginalHash) { throw 'SL1 原版备份校验失败。' }
        if ($current -eq $e.OriginalHash) { $e.Status='Restored' }
        elseif ($current -eq $e.DeployedHash) {
            Copy-AuroraAtomic $e.BackupPath $e.TargetPath $current $e.OriginalHash
            $e.Status='Restored'; Write-Host "[SL1 已恢复] $($e.TargetPath)"
        } else { throw '存在 SL1 备份，但当前文件已变化，保留现状。' }
        Write-AuroraJson $manifestPath $journal
    }
    foreach ($item in @($inventory | Where-Object { $_.Action -eq '可同步' })) {
        Install-AuroraFile $journal $manifestPath $sources[$item.Name] $item.Path $item.SourceHash $item.SHA256
    }
    Write-Host '同步完成。SL1、未知版本及 DLSSNR 已保留；请进游戏按 Insert 核对加载和倍率。'
    exit 0
} catch {
    Write-Host "[操作停止] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host '已完成的文件操作记录和原版备份仍保留，可使用恢复操作。'; exit 4
} finally { if ($null -ne $opLock) { $opLock.Dispose() } }
