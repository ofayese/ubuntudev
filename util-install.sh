#!/usr/bin/env bash
# util-install.sh - Centralized installation functions
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/util-log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/util-env.sh"

ENV_TYPE="${ENV_TYPE:-$(detect_environment)}"

update_package_index() {
  log_info "Updating package index..."
  sudo apt-get update -y || { log_error "apt update failed."; return 1; }
}

install_packages() {
  local pkgs=("$@") failed=()
  if [[ "$ENV_TYPE" == "WSL2" && -x "$(command -v brew)" ]]; then
    for p in "${pkgs[@]}"; do
      log_info "Installing $p via brew..."
      brew install "$p" || failed+=("$p")
    done
  else
    update_package_index
    for p in "${pkgs[@]}"; do
      log_info "Installing $p via apt..."
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o DPkg::Lock::Timeout=30 "$p" || failed+=("$p")
    done
  fi
  [[ ${#failed[@]} -eq 0 ]] || { log_error "Failed: ${failed[*]}"; return 1; }
}

install_snap() {
  local s="$1" c="${2:-}" cmd="sudo snap install $s"
  [[ "$c" == "--classic" ]] && cmd+=" --classic"
  log_info "Installing snap: $s"
  $cmd || { log_error "Snap $s failed."; return 1; }
}

install_deb_package() {
  local url="$1" name="${2:-$(basename "$url" .deb)}"
  local tmp="/tmp/${name}_$$.deb"
  log_info "Downloading $name..."
  wget -q -O "$tmp" "$url" &&   { log_info "Installing $name"; sudo dpkg -i "$tmp" && sudo apt-get install -f -y; rm -f "$tmp"; }   || { log_error "Failed $name"; return 1; }
}

install_from_github() {
  local repo="$1" pat="$2" cmd_tmpl="$3" bin="${4:-$(basename "$repo")}"
  command -v "$bin" &>/dev/null && { log_info "$bin exists, skipping."; return 0; }
  log_info "Fetching latest release of $repo"
  local api="https://api.github.com/repos/$repo/releases/latest"
  local dl=$(wget -qO- "$api" | grep -Eo '"browser_download_url": "[^"]*'" | grep "$pat" | head -n1 | cut -d" -f4)
  [[ -n "$dl" ]] || { log_error "No asset matching $pat"; return 1; }
  local fn="/tmp/$(basename "$dl")"
  wget -q -O "$fn" "$dl" &&   { log_info "Installing $bin"; eval "${cmd_tmpl//\{\}/$fn}"; rm -f "$fn"; }   || { log_error "Install $bin failed"; return 1; }
}

install_python_package() {
  local pkg="$1"
  log_info "Installing Python pkg: $pkg"
  command -v pip3 &>/dev/null || sudo apt-get install -y python3-pip
  pip3 install -U "$pkg" || { log_error "pip install $pkg failed"; return 1; }
}

install_node_package() {
  local pkg="$1"
  log_info "Installing Node pkg: $pkg"
  npm install -g "$pkg" || { log_error "npm install $pkg failed"; return 1; }
}
