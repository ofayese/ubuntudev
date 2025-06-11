#!/bin/bash
set -euo pipefail

echo "=== [validate-installation.sh] Started at $(date) ==="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if a command exists
check_command() {
    local cmd="$1"
    local description="$2"
    
    if command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ $description ($cmd)${NC}"
        return 0
    else
        echo -e "${RED}❌ $description ($cmd) not found${NC}"
        return 1
    fi
}

# Function to check if a service is running
check_service() {
    local service="$1"
    local description="$2"
    
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo -e "${GREEN}✅ $description service is running${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️ $description service is not running${NC}"
        return 1
    fi
}

# Function to check Python packages
check_python_package() {
    local package="$1"
    
    if python -c "import $package" 2>/dev/null; then
        echo -e "${GREEN}✅ Python package: $package${NC}"
        return 0
    else
        echo -e "${RED}❌ Python package: $package not found${NC}"
        return 1
    fi
}

# Function to check Node.js packages
check_node_package() {
    local package="$1"
    
    if npm list -g "$package" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Node.js package: $package${NC}"
        return 0
    else
        echo -e "${RED}❌ Node.js package: $package not found${NC}"
        return 1
    fi
}

echo "🔍 Validating Ubuntu Development Environment Setup"
echo "================================================="

# Check basic tools
echo "📋 Checking Basic Development Tools:"
check_command "git" "Git"
check_command "curl" "cURL"
check_command "wget" "wget"
check_command "vim" "Vim"
check_command "tmux" "tmux"
check_command "zsh" "Zsh"

# Check modern CLI tools
echo ""
echo "🛠️ Checking Modern CLI Tools:"
check_command "bat" "bat (cat replacement)"
check_command "ripgrep" "ripgrep (grep replacement)"
check_command "fd" "fd (find replacement)"
check_command "fzf" "fzf (fuzzy finder)"
check_command "eza" "eza (ls replacement)"
check_command "duf" "duf (df replacement)"
check_command "dust" "dust (du replacement)"
check_command "starship" "Starship prompt"
check_command "zoxide" "zoxide (cd replacement)"

# Check language runtimes
echo ""
echo "🌐 Checking Language Runtimes:"
check_command "node" "Node.js"
check_command "npm" "npm"
check_command "python" "Python"
check_command "pip" "pip"
check_command "pyenv" "pyenv"
check_command "nvm" "nvm"

# Check development tools
echo ""
echo "💻 Checking Development Tools:"

# Check VS Code based on environment
if grep -qi microsoft /proc/version 2>/dev/null; then
    # WSL2 environment - check for Windows VS Code installations
    echo "🔍 WSL2 detected - checking for Windows VS Code installations..."
    if [ -f "/mnt/c/Program Files/Microsoft VS Code/bin/code.cmd" ]; then
        echo -e "${GREEN}✅ VS Code (Windows) is accessible from WSL2${NC}"
    else
        echo -e "${YELLOW}⚠️ VS Code (Windows) not found - install on Windows for WSL2 integration${NC}"
    fi
    
    if [ -f "/mnt/c/Program Files/Microsoft VS Code Insiders/bin/code-insiders.cmd" ]; then
        echo -e "${GREEN}✅ VS Code Insiders (Windows) is accessible from WSL2${NC}"
    else
        echo -e "${YELLOW}⚠️ VS Code Insiders (Windows) not found - install on Windows for WSL2 integration${NC}"
    fi
else
    # Desktop environment - check for local installations
    check_command "code" "VS Code"
    check_command "code-insiders" "VS Code Insiders"
fi

check_command "docker" "Docker"
check_command "gh" "GitHub CLI"

# Check container tools
echo ""
echo "🐳 Checking Container Tools:"
check_command "docker" "Docker CLI"
if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Docker daemon is accessible${NC}"
    else
        echo -e "${RED}❌ Docker daemon is not accessible${NC}"
    fi
fi

# Check .NET tools
echo ""
echo "🔷 Checking .NET Tools:"
check_command "dotnet" ".NET SDK"
check_command "pwsh" "PowerShell"

# Check Python environment
echo ""
echo "🐍 Checking Python Environment:"
if command -v python >/dev/null 2>&1; then
    echo "Python version: $(python --version)"
    echo "Python path: $(which python)"
    
    # Check common Python packages
    check_python_package "pip"
    check_python_package "numpy" || true
    check_python_package "pandas" || true
fi

# Check Node.js environment
echo ""
echo "📦 Checking Node.js Environment:"
if command -v node >/dev/null 2>&1; then
    echo "Node.js version: $(node --version)"
    echo "npm version: $(npm --version)"
    
    # Check common global packages
    check_node_package "typescript" || true
    check_node_package "eslint" || true
    check_node_package "prettier" || true
fi

# Check shell configuration
echo ""
echo "🐚 Checking Shell Configuration:"
if [ -f "$HOME/.zshrc" ]; then
    echo -e "${GREEN}✅ .zshrc exists${NC}"
    if grep -q "starship" "$HOME/.zshrc"; then
        echo -e "${GREEN}✅ Starship configured in .zshrc${NC}"
    else
        echo -e "${YELLOW}⚠️ Starship not configured in .zshrc${NC}"
    fi
else
    echo -e "${RED}❌ .zshrc not found${NC}"
fi

# Check Git configuration
echo ""
echo "🔧 Checking Git Configuration:"
if git config --global --get user.name >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Git user.name configured: $(git config --global --get user.name)${NC}"
else
    echo -e "${RED}❌ Git user.name not configured${NC}"
fi

if git config --global --get user.email >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Git user.email configured: $(git config --global --get user.email)${NC}"
else
    echo -e "${RED}❌ Git user.email not configured${NC}"
fi

# Check WSL-specific configuration
if grep -qi microsoft /proc/version 2>/dev/null; then
    echo ""
    echo "🧠 Checking WSL Configuration:"
    
    if [ -f "/etc/wsl.conf" ]; then
        echo -e "${GREEN}✅ /etc/wsl.conf exists${NC}"
        if grep -q "systemd=true" /etc/wsl.conf; then
            echo -e "${GREEN}✅ systemd enabled in WSL${NC}"
        else
            echo -e "${YELLOW}⚠️ systemd not enabled in WSL${NC}"
        fi
    else
        echo -e "${RED}❌ /etc/wsl.conf not found${NC}"
    fi
    
    if pidof systemd >/dev/null 2>&1; then
        echo -e "${GREEN}✅ systemd is running${NC}"
    else
        echo -e "${RED}❌ systemd is not running${NC}"
    fi
fi

echo ""
echo "🎉 Validation complete!"
echo "📝 If you see any ❌ errors above, you may need to re-run the relevant setup scripts."
