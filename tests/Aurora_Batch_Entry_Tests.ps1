param([string]$ScratchRoot=(Join-Path $env:TEMP ('AuroraBatch-'+[Guid]::NewGuid().ToString('N'))))
. (Join-Path $PSScriptRoot 'Aurora_Hardening_TestSupport.ps1')
foreach ($wrapper in @('Aurora_Setup.bat','Remove_Aurora.bat')) {
    foreach ($expected in @(0,4)) {
        $dir=Join-Path $ScratchRoot ("入口 [中文] ! & $wrapper $expected")
        [IO.Directory]::CreateDirectory($dir) | Out-Null
        $path=Join-Path $dir $wrapper; [IO.File]::Copy((Join-Path $toolsDir $wrapper),$path)
        $fake=@'
param([string]$Action,[string]$InstallDir)
Remove-Item -LiteralPath (Join-Path $PSScriptRoot '__WRAPPER__')
exit __CODE__
'@
        Put (Join-Path $dir 'Aurora_Setup.ps1') $fake.Replace('__WRAPPER__',$wrapper).Replace('__CODE__',[string]$expected)
        $psi=New-Object Diagnostics.ProcessStartInfo
        $psi.FileName=$env:ComSpec; $psi.Arguments='/d /c ""'+$path+'""'; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
        $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
        $process=[Diagnostics.Process]::Start($psi); $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Wrapper test timed out.' }
        Assert ($process.ExitCode -eq $expected) "$wrapper propagates exit $expected after self-removal"
        Assert (-not (Test-Path -LiteralPath $path)) "$wrapper fixture actually removed its entry file"
        Assert (-not $stderr.Result -and -not $stdout.Result) "$wrapper produces no missing-BAT error"
        $process.Dispose()
    }
}
Finish 'BATCH ENTRY'
