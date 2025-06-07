#!/bin/bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-desktop.sh] Started at $(date) ==="

# --- Detect headless environments ---
if ! (command -v gnome-shell >/dev/null 2>&1 && echo $XDG_SESSION_TYPE | grep -q 'x11\|wayland'); then
  echo "🚫 Headless environment detected — skipping desktop customization."
  exit 0
fi


#!/bin/bash

set -e

# --- SYSTEM UPDATE & UPGRADE ---
sudo apt update
sudo apt upgrade -y

# --- DEFAULT SYSTEM EDITOR ---
sudo apt install -y vim nano
sudo update-alternatives --set editor /usr/bin/vim.basic

# --- UNATTENDED SECURITY UPDATES ---
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# --- FIREWALL, GUFW, FAIL2BAN ---
sudo apt install -y ufw gufw fail2ban
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable

# --- DISABLE SYSTEM CRASH REPORTS ---
sudo systemctl disable apport.service
sudo systemctl stop apport.service
sudo sed -i 's/enabled=1/enabled=0/' /etc/default/apport

# --- TUNE SWAPPINESS ---
sudo sysctl vm.swappiness=10
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf

# --- ARCHIVING TOOLS ---
sudo apt install -y zip unzip rar unrar p7zip-full p7zip-rar tar

# --- LIBREOFFICE, FOLIATE ---
sudo apt install -y libreoffice foliate

# --- MARKDOWN EDITORS ---
sudo apt install -y glow apostrophe
wget -O /tmp/obsidian.deb https://github.com/obsidianmd/obsidian-releases/releases/latest/download/obsidian_amd64.deb
sudo dpkg -i /tmp/obsidian.deb || sudo apt --fix-broken install -y
rm /tmp/obsidian.deb

# --- DIVE (Docker Image Explorer) ---
wget https://github.com/wagoodman/dive/releases/latest/download/dive_amd64.deb -O /tmp/dive.deb
sudo dpkg -i /tmp/dive.deb || sudo apt --fix-broken install -y
rm /tmp/dive.deb

# --- POWER MANAGEMENT ---
sudo apt install -y tlp tlp-rdw
sudo systemctl enable tlp
sudo systemctl start tlp

# --- DEVELOPMENT TOOLS ---
sudo apt install -y android-tools-adb android-tools-fastboot awscli httpie clusterssh filezilla golang-go python3-pip pipenv nala

# --- FORMATTERS / LINTERS ---
python3 -m pip install --upgrade pip
python3 -m pip install black ruff ansible-lint pre-commit

# --- GOPATH SETUP ---
mkdir -p "$HOME/go/bin" "$HOME/go/src" "$HOME/go/pkg"
echo 'export GOPATH=$HOME/go' >> ~/.profile
echo 'export PATH=$PATH:$GOPATH/bin' >> ~/.profile
source ~/.profile

# --- DOWNLOAD UTILITIES ---
sudo apt install -y axel transmission wget aria2

# --- MULTIMEDIA TOOLS ---
sudo apt install -y vlc totem gimp imagemagick ffmpeg audacity

# --- VIRTUALIZATION ---
sudo apt install -y virtualbox vagrant

# --- DOCKER DESKTOP INSTALL ---
sudo apt-get remove -y docker docker-engine docker.io containerd runc || true
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common lsb-release
DOCKER_DESKTOP_URL=$(curl -s https://api.github.com/repos/docker/desktop/releases/latest | grep browser_download_url | grep "docker-desktop-.*-amd64.deb" | cut -d '"' -f 4)
if [ -z "$DOCKER_DESKTOP_URL" ]; then
  echo "Could not fetch Docker Desktop URL. Exiting."
  exit 1
fi
cd /tmp
curl -LO "$DOCKER_DESKTOP_URL"
sudo apt-get install -y ./docker-desktop-*-amd64.deb
systemctl --user start docker-desktop || true
echo "Docker Desktop installed. Re-login to finalize."

# --- PODMAN, KIND, MINIKUBE ---
sudo apt install -y podman
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64
curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind

# --- OPENSSH SERVER ---
sudo apt install -y openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh

# --- GITHUB CLI ---
type -p curl >/dev/null || sudo apt install curl -y
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install -y gh

# --- DOTNET SDK 8/9/10 ---
wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb
sudo apt update
sudo apt install -y dotnet-sdk-8.0 dotnet-sdk-9.0 dotnet-sdk-10.0

# --- POWERSHELL ---
sudo apt install -y wget apt-transport-https software-properties-common
sudo apt update
sudo apt install -y powershell

# --- AI/ML TOOLS (Anaconda + Py Packages) ---
sudo apt install -y python3 python3-pip python3-venv
cd /tmp
curl -LO https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh -b -p $HOME/miniconda
export PATH="$HOME/miniconda/bin:$PATH"
echo 'export PATH="$HOME/miniconda/bin:$PATH"' >> ~/.bashrc
pip3 install --upgrade pip
pip3 install numpy scipy pandas matplotlib seaborn scikit-learn tqdm jupyterlab jupyter notebook
pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu
pip3 install tensorflow keras opencv-python xgboost lightgbm catboost fastai transformers datasets ipywidgets openai anthropic

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

# --- LANGUAGE SDKs ---
sudo apt install -y openjdk-17-jdk gpg
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | bash -s -- -y

# --- FONTS ---
sudo apt install -y fonts-firacode fonts-jetbrains-mono

# --- GNOME CUSTOMIZATIONS ---
sudo apt install -y gnome-tweaks gnome-shell-extensions
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true

# --- SCREENSHOTS & BACKUPS ---
sudo apt install -y timeshift shutter flameshot

# --- SSD TRIM ---
sudo systemctl enable fstrim.timer
sudo systemctl start fstrim.timer

# --- SYSTEMD TIMER FOR APT MAINTENANCE ---
echo -e "[Unit]\nDescription=Auto APT Update\n\n[Timer]\nOnCalendar=daily\n\n[Install]\nWantedBy=timers.target\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/apt update && /usr/bin/apt upgrade -y" | sudo tee /etc/systemd/system/autoaptupdate.timer
sudo systemctl enable autoaptupdate.timer

# --- TERMINAL EMULATORS & LAZYGIT ---
sudo apt install -y tilix
sudo add-apt-repository -y ppa:aslatter/ppa
sudo apt update
sudo apt install -y alacritty
mkdir -p ~/.config/alacritty
echo -e "[shell]\nprogram = \"tmux\"" > ~/.config/alacritty/alacritty.toml
LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')
wget "https://github.com/jesseduffield/lazygit/releases/download/${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION#v}_Linux_x86_64.tar.gz" -O /tmp/lazygit.tar.gz
tar -xf /tmp/lazygit.tar.gz -C /tmp lazygit
sudo install /tmp/lazygit /usr/local/bin
rm /tmp/lazygit /tmp/lazygit.tar.gz

echo -e "\n✅ Ubuntu dev workstation is ready! Reboot or re-login may be required for full Docker/Desktop & group changes to take effect."

