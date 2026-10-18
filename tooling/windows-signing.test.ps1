$ErrorActionPreference = 'Stop'
$signingScript = Join-Path $PSScriptRoot 'windows-signing.ps1'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('sctv-signing-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $fixtureRoot
$thumbprint = 'A' * 40
$global:signingFixture = @{ imported = 0; removed = @(); hasPrivateKey = $true }

# Replace only certificate-store operations; file writes, environment output, and cleanup stay real.
function Import-PfxCertificate {
    param($FilePath, $CertStoreLocation, $Password, [switch]$Exportable)
    if ($CertStoreLocation -ne 'Cert:\CurrentUser\My' -or $Exportable) {
        throw 'Unexpected certificate import policy.'
    }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($FilePath)) -ne 'AQID' -or !$Password) {
        throw 'Invalid disposable certificate input.'
    }
    $global:signingFixture.imported++
    [pscustomobject]@{ Thumbprint = ('A' * 40); HasPrivateKey = $global:signingFixture.hasPrivateKey }
    if ($global:signingFixture.failAfterImport) { throw 'Fixture import failed after emitting an identity.' }
}

function Remove-Item {
    [CmdletBinding()]
    param([Alias('LiteralPath')][string]$Path, [switch]$Force)
    if ($Path.StartsWith('Cert:')) {
        $global:signingFixture.removed += $Path
        return
    }
    if ($Path.EndsWith('.pfx') -and $global:signingFixture.failFileCleanup) {
        throw 'Fixture certificate file cleanup failed.'
    }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $Path -Force:$Force -ErrorAction $ErrorActionPreference
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}

function Assert-Fails([scriptblock]$Action, [string]$ExpectedMessage = '') {
    $failed = $false
    try { & $Action } catch {
        $failed = $true
        if ($ExpectedMessage) {
            Assert-True ($_.Exception.Message -eq $ExpectedMessage) 'The original failure was replaced.'
        }
    }
    Assert-True $failed 'Expected signing preparation to fail.'
}

$environmentNames = @('RUNNER_TEMP', 'GITHUB_ENV', 'WINDOWS_CERTIFICATE', 'WINDOWS_CERTIFICATE_PASSWORD', 'DESKTOP_CERTIFICATE_THUMBPRINT')
$savedEnvironment = @{}
foreach ($name in $environmentNames) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name) }

try {
    $env:RUNNER_TEMP = $fixtureRoot
    $env:GITHUB_ENV = Join-Path $fixtureRoot 'github-env'
    $env:WINDOWS_CERTIFICATE = 'AQID'
    $env:WINDOWS_CERTIFICATE_PASSWORD = 'disposable-password'
    $env:DESKTOP_CERTIFICATE_THUMBPRINT = ''
    $configPath = Join-Path $fixtureRoot 'release.json'

    & $signingScript -Mode Prepare -ConfigPath $configPath

    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    Assert-True ($config.bundle.windows.certificateThumbprint -eq $thumbprint) 'Signing identity was not written.'
    Assert-True ($config.bundle.windows.digestAlgorithm -eq 'sha256') 'Signing digest changed.'
    Assert-True ($config.bundle.windows.timestampUrl -eq 'http://timestamp.digicert.com') 'Timestamp service changed.'
    Assert-True ((Get-Content -LiteralPath $env:GITHUB_ENV -Raw).Contains("DESKTOP_CERTIFICATE_THUMBPRINT=$thumbprint")) 'Cleanup identity was not published.'
    Assert-True (@(Get-ChildItem $fixtureRoot -Filter '*.pfx').Count -eq 0) 'Temporary certificate was retained.'

    $env:DESKTOP_CERTIFICATE_THUMBPRINT = $thumbprint
    & $signingScript -Mode Cleanup
    Assert-True ($global:signingFixture.removed -contains "Cert:\CurrentUser\My\$thumbprint") 'Build cleanup did not release the certificate.'

    $env:WINDOWS_CERTIFICATE_PASSWORD = ''
    Assert-Fails { & $signingScript -Mode Prepare -ConfigPath $configPath }
    Assert-True ($global:signingFixture.imported -eq 1) 'Missing credentials reached the certificate store.'
    $env:WINDOWS_CERTIFICATE_PASSWORD = 'disposable-password'

    $global:signingFixture.removed = @()
    $global:signingFixture.hasPrivateKey = $false
    Assert-Fails { & $signingScript -Mode Prepare -ConfigPath $configPath }
    Assert-True ($global:signingFixture.removed -contains "Cert:\CurrentUser\My\$thumbprint") 'An unusable imported certificate was not released.'
    Assert-True (@(Get-ChildItem $fixtureRoot -Filter '*.pfx').Count -eq 0) 'Failed setup retained a certificate file.'

    $global:signingFixture.removed = @()
    $global:signingFixture.hasPrivateKey = $true
    Assert-Fails { & $signingScript -Mode Prepare -ConfigPath (Join-Path $fixtureRoot 'missing/release.json') }
    Assert-True ($global:signingFixture.removed -contains "Cert:\CurrentUser\My\$thumbprint") 'Failed configuration write leaked a certificate.'

    $global:signingFixture.removed = @()
    $env:GITHUB_ENV = Join-Path $fixtureRoot 'missing/environment'
    Assert-Fails { & $signingScript -Mode Prepare -ConfigPath $configPath }
    Assert-True ($global:signingFixture.removed -contains "Cert:\CurrentUser\My\$thumbprint") 'Failed ownership publication leaked a certificate.'
    Assert-True (!(Test-Path -LiteralPath $configPath)) 'Failed ownership publication retained a signing config.'

    $global:signingFixture.hasPrivateKey = $false
    $global:signingFixture.failFileCleanup = $true
    Assert-Fails { & $signingScript -Mode Prepare -ConfigPath $configPath } 'Expected exactly one imported signing certificate with a private key.'

    $global:signingFixture.hasPrivateKey = $true
    $env:GITHUB_ENV = Join-Path $fixtureRoot 'github-env'
    Assert-Fails { & $signingScript -Mode Prepare -ConfigPath $configPath } 'Fixture certificate file cleanup failed.'

    $global:signingFixture.failFileCleanup = $false
    $global:signingFixture.hasPrivateKey = $true
    $global:signingFixture.removed = @()
    $global:signingFixture.failAfterImport = $true
    Assert-Fails { & $signingScript -Mode Prepare -ConfigPath $configPath } 'Fixture import failed after emitting an identity.'
    Assert-True ($global:signingFixture.removed -contains "Cert:\CurrentUser\My\$thumbprint") 'An identity emitted before import failure escaped rollback.'

    Write-Output 'Windows signing lifecycle checks passed.'
}
finally {
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
    Microsoft.PowerShell.Management\Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    Remove-Variable signingFixture -Scope Global
}
