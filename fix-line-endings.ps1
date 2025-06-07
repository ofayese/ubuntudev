# This script ensures all shell scripts have Linux line endings
# Run with: powershell -ExecutionPolicy Bypass -File fix-line-endings.ps1

$files = @(
    "install.sh",
    "setup-desktop.sh",
    "setup-devcontainers.sh",
    "setup-devtools.sh",
    "setup-dotnet-ai.sh",
    "setup-npm.sh",
    "setup-node-python.sh",
    "setup-wsl.sh",
    "setup-vscode.sh"
)

foreach ($file in $files) {
    $content = Get-Content -Path $file -Raw
    $content = $content -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($file, $content)
    Write-Host "Fixed line endings for $file"
}

Write-Host "`nAll files prepared for Linux deployment"
Write-Host "Remember to make them executable with 'chmod +x *.sh' after copying to Linux"
