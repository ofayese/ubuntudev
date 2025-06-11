#!/usr/bin/env bash
# setup-devtools.sh - Dev tools setup using util-install
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-env.sh"
source "$SCRIPT_DIR/util-install.sh"

LOGFILE="/var/log/ubuntu-dev-tools.log"
init_logging "$LOGFILE"

update_package_index
log_info "Installing system monitoring..."
install_packages htop btop glances ncdu iftop

log_info "Installing CLI utilities..."
install_packages bat exa fzf ripgrep

log_info "Installing eza from GitHub..."
install_from_github "eza-community/eza" "_amd64.deb" "sudo dpkg -i {}" "eza"

log_info "Installing Zsh & Oh-My-Zsh..."
install_packages zsh
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(wget -qO- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

finish_logging
