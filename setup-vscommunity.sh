#!/usr/bin/env bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-vscommunity.sh] Started at $(date) ==="

# --- Check if in WSL ---
if grep -qi microsoft /proc/version || grep -qi microsoft /proc/sys/kernel/osrelease; then
  echo "🧠 Running in WSL environment (Windows Subsystem for Linux)"
else
  echo "❌ Not in WSL. Visual Studio Community is only supported in Windows."
  exit 0
fi

# --- Check if winget is installed ---
echo "📦 Checking for winget..."
if ! powershell.exe -Command "Get-Command winget -ErrorAction SilentlyContinue" >/dev/null 2>&1; then
  echo "❌ winget is not available in your Windows environment. Please install App Installer from the Microsoft Store."
  exit 1
fi

# --- Check if Visual Studio Community is already installed ---
echo "🔍 Checking for existing installation of Visual Studio Community..."
if powershell.exe -Command "winget list --id Microsoft.VisualStudio.2022.Community | Select-String 'Visual Studio'" >/dev/null 2>&1; then
  echo "✅ Visual Studio Community 2022 is already installed. Skipping installation."
  exit 0
fi

# --- Install Visual Studio Community 2022 via winget ---
echo "⬇️ Installing Visual Studio Community 2022 using winget..."

powershell.exe -Command "winget install --exact --id Microsoft.VisualStudio.2022.Community --silent --accept-package-agreements --accept-source-agreements"

echo "✅ Visual Studio Community installation requested via winget. You can customize components via Visual Studio Installer GUI if needed."