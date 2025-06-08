#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-lang-sdks.sh] Started at $(date) ==="

# --- RUST (Rustup) ---
echo "🦀 Installing Rust via rustup..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"

# Add Rust to shell profile
for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
  if [ -f "$PROFILE" ] && ! grep -q 'cargo/env' "$PROFILE"; then
    echo 'source "$HOME/.cargo/env"' >> "$PROFILE"
  fi
done

# --- JAVA / JVM via SDKMAN ---
echo "☕ Installing SDKMAN and JVM toolchain..."
curl -s "https://get.sdkman.io" | bash

# Initialize SDKMAN immediately
source "$HOME/.sdkman/bin/sdkman-init.sh"

# Add SDKMAN init to shell profiles
for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
  if [ -f "$PROFILE" ] && ! grep -q 'sdkman-init.sh' "$PROFILE"; then
    echo 'source "$HOME/.sdkman/bin/sdkman-init.sh"' >> "$PROFILE"
  fi
done

# Install Java SDKs (choose common versions)
sdk install java 17.0.9-tem
sdk install java 21.0.2-tem
sdk default java 17.0.9-tem

# --- HASKELL via GHCup ---
echo "🧮 Installing Haskell via GHCup..."
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | bash -s -- -y

# Add GHCup to shell profiles
for PROFILE in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
  if [ -f "$PROFILE" ] && ! grep -q '.ghcup/env' "$PROFILE"; then
    echo 'source "$HOME/.ghcup/env"' >> "$PROFILE"
  fi
done

echo "✅ Rust, Java (SDKMAN), and Haskell (GHCup) installed!"
