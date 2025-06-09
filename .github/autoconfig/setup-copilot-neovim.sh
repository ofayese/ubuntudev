#!/usr/bin/env bash
set -eux

# Install Copilot.vim via Git if not present
if [ ! -d "$HOME/.config/nvim/pack/github/start/copilot.vim" ]; then
  git clone https://github.com/github/copilot.vim     "$HOME/.config/nvim/pack/github/start/copilot.vim"
fi

echo "✅ Copilot.vim installed. Configure keybindings in your init.vim or lua config."
