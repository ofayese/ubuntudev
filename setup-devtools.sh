#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-devtools.sh] Started at $(date) ==="

# --- SYSTEM MONITORING ---
sudo apt install -y htop btop glances ncdu net-tools iftop

# --- MODERN UTILITIES ---
sudo apt install -y bat ripgrep exa fd-find zoxide fzf tmux starship direnv flameshot syncthing dnsmasq

# --- ZSH & ENHANCEMENTS ---
sudo apt install -y zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
echo "[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh" >> ~/.zshrc
echo 'eval "$(starship init zsh)"' >> ~/.zshrc
echo 'eval "$(zoxide init zsh)"' >> ~/.zshrc
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc

# --- TMUX PLUGIN MANAGER ---
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# --- GIT CONFIGURATION ---
git config --global core.editor "vim"
git config --global pull.rebase false
git config --global init.defaultBranch main
git config --global commit.gpgsign false
echo ".DS_Store" >> ~/.gitignore_global
git config --global core.excludesfile ~/.gitignore_global

