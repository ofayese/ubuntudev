#!/bin/bash
set -euo pipefail

# Set non-interactive environment for apt
export DEBIAN_FRONTEND=noninteractive

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-devtools.sh] Started at $(date) ==="

# Function to safely download and install from GitHub releases
install_from_github() {
    local repo="$1"
    local pattern="$2"
    local install_cmd="$3"
    local name="$4"
    
    echo "📦 Installing $name from $repo..."
    
    local version
    if ! version=$(curl -s "https://api.github.com/repos/$repo/releases/latest" | grep tag_name | cut -d '"' -f 4); then
        echo "⚠️ Failed to fetch version for $name, skipping..."
        return 1
    fi
    
    if [ -z "$version" ]; then
        echo "⚠️ Empty version for $name, skipping..."
        return 1
    fi
    
    local download_url
    download_url=$(curl -s "https://api.github.com/repos/$repo/releases/latest" | grep browser_download_url | grep "$pattern" | head -1 | cut -d '"' -f 4)
    
    if [ -z "$download_url" ]; then
        echo "⚠️ No download URL found for $name with pattern $pattern, skipping..."
        return 1
    fi
    
    local temp_file="/tmp/${name}_$(basename "$download_url")"
    
    if wget -q -O "$temp_file" "$download_url"; then
        # Create a temporary directory for extraction to avoid conflicts (only for tar files)
        local temp_dir="/tmp/${name}_extract_$$"
        
        if [[ "$temp_file" == *.tar.gz ]] || [[ "$temp_file" == *.tgz ]]; then
            mkdir -p "$temp_dir"
            if eval "$install_cmd '$temp_file' '$temp_dir'"; then
                echo "✅ $name installed successfully"
                rm -f "$temp_file"
                rm -rf "$temp_dir"
                return 0
            else
                echo "⚠️ Failed to install $name"
                rm -f "$temp_file"
                rm -rf "$temp_dir"
                return 1
            fi
        else
            # For .deb files, don't use temp_dir
            if eval "$install_cmd '$temp_file'"; then
                echo "✅ $name installed successfully"
                rm -f "$temp_file"
                return 0
            else
                echo "⚠️ Failed to install $name"
                rm -f "$temp_file"
                return 1
            fi
        fi
    else
        echo "⚠️ Failed to download $name"
        rm -f "$temp_file"
        return 1
    fi
}

# Function to safely install apt packages
safe_apt_install() {
    local packages=("$@")
    local failed_packages=()
    
    for pkg in "${packages[@]}"; do
        if sudo apt install -y "$pkg" 2>/dev/null; then
            echo "✅ Installed $pkg"
        else
            echo "⚠️ Could not install $pkg - may not be available in this Ubuntu version"
            failed_packages+=("$pkg")
        fi
    done
    
    if [ ${#failed_packages[@]} -gt 0 ]; then
        echo "📋 Failed to install: ${failed_packages[*]}"
    fi
}

# --- SYSTEM MONITORING TOOLS ---
echo "📈 Installing system monitoring tools..."
sudo apt update
safe_apt_install htop btop glances ncdu net-tools iftop

# --- MODERN UTILITIES ---
echo "🧰 Installing modern CLI utilities..."
# Install packages that are definitely available in Ubuntu repositories
safe_apt_install bat ripgrep fd-find fzf tmux direnv

# Try to install additional packages that might not be available
safe_apt_install zoxide flameshot syncthing dnsmasq

# Install starship from official installer
echo "🚀 Installing Starship prompt..."
if curl -sS https://starship.rs/install.sh | sh -s -- --yes; then
    echo "✅ Starship installed successfully"
else
    echo "⚠️ Starship installation failed, continuing..."
fi

# Install modern CLI tools from GitHub
install_from_github "eza-community/eza" "x86_64-unknown-linux-gnu.tar.gz" \
    "tar -xf \$1 -C \$2 && find \$2 -name 'eza' -type f | xargs sudo install -m 755 -D -t /usr/local/bin" "eza"

install_from_github "muesli/duf" "linux_amd64.deb" \
    "sudo apt install -y \$1" "duf"

install_from_github "lsd-rs/lsd" "amd64.deb" \
    "sudo apt install -y \$1" "lsd"

install_from_github "bootandy/dust" "amd64.deb" \
    "sudo apt install -y \$1" "dust"

install_from_github "ClementTsang/bottom" "amd64.tar.gz" \
    "tar -xf \$1 -C \$2 --strip-components=1 && sudo install \$2/btm /usr/local/bin/btm" "bottom"

install_from_github "jesseduffield/lazydocker" "Linux_x86_64.tar.gz" \
    "tar -xf \$1 -C \$2 --strip-components=1 && sudo install \$2/lazydocker /usr/local/bin" "lazydocker"

# --- ZSH + Oh-My-Zsh ---
echo "🐚 Installing ZSH and Oh-My-Zsh..."
safe_apt_install zsh

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || echo "⚠️ Oh-My-Zsh installation failed"
fi

# Enhance .zshrc with modern tools (only if not already present)
if [ -f "$HOME/.zshrc" ] && ! grep -q "Dev Tool Enhancements" "$HOME/.zshrc"; then
    {
        echo ''
        echo '# Dev Tool Enhancements'
        echo '[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh'
        echo 'command -v starship >/dev/null && eval "$(starship init zsh)"'
        echo 'command -v zoxide >/dev/null && eval "$(zoxide init zsh)"'
        echo 'command -v direnv >/dev/null && eval "$(direnv hook zsh)"'
    } >> ~/.zshrc
fi

# --- TMUX Plugin Manager ---
echo "🔗 Installing tmux plugin manager..."
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm || echo "⚠️ Failed to install tmux plugin manager"
fi

# --- GIT CONFIGURATION ---
echo "🛠 Configuring Git..."
git config --global user.name "Olaolu Fayese" || true
git config --global user.email "60392167+ofayese@users.noreply.github.com" || true
git config --global core.editor "code-insiders --wait" || true
git config --global pull.rebase false || true
git config --global init.defaultBranch main || true
git config --global commit.gpgsign false || true
git config --global core.excludesfile ~/.gitignore_global || true

# Add common ignores (only if file doesn't exist)
if [ ! -f ~/.gitignore_global ]; then
    {
        echo ".DS_Store"
        echo "node_modules"
        echo "venv/"
        echo "*.log"
        echo ".env"
        echo "*.tmp"
        echo "*.temp"
    } > ~/.gitignore_global
fi

echo "✅ Dev tools and shell environment successfully configured!"
echo "🔄 Restart your terminal or run 'source ~/.zshrc' to apply changes."
