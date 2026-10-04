# Starts a packaged game the way a friend's machine would and fails if it
# does not come up: packaging/start-check.ps1 <executable>
#
# PATH holds only Windows itself and no Qt variable is set, so the game has
# only what its package carries. QT_QPA_PLATFORM=minimal is clay_app's start
# check: any QML warning while Main.qml and the title load exits 1, else
# Main.qml quits with 0. A missing DLL exits with 0xC0000135.
param([string]$Exe)

$env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
foreach ($v in "QT_PLUGIN_PATH", "QML_IMPORT_PATH", "QML2_IMPORT_PATH", "QT_QPA_PLATFORM_PLUGIN_PATH") {
    Remove-Item "Env:$v" -ErrorAction SilentlyContinue
}
$env:QT_QPA_PLATFORM = "minimal"
$env:QT_FORCE_STDERR_LOGGING = "1"

$log = New-TemporaryFile
$p = Start-Process -FilePath $Exe -Wait -PassThru -NoNewWindow `
    -RedirectStandardError $log.FullName -RedirectStandardOutput "$($log.FullName).out"
Get-Content $log.FullName, "$($log.FullName).out"
Write-Output ("exit code: {0} (0x{0:X8})" -f $p.ExitCode)
exit $p.ExitCode
