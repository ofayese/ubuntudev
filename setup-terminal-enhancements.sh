#!/usr/bin/env bash
# setup-terminal-enhancements.sh - Configure modern terminal environment with Alacritty, tmux, and Starship
#
# This script installs and configures:
# - Alacritty terminal emulator with JetBrains Mono font
# - tmux terminal multiplexer with mouse support
# - Starship cross-shell prompt
# - Enhanced shell configuration for bash and zsh
# - PowerShell profile (if available)
#
# Usage: ./setup-terminal-enhancements.sh
# 
# Environment support: WSL2, Desktop, Headless
# Dependencies: util-log.sh, util-env.sh, util-install.sh
#
set -euo pipefail

# Cleanup function for safe exit
cleanup() {
  local exit_code=$?
  log_info "Cleaning up temporary files..."
  # Remove any temporary files if they exist
  rm -f /tmp/alacritty_*.deb /tmp/starship_* 2>/dev/null || true
  finish_logging
  exit $exit_code
}

# Set up signal handlers for cleanup
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Source utility modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./util-log.sh
source "$SCRIPT_DIR/util-log.sh"
# shellcheck source=./util-env.sh
source "$SCRIPT_DIR/util-env.sh"
# shellcheck source=./util-install.sh
source "$SCRIPT_DIR/util-install.sh"

# Initialize logging
init_logging
log_info "Terminal enhancements setup started"

# Detect environment
ENV_TYPE=$(detect_environment)
log_info "Environment detected: $ENV_TYPE"

# Check if desktop environment is available for GUI apps
if [[ "$ENV_TYPE" == "$ENV_HEADLESS" ]]; then
  log_warning "Headless environment detected - some GUI features may not work"
fi

# Define installation steps for progress tracking
declare -a SETUP_STEPS=(
  "fonts_and_terminal"
  "alacritty_config"
  "tmux_setup"
  "starship_install"
  "shell_configs"
)

current_step=0
total_steps=${#SETUP_STEPS[@]}

# Step 1: Install Alacritty + Fonts
((current_step++))
log_info "[$current_step/$total_steps] Installing fonts and terminal emulator..."
show_progress "$current_step" "$total_steps" "Terminal Setup"

# Create backup function for safety
create_config_backup() {
  local config_path="$1"
  if [ -f "$config_path" ]; then
    local backup_path
    backup_path="${config_path}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$config_path" "$backup_path"
    log_info "Backed up existing config to $backup_path"
  fi
}

start_spinner "Installing fonts and terminal packages"

# Try to add the PPA using consolidated function
safe_add_apt_repository "ppa:aslatter/ppa" "Alacritty PPA" >/dev/null 2>&1

# Install packages using consolidated function
packages_to_install=(fonts-jetbrains-mono fonts-firacode neofetch)
optional_packages=(alacritty)

safe_apt_install "${packages_to_install[@]}" >/dev/null 2>&1

# Try optional packages individually
for pkg in "${optional_packages[@]}"; do
    safe_apt_install "$pkg" >/dev/null 2>&1 || log_warning "Could not install optional package: $pkg"
done

stop_spinner "Installing fonts and terminal packages"

# Step 2: Configure Alacritty
((current_step++))
log_info "[$current_step/$total_steps] Configuring Alacritty..."
show_progress "$current_step" "$total_steps" "Terminal Setup"
start_spinner "Configuring Alacritty"

# Create Alacritty config with backup
mkdir -p ~/.config/alacritty
create_config_backup ~/.config/alacritty/alacritty.toml
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
create_config_backup ~/.tmux.conf
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
create_config_backup ~/.config/starship.toml
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
readonly ENV_BANNER_FUNC='
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
  # Ensure .bashrc exists
  touch ~/.bashrc
  echo "$ENV_BANNER_FUNC" >> ~/.bashrc
fi

# Zsh version - ensure .zshrc exists
if ! [ -f ~/.zshrc ]; then
  touch ~/.zshrc
  log_info "Created new .zshrc file"
fi

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
  # Check if zsh is available
  if command_exists zsh; then
    log_info "Changing default shell to zsh..."
    log_warning "This will require a logout/login to take effect"
    chsh -s "$(command -v zsh)" "$USER"
  else
    log_warning "zsh not found - install it first with: sudo apt install zsh"
  fi
fi

# --- PowerShell Integration ---
if command_exists pwsh; then
  log_info "Setting up PowerShell profile..."
  mkdir -p ~/.config/powershell
  cat > ~/.config/powershell/Microsoft.PowerShell_profile.ps1 <<'EOF'
Invoke-Expression (&starship init powershell)
if (Get-Command neofetch -ErrorAction SilentlyContinue) { neofetch }
EOF
  log_success "PowerShell profile updated"
fi

# --- Git configuration is handled in setup-devtools.sh ---
log_info "Git configuration is handled in setup-devtools.sh to avoid redundancy"

# --- Manual Terminal Tips ---
log_info "Manual Terminal Tips:"
log_info "• iTerm2: Set Zsh login shell, Nerd Font, 256-color"
log_info "• Windows Terminal: profile -> commandLine: 'zsh' or 'tmux', font: JetBrains Mono Nerd Font"
log_info "• VS Code: set 'terminal.integrated.defaultProfile.linux': 'zsh'"

log_success "Terminal enhancements complete!"
log_success "Starship configuration installed."
log_info "Restart your shell to see the effects."

finish_logging
