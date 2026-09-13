param(
    [ValidateSet('Check','Repair','Restore','Remove')][string]$Action='Check',
    [string]$PackageDir=$PSScriptRoot, [string]$InstallDir=$PSScriptRoot,
    [string]$GameRoot, [string]$GameExe,
    [ValidateSet('dxgi.dll','winmm.dll','version.dll','dbghelp.dll','d3d12.dll','wininet.dll','winhttp.dll','OptiScaler.asi')][string]$Proxy,
    [switch]$NonInteractive
)
. (Join-Path $PSScriptRoot 'Aurora_Common.ps1')
$opLock=$null; $stage=$null; $installedNow=$false
try {
    $PackageDir=Get-AuroraPath $PackageDir; $InstallDir=Get-AuroraPath $InstallDir
    if ($Action -eq 'Menu') {
        $n=Read-AuroraChoice 'Aurora 安装与诊断' @('安装 / 更新 Aurora','只读检查运行库和加载情况','备份后修复运行库','恢复游戏原版运行库','卸载本工具记录的 Aurora 文件','退出')
        if ($n -eq 6) { exit 0 }
        $Action=@('Install','Check','Repair','Restore','Remove')[$n-1]
    }
    $metaPath=Join-Path $InstallDir 'OptiScaler\AuroraSetup\installation.json'
    Assert-AuroraPlainPath $metaPath
    if ($Action -ne 'Install' -and (Test-Path -LiteralPath $metaPath)) {
        $meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $GameRoot) { $GameRoot=[string]$meta.GameRoot }
        if (-not $GameExe) { $GameExe=[string]$meta.GameExe }
    }
    if (-not $GameRoot) { $GameRoot=Resolve-AuroraGameRoot $InstallDir }
    $GameRoot=Get-AuroraPath $GameRoot; Assert-AuroraGameRoot $GameRoot
    if (-not (Test-AuroraWithin $InstallDir $GameRoot)) { throw '安装目录超出游戏范围。' }
    $runtime=Join-Path $PSScriptRoot 'runtime_sync.ps1'
    $mode=@{Check='Check';Repair='Install';Restore='Restore';Remove='Restore'}[$Action]
    if (-not $mode) { throw '操作无效。' }
    if ($Action -in @('Repair','Restore','Remove') -and -not $NonInteractive) {
        Write-Host "操作范围：$GameRoot"
        if ((Read-AuroraChoice '请先关闭游戏和启动器的更新任务' @('继续操作','取消')) -eq 2) { exit 0 }
    }
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$runtime,'-Mode',$mode,'-InstallDir',$InstallDir,'-GameRoot',$GameRoot)
    if ($GameExe) { $args += @('-GameExe',$GameExe) }
    if ($Action -eq 'Check') {
        $report=Join-Path ([IO.Path]::GetTempPath()) ('Aurora-Report-'+[Guid]::NewGuid().ToString('N')+'.json')
        $args += @('-ReportPath',$report)
    }
    if ($Action -eq 'Remove') { $opLock=Enter-AuroraLock $GameRoot; $args += '-CallerHasLock' }
    & powershell.exe @args
    if ($LASTEXITCODE -ne 0) { throw '运行库操作未完成，请按上方提示处理，备份已保留。' }
    if ($installedNow -and -not $NonInteractive) {
        $choice=Read-AuroraChoice '文件检查完成，是否同步上方列出的可同步运行库？' @('保持游戏原版运行库，结束安装','先备份，再同步已识别的运行库（SL1 / 未知版本仍保留）')
        if ($choice -eq 2) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runtime -Mode Install -InstallDir $InstallDir -GameRoot $GameRoot -GameExe $GameExe
            if ($LASTEXITCODE -ne 0) { throw '运行库同步未完成，安装文件及恢复记录已保留。' }
        }
    }
    if ($Action -eq 'Remove') {
        $journalPath=Join-Path $InstallDir 'OptiScaler\AuroraSetup\manifest.json'
        if (-not (Test-Path -LiteralPath $journalPath)) { throw '未找到新版安装清单。旧版安装请使用其原卸载器；不会猜测删除文件。' }
        $journal=Open-AuroraJournal $journalPath $GameRoot $InstallDir
        foreach ($e in @($journal.Entries)) {
            if ($e.TargetPath -ieq (Join-Path $InstallDir 'OptiScaler.ini') -and (Test-Path -LiteralPath $e.TargetPath)) {
                $current=Get-AuroraHash $e.TargetPath
                if ($current -ne $e.DeployedHash -and $current -ne $e.OriginalHash) {
                    $e.Status='Preserved'; Write-Host '保留你修改过的 OptiScaler.ini。'
                }
            }
        }
        Assert-AuroraRestoreReady $journal
        Write-AuroraJson $journalPath $journal
        $fails=Restore-AuroraJournal $journal $journalPath
        if ($fails) { throw '部分文件已变化，保留这些文件和备份，请查看上方路径。' }
        Write-Host '已卸载本工具记录且未被修改的文件；原有文件、用户改动和备份保留。'
    }
    exit 0
} catch { Write-Host "[操作停止] $($_.Exception.Message)" -ForegroundColor Red; exit 4 }
finally {
    if ($null -ne $opLock) { $opLock.Dispose() }
    if ($stage -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Force }
}
