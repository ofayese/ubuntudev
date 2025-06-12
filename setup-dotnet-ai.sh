#!/usr/bin/env bash
set -euo pipefail

LOGFILE="/var/log/ubuntu-dev-tools.log"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== [setup-dotnet-ai.sh] Started at $(date) ==="

# --- DOTNET SDKs ---
echo "📦 Installing .NET SDKs 8.0, 9.0..."
wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
sudo dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb
sudo apt update

# Install .NET SDKs with error handling
if sudo apt install -y dotnet-sdk-8.0; then
    echo "✅ .NET 8.0 SDK installed"
else
    echo "⚠️ Failed to install .NET 8.0 SDK"
fi

if sudo apt install -y dotnet-sdk-9.0; then
    echo "✅ .NET 9.0 SDK installed"
else
    echo "⚠️ Failed to install .NET 9.0 SDK"
fi

# .NET 10.0 might not be available yet (preview/RC)
if sudo apt install -y dotnet-sdk-10.0 2>/dev/null; then
    echo "✅ .NET 10.0 SDK installed"
else
    echo "⚠️ .NET 10.0 SDK not available (may be in preview)"
fi

# --- PowerShell ---
echo "💻 Installing PowerShell..."
sudo apt install -y apt-transport-https software-properties-common
sudo apt update
sudo apt install -y powershell

# --- Miniconda Setup ---
echo "🧠 Installing Miniconda for Python AI/ML stack..."
sudo apt install -y python3 python3-pip python3-venv curl

cd /tmp || exit 1
curl -LO https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh -b -p "$HOME/miniconda"
export PATH="$HOME/miniconda/bin:$PATH"
echo 'export PATH="$HOME/miniconda/bin:$PATH"' >> ~/.bashrc

# --- Python Packages for Data Science + AI ---
echo "📦 Installing Python packages for ML and data science..."

pip3 install --upgrade pip
pip3 install numpy scipy pandas matplotlib seaborn scikit-learn tqdm jupyterlab jupyter notebook

# CPU versions for PyTorch (safe for WSL2, headless, etc.)
pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu

python3.11 -m pip install --upgrade pip
python3.11 -m pip install tensorflow keras opencv-python || echo "⚠️ TensorFlow skipped if wheel unavailable"

# HuggingFace + Transformers
pip3 install transformers datasets ipywidgets openai anthropic

echo "✅ .NET SDKs, PowerShell, and AI/ML toolchains installed!"
