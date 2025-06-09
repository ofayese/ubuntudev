#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-terminal-enhancements.sh] Started at $(date) ==="

# --- Install Alacritty + Fonts ---
echo "🖥️ Installing Alacritty + JetBrains Mono..."

# Try to add the PPA, but don't fail if it doesn't work
if sudo add-apt-repository -y ppa:aslatter/ppa 2>/dev/null; then
    echo "✅ Added Alacritty PPA"
else
    echo "⚠️ Could not add Alacritty PPA, trying from default repos..."
fi

sudo apt update || echo "⚠️ apt update failed, continuing..."

# Install packages with error handling
packages_to_install=(fonts-jetbrains-mono fonts-firacode neofetch)
optional_packages=(alacritty)

for pkg in "${packages_to_install[@]}"; do
    if sudo apt install -y "$pkg" 2>/dev/null; then
        echo "✅ Installed $pkg"
    else
        echo "⚠️ Could not install $pkg"
    fi
done

for pkg in "${optional_packages[@]}"; do
    if sudo apt install -y "$pkg" 2>/dev/null; then
        echo "✅ Installed $pkg"
    else
        echo "⚠️ Could not install $pkg, may not be available"
    fi
done

mkdir -p ~/.config/alacritty
cat > ~/.config/alacritty/alacritty.toml <<'EOF'
[shell]
program = "tmux"

[font]
normal.family = "JetBrains Mono"
size = 13

[window]
padding = { x = 10, y = 10 }
decorations = "full"

[scrolling]
history = 10000
multiplier = 3

[colors.primary]
background = "#1e1e2e"
foreground = "#cdd6f4"

[colors.normal]
black   = "#1e1e2e"
red     = "#f38ba8"
green   = "#a6e3a1"
yellow  = "#f9e2af"
blue    = "#89b4fa"
magenta = "#f5c2e7"
cyan    = "#94e2d5"
white   = "#cdd6f4"

[colors.bright]
black   = "#45475a"
red     = "#f38ba8"
green   = "#a6e3a1"
yellow  = "#f9e2af"
blue    = "#89b4fa"
magenta = "#f5c2e7"
cyan    = "#94e2d5"
white   = "#bac2de"
EOF

# --- Tmux Config ---
cat > ~/.tmux.conf <<'EOF'
set -g mouse on
set -g history-limit 100000
set-option -g allow-rename off
set-option -g status-interval 2
set-option -g default-terminal "screen-256color"
bind r source-file ~/.tmux.conf \; display-message "Reloaded!"

setw -g mode-keys vi
set -g status-left "#[fg=green]#H"
set -g status-right "#[fg=cyan]%Y-%m-%d #[fg=white]%H:%M:%S "

bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "xclip -sel clip -i"
EOF

# --- Starship Configuration ---
mkdir -p ~/.config
cat > ~/.config/starship.toml <<'EOF'
add_newline = false

[character]
success_symbol = "[➜](bold green)"
error_symbol = "[✗](bold red)"

[git_branch]
symbol = "🌱 "

[directory]
truncate_to_repo = false

[package]
disabled = true

[hostname]
ssh_only = false
format = "on [$hostname](bold blue) "

[username]
format = "[$user]($style) "
style_user = "bold yellow"
style_root = "bold red"

[docker_context]
symbol = "🐳 "

[cmd_duration]
min_time = 1000
format = "took [$duration](bold yellow)"
EOF

# --- Shell Enhancements ---
ENV_BANNER_FUNC='
# 🧠 Terminal Env Banner + Starship
__show_env_banner() {
  if grep -qi microsoft /proc/version; then
    echo -e "\033[1;36m💻 WSL2 Environment\033[0m"
  elif command -v gnome-shell >/dev/null 2>&1; then
    echo -e "\033[1;32m🖥️ Desktop Environment\033[0m"
  else
    echo -e "\033[1;33m🔧 Headless Environment\033[0m"
  fi
}
__show_env_banner
eval "$(starship init bash)"
if [ -z "$TMUX" ] && command -v tmux >/dev/null 2>&1; then
  exec tmux
fi
if command -v neofetch >/dev/null 2>&1; then
  neofetch
elif command -v screenfetch >/dev/null 2>&1; then
  screenfetch
fi
'

if ! grep -q '__show_env_banner' ~/.bashrc 2>/dev/null; then
  echo "$ENV_BANNER_FUNC" >> ~/.bashrc
fi

# Zsh version
{
  echo ''
  echo '# Zsh terminal UX enhancements'
  echo '[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh'
  echo 'eval "$(starship init zsh)"'
  echo 'eval "$(zoxide init zsh)"'
  echo 'eval "$(direnv hook zsh)"'
  echo '__show_env_banner() {
    if grep -qi microsoft /proc/version; then
      echo -e "\033[1;36m💻 WSL2 Environment\033[0m"
    elif command -v gnome-shell >/dev/null 2>&1; then
      echo -e "\033[1;32m🖥️ Desktop Environment\033[0m"
    else
      echo -e "\033[1;33m🔧 Headless Environment\033[0m"
    fi
  }
  __show_env_banner'
  echo '[ -z "$TMUX" ] && command -v tmux >/dev/null && exec tmux'
  echo 'command -v neofetch >/dev/null && neofetch || command -v screenfetch >/dev/null && screenfetch'
} >> ~/.zshrc

# --- Auto-switch to Zsh ---
CURRENT_SHELL=$(basename "$SHELL")
if [ "$CURRENT_SHELL" != "zsh" ]; then
  echo "💡 Changing default shell to zsh..."
  chsh -s "$(command -v zsh)" "$USER"
fi

# --- PowerShell Integration ---
if command -v pwsh >/dev/null 2>&1; then
  mkdir -p ~/.config/powershell
  cat > ~/.config/powershell/Microsoft.PowerShell_profile.ps1 <<'EOF'
Invoke-Expression (&starship init powershell)
if (Get-Command neofetch -ErrorAction SilentlyContinue) { neofetch }
EOF
  echo "✅ PowerShell profile updated."
fi

# --- Git Best Practice ---
echo "🔧 Configuring Git..."

git config --global core.editor "code-insiders --wait"
git config --global pull.rebase false
git config --global init.defaultBranch main
git config --global commit.gpgsign false
git config --global core.excludesfile ~/.gitignore_global
git config --global user.name "Olaolu Fayese"
git config --global user.email "60392167+ofayese@users.noreply.github.com"
echo ".DS_Store" >> ~/.gitignore_global

# --- Manual Terminal Tips ---
echo ""
echo "📋 Manual Terminal Tips:"
echo "• iTerm2: Set Zsh login shell, Nerd Font, 256-color"
echo "• Windows Terminal: profile -> commandLine: 'zsh' or 'tmux', font: JetBrains Mono Nerd Font"
echo "• VS Code: set 'terminal.integrated.defaultProfile.linux': 'zsh'"
echo ""

echo "✅ Terminal enhancements complete!"
echo "🎨 Starship configuration installed."
echo "🔄 Restart your shell to see the effects."
