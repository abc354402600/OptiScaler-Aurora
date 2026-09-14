# RC3 orchestration; file writes and recovery use the RC2 journal primitives.
function Get-AuroraExecutableEvidence([string]$Path) {
    $stream=$null; $guard=$null; $valid=$false; $imports=@()
    try {
        Assert-AuroraPlainPath $Path
        $guard=Enter-AuroraPathGuard $Path
        $stream=[AuroraDirectoryGuard]::Read((Get-AuroraPath $Path)); $reader=New-Object IO.BinaryReader($stream)
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { throw 'MZ' }
        $stream.Position=60; $offset=$reader.ReadInt32()
        if ($offset -lt 64 -or $offset -gt $stream.Length-264) { throw 'PE offset' }
        $stream.Position=$offset
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) { throw 'PE x64' }
        $count=$reader.ReadUInt16(); $stream.Position=$offset+20
        $optionalSize=$reader.ReadUInt16(); $flags=$reader.ReadUInt16()
        if (-not ($flags -band 2) -or ($flags -band 0x2000) -or $optionalSize -lt 128 -or $reader.ReadUInt16() -ne 0x20b) { throw 'Not PE32+ executable' }
        if ($count -lt 1 -or $count -gt 96 -or $offset+24+$optionalSize+40*$count -gt $stream.Length) { throw 'Section table' }
        $valid=$true
        $stream.Position=$offset+24+120; $importRva=$reader.ReadUInt32(); $importSize=$reader.ReadUInt32()
        $sections=@(); $stream.Position=$offset+24+$optionalSize
        for ($i=0; $i -lt $count; $i++) {
            $stream.Position+=8; $virtualSize=$reader.ReadUInt32(); $rva=$reader.ReadUInt32(); $rawSize=$reader.ReadUInt32(); $raw=$reader.ReadUInt32(); $stream.Position+=16
            $sections+=@([pscustomobject]@{Rva=$rva;Size=$rawSize;Raw=$raw})
        }
        $map={ param([long]$Rva)
            foreach ($section in $sections) {
                if ($Rva -ge $section.Rva -and $Rva -lt [long]$section.Rva+$section.Size) {
                    $result=[long]$section.Raw+$Rva-$section.Rva
                    if ($result -lt $stream.Length) { return $result }
                }
            }
            return -1
        }
        $table=& $map $importRva
        if ($importRva -and $table -ge 0) {
            for ($i=0; $i -lt 256 -and ($i+1)*20 -le $importSize; $i++) {
                if ($table+$i*20+20 -gt $stream.Length) { break }
                $stream.Position=$table+$i*20+12; $nameRva=$reader.ReadUInt32()
                if (-not $nameRva) { break }; $nameOffset=& $map $nameRva
                if ($nameOffset -lt 0) { break }; $stream.Position=$nameOffset
                $name=''
                for ($n=0; $n -lt 128 -and $stream.Position -lt $stream.Length; $n++) { $b=$reader.ReadByte(); if (-not $b) { break }; $name+=[char]$b }
                if ($name -match '^(?i)(d3d(?:9|10|11|12)|dxgi|vulkan-1|opengl32|UnityPlayer)\.dll$') { $imports+=$name }
            }
        }
    } catch { } finally { if ($stream) { $stream.Dispose() }; if ($guard) { $guard.Dispose() } }
    [pscustomobject]@{Valid=$valid;GraphicsImports=$imports}
}
function Test-AuroraUtilityPath([string]$RelativePath, [switch]$Runtime) {
    $parts=$RelativePath -split '[\\/]'
    foreach ($part in $parts) {
        if ($part -match '(?i)^(?:.*launcher.*|bootstrap.*|updat(?:er|e).*|crash(?:report.*|handler.*)?|.*crashreport.*|editor|install(?:er)?|uninstall.*|unins\d*|EasyAntiCheat.*|EAC|BattlEye|BEservice.*|CEF|.*cefsubprocess.*|_?CommonRedist|Redist|Prerequisites?|Support|Tools?|SDK|ThirdParty|Extras)$') { return $true }
    }
    $base=[IO.Path]::GetFileNameWithoutExtension($RelativePath)
    if (-not $Runtime -and $base -match '(?i)(launcher|bootstrap|updater|crashreport|crashhandler|uninstall|^unins|^setup$|installer|editor$|easyanticheat|^eac(?:_|$)|battleye|^beservice|cefsubprocess|^HYP$|modmanager|benchmark|diagnostic|crashpad|helper$|reporter$)') { return $true }
    # Engine plugins contain real native runtimes; Engine executables are tools.
    if (-not $Runtime -and $parts -icontains 'Engine') { return $true }
    return $false
}
function Get-AuroraDeploymentCandidates($Scan) {
    $exes=@($Scan.Files | Where-Object { $_.Extension -ieq '.exe' })
    $unsafeDirectories=@{}
    foreach ($exe in $exes) {
        if ((Test-AuroraUtilityPath $exe.FullName.Substring($Scan.Root.Length).TrimStart('\')) -and (Get-AuroraExecutableEvidence $exe.FullName).Valid) { $unsafeDirectories[$exe.DirectoryName]=$true }
    }
    foreach ($f in $exes) {
        $rel=$f.FullName.Substring($Scan.Root.Length).TrimStart('\')
        if (Test-AuroraUtilityPath $rel) { continue }
        # Excluding a filename cannot prevent a colocated x64 utility loading a Proxy.
        if ($unsafeDirectories.ContainsKey($f.DirectoryName)) { continue }
        $evidence=Get-AuroraExecutableEvidence $f.FullName
        if (-not $evidence.Valid) { continue }
        $score=0; $reasons=@('PE x64')
        if ($rel -match '(?i)(^|\\)Binaries\\(Win64r?|WinGDK)\\') { $score+=60; $reasons+='Binaries 游戏目录' }
        if ($rel -match '(?i)(^|\\)(Win64r?|WinGDK|x64(?:_dx1[12])?|DX1[12])\\') { $score+=30; $reasons+='64 位 / DX 游戏目录' }
        if ($f.BaseName -match '(?i)(-Shipping$|^HTGame$|^wwm$|^witcher3$|^ZenlessZoneZero$)') { $score+=30; $reasons+='游戏入口特征' }
        $near=@($Scan.Files | Where-Object { $_.Extension -ieq '.dll' -and $_.DirectoryName -ieq $f.DirectoryName })
        $d3d=@('d3d11.dll','d3d12.dll','D3D12Core.dll','UnityPlayer.dll','GameAssembly.dll') | Where-Object { Test-Path -LiteralPath (Join-Path $f.DirectoryName $_) -PathType Leaf }
        if ($near.Count -or @($d3d).Count) { $score+=30; $reasons+='同目录渲染 Runtime' }
        if ($evidence.GraphicsImports.Count) { $score+=30; $reasons+='PE 导入图形 API' }
        # Unity data directory is specific to this executable, unlike file size alone.
        if (Test-Path -LiteralPath (Join-Path $f.DirectoryName ($f.BaseName+'_Data')) -PathType Container) { $score+=30; $reasons+='对应 Unity 数据目录' }
        if ($score -lt 30) { continue }
        [pscustomobject]@{Path=$f.FullName;Directory=$f.DirectoryName;Score=$score;Reasons=($reasons -join '；')}
    }
}
function Resolve-AuroraDeploymentRoot([string]$InputPath) {
    $p=Get-AuroraPath $InputPath
    if (Test-Path -LiteralPath $p -PathType Leaf) { $p=[IO.Path]::GetDirectoryName($p) }
    $meta=Join-Path $p 'OptiScaler\AuroraSetup\installation.json'
    if (Test-Path -LiteralPath $meta) {
        Assert-AuroraPlainPath $meta
        $saved=Get-Content -LiteralPath $meta -Raw -Encoding UTF8 | ConvertFrom-Json
        $root=Get-AuroraPath $saved.GameRoot
        if (-not (Test-AuroraWithin $p $root)) { throw '安装记录指向其他游戏目录。' }
        Assert-AuroraGameRoot $root; return $root
    }
    $p=Resolve-AuroraGameRoot $p
    $cur=[IO.DirectoryInfo]$p
    if ($cur.Name -match '^(x64|DX11|DX12)$' -and $cur.Parent) { $cur=$cur.Parent }
    if ($cur.Name -ieq 'bin' -and $cur.Parent) { $cur=$cur.Parent }
    Assert-AuroraGameRoot $cur.FullName; return $cur.FullName
}
function Get-AuroraSteamRoots([string[]]$SteamPaths=@()) {
    $paths=@($SteamPaths)
    if (-not $paths.Count) {
        foreach ($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam')) {
            $item=Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
            if ($item) { foreach ($name in @('SteamPath','InstallPath')) { if ($item.PSObject.Properties[$name]) { $paths+=[string]$item.$name } } }
        }
        if (${env:ProgramFiles(x86)}) { $paths+=Join-Path ${env:ProgramFiles(x86)} 'Steam' }
        foreach ($drive in @(Get-PSDrive -PSProvider FileSystem)) { $paths+=Join-Path $drive.Root 'SteamLibrary' }
    }
    $libraries=@($paths)
    foreach ($path in $paths) {
        $vdf=Join-Path $path 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            Assert-AuroraPlainPath $vdf
            $text=Get-Content -LiteralPath $vdf -Raw -Encoding UTF8
            foreach ($m in [regex]::Matches($text,'"(?:path|\d+)"\s*"([^"]+)"')) {
                $candidate=$m.Groups[1].Value.Replace('\\','\')
                if ([IO.Path]::IsPathRooted($candidate)) { $libraries+=$candidate }
            }
        }
    }
    foreach ($library in @($libraries | Sort-Object -Unique)) {
        $apps=Join-Path $library 'steamapps'
        if (-not (Test-Path -LiteralPath $apps -PathType Container)) { continue }
        Assert-AuroraPlainPath $apps
        foreach ($acf in @(Get-ChildItem -LiteralPath $apps -File -Filter 'appmanifest_*.acf')) {
            Assert-AuroraPlainPath $acf.FullName
            $data=Get-Content -LiteralPath $acf.FullName -Raw -Encoding UTF8
            if ($data -match '"installdir"\s*"([^"\\/:]+)"') {
                $root=Join-Path (Join-Path $apps 'common') $matches[1]
                if (Test-Path -LiteralPath $root -PathType Container) { Get-AuroraPath $root }
            }
        }
    }
}
function Find-AuroraGames([string[]]$Contexts, [string[]]$SteamPaths=@()) {
    $seen=@{}; $found=@()
    # Extraction context wins over unrelated installed Steam games.
    foreach ($context in @($Contexts | Select-Object -Unique)) {
        if (-not $context) { continue }
        $possibles=@($context)
        $dir=[IO.DirectoryInfo](Get-AuroraPath $context)
        if ($dir.Parent -and $dir.Name -match '(?i)^(Aurora.*|OptiScaler.*|release|package)$') { $possibles+=$dir.Parent.FullName }
        foreach ($possible in $possibles) {
            try {
                $root=Resolve-AuroraDeploymentRoot $possible
                if ([IO.Path]::GetFileName($root) -match '^(Downloads|Desktop|Documents|Codex|work|source|dist)$') { continue }
                if ($seen.ContainsKey($root)) { continue }; $seen[$root]=$true
                $scan=Get-AuroraScan $root
                $entries=@(Get-AuroraDeploymentCandidates $scan)
                if ($scan.Complete -and $entries.Count) { $found+=$root }
            } catch { }
        }
    }
    if ($found.Count) { return @($found | Sort-Object -Unique) }
    foreach ($root in @(Get-AuroraSteamRoots $SteamPaths | Sort-Object -Unique)) {
        if ($seen.ContainsKey($root)) { continue }; $seen[$root]=$true
        try {
            # ACF already identifies installed game roots. Scan only the chosen game,
            # not every byte of every Steam game before showing a selection.
            Assert-AuroraGameRoot $root; $found+=$root
        } catch { }
    }
    return @($found)
}
function Get-AuroraRuntimeGroups($Scan, [object[]]$Candidates, $ProcessEvidence=$null, [string]$ObservedExe='') {
    foreach ($group in @($Scan.Files | Where-Object { $_.Extension -ieq '.dll' } | Group-Object DirectoryName)) {
        $dir=$group.Name
        $direct=@($Candidates | Where-Object { $_.Directory -ieq $dir } | ForEach-Object { $_.Path })
        $files=@($group.Group | ForEach-Object { $b=Get-AuroraBinary $_.FullName; [pscustomobject]@{Path=$_.FullName;SHA256=(Get-AuroraHash $_.FullName);Version=$b.Version;Major=$b.Major;Architecture=$b.Architecture} })
        # A disk layout can suggest association, never prove a process loaded it.
        $kind='SharedOrUnresolved'; $associated=@($Candidates | ForEach-Object { $_.Path })
        if ($direct.Count) { $kind='SameDirectory'; $associated=$direct }
        $observed=@()
        if ($ProcessEvidence) {
            foreach ($module in @($ProcessEvidence.Modules)) {
                if ([IO.Path]::GetDirectoryName($module.Path) -ieq $dir) {
                    $process=@($ProcessEvidence.Processes | Where-Object { $_.ProcessId -eq $module.ProcessId -and $_.Path -ieq $ObservedExe })
                    if ($process.Count) { $observed+=@([pscustomobject]@{Executable=$ObservedExe;ProcessId=$module.ProcessId;ModulePath=$module.Path}) }
                }
            }
        }
        $loaded='未观察'; if ($observed.Count) { $loaded='已观察模块路径' }
        [pscustomobject]@{Id=$dir.Substring($Scan.Root.Length).TrimStart('\');Directory=$dir;Files=$files;CandidatePaths=$associated;Association=$kind;LoadedAssociation=$loaded;ObservedBy=$observed;SL1=(@($files | Where-Object { [IO.Path]::GetFileName($_.Path) -like 'sl.*' -and $_.Major -eq 1 }).Count -gt 0)}
    }
}
function Get-AuroraRecommendedProxy([object[]]$Candidates, [string]$Override) {
    if ($Override) { return $Override }
    if (@($Candidates | Where-Object { [IO.Path]::GetFileName($_.Path) -ieq 'HTGame.exe' }).Count) { return 'winmm.dll' }
    return 'dxgi.dll'
}

function New-AuroraPayload([string]$PackageDir,[string]$InstallDir,[string]$Proxy) {
    $dll=Join-Path $PackageDir 'OptiScaler.dll'
    $stage=$null
    try {
        # Construct the payload before any game-file write. Never copy state/backups/plugins
        # from an existing game installation into a different game.
        $payload=@([pscustomobject]@{Source=$dll;Target=(Join-Path $InstallDir $Proxy)}, [pscustomobject]@{Source=$dll;Target=(Join-Path $InstallDir 'OptiScaler.dll')})
        foreach ($name in @('Aurora_Common.ps1','Aurora_Installer.ps1','Aurora_RuntimeCatalog.ps1','Aurora_Diagnostics.ps1','Aurora_Setup.ps1','Aurora_Setup_Legacy.ps1','runtime_sync.ps1','Check_DLSS_Runtime.bat','Aurora_Setup.bat')) {
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
            [IO.File]::WriteAllText($stage,$ini,(New-Object Text.UTF8Encoding($true)))
            $payload += [pscustomobject]@{Source=$stage;Target=$config}
        }
        foreach ($p in $payload) {
            Assert-AuroraPlainPath $p.Source; Assert-AuroraPlainPath $p.Target
            $p | Add-Member NoteProperty Hash (Get-AuroraHash $p.Source)
        }
        return $payload
    } catch {
        if ($stage -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Force }
        throw
    }
}

function Get-AuroraIndexPath([string]$Root) { Join-Path $Root 'OptiScaler\AuroraSetup\AuroraInstallManifest.json' }
function Open-AuroraIndex([string]$Root) {
    $Root=Get-AuroraMetadataPath $Root
    $path=Get-AuroraIndexPath $Root; Assert-AuroraPlainPath $path
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $index=Read-AuroraJson $path
    Assert-AuroraFields $index @('SchemaVersion','GameRoot','Status','Targets','RuntimeOwners','RuntimeGroups')
    if ($index.SchemaVersion -isnot [int] -or $index.Targets -isnot [array] -or $index.Targets.Count -lt 1 -or $index.Targets.Count -gt 256 -or $index.RuntimeOwners -isnot [array] -or $index.RuntimeGroups -isnot [array]) { throw 'RC3 总清单字段类型或目标数量无效。' }
    if ($index.PSObject.Properties['RuntimeJournalExpected'] -and $index.RuntimeJournalExpected -isnot [bool]) { throw 'Runtime 日志登记状态无效。' }
    if ($index.SchemaVersion -ne 3 -or (Get-AuroraMetadataPath $index.GameRoot) -ine $Root -or $index.Status -notin @('Pending','Applied','Removed','NeedsAttention')) { throw 'RC3 总清单版本、目录或状态不匹配。' }
    $index.GameRoot=$Root
    $seen=@{}
    foreach ($target in @($index.Targets)) {
        Assert-AuroraFields $target @('Directory','Proxy','JournalPath','Executables')
        if ($target.Executables -isnot [array] -or -not $target.Executables.Count) { throw '入口列表必须是非空数组。' }
        $dir=Get-AuroraMetadataPath $target.Directory; $target.Directory=$dir
        if (-not (Test-AuroraWithin $dir $Root) -or (Test-AuroraWithin $dir (Join-Path $Root 'OptiScaler')) -or $seen.ContainsKey($dir)) { throw 'RC3 清单入口重复或越界。' }
        $seen[$dir]=$true; Assert-AuroraPlainPath $dir
        if ($target.Proxy -notin @('dxgi.dll','winmm.dll','version.dll','dbghelp.dll','d3d12.dll','wininet.dll','winhttp.dll','OptiScaler.asi')) { throw 'RC3 清单 Proxy 无效。' }
        $target.JournalPath=Get-AuroraMetadataPath $target.JournalPath
        if ($target.JournalPath -ine (Join-Path $dir 'OptiScaler\AuroraSetup\manifest.json')) { throw 'RC3 文件日志路径不匹配。' }
        if ($target.PSObject.Properties['JournalExpected'] -and $target.JournalExpected -isnot [bool]) { throw '核心日志登记状态无效。' }
        if (($index.Status -eq 'Applied' -or ($target.PSObject.Properties['JournalExpected'] -and $target.JournalExpected)) -and -not (Test-Path -LiteralPath $target.JournalPath -PathType Leaf)) { throw '部署文件日志缺失，停止操作，不能猜测文件归属。' }
        foreach ($exe in @($target.Executables)) { if ([IO.Path]::GetDirectoryName((Get-AuroraMetadataPath $exe)) -ine $dir) { throw 'RC3 入口路径与目录不匹配。' } }
    }
    $owners=@{}
    foreach ($dir in @($index.RuntimeOwners)) {
        if (-not $seen.ContainsKey((Get-AuroraMetadataPath $dir))) { throw 'RC3 Runtime 日志未关联部署入口。' }
        $owner=Get-AuroraMetadataPath $dir
        if ($owners.ContainsKey($owner)) { throw 'Runtime 日志所有者重复。' }; $owners[$owner]=$true
    }
    return $index
}
function Assert-AuroraPayloadReady($Target, $Journal, [object[]]$Payload) {
    $proxies=@('dxgi.dll','winmm.dll','version.dll','dbghelp.dll','d3d12.dll','wininet.dll','winhttp.dll','OptiScaler.asi')
    foreach ($name in $proxies) {
        $path=Join-Path $Target.Directory $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $info=Get-AuroraBinary $path
            if ($name -ine $Target.Proxy -and $info.OriginalFilename -ieq 'OptiScaler.dll') { throw "存在另一 Aurora Proxy，请先卸载后切换：$path" }
            if ($name -ieq $Target.Proxy -and $info.OriginalFilename -ine 'OptiScaler.dll') { throw "Proxy 被其他 Mod 占用，已保留。请在高级选项中更换：$path" }
        }
    }
    foreach ($p in $Payload) {
        $p | Add-Member NoteProperty BeforeHash ''
        if (-not (Test-Path -LiteralPath $p.Target)) { continue }
        $current=Get-AuroraHash $p.Target; $p.BeforeHash=$current
        if ($current -eq $p.Hash) { continue }
        $owned=@($Journal.Entries | Where-Object { $_.TargetPath -ieq $p.Target -and $_.Status -ne 'Restored' })
        if (-not $owned.Count) { throw "存在未受清单管理的同名文件，已保留：$($p.Target)" }
        $e=$owned[0]
        if ($current -ne $e.DeployedHash -and -not ($e.Status -eq 'Pending' -and $current -eq $e.BeforeHash)) { throw "用户或游戏修改过文件，已保留：$($p.Target)" }
        if ($e.BackupPath -and (Get-AuroraHash $e.BackupPath) -ne $e.OriginalHash) { throw '原始备份校验失败，未开始部署。' }
    }
}
function Save-AuroraInstallReport($Index,[string]$ReportPath) {
    $core=@(); $runtime=@()
    foreach ($target in @($Index.Targets)) {
        $j=Open-AuroraJournal $target.JournalPath $Index.GameRoot $target.Directory
        $core+=@($j.Entries)
    }
    foreach ($dir in @($Index.RuntimeOwners)) {
        $j=Open-AuroraJournal (Join-Path $dir 'OptiScaler\RuntimeSync\manifest.json') $Index.GameRoot $dir
        $runtime+=@($j.Entries)
    }
    $report=[pscustomobject]@{SchemaVersion=3;Status=$Index.Status;GameRoot=$Index.GameRoot;Targets=$Index.Targets;RuntimeGroups=$Index.RuntimeGroups;CoreFiles=$core;RuntimeFiles=$runtime;Notes=@('每份文件日志是事务恢复依据；本报告是快照。','SharedOrUnresolved 是待核对关联，不代表已观察到加载。','SL1 / 未知 Streamline 继续触发整个游戏的保守保护；源 SL2 必须匹配 RC2 固定 SHA256。')}
    Write-AuroraJson $ReportPath $report
    $txt=$report | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText([IO.Path]::ChangeExtension($ReportPath,'.txt'),"Aurora RC3 安装 / 恢复详细报告`r`n"+$txt,(New-Object Text.UTF8Encoding($true)))
}
function Invoke-AuroraRuntimeTask([string]$Mode,[string]$Root,[string]$Owner,[string]$LogPath,[string]$GameExe='',[switch]$CallerHasLock) {
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'runtime_sync.ps1'),'-Mode',$Mode,'-GameRoot',$Root,'-InstallDir',$Owner,'-RC3Safety')
    if ($CallerHasLock) { $args+='-CallerHasLock' }
    if ($GameExe) { $args+=@('-GameExe',$GameExe) }
    if ($Mode -ne 'Restore') { $args+=@('-ReportPath',([IO.Path]::ChangeExtension($LogPath,'.runtime.json'))) }
    & powershell.exe @args 2>&1 | Out-File -LiteralPath $LogPath -Encoding utf8 -Append
    if ($LASTEXITCODE) { throw "Runtime 操作未完成，文件与备份保留。详情：$LogPath" }
}
function Install-AuroraDeployment([string]$Root,[string]$PackageDir,[string]$Proxy,[string]$ReportPath) {
    Assert-AuroraGameRoot $Root
    $binary=Get-AuroraBinary (Join-Path $PackageDir 'OptiScaler.dll')
    if ($binary.Architecture -ne 'x64' -or $binary.OriginalFilename -ine 'OptiScaler.dll') { throw '发布包缺少可识别的 x64 OptiScaler.dll，请使用完整构建产物。' }
    $scan=Get-AuroraScan $Root
    if (-not $scan.Complete) { throw ($scan.Warnings -join "`n") }
    $candidates=@(Get-AuroraDeploymentCandidates $scan)
    if (-not $candidates.Count) { throw '未找到有渲染特征的 x64 游戏入口，未写入文件。' }
    $index=$null; $started=$false
    $prepared=@(); $lock=$null
    try {
        foreach ($candidate in $candidates) { Assert-AuroraGameClosed $Root $candidate.Path }
        $lock=Enter-AuroraLock $Root
        $index=Open-AuroraIndex $Root
        if (-not $index) { $index=[pscustomobject]@{SchemaVersion=3;GameRoot=$Root;Status='Pending';Targets=@();RuntimeOwners=@();RuntimeGroups=@();RuntimeJournalExpected=$false} }
        foreach ($group in @($candidates | Group-Object Directory)) {
            $dir=$group.Name
            $chosen=Get-AuroraRecommendedProxy @($group.Group) $Proxy
            $target=@($index.Targets | Where-Object { $_.Directory -ieq $dir })
            if ($target.Count) {
                $target=$target[0]
                if (-not $Proxy) { $chosen=$target.Proxy }
                if ($target.Proxy -ine $chosen -and $index.Status -ne 'Removed') { throw '更换 Proxy 前请先卸载当前版本。' }
                $target.Proxy=$chosen; $target.Executables=@($group.Group | ForEach-Object { $_.Path })
            } else {
                $metaPath=Join-Path $dir 'OptiScaler\AuroraSetup\installation.json'
                if (-not $Proxy -and (Test-Path -LiteralPath $metaPath)) {
                    Assert-AuroraPlainPath $metaPath
                    $meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ((Get-AuroraPath $meta.GameRoot) -ine $Root) { throw '旧安装记录的游戏目录不匹配。' }
                    if ($meta.Proxy -notin @('dxgi.dll','winmm.dll','version.dll','dbghelp.dll','d3d12.dll','wininet.dll','winhttp.dll','OptiScaler.asi')) { throw '旧安装记录的 Proxy 无效。' }
                    $chosen=$meta.Proxy
                }
                $target=[pscustomobject]@{Directory=$dir;Executables=@($group.Group | ForEach-Object { $_.Path });Proxy=$chosen;JournalPath=(Join-Path $dir 'OptiScaler\AuroraSetup\manifest.json')}
                $index.Targets+=@($target)
            }
            $journal=Open-AuroraJournal $target.JournalPath $Root $dir
            $target | Add-Member NoteProperty JournalExpected (Test-Path -LiteralPath $target.JournalPath -PathType Leaf) -Force
            $payload=@(New-AuroraPayload $PackageDir $dir $chosen)
            $prepared+=@([pscustomobject]@{Target=$target;Journal=$journal;Payload=$payload})
            Assert-AuroraPayloadReady $target $journal $payload
        }
        # Retain all historical owners, including RC2 records, so nothing loses its backup.
        $activeOwners=@()
        foreach ($target in @($index.Targets)) {
            $jp=Join-Path $target.Directory 'OptiScaler\RuntimeSync\manifest.json'
            if (Test-Path -LiteralPath $jp) {
                $legacy=Open-AuroraJournal $jp $Root $target.Directory
                if (@($legacy.Entries | Where-Object { $_.Status -ne 'Restored' }).Count) { $activeOwners+=@($target.Directory) }
            }
        }
        $index.RuntimeOwners=@($activeOwners | Sort-Object -Unique)
        if (-not $index.RuntimeOwners.Count) { $index.RuntimeOwners=@($prepared[0].Target.Directory) }
        if ($index.RuntimeOwners.Count -gt 1) { throw '发现多份旧 Runtime 恢复记录，请先从原安装位置恢复原版，再安装。' }
        $index.RuntimeGroups=@(Get-AuroraRuntimeGroups $scan $candidates)
        foreach ($target in @($index.Targets)) {
            $ids=@($index.RuntimeGroups | Where-Object { $g=$_; @($target.Executables | Where-Object { $g.CandidatePaths -icontains $_ }).Count } | ForEach-Object { $_.Id })
            $target | Add-Member NoteProperty RuntimeGroupIds $ids -Force
        }
        foreach ($candidate in $candidates) { Assert-AuroraGameClosed $Root $candidate.Path }
        $index.Status='Pending'; Write-AuroraJson (Get-AuroraIndexPath $Root) $index; $started=$true
        # Create every payload before activating any new Proxy; each copy is journaled.
        foreach ($p in $prepared) {
            Write-AuroraJson $p.Target.JournalPath $p.Journal
            $p.Target.JournalExpected=$true; Write-AuroraJson (Get-AuroraIndexPath $Root) $index
            Write-AuroraJson (Join-Path $p.Target.Directory 'OptiScaler\AuroraSetup\installation.json') ([pscustomobject]@{GameRoot=$Root;GameExe=$p.Target.Executables[0];Proxy=$p.Target.Proxy;RC3Manifest=(Get-AuroraIndexPath $Root)})
            foreach ($file in @($p.Payload | Select-Object -Skip 1)) {
                Assert-AuroraPlannedFile $file
                Install-AuroraFile $p.Journal $p.Target.JournalPath $file.Source $file.Target $file.Hash $file.BeforeHash 6>&1 | Out-File -LiteralPath ([IO.Path]::ChangeExtension($ReportPath,'.log.txt')) -Encoding utf8 -Append
            }
        }
        # One full-tree synchronization prevents different entries fighting over shared DLLs.
        # Recover pre-RC3 journals first only when explicitly requested by Remove/Restore;
        # multiple existing owners are kept read-only until that recovery is done.
        $runtimeJournalPath=Join-Path $index.RuntimeOwners[0] 'OptiScaler\RuntimeSync\manifest.json'
        $runtimeJournal=Open-AuroraJournal $runtimeJournalPath $Root $index.RuntimeOwners[0]
        Write-AuroraJson $runtimeJournalPath $runtimeJournal
        $index | Add-Member NoteProperty RuntimeJournalExpected $true -Force
        Write-AuroraJson (Get-AuroraIndexPath $Root) $index
        Invoke-AuroraRuntimeTask Install $Root $index.RuntimeOwners[0] ([IO.Path]::ChangeExtension($ReportPath,'.log.txt')) -CallerHasLock
        foreach ($p in $prepared) {
            $file=$p.Payload[0]; Assert-AuroraPlannedFile $file
            Install-AuroraFile $p.Journal $p.Target.JournalPath $file.Source $file.Target $file.Hash $file.BeforeHash 6>&1 | Out-File -LiteralPath ([IO.Path]::ChangeExtension($ReportPath,'.log.txt')) -Encoding utf8 -Append
        }
        $index.Status='Applied'; Write-AuroraJson (Get-AuroraIndexPath $Root) $index
        Save-AuroraInstallReport $index $ReportPath
        return $index
    } catch {
        $originalFailure=$_
        if ($started) {
            $index.Status='NeedsAttention'
            try { Write-AuroraJson (Get-AuroraIndexPath $Root) $index; Save-AuroraInstallReport $index $ReportPath }
            catch { Write-Warning '状态/报告写入也失败；保留原有 Pending 日志，不能视为安装成功。' }
        }
        throw $originalFailure
    } finally {
        if ($lock) { $lock.Dispose() }
        foreach ($p in $prepared) { foreach ($f in $p.Payload) {
            if ($f.Source -match '\\Aurora-[0-9a-f]{32}\.ini$' -and (Test-Path -LiteralPath $f.Source)) { Remove-Item -LiteralPath $f.Source -Force }
        } }
    }
}
function Assert-AuroraPlannedFile($File) {
    $current=''; if (Test-Path -LiteralPath $File.Target) { $current=Get-AuroraHash $File.Target }
    if ($current -ne $File.BeforeHash) { throw "文件在预检后变化，已停止：$($File.Target)" }
}
function Assert-AuroraCoreJournalScope($Journal) {
    $names=@('OptiScaler.dll','OptiScaler.ini','dxgi.dll','winmm.dll','version.dll','dbghelp.dll','d3d12.dll','wininet.dll','winhttp.dll','OptiScaler.asi','nvngx.dll_dlssnr.dll','LICENSE','READ ME - DLSS Neural Rendering.txt','Aurora_Common.ps1','Aurora_Installer.ps1','Aurora_RuntimeCatalog.ps1','Aurora_Diagnostics.ps1','Aurora_Setup.ps1','Aurora_Setup_Legacy.ps1','runtime_sync.ps1','Check_DLSS_Runtime.bat','Aurora_Setup.bat','Remove_Aurora.bat')
    foreach ($e in @($Journal.Entries)) {
        if (-not (Test-AuroraWithin $e.TargetPath $Journal.InstallDir)) { throw '核心日志目标不属于该入口目录。' }
        $rel=$e.TargetPath.Substring($Journal.InstallDir.Length).TrimStart('\')
        if ($rel -match '(?i)(^|\\)(AuroraSetup|RuntimeSync|_storage[^\\]*|\.git)(\\|$)') { throw '核心日志不得操作其他恢复记录。' }
        if ($rel -notin $names -and $rel -notmatch '(?i)^OptiScaler\\.+\.(dll|json|ini|txt|md|bin)$|^OptiScaler\\plugins\\OptiPatcher\.asi$|^Licenses\\[^\\]+$') { throw '核心日志指向非 Aurora payload 文件，保留现状。' }
    }
}
function Remove-AuroraDeployment($Index,[string]$ReportPath,[switch]$RuntimeOnly) {
    $root=$Index.GameRoot; $lock=$null; $preserved=@(); $started=$false
    try {
        foreach ($t in @($Index.Targets)) { foreach ($exe in @($t.Executables)) { Assert-AuroraGameClosed $root $exe } }
        $lock=Enter-AuroraLock $root
        $Index=Open-AuroraIndex $root
        if (-not $Index) { throw 'RC3 总清单已变化，停止恢复。' }
        $journals=@()
        foreach ($dir in @($Index.RuntimeOwners)) {
            $path=Join-Path $dir 'OptiScaler\RuntimeSync\manifest.json'
            if (-not (Test-Path -LiteralPath $path) -and (-not $Index.PSObject.Properties['RuntimeJournalExpected'] -or $Index.RuntimeJournalExpected)) { throw 'Runtime 日志缺失，不能证明原版恢复状态，保留文件。' }
            $journals+=@([pscustomobject]@{Path=$path;Journal=(Open-AuroraJournal $path $root $dir);Runtime=$true})
        }
        if (-not $RuntimeOnly) { foreach ($t in @($Index.Targets)) { $journals+=@([pscustomobject]@{Path=$t.JournalPath;Journal=(Open-AuroraJournal $t.JournalPath $root $t.Directory);Runtime=$false}) } }
        $ownership=@{}
        foreach ($pair in $journals) {
            if (-not $pair.Runtime) { Assert-AuroraCoreJournalScope $pair.Journal }
            foreach ($e in @($pair.Journal.Entries | Where-Object { $_.Status -ne 'Restored' })) {
                if ($ownership.ContainsKey($e.TargetPath)) { throw '不同日志对同一路径声明冲突 ownership，未恢复或删除任何文件。' }
                $ownership[$e.TargetPath]=$pair.Path
            }
        }
        # Validate every backup before removing any tool. Changed targets are individually retained.
        foreach ($pair in $journals) {
            foreach ($e in @($pair.Journal.Entries)) {
                if ($e.Status -in @('Restored','Preserved')) { if ($e.Status -eq 'Preserved') { $preserved+=@($e.TargetPath) }; continue }
                $current=''; if (Test-Path -LiteralPath $e.TargetPath) { $current=Get-AuroraHash $e.TargetPath }
                if ($current -ne $e.DeployedHash -and $current -ne $e.OriginalHash -and -not ($e.Status -eq 'Pending' -and $current -eq $e.BeforeHash)) {
                    $e.Status='Preserved'; $preserved+=@($e.TargetPath); continue
                }
                if ($current -ne $e.OriginalHash -and -not $e.Created -and (-not $e.BackupPath -or (Get-AuroraHash $e.BackupPath) -ne $e.OriginalHash)) { throw "备份校验失败，尚未删除文件：$($e.TargetPath)" }
            }
        }
        $previousStatus=$Index.Status
        $Index.Status='Pending'; Write-AuroraJson (Get-AuroraIndexPath $root) $Index; $started=$true
        foreach ($pair in $journals) {
            Write-AuroraJson $pair.Path $pair.Journal
            $events=@(Restore-AuroraJournal $pair.Journal $pair.Path 6>&1)
            $failures=@($events | Where-Object { $_ -is [int] })[-1]
            $events | Where-Object { $_ -isnot [int] } | Out-File -LiteralPath ([IO.Path]::ChangeExtension($ReportPath,'.log.txt')) -Encoding utf8 -Append
            if ($failures) { throw '恢复过程中发现文件变化；保留剩余文件和恢复工具，请查看详细报告。' }
        }
        if (-not $RuntimeOnly) { $Index.Status='Removed' } else { $Index.Status=$previousStatus }
        if ($preserved.Count) { $Index.Status='NeedsAttention' }
        # After explicit restoration, use a single owner on the next install.
        if ($RuntimeOnly -and -not $preserved.Count) { $Index.RuntimeOwners=@($Index.Targets[0].Directory) }
        Write-AuroraJson (Get-AuroraIndexPath $root) $Index
        Save-AuroraInstallReport $Index $ReportPath
        return @($preserved)
    } catch {
        $failure=$_
        if ($started) {
            $Index.Status='NeedsAttention'
            try { Write-AuroraJson (Get-AuroraIndexPath $root) $Index } catch { Write-Warning '恢复未完成，无法更新状态；请保留 Pending 清单与备份。' }
        }
        throw $failure
    } finally { if ($lock) { $lock.Dispose() } }
}
