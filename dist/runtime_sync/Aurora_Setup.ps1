param(
    [ValidateSet('Menu','Install','Check','Repair','Restore','Remove')][string]$Action='Menu',
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
    if ($Action -eq 'Install') {
        . (Join-Path $PSScriptRoot 'Aurora_Diagnostics.ps1')
        if (-not $GameRoot) {
            if ($NonInteractive) { throw '非交互安装必须指定 GameRoot 和 GameExe。' }
            $inputPath=Read-Host '请输入游戏目录或游戏 EXE 的完整路径，然后按 Enter（回车）'
            $GameRoot=Resolve-AuroraGameRoot $inputPath
        }
        $GameRoot=Get-AuroraPath $GameRoot
        $scan=Get-AuroraScan $GameRoot
        if (-not $scan.Complete) { throw ($scan.Warnings -join "`n") }
        $candidates=@(Get-AuroraCandidates $scan)
        if (-not $candidates.Count) { throw '未发现可信 x64 游戏程序。请选择单个游戏根目录，确认游戏已完整安装。' }
        if (-not $GameExe) {
            if ($NonInteractive) { throw '非交互安装必须明确指定 GameExe。' }
            $choices=@($candidates | ForEach-Object { "$($_.Path)`n    $($_.Reasons)" }) + @('取消安装')
            $n=Read-AuroraChoice '发现以下候选程序（排序仅供参考，请选择实际启动的版本）' $choices
            if ($n -gt $candidates.Count) { exit 0 }; $GameExe=$candidates[$n-1].Path
        }
        $GameExe=Get-AuroraPath $GameExe
        if (@($candidates | Where-Object { $_.Path -ieq $GameExe }).Count -ne 1) { throw '所选程序不在有效候选列表内，未安装。' }
        $InstallDir=[IO.Path]::GetDirectoryName($GameExe)
        foreach ($hint in @(Get-AuroraGameHints $GameExe)) { Write-Host $hint }
        $proxies=@('dxgi.dll','winmm.dll','version.dll','dbghelp.dll','d3d12.dll','wininet.dll','winhttp.dll','OptiScaler.asi')
        if (-not $Proxy) {
            if ($NonInteractive) { throw '非交互安装必须指定 Proxy。' }
            $n=Read-AuroraChoice '请选择加载方式（参考具体游戏教程；ASI 需要已有 ASI Loader）' ($proxies + @('取消安装'))
            if ($n -gt $proxies.Count) { exit 0 }; $Proxy=$proxies[$n-1]
        }
        if ([IO.Path]::GetFileName($GameExe) -ieq 'HTGame.exe' -and $Proxy -ieq 'dxgi.dll') {
            Write-Host '你选择了 dxgi.dll。若出现非法模块提示，请通过原卸载流程移除后再手动选择 winmm.dll；不要同时部署两个 Aurora Proxy。'
        }
        $dll=Join-Path $PackageDir 'OptiScaler.dll'
        $binary=Get-AuroraBinary $dll
        if ($binary.Architecture -ne 'x64' -or $binary.OriginalFilename -ine 'OptiScaler.dll') { throw '发布包缺少可识别的 x64 OptiScaler.dll。请使用完整构建产物。' }
        foreach ($name in $proxies) {
            $p=Join-Path $InstallDir $name
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
            $info=Get-AuroraBinary $p
            if ($name -ieq $Proxy -and $info.OriginalFilename -ine 'OptiScaler.dll') { throw "所选 $name 已被其他程序占用。请选择其他 Proxy，不能覆盖未知 DLL。" }
            if ($name -ine $Proxy -and $info.OriginalFilename -ieq 'OptiScaler.dll') { throw "已存在 Aurora/OptiScaler 代理 $name，请先用对应卸载器移除它，再切换 Proxy。" }
        }
        Write-Host "`n安装位置：$InstallDir`n游戏程序：$GameExe`n加载方式：$Proxy"
        Write-Host '保留已有配置；替换文件前备份。安装后只读检查，运行库修复需要单独选择。'
        if (-not $NonInteractive -and (Read-AuroraChoice '确认安装' @('安装','取消')) -eq 2) { exit 0 }
        Assert-AuroraGameClosed $GameRoot $GameExe
        $opLock=Enter-AuroraLock $GameRoot
        $journalPath=Join-Path $InstallDir 'OptiScaler\AuroraSetup\manifest.json'
        $journal=Open-AuroraJournal $journalPath $GameRoot $InstallDir
        # Construct the payload before any game-file write. Never copy state/backups/plugins
        # from an existing game installation into a different game.
        $payload=@([pscustomobject]@{Source=$dll;Target=(Join-Path $InstallDir $Proxy)})
        foreach ($name in @('Aurora_Common.ps1','Aurora_Diagnostics.ps1','Aurora_Setup.ps1','runtime_sync.ps1','Check_DLSS_Runtime.bat','Aurora_Setup.bat')) {
            $source=Join-Path $PSScriptRoot $name
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "工具文件缺失：$name" }
            $payload += [pscustomobject]@{Source=$source;Target=(Join-Path $InstallDir $name)}
        }
        $payload += [pscustomobject]@{Source=(Join-Path $PSScriptRoot 'Remove_Aurora.bat');Target=(Join-Path $InstallDir 'Remove_Aurora.bat')}
        foreach ($name in @('nvngx.dll_dlssnr.dll','LICENSE','READ ME - DLSS Neural Rendering.txt')) {
            $source=Join-Path $PackageDir $name
            if (Test-Path -LiteralPath $source -PathType Leaf) { $payload += [pscustomobject]@{Source=$source;Target=(Join-Path $InstallDir $name)} }
        }
        $licenses=Join-Path $PackageDir 'Licenses'
        if (Test-Path -LiteralPath $licenses -PathType Container) {
            Assert-AuroraPlainPath $licenses
            foreach ($f in @(Get-ChildItem -LiteralPath $licenses -File)) {
                $payload += [pscustomobject]@{Source=$f.FullName;Target=(Join-Path $InstallDir ('Licenses\'+$f.Name))}
            }
        }
        $bundle=Join-Path $PackageDir 'OptiScaler'
        if (-not (Test-Path -LiteralPath $bundle -PathType Container)) { throw '发布包缺少 OptiScaler 运行库目录。' }
        Assert-AuroraPlainPath $bundle
        $queue=New-Object 'Collections.Generic.Queue[string]'; $queue.Enqueue($bundle)
        $payloadDirs=0
        while ($queue.Count) {
            $payloadDirs++
            if ($payloadDirs -gt 1000 -or $payload.Count -gt 10000) { throw '发布包目录异常庞大，停止安装。' }
            foreach ($file in @(Get-ChildItem -LiteralPath $queue.Dequeue() -Force)) {
                Assert-AuroraPlainPath $file.FullName
                if ($file.PSIsContainer) {
                    if ($file.Name -match '^(RuntimeSync|AuroraSetup|\.git|_storage.*)$') { continue }
                    if ($file.Name -ieq 'plugins') {
                        # Do not transfer arbitrary per-game plugins; retain the bundled OptiPatcher.
                        $patcher=Join-Path $file.FullName 'OptiPatcher.asi'
                        if (Test-Path -LiteralPath $patcher) { $payload += [pscustomobject]@{Source=$patcher;Target=(Join-Path $InstallDir 'OptiScaler\plugins\OptiPatcher.asi')} }
                        continue
                    }
                    $queue.Enqueue($file.FullName)
                } elseif ($file.Extension -in @('.dll','.json','.ini','.txt','.md','.bin')) {
                    $rel=$file.FullName.Substring($bundle.Length).TrimStart('\')
                    $payload += [pscustomobject]@{Source=$file.FullName;Target=(Join-Path $InstallDir ('OptiScaler\'+$rel))}
                }
            }
        }
        $config=Join-Path $InstallDir 'OptiScaler.ini'
        if (-not (Test-Path -LiteralPath $config)) {
            $sourceIni=Join-Path $PackageDir 'OptiScaler.ini'
            if (-not (Test-Path -LiteralPath $sourceIni)) { throw '缺少 OptiScaler.ini。' }
            $stage=Join-Path ([IO.Path]::GetTempPath()) ('Aurora-'+[Guid]::NewGuid().ToString('N')+'.ini')
            $ini=Get-Content -LiteralPath $sourceIni -Raw -Encoding UTF8
            if ($ini -notmatch '(?m)^DualFeature=false\s*$') { throw '发布包默认配置不满足 DualFeature=false，停止安装。' }
            if (-not $NonInteractive) {
                $gpu=Read-AuroraChoice '使用什么显卡？' @('NVIDIA','AMD / Intel')
                if ($gpu -eq 2) {
                    $spoof=Read-AuroraChoice '是否需要 DLSS 输入或游戏教程要求的显卡伪装？' @('保留自动设置','关闭伪装（Dxgi=false）','启用伪装（Dxgi=true）')
                    if ($spoof -eq 2) { $ini=$ini -replace '(?m)^Dxgi=auto\s*$', 'Dxgi=false' }
                    if ($spoof -eq 3) { $ini=$ini -replace '(?m)^Dxgi=auto\s*$', 'Dxgi=true' }
                }
            }
            [IO.File]::WriteAllText($stage,$ini,(New-Object Text.UTF8Encoding($true)))
            $payload += [pscustomobject]@{Source=$stage;Target=$config}
        }
        foreach ($p in $payload) {
            Assert-AuroraPlainPath $p.Source; Assert-AuroraPlainPath $p.Target
            $p | Add-Member NoteProperty Hash (Get-AuroraHash $p.Source)
        }
        # Keep the chosen root available even if deployment is interrupted midway.
        $metaPath=Join-Path $InstallDir 'OptiScaler\AuroraSetup\installation.json'
        Write-AuroraJson $metaPath ([pscustomobject]@{GameRoot=$GameRoot;GameExe=$GameExe;Proxy=$Proxy})
        # Deploy Proxy last: incomplete payload deployment must not create a new loader.
        foreach ($p in @($payload | Select-Object -Skip 1) + @($payload[0])) { Install-AuroraFile $journal $journalPath $p.Source $p.Target $p.Hash }
        Write-Host 'Aurora 文件已部署并通过 SHA256 校验。已有配置未改动。'
        $opLock.Dispose(); $opLock=$null; $Action='Check'; $installedNow=$true
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
