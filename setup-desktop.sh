#!/usr/bin/env bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-desktop.sh] Started at $(date) ==="

# Use shared utility functions for package installation and GitHub downloads
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/util-log.sh"
source "$SCRIPT_DIR/util-packages.sh"
source "$SCRIPT_DIR/util-env.sh"
# --- Safe install function ---
safe_install() {
  safe_apt_install "$@"
}

# --- Safe install .deb function ---
safe_install_deb() {
  safe_install_deb_package "$1" "${2:-}"
}

# --- Detect headless environments ---
if ! (command -v gnome-shell >/dev/null 2>&1 && echo "${XDG_SESSION_TYPE:-}" | grep -qE 'x11|wayland'); then
  echo "🚫 Headless environment detected — skipping desktop customization."
  exit 0
fi

# --- System Update & Essentials ---
sudo apt update && sudo apt upgrade -y
safe_install vim nano unzip zip curl wget git software-properties-common

# --- Set Default Editor ---
sudo update-alternatives --set editor /usr/bin/vim.basic

# --- Enable Unattended Security Updates ---
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# --- Firewall & Hardening ---
safe_install ufw gufw fail2ban
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable

# --- Disable Crash Reports ---
sudo systemctl disable --now apport.service
sudo sed -i 's/enabled=1/enabled=0/' /etc/default/apport

# --- Tune Swappiness ---
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
sudo sysctl -p /etc/sysctl.d/99-swappiness.conf

# --- Dev & Archive Tools ---
safe_install p7zip-full p7zip-rar rar unrar tar glow filezilla httpie awscli

# --- Markdown & Reading Tools ---
safe_install libreoffice foliate apostrophe
safe_install_deb "https://github.com/obsidianmd/obsidian-releases/releases/latest/download/obsidian_amd64.deb" "obsidian"

# --- Fonts & Terminal Enhancements ---
safe_install fonts-firacode fonts-jetbrains-mono zsh tmux alacritty tilix fzf bat fd-find zoxide direnv

# Install starship from official installer
echo "🚀 Installing Starship prompt..."
if ! command -v starship >/dev/null 2>&1; then
    curl -sS https://starship.rs/install.sh | sh -s -- -y
else
    echo "✅ Starship already installed"
fi

# Install eza (modern ls replacement) from GitHub
install_from_github "eza-community/eza" "eza_.*_amd64.deb" \
    "sudo apt install -y \$1" "eza"

# --- Oh-My-Zsh & Shell Plugins ---
RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
echo "[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh" >> ~/.zshrc
echo 'eval "$(starship init zsh)"' >> ~/.zshrc
echo 'eval "$(zoxide init zsh)"' >> ~/.zshrc
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc

# --- TMUX Plugin Manager ---
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# --- Git Configuration ---
git config --global core.editor "code-insiders --wait"
git config --global pull.rebase false
# Git configuration is handled in setup-devtools.sh
echo "🔄 Skip Git configuration here to avoid redundancy"

# --- GNOME Customizations ---
safe_apt_install gnome-tweaks gnome-shell-extensions
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true

# --- Screenshot & Backup Tools ---
safe_apt_install timeshift shutter flameshot

# --- Power Management ---
safe_apt_install tlp tlp-rdw
sudo systemctl enable --now tlp

# --- Multimedia ---
safe_apt_install vlc totem gimp imagemagick ffmpeg audacity

# --- Development Utilities ---
safe_apt_install golang-go python3-pip pipenv nala android-tools-adb android-tools-fastboot

# --- Formatters / Linters ---
python3 -m pip install --upgrade pip
python3 -m pip install black ruff ansible-lint pre-commit

# --- Go Environment Setup ---
mkdir -p "$HOME/go/bin" "$HOME/go/src" "$HOME/go/pkg"
echo 'export GOPATH=$HOME/go' >> ~/.profile
echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.profile

# --- Download Tools ---
safe_apt_install axel transmission aria2

# --- Virtualization ---
safe_apt_install virtualbox vagrant

# --- OpenSSH Server ---
safe_apt_install openssh-server
sudo systemctl enable --now ssh

# --- GitHub CLI ---
type -p curl >/dev/null || sudo apt install -y curl
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update && sudo apt install -y gh

# --- Docker Desktop ---
DOCKER_DESKTOP_URL=$(curl -s https://api.github.com/repos/docker/desktop/releases/latest | grep browser_download_url | grep "docker-desktop-.*-amd64.deb" | cut -d '"' -f 4)
if [[ -n "$DOCKER_DESKTOP_URL" ]]; then
  curl -Lo /tmp/docker-desktop.deb "$DOCKER_DESKTOP_URL"
  sudo apt install -y /tmp/docker-desktop.deb
  rm -f /tmp/docker-desktop.deb
  systemctl --user start docker-desktop || true
fi

# --- Podman, Kind, Minikube ---
safe_apt_install podman
curl -Lo /tmp/minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install /tmp/minikube /usr/local/bin/minikube
rm /tmp/minikube

curl -Lo /tmp/kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
chmod +x /tmp/kind && sudo mv /tmp/kind /usr/local/bin/kind

# --- AI/ML (Miniconda + Py packages) ---
cd /tmp || exit 1
curl -LO https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh -b -p "$HOME/miniconda"
echo 'export PATH="$HOME/miniconda/bin:$PATH"' >> ~/.bashrc
export PATH="$HOME/miniconda/bin:$PATH"

pip3 install --upgrade pip
pip3 install numpy scipy pandas matplotlib seaborn scikit-learn tqdm jupyterlab jupyter notebook
pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
pip3 install tensorflow keras opencv-python xgboost lightgbm catboost fastai transformers datasets ipywidgets openai anthropic

# --- .NET SDKs ---
wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb
sudo apt update && sudo apt install -y dotnet-sdk-8.0 dotnet-sdk-9.0 dotnet-sdk-10.0

# --- PowerShell ---
sudo apt install -y powershell

# --- Language SDKs ---
safe_apt_install openjdk-17-jdk gpg
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | bash -s -- -y

# --- LazyGit ---
LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')
if [ -n "$LAZYGIT_VERSION" ]; then
    wget "https://github.com/jesseduffield/lazygit/releases/download/${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION#v}_Linux_x86_64.tar.gz" -O /tmp/lazygit.tar.gz
    tar -xf /tmp/lazygit.tar.gz -C /tmp lazygit
    sudo install /tmp/lazygit /usr/local/bin
    rm /tmp/lazygit /tmp/lazygit.tar.gz
else
    echo "⚠️ Failed to get LazyGit version"
fi

# --- SSD TRIM ---
sudo systemctl enable fstrim.timer
sudo systemctl start fstrim.timer

# --- Systemd Timer for Auto Updates ---
cat <<EOF | sudo tee /etc/systemd/system/autoaptupdate.timer
[Unit]
Description=Auto APT Update

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

cat <<EOF | sudo tee /etc/systemd/system/autoaptupdate.service
[Service]
Type=oneshot
ExecStart=/usr/bin/apt update && /usr/bin/apt upgrade -y
EOF

sudo systemctl enable --now autoaptupdate.timer

echo -e "\n✅ Ubuntu developer desktop setup complete!"
echo "➡️ You may need to reboot or re-login to apply all changes."
