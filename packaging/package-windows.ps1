# Packages the built game into a zip a friend without Qt can start:
# packaging/package-windows.ps1 <build dir> <out dir>
#
# Needs windeployqt of the Qt the game was built with on PATH, run from an
# MSVC developer shell (for the compiler runtime).
#
# Workaround: clay_app has no deploy step, so the game runs windeployqt
# itself. It waits on clayground#380, a packaging step in clay_app
# (see README, BUILD).
param([string]$Build, [string]$Out)
$ErrorActionPreference = "Stop"

$Build = (Resolve-Path $Build).Path
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = (Resolve-Path $Out).Path
$Src = (Resolve-Path "$PSScriptRoot\..").Path
$Pkg = "$Out\ShapesAndStone"

if (Test-Path $Pkg) { Remove-Item -Recurse -Force $Pkg }
New-Item -ItemType Directory $Pkg | Out-Null

# The game, Clayground's libraries and theirs (libdatachannel, ggml, ...)
# beside it, and Clayground's QML modules in qml\, where clay_app's main
# looks for them. The bench and test executables stay out.
Copy-Item "$Build\bin\shapes_and_stone.exe" $Pkg
Copy-Item "$Build\bin\*.dll" $Pkg
Copy-Item -Recurse "$Build\bin\qml" "$Pkg\qml"

# Qt itself, the Qt QML modules the game and Clayground import, and the
# compiler runtime. Clayground's libraries are named too: the game does not
# link them, so only that way their Qt (Multimedia and its FFmpeg, Widgets,
# Concurrent) comes along. The minimal platform is for the start check
# (QT_QPA_PLATFORM=minimal) on a machine without Qt.
$ClayLibs = Get-ChildItem "$Pkg\Clay*.dll" | ForEach-Object { $_.FullName }
windeployqt --release --qmldir "$Src\src" --qmlimport "$Pkg\qml" `
    --no-translations --compiler-runtime "$Pkg\shapes_and_stone.exe" @ClayLibs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$QtPlugins = (& qtpaths --query QT_INSTALL_PLUGINS)
Copy-Item "$QtPlugins\platforms\qminimal.dll" "$Pkg\platforms\"
# Every SQL driver comes along; the game needs only SQLite
# (Clayground.Storage), the others link to client libraries a friend lacks.
Get-ChildItem "$Pkg\sqldrivers\*.dll" -Exclude qsqlite.dll | Remove-Item

# libdatachannel links OpenSSL, which the build found outside Qt.
$Ssl = Get-Command libssl-3-x64.dll -ErrorAction SilentlyContinue
if (-not $Ssl) { $Ssl = Get-Item "C:\Program Files\OpenSSL*\bin\libssl-3-x64.dll" | Select-Object -First 1 }
$SslDir = Split-Path ($Ssl.Source ?? $Ssl.FullName)
Copy-Item "$SslDir\libssl-3-x64.dll", "$SslDir\libcrypto-3-x64.dll" $Pkg

# The compiler runtime beside the game, not as an installer to run first
$Redist = Get-ChildItem "$env:VCToolsRedistDir\x64\Microsoft.VC*.CRT" -Directory | Select-Object -First 1
Copy-Item "$($Redist.FullName)\*.dll" $Pkg
# ggml's OpenMP runtime
$OpenMP = Get-ChildItem "$env:VCToolsRedistDir\x64\Microsoft.VC*.OpenMP" -Directory | Select-Object -First 1
Copy-Item "$($OpenMP.FullName)\vcomp140.dll" $Pkg
Remove-Item "$Pkg\vc_redist*.exe" -ErrorAction SilentlyContinue

& "$PSScriptRoot\check-windows.ps1" $Pkg
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$Zip = "$Out\ShapesAndStone-windows-x64.zip"
if (Test-Path $Zip) { Remove-Item $Zip }
Compress-Archive -Path $Pkg -DestinationPath $Zip
Write-Output "packaged: $Zip"
