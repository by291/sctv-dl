param([string]$NsisDirectory = (Join-Path $env:LOCALAPPDATA 'tauri/NSIS'))

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot
$compiler = Join-Path $NsisDirectory 'makensis.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    throw 'NSIS is unavailable. Build the Windows installer first, or pass -NsisDirectory.'
}

$testId = [guid]::NewGuid().ToString('N')
$fixtureRoot = Join-Path $repositoryRoot ".cache/installer-tests/$testId"
$null = New-Item -ItemType Directory -Path $fixtureRoot -Force
try {
    $linkTarget = Join-Path $fixtureRoot 'linked-data'
    $null = New-Item -ItemType Directory -Path $linkTarget -Force
    Set-Content -LiteralPath (Join-Path $linkTarget 'keep.json') -Value 'unrelated data'
    $null = New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'profile') -Force
    $null = New-Item -ItemType Junction -Path (Join-Path $fixtureRoot 'profile/linked') -Target $linkTarget
    & $compiler /V2 "/DTEST_ID=$testId" "/DTEST_OUTPUT=$fixtureRoot" (Join-Path $repositoryRoot 'src-tauri/windows/tests/cleanup.nsi')
    if ($LASTEXITCODE -ne 0) { throw 'NSIS regression fixture compilation failed.' }

    $process = Start-Process -FilePath (Join-Path $fixtureRoot 'cleanup-check.exe') -WindowStyle Hidden -Wait -PassThru
    Get-Content -LiteralPath (Join-Path $fixtureRoot 'cleanup-result.txt')
    if ($process.ExitCode -ne 0) { throw 'NSIS cleanup regression failed.' }
}
finally {
    # Delete only this invocation's disposable files and registry subtree.
    $resolved = (Resolve-Path -LiteralPath $fixtureRoot).Path
    $expectedRoot = [IO.Path]::GetFullPath((Join-Path $repositoryRoot '.cache/installer-tests'))
    if (-not $resolved.StartsWith($expectedRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Fixture path escaped the installer-test directory.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
    $registryPath = "HKCU:/Software/SctvInstallerTests/$testId"
    if (Test-Path -LiteralPath $registryPath) { Remove-Item -LiteralPath $registryPath -Recurse -Force }
}
