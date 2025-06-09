#!/bin/bash
set -euo pipefail

echo "=== [check-prerequisites.sh] Prerequisites Check Started at $(date) ==="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PREREQUISITES_MET=true

# Check if running as root (not recommended)
if [[ $EUID -eq 0 ]]; then
   echo -e "${YELLOW}⚠️ Running as root is not recommended. Please run as a regular user with sudo privileges.${NC}"
fi

# Check for sudo privileges
if ! sudo -n true 2>/dev/null; then
    echo -e "${YELLOW}⚠️ sudo privileges are required for package installation${NC}"
    if ! sudo -v; then
        echo -e "${RED}❌ Failed to obtain sudo privileges${NC}"
        PREREQUISITES_MET=false
    fi
fi

# Check internet connectivity
echo "🌐 Checking internet connectivity..."
if ping -c 1 google.com >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Internet connectivity confirmed${NC}"
else
    echo -e "${RED}❌ No internet connectivity - required for package downloads${NC}"
    PREREQUISITES_MET=false
fi

# Check Ubuntu version
echo "🐧 Checking Ubuntu version..."
if [ -f /etc/os-release ]; then
    source /etc/os-release
    if [[ "$ID" == "ubuntu" ]]; then
        echo -e "${GREEN}✅ Ubuntu $VERSION_ID detected${NC}"
        
        # Check if version is supported (20.04+)
        VERSION_MAJOR=$(echo "$VERSION_ID" | cut -d. -f1)
        VERSION_MINOR=$(echo "$VERSION_ID" | cut -d. -f2)
        
        if [[ $VERSION_MAJOR -gt 20 ]] || [[ $VERSION_MAJOR -eq 20 && $VERSION_MINOR -ge 4 ]]; then
            echo -e "${GREEN}✅ Ubuntu version is supported${NC}"
        else
            echo -e "${YELLOW}⚠️ Ubuntu $VERSION_ID may not be fully supported (recommended: 20.04+)${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️ Non-Ubuntu distribution detected: $ID${NC}"
        echo -e "${YELLOW}   Scripts are designed for Ubuntu but may work on Debian-based distributions${NC}"
    fi
else
    echo -e "${RED}❌ Cannot determine OS version${NC}"
    PREREQUISITES_MET=false
fi

# Check available disk space (minimum 5GB recommended)
echo "💾 Checking available disk space..."
AVAILABLE_SPACE_KB=$(df / | awk 'NR==2 {print $4}')
AVAILABLE_SPACE_GB=$((AVAILABLE_SPACE_KB / 1024 / 1024))

if [[ $AVAILABLE_SPACE_GB -ge 5 ]]; then
    echo -e "${GREEN}✅ Sufficient disk space available: ${AVAILABLE_SPACE_GB}GB${NC}"
else
    echo -e "${YELLOW}⚠️ Low disk space: ${AVAILABLE_SPACE_GB}GB available (5GB+ recommended)${NC}"
fi

# Check for essential commands
echo "🔧 Checking essential commands..."
ESSENTIAL_COMMANDS=("curl" "wget" "git" "sudo")

for cmd in "${ESSENTIAL_COMMANDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ $cmd is available${NC}"
    else
        echo -e "${RED}❌ $cmd is not available${NC}"
        PREREQUISITES_MET=false
    fi
done

# Check if apt can be updated
echo "📦 Testing apt update..."
if sudo apt update >/dev/null 2>&1; then
    echo -e "${GREEN}✅ apt update successful${NC}"
else
    echo -e "${RED}❌ apt update failed - check network and repository configuration${NC}"
    PREREQUISITES_MET=false
fi

# Environment detection
echo "🔍 Environment detection..."
if grep -qi microsoft /proc/version 2>/dev/null; then
    echo -e "${GREEN}✅ WSL environment detected${NC}"
    
    # Check if systemd is enabled in WSL2
    if grep -qi "microsoft-standard" /proc/sys/kernel/osrelease 2>/dev/null; then
        echo -e "${GREEN}✅ WSL2 environment confirmed${NC}"
        
        if ! pidof systemd >/dev/null 2>&1; then
            echo -e "${YELLOW}⚠️ systemd is not running - add 'systemd=true' to /etc/wsl.conf and restart WSL${NC}"
        else
            echo -e "${GREEN}✅ systemd is running${NC}"
        fi
    fi
elif command -v gnome-shell >/dev/null 2>&1 && echo "${XDG_SESSION_TYPE:-}" | grep -qE 'x11|wayland' >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Desktop environment detected${NC}"
else
    echo -e "${GREEN}✅ Headless environment detected${NC}"
fi

# Final summary
echo ""
echo "📊 Prerequisites Check Summary:"
if $PREREQUISITES_MET; then
    echo -e "${GREEN}✅ All prerequisites met! You can proceed with installation.${NC}"
    exit 0
else
    echo -e "${RED}❌ Some prerequisites are not met. Please address the issues above before proceeding.${NC}"
    exit 1
fi
