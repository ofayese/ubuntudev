#!/usr/bin/env bash
set -euo pipefail

# Source utility modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh" 
source "$SCRIPT_DIR/util-install.sh"

# Initialize logging
init_logging
log_info "Installation validation started"

# Function to check if a command exists (using util-env.sh function)
check_command() {
    local cmd="$1"
    local description="$2"
    
    if command_exists "$cmd"; then
        log_success "$description ($cmd)"
        return 0
    else
        log_error "$description ($cmd) not found"
        return 1
    fi
}

# Function to check if a service is running
check_service() {
    local service="$1"
    local description="$2"
    
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        log_success "$description service is running"
        return 0
    else
        log_warning "$description service is not running"
        return 1
    fi
}

# Function to check Python packages (using util-install.sh function)
check_python_package() {
    local package="$1"
    
    if is_pip_installed "$package"; then
        log_success "Python package: $package"
        return 0
    else
        log_error "Python package: $package not found"
        return 1
    fi
}

# Function to check Node.js packages (using util-install.sh function)
check_node_package() {
    local package="$1"
    
    if is_npm_global_installed "$package"; then
        log_success "Node.js package: $package"
        return 0
    else
        log_error "Node.js package: $package not found"
        return 1
    fi
}

echo "🔍 Validating Ubuntu Development Environment Setup"
echo "================================================="

# Define validation steps for progress tracking
declare -a VALIDATION_STEPS=(
  "basic_tools"
  "modern_cli_tools"
  "language_runtimes"
  "development_tools"
  "container_tools"
  "dotnet_tools"
  "python_environment"
  "shell_environment"
)

current_step=0
total_steps=${#VALIDATION_STEPS[@]}

# Step 1: Check basic tools
((current_step++))
echo ""
echo "📋 [$current_step/$total_steps] Checking Basic Development Tools:"
show_progress "$current_step" "$total_steps" "Validation Progress"

basic_tools=("git" "curl" "wget" "vim" "tmux" "zsh")
for tool in "${basic_tools[@]}"; do
  check_command "$tool" "${tool^}"
done

# Step 2: Check modern CLI tools
((current_step++))
echo ""
echo "🛠️ [$current_step/$total_steps] Checking Modern CLI Tools:"
show_progress "$current_step" "$total_steps" "Validation Progress"

declare -A modern_tools=(
  ["bat"]="bat (cat replacement)"
  ["ripgrep"]="ripgrep (grep replacement)"
  ["fd"]="fd (find replacement)"
  ["fzf"]="fzf (fuzzy finder)"
  ["eza"]="eza (ls replacement)"
  ["duf"]="duf (df replacement)"
  ["dust"]="dust (du replacement)"
  ["starship"]="Starship prompt"
  ["zoxide"]="zoxide (cd replacement)"
)

for tool in "${!modern_tools[@]}"; do
  check_command "$tool" "${modern_tools[$tool]}"
done

# Step 3: Check language runtimes
((current_step++))
echo ""
echo "🌐 [$current_step/$total_steps] Checking Language Runtimes:"
show_progress "$current_step" "$total_steps" "Validation Progress"

language_tools=("node" "npm" "python" "pip" "pyenv" "nvm")

for tool in "${language_tools[@]}"; do
  check_command "$tool" "${tool^}"
done

# Step 4: Check development tools  
((current_step++))
echo ""
echo "💻 [$current_step/$total_steps] Checking Development Tools:"
show_progress "$current_step" "$total_steps" "Validation Progress"

# Check VS Code based on environment (using detect_environment function)
ENV_TYPE=$(detect_environment)
if [[ "$ENV_TYPE" == "$ENV_WSL" ]]; then
    # WSL2 environment - check for Windows VS Code installations
    log_info "WSL2 detected - checking for Windows VS Code installations..."
    if [ -f "/mnt/c/Program Files/Microsoft VS Code/bin/code.cmd" ]; then
        log_success "VS Code (Windows) is accessible from WSL2"
    else
        log_warning "VS Code (Windows) not found - install on Windows for WSL2 integration"
    fi
    
    if [ -f "/mnt/c/Program Files/Microsoft VS Code Insiders/bin/code-insiders.cmd" ]; then
        log_success "VS Code Insiders (Windows) is accessible from WSL2"
    else
        log_warning "VS Code Insiders (Windows) not found - install on Windows for WSL2 integration"
    fi
else
    # Desktop environment - check for local installations
    check_command "code" "VS Code"
    check_command "code-insiders" "VS Code Insiders"
fi

check_command "docker" "Docker"
check_command "gh" "GitHub CLI"

# Check container tools (using Docker functions from util-install.sh)
echo ""
echo "🐳 Checking Container Tools:"
check_command "docker" "Docker CLI"
if command_exists docker; then
    if check_docker >/dev/null 2>&1; then
        log_success "Docker daemon is accessible"
    else
        log_error "Docker daemon is not accessible"
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
    log_success ".zshrc exists"
    if grep -q "starship" "$HOME/.zshrc"; then
        log_success "Starship configured in .zshrc"
    else
        log_warning "Starship not configured in .zshrc"
    fi
else
    log_error ".zshrc not found"
fi

# Check Git configuration
echo ""
echo "🔧 Checking Git Configuration:"
if git config --global --get user.name >/dev/null 2>&1; then
    log_success "Git user.name configured: $(git config --global --get user.name)"
else
    log_error "Git user.name not configured"
fi

if git config --global --get user.email >/dev/null 2>&1; then
    log_success "Git user.email configured: $(git config --global --get user.email)"
else
    log_error "Git user.email not configured"
fi

# Check WSL-specific configuration (using detect_environment function)
if [[ "$ENV_TYPE" == "$ENV_WSL" ]]; then
    echo ""
    echo "🧠 Checking WSL Configuration:"
    
    if [ -f "/etc/wsl.conf" ]; then
        log_success "/etc/wsl.conf exists"
        if grep -q "systemd=true" /etc/wsl.conf; then
            log_success "systemd enabled in WSL"
        else
            log_warning "systemd not enabled in WSL"
        fi
    else
        log_error "/etc/wsl.conf not found"
    fi
    
    if is_systemd_running; then
        log_success "systemd is running"
    else
        log_error "systemd is not running"
    fi
fi

echo ""
echo "🎉 Validation complete!"
echo "📝 If you see any ❌ errors above, you may need to re-run the relevant setup scripts."
