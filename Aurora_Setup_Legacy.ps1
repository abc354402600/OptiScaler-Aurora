param(
    [ValidateSet('Check','Repair','Restore','Remove')][string]$Action='Check',
    [string]$PackageDir=$PSScriptRoot, [string]$InstallDir=$PSScriptRoot,
    [string]$GameRoot, [string]$GameExe,
    [ValidateSet('dxgi.dll','winmm.dll','version.dll','dbghelp.dll','d3d12.dll','wininet.dll','winhttp.dll','OptiScaler.asi')][string]$Proxy,
    [switch]$NonInteractive
)
. (Join-Path $PSScriptRoot 'Aurora_Common.ps1')
$opLock=$null
try {
    $PackageDir=Get-AuroraPath $PackageDir; $InstallDir=Get-AuroraPath $InstallDir
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
}
