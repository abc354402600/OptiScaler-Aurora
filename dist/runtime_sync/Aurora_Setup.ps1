param(
    [ValidateSet('Menu','Install','Check','Repair','Restore','Remove')][string]$Action='Menu',
    [string]$PackageDir=$PSScriptRoot, [string]$InstallDir=$PSScriptRoot,
    [string]$GameRoot, [string]$GameExe,
    [ValidateSet('dxgi.dll','winmm.dll','version.dll','dbghelp.dll','d3d12.dll','wininet.dll','winhttp.dll','OptiScaler.asi')][string]$Proxy,
    [switch]$NonInteractive
)
. (Join-Path $PSScriptRoot 'Aurora_Common.ps1')
. (Join-Path $PSScriptRoot 'Aurora_Installer.ps1')
$exitCode=0; $session=New-AuroraReportSession; $report=$session.ReportPath
try {
    $PackageDir=Get-AuroraPath $PackageDir; $InstallDir=Get-AuroraPath $InstallDir
    Write-Host "`n  Aurora 安装器 RC3.1 · 入口与恢复修复版 20260915`n" -ForegroundColor Cyan
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
    $index=Open-AuroraIndex $GameRoot -ForNewInstall:($Action -in @('Menu','Install','Repair'))
    $localMeta=Join-Path $InstallDir 'OptiScaler\AuroraSetup\installation.json'
    if (-not $index -and (Test-Path -LiteralPath $localMeta)) {
        $savedMeta=Read-AuroraJson $localMeta
        if ($savedMeta.PSObject.Properties['RC3Manifest']) { throw 'RC3 总清单缺失，不能回退为单入口卸载；请保留文件与备份。' }
    }
    if ($Action -in @('Menu','Install','Repair')) {
        $scan=Get-AuroraScan $GameRoot
        if (-not $scan.Complete -and $Action -ne 'Menu') { throw '游戏目录未能完整读取，已停止安装。请确认目录权限，并避免目录联接。' }
        $candidates=@(Get-AuroraDeploymentCandidates $scan)
        if (-not $candidates.Count -and $Action -ne 'Menu') { throw '未发现安全的 x64 游戏入口。请确认完整游戏目录；与 x64 工具共用目录的入口不会自动注入。' }
        if ($GameExe -and -not @($candidates | Where-Object { $_.Path -ieq (Get-AuroraPath $GameExe) }).Count) { throw '指定 EXE 未通过安全筛选。' }
        Write-Host ('  ✓ 已检测到游戏：'+[IO.Path]::GetFileName($GameRoot)) -ForegroundColor Green
        Write-Host ('  ✓ 将覆盖 '+@($candidates | Group-Object Directory).Count+' 个游戏入口目录') -ForegroundColor Green
        foreach ($c in @($candidates | Select-Object -First 3)) { Write-Host ('    '+$c.Path.Substring($GameRoot.Length).TrimStart('\')+' → '+(Get-AuroraRecommendedProxy @($c) $Proxy)) }
        if ($candidates.Count -gt 3) { Write-Host '    其余入口见详细报告。' }
        if (-not $scan.Complete -or -not $candidates.Count) { Write-Host '  ! 当前不能安全安装；仍可选择恢复 / 卸载。' -ForegroundColor Yellow }
        if ($scan.CandidateRejections.Count) { Write-Host ('  ! 共享目录保护拦截了 '+$scan.CandidateRejections.Count+' 个入口，具体工具见详细报告。') -ForegroundColor Yellow }
        Write-Host '  ✓ 自动匹配 Proxy，保留现有配置，替换前备份' -ForegroundColor Green
        Write-Host '  ! SL1 和未知 Runtime 保留；安装后请进游戏核对效果' -ForegroundColor Yellow
        Write-AuroraJson $report ([pscustomobject]@{GameRoot=$GameRoot;Candidates=$candidates;RejectedCandidates=@($scan.CandidateRejections.ToArray());RuntimeGroups=@(Get-AuroraRuntimeGroups $scan $candidates)})
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
        $confirm=$null
        if (-not $NonInteractive) {
            $confirm={ param($conflicts)
                Write-Host ('  ! 发现 '+$conflicts.Count+' 个未受清单管理的同名文件，可能来自以前解压的包。') -ForegroundColor Yellow
                foreach ($file in @($conflicts | Select-Object -First 3)) { Write-Host ('    '+$file.Path.Substring($GameRoot.Length).TrimStart('\')) }
                if ($conflicts.Count -gt 3) { Write-Host '    其余文件按 D 查看。' }
                Write-Host '  选择备份更新将先保存原文件；以后卸载会恢复它们。现有配置保留。' -ForegroundColor Yellow
                while ($true) {
                    $answer=Read-Host '  [B] 备份上述文件并更新 / [D] 查看全部冲突 / [Enter] 取消'
                    if ($answer -ieq 'B') { return $true }
                    if ($answer -ieq 'D') { foreach ($file in $conflicts) { Write-Host $file.Path }; continue }
                    return $false
                }
            }
        }
        $index=Install-AuroraDeployment $GameRoot $PackageDir $Proxy $report -ConfirmConflicts $confirm
        Write-Host ("`n  ✓ 部署完成，"+$index.Verification.Count+' 个入口的 Proxy 与完整文件自检通过。') -ForegroundColor Green
        $summary=$index.RuntimeSummary
        Write-Host ('  ✓ Runtime：已同步 '+$summary.Synchronized+' 项，已是包内版本 '+$summary.AlreadyCurrent+' 项。') -ForegroundColor Green
        if ($summary.Protected) { Write-Host ('  ! 安全保留 '+$summary.Protected+' 项 Runtime（其中 SL1 '+$summary.SL1Preserved+' 项），原因见详细报告。') -ForegroundColor Yellow }
        Write-Host '  磁盘部署已完成；请启动游戏，按 Insert 核对实际加载。'
    } elseif ($index -and $Action -in @('Restore','Remove')) {
        $preserved=@(Remove-AuroraDeployment $index $report -RuntimeOnly:($Action -eq 'Restore'))
        Write-Host "`n  ✓ 已恢复可恢复的原版文件。" -ForegroundColor Green
        if ($Action -eq 'Remove') { Write-Host '  ✓ 已清理清单记录且未被修改的 Aurora 副本。' -ForegroundColor Green }
        if ($preserved.Count) { Write-Host ('  ! 保留了 '+$preserved.Count+' 个用户修改文件，备份与详情已保留。') -ForegroundColor Yellow }
    } elseif ($index -and $Action -eq 'Check') {
        foreach ($target in $index.Targets) {
            foreach ($exe in $target.Executables) {
                $log=Join-Path ([IO.Path]::GetDirectoryName($report)) ('check-'+[Guid]::NewGuid().ToString('N')+'.log.txt')
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
$session.Lease.Dispose()
exit $exitCode
