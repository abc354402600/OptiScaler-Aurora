# Read-only diagnostic observations and presentation; no installation policy lives here.
function New-AuroraFinding([string]$Code, [string]$Level, [string]$Finding,
    [string]$Cause, [string]$Action, [string[]]$Evidence=@()) {
    [pscustomobject]@{ Code=$Code; Level=$Level; Finding=$Finding; PossibleCause=$Cause; SuggestedAction=$Action; Evidence=@($Evidence) }
}
function Get-AuroraGameHints([string]$GameExe, [string]$Proxy='') {
    if (-not $GameExe) { return }
    switch ([IO.Path]::GetFileName($GameExe).ToLowerInvariant()) {
        'htgame.exe' {
            '异环已有反馈：dxgi.dll 可能触发非法模块检测，winmm.dll 在已验证环境中可用。请参考自己的游戏版本手动选择，不会自动改选 Proxy。'
            if ($Proxy -ieq 'dxgi.dll') { '当前仍选择 dxgi.dll。如果启动时出现非法模块提示，可用原卸载流程移除后改选 winmm.dll；不要同时放两个 Aurora Proxy。' }
        }
        'zenlesszonezero.exe' { '绝区零：参考已核对的官方说明，使用 DX12 启动参数 -use-d3d12，并手动选择合适 Proxy（如 d3d12.dll）；AMD/Intel 还需核对 Dxgi=true。工具不修改启动参数。' }
        'witcher3.exe' { '巫师3：沿用已验证的 OptiFG → DLSSG → None (Real DLSSG) 路径时，关闭游戏原生帧生成、保持 DualFeature=false，并保留原生 Streamline 1.x。' }
    }
}
function Get-AuroraProxyInventory([string]$InstallDir) {
    foreach ($name in @('OptiScaler.dll','dxgi.dll','winmm.dll','version.dll','dbghelp.dll','d3d12.dll','wininet.dll','winhttp.dll','OptiScaler.asi')) {
        $path=Join-Path $InstallDir $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $info=Get-AuroraBinary $path
        [pscustomobject]@{ Path=$path; Name=$name; Recognized=($info.OriginalFilename -ieq 'OptiScaler.dll'); IsProxy=($name -ine 'OptiScaler.dll'); Version=$info.Version }
    }
}
function Get-AuroraProcessEvidence([string]$GameExe) {
    $processes=@(); $modules=@()
    if (-not $GameExe) { return [pscustomobject]@{ State='Unselected'; Processes=@(); Modules=@() } }
    $name=[IO.Path]::GetFileNameWithoutExtension($GameExe)
    # Literal name comparison, not wildcard matching for executable names containing brackets.
    $running=@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -ieq $name })
    foreach ($p in $running) {
        $path=''
        try { $path=[string]$p.Path } catch { }
        if (-not $path) {
            $processes += [pscustomobject]@{ ProcessId=$p.Id; Path=''; State='PathUnavailable'; ModulesComplete=$false }; continue
        }
        if ($path -ine $GameExe) {
            $processes += [pscustomobject]@{ ProcessId=$p.Id; Path=$path; State='OtherExecutable'; ModulesComplete=$false }; continue
        }
        $observation=[pscustomobject]@{ ProcessId=$p.Id; Path=$path; State='Observed'; ModulesComplete=$false }
        try {
            $snapshot=@($p.Modules)
            if (-not $snapshot.Count -or $null -eq $snapshot[0]) { throw '模块列表不可读。' }
            foreach ($m in $snapshot) {
                $isAurora=$m.FileVersionInfo.OriginalFilename -ieq 'OptiScaler.dll'
                if (-not $isAurora -and $m.ModuleName -notmatch '^(sl\..*|nvngx_dlss.*)\.dll$') { continue }
                $diskHash=''; try { $diskHash=Get-AuroraHash $m.FileName } catch { }
                $modules += [pscustomobject]@{ ProcessId=$p.Id; Path=$m.FileName; Name=$m.ModuleName.ToLowerInvariant(); Version=$m.FileVersionInfo.FileVersion; Aurora=$isAurora; DiskSHA256=$diskHash }
            }
            $p.Refresh()
            if ($p.HasExited) { $observation.State='Exited' }
            else { $observation.ModulesComplete=$true }
        } catch { $observation.State='ModulesUnavailable' }
        $processes += $observation
    }
    $state='NotRunning'; if ($processes.Count) { $state='Observed' }
    [pscustomobject]@{ State=$state; Processes=$processes; Modules=$modules }
}
function Get-AuroraDiagnosticFindings([string]$InstallDir, [string]$GameRoot, [string]$GameExe,
    [object[]]$Candidates, [object[]]$Inventory, [object[]]$Proxies, $ProcessEvidence,
    [object[]]$Entries, [bool]$ScanComplete) {
    if (-not $ScanComplete) {
        New-AuroraFinding 'ScanIncomplete' '注意' '目录扫描未完成。' '部分目录不可读、是链接，或超过扫描预算；清单可能遗漏文件。' '查看扫描警告，选择更准确的游戏目录后重新检查；本次不会同步运行库。'
    }
    $loaders=@($Proxies | Where-Object { $_.Recognized -and $_.IsProxy })
    if (-not $loaders.Count) {
        New-AuroraFinding 'ProxyNotFound' '待核对' '安装目录内未发现可识别的 Aurora Proxy。' '可能只解压了 OptiScaler.dll、安装在其他目录，或使用了单独的外部加载器。' '若按常规方式安装，请运行 Aurora_Setup.bat，选择真实游戏 EXE，再手动选择 Proxy；不要删除未知 DLL。'
    } elseif ($loaders.Count -gt 1) {
        New-AuroraFinding 'MultipleProxies' '注意' '同一目录存在多个 Aurora Proxy。' '可能残留了不同加载方式，存在重复加载风险。' '关闭游戏，使用对应安装记录卸载后只保留一种手动选择的加载方式。' @($loaders | ForEach-Object { $_.Path })
    }
    if ($GameExe -and [IO.Path]::GetDirectoryName($GameExe) -ine $InstallDir) {
        New-AuroraFinding 'ExecutableDirectoryMismatch' '待核对' '所选游戏 EXE 与当前安装目录不同。' '可能装在 Launcher 目录，也可能是你特意使用外部加载器。' '若未自行配置外部加载，请从完整发布包重新选择实际游戏 EXE 所在目录安装。' @($InstallDir,$GameExe)
    }
    $direct=@($Candidates | Where-Object { $_.Directory -ieq $InstallDir })
    if (-not $direct.Count -and $Candidates.Count) {
        New-AuroraFinding 'OtherExecutableCandidates' '待核对' '安装目录没有候选游戏程序，但其他目录发现了候选。' 'Launcher、UE Binaries 或 Win64/Win64r 可能使用了另一条启动路径。' '对照下方完整路径，从安装菜单选择实际版本；排序只是线索，不会自动搬移文件。' @($Candidates | Select-Object -First 5 | ForEach-Object { $_.Path })
    } elseif (-not $GameExe -and $direct.Count -gt 1) {
        New-AuroraFinding 'MultipleExecutables' '待核对' '目录内有多个候选游戏程序，尚不能确定要检查哪个进程。' '同一安装目录可能包含不同客户端或启动版本。' '安装时明确选择实际使用的 EXE；高级检查可传入 -GameExe 完整路径。' @($direct | ForEach-Object { $_.Path })
    }
    foreach ($group in @($Inventory | Group-Object Name | Where-Object { $_.Count -gt 1 })) {
        New-AuroraFinding 'RuntimeCopies' '信息' "发现 $($group.Count) 份 $($group.Name)。" '游戏可能按引擎、插件或启动版本加载不同副本；多份文件本身不代表错误。' '进入游戏场景后再次检查，把实际加载路径与下方副本路径对照，不要只替换 EXE 同级文件。' @($group.Group | ForEach-Object { $_.Path })
    }
    $nativeSl=@($Inventory | Where-Object { $_.Name -like 'sl.*.dll' })
    if (@($nativeSl | Where-Object { $_.Major -eq 1 }).Count) {
        New-AuroraFinding 'SL1Protected' '保护中' '检测到游戏原生 Streamline 1.x。' 'SL1 与 SL2 不能作为普通小版本直接互换；保护不等于禁用 Aurora 的 6X。' '保持原版 SL1，使用该游戏已验证的 FG 输入路径；不要强制替换成 SL2。'
    }
    if (@($Inventory | Where-Object { $_.Name -ne 'nvngx_dlssnr.dll' -and ($_.Major -le 0 -or $_.Architecture -ne 'x64' -or -not $_.SHA256) }).Count) {
        New-AuroraFinding 'UnknownRuntime' '保护中' '部分 Runtime 的版本、架构或哈希无法确认。' '文件可能没有完整版本信息、不是 x64，或无法读取。' '查看对应文件的清单原因并保留原文件；不要通过改名或强制替换绕过保护。'
    }
    switch ($ProcessEvidence.State) {
        'Unselected' { New-AuroraFinding 'ProcessUnselected' '未知' '尚未指定用于诊断的游戏 EXE。' '没有可靠依据选择运行中的进程。' '从安装菜单选择实际游戏程序，进入场景后再运行检查。' }
        'NotRunning' { New-AuroraFinding 'GameNotRunning' '未知' '未发现所选游戏程序正在运行。' '游戏尚未启动，或实际运行的是其他 EXE；这不等于 Aurora 加载失败。' '保持游戏处于实际场景，再运行一键检查。检查为只读，可以在游戏运行时使用。' }
    }
    foreach ($p in $ProcessEvidence.Processes) {
        if ($p.State -eq 'OtherExecutable') {
            New-AuroraFinding 'OtherRunningExecutable' '待核对' "同名进程 $($p.ProcessId) 的路径与所选 EXE 不同。" '可能运行了另一套客户端或另一份游戏安装。' '核对下方实际进程路径；不要修改另一套安装的文件。' @($p.Path); continue
        }
        if (-not $p.ModulesComplete) {
            New-AuroraFinding 'ModuleObservationIncomplete' '未知' "无法完整读取进程 $($p.ProcessId) 的模块。" '路径/模块访问受限，或进程已退出；不能据此判断 Aurora 没有加载。' '保持游戏场景运行后重试；若仍受限，请结合 Insert 面板和游戏日志核对。'; continue
        }
        $aurora=@($ProcessEvidence.Modules | Where-Object { $_.ProcessId -eq $p.ProcessId -and $_.Aurora })
        if (-not $aurora.Count) {
            New-AuroraFinding 'AuroraNotObserved' '待核对' "进程 $($p.ProcessId) 的完整模块快照中未发现可识别的 Aurora。" '可能安装位置或 Proxy 不适合当前启动路径；也可能所用 DLL 缺少识别元数据。' '先核对真实 EXE 和安装目录，再按游戏指引手动换 Proxy。此时不要先把问题归为 MFG 只有 2X。' @($p.Path)
        } else {
            New-AuroraFinding 'AuroraObserved' '已观察' "已在进程 $($p.ProcessId) 中看到 Aurora/OptiScaler 模块。" '只能证明该次快照中模块存在，不能证明 MFG 已启用或可用 6X。' '按 Insert 核对 FG Input、FG Output 和倍率；保存设置并完全重启后再比较。' @($aurora | ForEach-Object { $_.Path })
            foreach ($m in $aurora) {
                if ([IO.Path]::GetDirectoryName($m.Path) -ine $InstallDir) {
                    New-AuroraFinding 'OtherAuroraLocation' '待核对' '游戏加载的 Aurora/OptiScaler 来自另一个目录。' '当前工具检查的安装位置可能不是生效位置，也可能配置了外部加载。' '先核对实际加载来源，避免反复修改当前未生效目录。' @($m.Path)
                }
            }
        }
    }
    foreach ($m in @($ProcessEvidence.Modules | Where-Object { -not $_.Aurora })) {
        if (-not (Test-AuroraWithin $m.Path $GameRoot)) {
            New-AuroraFinding 'RuntimeOutsideScan' '待核对' "进程 $($m.ProcessId) 加载的 $($m.Name) 位于扫描范围外。" '游戏、驱动或外部加载器可能从其他位置提供 Runtime。' '把实际路径写入反馈；本工具只报告，不扫描或修改游戏目录外的文件。' @($m.Path)
            continue
        }
        $sameName=@($Inventory | Where-Object { $_.Name -ieq $m.Name })
        $samePath=@($sameName | Where-Object { $_.Path -ieq $m.Path })
        if (-not $samePath.Count -and -not (Test-AuroraWithin $m.Path (Join-Path $InstallDir 'OptiScaler'))) {
            New-AuroraFinding 'LoadedRuntimeNotInventoried' '待核对' "实际加载的 $($m.Name) 没有出现在本次文件清单中。" '文件可能位于被跳过的位置，或目录内容在扫描后发生变化。' '按实际加载路径重新定位；不要把其他同名副本同步成功当成当前副本已更新。' @($m.Path)
        }
        $managed=@($Entries | Where-Object { $_.SourceName -ieq $m.Name -and $_.Status -in @('Applied','Pending') })
        $active=@($managed | Where-Object { $_.TargetPath -ieq $m.Path })
        if ($managed.Count -and -not $active.Count -and -not (Test-AuroraWithin $m.Path (Join-Path $InstallDir 'OptiScaler'))) {
            New-AuroraFinding 'LoadedDifferentRuntimeCopy' '待核对' "同步记录与实际加载的 $($m.Name) 指向不同副本。" '启动链可能使用了另一个插件或客户端目录。' '核对实际路径后再选择正确游戏范围修复；不要手动把所有同名 DLL 都覆盖。' (@($m.Path)+@($managed | ForEach-Object { $_.TargetPath }))
        }
        foreach ($e in $active) {
            if ($m.DiskSHA256 -and $m.DiskSHA256 -ne $e.DeployedHash) {
                New-AuroraFinding 'RuntimeChangedSinceSync' '待核对' "$($m.Name) 当前路径上的磁盘文件与上次同步哈希不同。" '游戏更新、校验或用户操作可能改过此文件；这不是进程内存哈希。' '先关闭游戏并查看恢复/修复清单中的冲突；不要强制覆盖，重新启动后再检查加载路径。' @($m.Path)
            }
        }
    }
    New-AuroraFinding 'ExternalSettingsUnknown' '需手动核对' 'NVIDIA App 覆盖、游戏 FG 开关和当前 MFG 倍率未由本工具读取。' '只能 2X 可能涉及这些设置，但当前没有直接检测证据。' '先确认 Aurora 加载和 Runtime 路径；再参考对应游戏教程逐项核对 NVIDIA App AI 插帧/帧生成覆盖及 DLSS 优设，尝试使用 3D 应用程序设置，每次只改一项并重启。'
    New-AuroraFinding 'FrameGenerationRoute' '操作建议' '游戏原生 DLSSG 输入和 OptiFG 输入需要不同的游戏 FG 设置。' '把两种路径的开关规则混用，可能导致无帧生成或只看到 2X。' '原生 DLSSG 输入按该游戏教程开启游戏 FG；巫师3已验证的 OptiFG → DLSSG 路径关闭原生 FG、保持 DualFeature=false，保存并重启。'
}
function Format-AuroraDiagnosticText($Report) {
    $lines=New-Object 'Collections.Generic.List[string]'
    $lines.Add('Aurora 一键诊断报告')
    $lines.Add("检查时间（UTC）：$($Report.Timestamp)")
    $lines.Add("安装目录：$($Report.InstallDir)")
    $lines.Add("游戏目录：$($Report.GameRoot)")
    $lines.Add("所选游戏程序：$($Report.GameExe)")
    $lines.Add('本报告为只读观察；磁盘 SHA256 不代表进程内存中的 DLL 字节。')
    foreach ($o in $Report.Observations) { $lines.Add($o) }
    foreach ($hint in @(Get-AuroraGameHints $Report.GameExe)) { $lines.Add($hint) }
    foreach ($f in $Report.Findings) {
        $lines.Add(''); $lines.Add("[$($f.Level)] 发现：$($f.Finding)")
        $lines.Add("可能原因：$($f.PossibleCause)"); $lines.Add("操作：$($f.SuggestedAction)")
        foreach ($e in $f.Evidence) { $lines.Add("依据：$e") }
    }
    $lines.Add(''); $lines.Add('实际模块路径（瞬时观察）')
    foreach ($m in $Report.LoadedModules) { $lines.Add("进程 $($m.ProcessId)：$($m.Path) [$($m.Version)]；当前磁盘 SHA256：$($m.DiskSHA256)") }
    $lines.Add(''); $lines.Add('磁盘运行库清单（完整路径）')
    foreach ($i in $Report.Inventory) { $lines.Add("$($i.Path) [$($i.Version)] $($i.Architecture)；SHA256：$($i.SHA256)；$($i.Action)：$($i.Reason)") }
    foreach ($w in $Report.ScanWarnings) { $lines.Add("扫描警告：$w") }
    return ($lines -join "`r`n")
}
function Write-AuroraDiagnosticText([string]$Path, [string]$Text) {
    # A sidecar must never overwrite an unrelated user file. JSON is saved separately.
    Assert-AuroraPlainPath $Path
    $stream=$null
    try {
        $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $encoding=New-Object Text.UTF8Encoding($true)
        $bytes=$encoding.GetPreamble()+$encoding.GetBytes($Text)
        $stream.Write($bytes,0,$bytes.Length)
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
}
