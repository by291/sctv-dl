param(
    [Parameter(Mandatory)]
    [ValidateSet('Prepare', 'Cleanup')]
    [string]$Mode,
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot) 'src-tauri/tauri.release.conf.json')
)

$ErrorActionPreference = 'Stop'

# This script runs on a disposable CI runner; cleanup targets the identity imported by this job.
function Remove-SigningCertificate([string]$Thumbprint) {
    if ($Thumbprint) {
        Remove-Item "Cert:\CurrentUser\My\$Thumbprint" -Force
    }
}

function Initialize-WindowsSigning {
    if (!$env:WINDOWS_CERTIFICATE -or !$env:WINDOWS_CERTIFICATE_PASSWORD) {
        throw 'Windows signing credentials are required.'
    }
    if (!$env:RUNNER_TEMP -or !$env:GITHUB_ENV) {
        throw 'Runner temporary storage and environment output are required.'
    }

    $certificatePath = Join-Path $env:RUNNER_TEMP ('desktop-signing-' + [guid]::NewGuid().ToString('N') + '.pfx')
    $importedCertificates = [Collections.Generic.List[object]]::new()
    $writingConfig = $false
    $setupFailed = $false

    try {
        [IO.File]::WriteAllBytes($certificatePath, [Convert]::FromBase64String($env:WINDOWS_CERTIFICATE))
        $password = ConvertTo-SecureString $env:WINDOWS_CERTIFICATE_PASSWORD -AsPlainText -Force
        $importOptions = @{
            FilePath = $certificatePath
            CertStoreLocation = 'Cert:\CurrentUser\My'
            Password = $password
            Exportable = $false
        }
        # Retain each reported identity even if a later part of the import fails.
        Import-PfxCertificate @importOptions | ForEach-Object { $importedCertificates.Add($_) }
        if ($importedCertificates.Count -ne 1 -or !$importedCertificates[0].Thumbprint -or !$importedCertificates[0].HasPrivateKey) {
            throw 'Expected exactly one imported signing certificate with a private key.'
        }

        $thumbprint = $importedCertificates[0].Thumbprint
        $config = @{
            bundle = @{
                windows = @{
                    certificateThumbprint = $thumbprint
                    digestAlgorithm = 'sha256'
                    timestampUrl = 'http://timestamp.digicert.com'
                }
            }
        }

        $writingConfig = $true
        $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ConfigPath
        # Publish ownership only after setup succeeds; the workflow releases it after the build.
        "DESKTOP_CERTIFICATE_THUMBPRINT=$thumbprint" >> $env:GITHUB_ENV
    }
    catch {
        $setupFailed = $true
        # Setup can fail before GITHUB_ENV is published, so release locally owned certificates here.
        foreach ($certificate in $importedCertificates) {
            try { Remove-SigningCertificate $certificate.Thumbprint }
            catch { Write-Warning 'Failed to remove an imported signing certificate during rollback.' }
        }
        if ($writingConfig -and (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
            # Keep the setup error primary while attempting to remove a partial generated config.
            Remove-Item -LiteralPath $ConfigPath -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    finally {
        try {
            if (Test-Path -LiteralPath $certificatePath) {
                Remove-Item -LiteralPath $certificatePath -Force
            }
        }
        catch {
            if (!$setupFailed) { throw }
            # Report cleanup trouble without replacing the preparation failure already in flight.
            Write-Warning 'Failed to remove the temporary certificate file during rollback.'
        }
    }
}

if ($Mode -eq 'Prepare') {
    Initialize-WindowsSigning
}
else {
    Remove-SigningCertificate $env:DESKTOP_CERTIFICATE_THUMBPRINT
}
