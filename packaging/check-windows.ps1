# Fails when a DLL or executable of the package imports a DLL that is
# neither in the package nor part of Windows: packaging/check-windows.ps1 <dir>
#
# Needs dumpbin (an MSVC developer shell). Part of Windows means in
# System32, except the compiler runtime, which a build machine has there
# and a friend's machine may not. Prints each offender and exits with their
# number.
param([string]$Dir)

$Dir = (Resolve-Path $Dir).Path
$System = "$env:SystemRoot\System32"
$Runtime = '^(vcruntime|msvcp|vcomp|concrt)'
$Have = @{}
Get-ChildItem $Dir -Recurse -Include *.dll, *.exe | ForEach-Object { $Have[$_.Name.ToLower()] = $true }

$Offenders = @()
$Count = 0
foreach ($f in Get-ChildItem $Dir -Recurse -Include *.dll, *.exe) {
    $Count++
    $Deps = dumpbin /nologo /dependents $f.FullName |
        Where-Object { $_ -match '^\s+(\S+\.dll)\s*$' } | ForEach-Object { $Matches[1].ToLower() }
    foreach ($d in $Deps) {
        if ($Have[$d]) { continue }
        if ($d -match '^(api|ext)-ms-') { continue }
        if (($d -notmatch $Runtime) -and (Test-Path "$System\$d")) { continue }
        $Offenders += "$($f.FullName.Substring($Dir.Length + 1)) imports $d"
    }
}
$Offenders | ForEach-Object { Write-Output "FAIL $_" }
Write-Output "$Count binaries, $($Offenders.Count) import from outside the package"
exit $Offenders.Count
