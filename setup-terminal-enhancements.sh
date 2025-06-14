#!/usr/bin/env bash
# setup-terminal-enhancements.sh - Configure modern terminal environment with Alacritty, tmux, and Starship
# Version: 1.0.0
# Last updated: 2025-06-13
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

# Script version and last updated timestamp
readonly VERSION="1.0.0"
readonly LAST_UPDATED="2025-06-13"

# Cross-platform support
OS_TYPE="$(uname -s)"
readonly OS_TYPE

# Dry-run mode support
readonly DRY_RUN="${DRY_RUN:-false}"

# Define trusted domains for downloads
readonly TRUSTED_DOMAINS=(
  "starship.rs"
  "github.com"
  "raw.githubusercontent.com"
)

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

# Source utility modules with error checking
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

source "$SCRIPT_DIR/util-log.sh" || {
  echo "FATAL: Failed to source util-log.sh" >&2
  exit 1
}
source "$SCRIPT_DIR/util-env.sh" || {
  echo "FATAL: Failed to source util-env.sh" >&2
  exit 1
}
source "$SCRIPT_DIR/util-install.sh" || {
  echo "FATAL: Failed to source util-install.sh" >&2
  exit 1
}

# Secure download and validation function
validate_and_download() {
  local url="$1"
  local output_file="$2"
  local description="$3"

  # Extract domain for validation
  local domain
  domain=$(echo "$url" | sed -n 's|^https://\([^/]*\).*|\1|p')

  # Validate domain is in trusted list
  local is_trusted=false
  for trusted_domain in "${TRUSTED_DOMAINS[@]}"; do
    if [[ "$domain" == "$trusted_domain" || "$domain" == *".$trusted_domain" ]]; then
      is_trusted=true
      break
    fi
  done

  if [[ "$is_trusted" != "true" ]]; then
    log_error "Security error: Domain $domain is not in trusted domains list"
    return 1
  fi

  # Download with proper error handling and HTTPS enforcement
  log_info "Downloading $description from $domain..."
  if ! curl --proto '=https' --tlsv1.2 -sSf -o "$output_file" "$url"; then
    log_error "Failed to download $description from $url"
    return 1
  fi

  # Basic validation - file exists and is not empty
  if [[ ! -s "$output_file" ]]; then
    log_error "Downloaded file is empty or does not exist"
    return 1
  fi

  log_success "Successfully downloaded and validated $description"
  return 0
}

# Initialize logging
init_logging
log_info "Terminal enhancements setup started (v$VERSION, updated $LAST_UPDATED)"

# Display dry-run mode notice if active
if [[ "$DRY_RUN" == "true" ]]; then
  log_info "=== DRY RUN MODE: No system changes will be made ==="
  log_info "This is a simulation to show what would be installed."
fi

# Detect environment
ENV_TYPE=$(detect_environment)
log_info "Environment detected: $ENV_TYPE"

# Check if desktop environment is available for GUI apps
if [[ "$ENV_TYPE" == "$ENV_HEADLESS" ]]; then
  log_warning "Headless environment detected - some GUI features may not work"
fi

# Install Starship if not already installed
install_starship() {
  if command -v starship &>/dev/null; then
    log_info "Starship is already installed, skipping..."
    return 0
  fi

  log_info "Installing Starship prompt..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would download and install Starship from https://starship.rs"
    log_success "[DRY-RUN] Starship would be installed successfully"
    return 0
  fi

  # Create a secure temporary directory for the download
  TEMP_DIR=$(mktemp -d)
  chmod 700 "$TEMP_DIR"
  STARSHIP_SCRIPT="$TEMP_DIR/starship.sh"

  if validate_and_download "https://starship.rs/install.sh" "$STARSHIP_SCRIPT" "Starship installer"; then
    # Make the script executable
    chmod 700 "$STARSHIP_SCRIPT"

    # Execute the validated script with required parameters
    if sh "$STARSHIP_SCRIPT" --yes; then
      log_success "Starship installed successfully"
    else
      log_error "Failed to run the Starship installer"
      rm -rf "$TEMP_DIR"
      log_warning "Failed to install Starship using download script, trying alternative methods..."
    fi
  else
    log_warning "Failed to download Starship installer, trying alternative methods..."

    # Clean up temp dir from failed download
    rm -rf "$TEMP_DIR"

    # Try installing via cargo if available
    if command -v cargo &>/dev/null; then
      cargo install starship >/dev/null 2>&1 || {
        log_warning "Failed to install Starship via cargo, creating a simple PS1 prompt instead."
        echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >>~/.bashrc
        return 1
      }
    else
      log_warning "Failed to install Starship and cargo not available. Creating a simple PS1 prompt instead."
      echo 'export PS1="\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "' >>~/.bashrc
      return 1
    fi
  fi

  # Clean up successful install temp dir
  rm -rf "$TEMP_DIR" 2>/dev/null || true
  log_success "Starship installed successfully"
  return 0
}

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
cat >~/.config/alacritty/alacritty.toml <<'EOF'
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
cat >~/.tmux.conf <<'EOF'
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

# --- Install Starship Prompt ---
((current_step++))
log_info "[$current_step/$total_steps] Installing Starship prompt..."
show_progress "$current_step" "$total_steps" "Terminal Setup"
start_spinner "Installing Starship prompt"
install_starship
stop_spinner "Installing Starship prompt"

# --- Starship Configuration ---
mkdir -p ~/.config
create_config_backup ~/.config/starship.toml
cat >~/.config/starship.toml <<'EOF'
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
  echo "$ENV_BANNER_FUNC" >>~/.bashrc
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
} >>~/.zshrc

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
  cat >~/.config/powershell/Microsoft.PowerShell_profile.ps1 <<'EOF'
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
