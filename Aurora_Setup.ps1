param(
    [ValidateSet('Menu','Install','Check','Repair','Restore','Remove')][string]$Action='Menu',
    [string]$PackageDir=$PSScriptRoot, [string]$InstallDir=$PSScriptRoot,
    [string]$GameRoot, [string]$GameExe,
    [ValidateSet('dxgi.dll','winmm.dll','version.dll','dbghelp.dll','d3d12.dll','wininet.dll','winhttp.dll','OptiScaler.asi')][string]$Proxy,
    [switch]$NonInteractive
)
. (Join-Path $PSScriptRoot 'Aurora_Common.ps1')
. (Join-Path $PSScriptRoot 'Aurora_Installer.ps1')
$exitCode=0; $report=Join-Path ([IO.Path]::GetTempPath()) ('Aurora-RC3-'+[Guid]::NewGuid().ToString('N')+'.json')
try {
    $PackageDir=Get-AuroraPath $PackageDir; $InstallDir=Get-AuroraPath $InstallDir
    Write-Host "`n  Aurora 安装器 RC3`n" -ForegroundColor Cyan
    Write-Host '  正在自动检测游戏…'
    if (-not $GameRoot -and ((Test-Path -LiteralPath (Join-Path $InstallDir 'OptiScaler\AuroraSetup\installation.json')) -or (Test-Path -LiteralPath (Get-AuroraIndexPath $InstallDir)))) {
        $GameRoot=Resolve-AuroraDeploymentRoot $InstallDir
    }
    if (-not $GameRoot) {
        $roots=@(Find-AuroraGames @($InstallDir,$PackageDir))
        if ($roots.Count -eq 1) { $GameRoot=$roots[0] }
        elseif ($roots.Count -gt 1) {
            if ($NonInteractive) { throw '检测到多个游戏，请通过 GameRoot 指定本次游戏。' }
            $n=Read-AuroraChoice '检测到多个游戏，请选择要安装的游戏' ($roots+@('取消'))
            if ($n -gt $roots.Count) { exit 0 }; $GameRoot=$roots[$n-1]
        } else {
            if ($NonInteractive) { throw '未能自动定位游戏，请通过 GameRoot 指定游戏目录。' }
            $inputPath=Read-Host '  未自动找到游戏，请粘贴游戏目录或 EXE 路径（直接回车退出）'
            if (-not $inputPath) { exit 0 }; $GameRoot=Resolve-AuroraDeploymentRoot $inputPath
        }
    }
    $GameRoot=Get-AuroraPath $GameRoot; Assert-AuroraGameRoot $GameRoot
    $index=Open-AuroraIndex $GameRoot
    if ($Action -in @('Menu','Install','Repair')) {
        $scan=Get-AuroraScan $GameRoot
        if (-not $scan.Complete -and $Action -ne 'Menu') { throw '游戏目录未能完整读取，已停止安装。请确认目录权限，并避免目录联接。' }
        $candidates=@(Get-AuroraDeploymentCandidates $scan)
        if (-not $candidates.Count -and $Action -ne 'Menu') { throw '未发现安全的 x64 游戏入口。请确认完整游戏目录；与 x64 工具共用目录的入口不会自动注入。' }
        if ($GameExe -and -not @($candidates | Where-Object { $_.Path -ieq (Get-AuroraPath $GameExe) }).Count) { throw '指定 EXE 未通过安全筛选。' }
        Write-Host ('  ✓ 已检测到游戏：'+[IO.Path]::GetFileName($GameRoot)) -ForegroundColor Green
        Write-Host ('  ✓ 将覆盖 '+@($candidates | Group-Object Directory).Count+' 个游戏入口目录') -ForegroundColor Green
        foreach ($c in @($candidates | Select-Object -First 3)) { Write-Host ('    '+$c.Path.Substring($GameRoot.Length).TrimStart('\')) }
        if ($candidates.Count -gt 3) { Write-Host '    其余入口见详细报告。' }
        if (-not $scan.Complete -or -not $candidates.Count) { Write-Host '  ! 当前不能安全安装；仍可选择恢复 / 卸载。' -ForegroundColor Yellow }
        Write-Host '  ✓ 自动匹配 Proxy，保留现有配置，替换前备份' -ForegroundColor Green
        Write-Host '  ! SL1 和未知 Runtime 保留；安装后请进游戏核对效果' -ForegroundColor Yellow
        Write-AuroraJson $report ([pscustomobject]@{GameRoot=$GameRoot;Candidates=$candidates;RuntimeGroups=@(Get-AuroraRuntimeGroups $scan $candidates)})
        if (-not $NonInteractive) {
            while ($true) {
                Write-Host "`n  [1 / Enter] 一键安装 / 更新`n  [2] 修复 / 恢复 / 卸载`n  [3] 高级工具与诊断`n  [Q] 退出"
                $choice=Read-Host '  请选择'
                if ($choice -in @('','1')) { $Action='Install'; break }
                if ($choice -ieq 'Q') { exit 0 }
                if ($choice -eq '2') {
                    $n=Read-AuroraChoice '修复 / 恢复 / 卸载' @('修复安装并安全同步 Runtime','恢复游戏原版 Runtime','卸载所有已记录的 Aurora 副本','返回')
                    if ($n -eq 4) { continue }; $Action=@('Repair','Restore','Remove')[$n-1]; break
                }
                if ($choice -eq '3') {
                    $n=Read-AuroraChoice '高级工具与诊断' @('查看完整扫描报告','手动修改 Proxy','只读诊断实际加载情况','返回')
                    if ($n -eq 1) { Get-Content -LiteralPath $report -Raw -Encoding UTF8 | Write-Host }
                    if ($n -eq 2) {
                        $proxies=@('dxgi.dll','winmm.dll','version.dll','dbghelp.dll','d3d12.dll','wininet.dll','winhttp.dll','OptiScaler.asi')
                        Write-Host '  异环默认 winmm.dll；已有第三方 Proxy 时不会覆盖。ASI 需要已有 ASI Loader。' -ForegroundColor Yellow
                        $p=Read-AuroraChoice 'Proxy' ($proxies+@('返回自动策略'))
                        $Proxy=$null; if ($p -le $proxies.Count) { $Proxy=$proxies[$p-1] }
                    }
                    if ($n -eq 3) { $Action='Check'; break }
                }
            }
        } elseif ($Action -eq 'Menu') { $Action='Install' }
    }
    if ($Action -in @('Install','Repair')) {
        Write-Host "`n  正在备份并部署 Aurora…"
        $index=Install-AuroraDeployment $GameRoot $PackageDir $Proxy $report
        Write-Host "`n  ✓ 安装完成，所有候选入口已部署并校验。" -ForegroundColor Green
        Write-Host '  可以启动游戏，按 Insert 核对 Aurora。'
    } elseif ($index -and $Action -in @('Restore','Remove')) {
        $preserved=@(Remove-AuroraDeployment $index $report -RuntimeOnly:($Action -eq 'Restore'))
        Write-Host "`n  ✓ 已恢复可恢复的原版文件。" -ForegroundColor Green
        if ($Action -eq 'Remove') { Write-Host '  ✓ 已清理清单记录且未被修改的 Aurora 副本。' -ForegroundColor Green }
        if ($preserved.Count) { Write-Host ('  ! 保留了 '+$preserved.Count+' 个用户修改文件，备份与详情已保留。') -ForegroundColor Yellow }
    } elseif ($index -and $Action -eq 'Check') {
        foreach ($target in $index.Targets) {
            foreach ($exe in $target.Executables) {
                $log=Join-Path ([IO.Path]::GetTempPath()) ('Aurora-Check-'+[Guid]::NewGuid().ToString('N')+'.log.txt')
                Invoke-AuroraRuntimeTask Check $GameRoot $target.Directory $log $exe
                Write-Host ('  ✓ 诊断报告：'+$log) -ForegroundColor Green
            }
        }
        Save-AuroraInstallReport $index $report
    } else {
        # Existing RC2 installations keep their original recovery path and journals.
        $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Aurora_Setup_Legacy.ps1'),'-Action',$Action,'-InstallDir',$InstallDir,'-GameRoot',$GameRoot,'-NonInteractive')
        if ($GameExe) { $args+=@('-GameExe',$GameExe) }
        & powershell.exe @args 2>&1 | Out-File -LiteralPath ([IO.Path]::ChangeExtension($report,'.txt')) -Encoding utf8 -Append
        if ($LASTEXITCODE) { throw 'RC2 恢复 / 诊断未完成，请查看详情。' }
        Write-Host '  ✓ 操作完成。' -ForegroundColor Green
    }
} catch {
    $exitCode=4
    Write-Host ("`n  ✕ "+$_.Exception.Message) -ForegroundColor Red
    $_ | Out-String | Add-Content -LiteralPath ([IO.Path]::ChangeExtension($report,'.log.txt')) -Encoding UTF8
}
$available=@($report,[IO.Path]::ChangeExtension($report,'.txt'),[IO.Path]::ChangeExtension($report,'.log.txt')) | Where-Object { Test-Path -LiteralPath $_ }
if (@($available).Count) { Write-Host ("`n  详细报告："+@($available)[0]) }
if (-not $NonInteractive) {
    while ((Read-Host '  [D] 查看详情 / [Enter] 退出') -ieq 'D') {
        foreach ($path in @($report,[IO.Path]::ChangeExtension($report,'.txt'),[IO.Path]::ChangeExtension($report,'.log.txt'))) {
            if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw -Encoding UTF8 | Write-Host }
        }
    }
}
exit $exitCode
