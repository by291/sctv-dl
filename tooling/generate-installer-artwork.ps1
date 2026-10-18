$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$repositoryRoot = Split-Path $PSScriptRoot
$outputDirectory = Join-Path $repositoryRoot 'src-tauri/windows'
$generatedIconDirectory = Join-Path $repositoryRoot '.cache/installer-artwork'
# Tauri renders the vector at each ICO size so small shell icons remain legible.
Push-Location $repositoryRoot
try {
    & pnpm tauri icon (Join-Path $outputDirectory 'uninstaller.svg') --output $generatedIconDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Uninstaller icon generation failed.' }
    Copy-Item -LiteralPath (Join-Path $generatedIconDirectory 'icon.ico') -Destination (Join-Path $outputDirectory 'uninstaller.ico')
}
finally {
    Pop-Location
}

$icon = [Drawing.Image]::FromFile((Join-Path $repositoryRoot 'src-tauri/icons/icon.png'))
$headerFont = [Drawing.Font]::new('Segoe UI', 16, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$ink = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#252b30'))
$accent = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#dc4f41'))

try {
    foreach ($kind in @('sidebar', 'header')) {
        $width = if ($kind -eq 'sidebar') { 164 } else { 150 }
        $height = if ($kind -eq 'sidebar') { 314 } else { 57 }
        # MUI scales the artwork to the control. Keep enough pixels for high-DPI displays;
        # installer-ui.nsh renders sidebar lettering with native text controls.
        $bitmap = [Drawing.Bitmap]::new($width * 4, $height * 4, [Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.ScaleTransform(4, 4)
            $graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
            if ($kind -eq 'sidebar') {
                $graphics.Clear([Drawing.ColorTranslator]::FromHtml('#f7f2ef'))
                $graphics.DrawImage($icon, 38, 55, 88, 88)
                $graphics.FillRectangle($accent, 62, 256, 40, 3)
            }
            else {
                $graphics.Clear([Drawing.Color]::White)
                $graphics.DrawImage($icon, 8, 10, 36, 36)
                $graphics.DrawString('SCTV DL', $headerFont, $ink, 52, 18)
            }
            $bitmap.Save((Join-Path $outputDirectory "installer-$kind.bmp"), [Drawing.Imaging.ImageFormat]::Bmp)
        }
        finally {
            $graphics.Dispose()
            $bitmap.Dispose()
        }
    }
}
finally {
    foreach ($resource in @($icon, $headerFont, $ink, $accent)) { $resource.Dispose() }
}
