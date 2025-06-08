#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-devtools.sh] Started at $(date) ==="

# --- SYSTEM MONITORING TOOLS ---
echo "📈 Installing system monitoring tools..."
sudo apt update
sudo apt install -y htop btop glances ncdu net-tools iftop

# --- MODERN UTILITIES ---
echo "🧰 Installing modern CLI utilities..."
sudo apt install -y bat ripgrep fd-find zoxide fzf tmux starship direnv flameshot syncthing dnsmasq

# Replace deprecated or archived tools
sudo apt install -y eza duf

# Add from GitHub: lsd, lazydocker, dust, bottom (btm)
echo "⬇️ Installing CLI enhancements from GitHub releases..."

# LSD (LS Deluxe)
curl -s https://api.github.com/repos/lsd-rs/lsd/releases/latest \
  | grep browser_download_url | grep 'amd64.deb' | cut -d '"' -f 4 \
  | wget -qi - -O /tmp/lsd.deb && sudo apt install -y /tmp/lsd.deb && rm /tmp/lsd.deb

# Dust (disk usage)
DUST_VER=$(curl -s https://api.github.com/repos/bootandy/dust/releases/latest | grep tag_name | cut -d '"' -f 4)
wget -qO /tmp/dust.deb "https://github.com/bootandy/dust/releases/download/${DUST_VER}/dust_${DUST_VER#v}_amd64.deb"
sudo apt install -y /tmp/dust.deb && rm /tmp/dust.deb

# Bottom (btm)
BTM_VER=$(curl -s https://api.github.com/repos/ClementTsang/bottom/releases/latest | grep tag_name | cut -d '"' -f 4)
wget -qO /tmp/btm.tar.gz "https://github.com/ClementTsang/bottom/releases/download/${BTM_VER}/bottom_${BTM_VER#v}_amd64.tar.gz"
tar -xf /tmp/btm.tar.gz -C /tmp btm && sudo install /tmp/btm /usr/local/bin/btm && rm /tmp/btm /tmp/btm.tar.gz

# Lazydocker
LD_VER=$(curl -s https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | grep tag_name | cut -d '"' -f 4)
wget -qO /tmp/lazydocker.tar.gz "https://github.com/jesseduffield/lazydocker/releases/download/${LD_VER}/lazydocker_${LD_VER#v}_Linux_x86_64.tar.gz"
tar -xf /tmp/lazydocker.tar.gz -C /tmp lazydocker && sudo install /tmp/lazydocker /usr/local/bin && rm /tmp/lazydocker /tmp/lazydocker.tar.gz

# --- ZSH + Oh-My-Zsh ---
echo "🐚 Installing ZSH and Oh-My-Zsh..."
sudo apt install -y zsh
RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Enhance .zshrc with modern tools
{
  echo ''
  echo '# Dev Tool Enhancements'
  echo '[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh'
  echo 'eval "$(starship init zsh)"'
  echo 'eval "$(zoxide init zsh)"'
  echo 'eval "$(direnv hook zsh)"'
} >> ~/.zshrc

# --- TMUX Plugin Manager ---
echo "🔗 Installing tmux plugin manager..."
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# --- GIT CONFIGURATION ---
echo "🛠 Configuring Git..."
git config --global user.name "Olaolu Fayese"
git config --global user.email "60392167+ofayese@users.noreply.github.com"
git config --global core.editor "code-insiders --wait"
git config --global pull.rebase false
git config --global init.defaultBranch main
git config --global commit.gpgsign false
git config --global core.excludesfile ~/.gitignore_global

# Add common ignores
echo ".DS_Store" >> ~/.gitignore_global
echo "node_modules" >> ~/.gitignore_global
echo "venv/" >> ~/.gitignore_global
echo "*.log" >> ~/.gitignore_global

echo "✅ Dev tools and shell environment successfully configured!"