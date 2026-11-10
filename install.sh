#!/bin/bash

# AI Terminal - Cross-Platform Installation Script
# Compatible with macOS and Linux
#
# Optional environment variable:
#   NEWTERMINAL_AI_BIN_DIR   directory for the `ai-terminal` launcher.
#                            Default: /usr/local/bin (with sudo if needed), else ~/.local/bin.

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="llama3.2:1b"
POWERSHELL_DOCS="https://learn.microsoft.com/powershell/scripting/install/installing-powershell"

echo "🤖 AI Terminal - Cross-Platform Installation"
echo "==========================================="

if [[ ! -f "$SCRIPT_DIR/NewTerminal-AI.psm1" ]]; then
    echo "❌ NewTerminal-AI.psm1 was not found next to this script."
    echo "   Run install.sh from a clone of the repository."
    exit 1
fi

powershell_manual_install() {
    echo "❌ Could not install PowerShell automatically. Please install it manually:"
    echo "   $POWERSHELL_DOCS"
    exit 1
}

# Check if PowerShell is installed
if ! command -v pwsh &> /dev/null; then
    echo "❌ PowerShell Core (pwsh) is required but not installed."
    echo "📦 Installing PowerShell Core..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install --cask powershell
        else
            echo "❌ Homebrew not found."
            powershell_manual_install
        fi
    elif [[ -r /etc/os-release ]]; then
        # Linux: use the Microsoft package repository that matches this distribution and release
        os_id="$(. /etc/os-release && echo "$ID")"
        os_version="$(. /etc/os-release && echo "$VERSION_ID")"
        case "$os_id" in
            ubuntu|debian)
                deb="$(mktemp)"
                curl -fsSL "https://packages.microsoft.com/config/${os_id}/${os_version}/packages-microsoft-prod.deb" -o "$deb" || powershell_manual_install
                sudo dpkg -i "$deb"
                rm -f "$deb"
                sudo apt-get update
                sudo apt-get install -y powershell
                ;;
            rhel|centos|rocky|almalinux|ol)
                curl -fsSL "https://packages.microsoft.com/config/rhel/${os_version%%.*}/prod.repo" | sudo tee /etc/yum.repos.d/microsoft.repo > /dev/null || powershell_manual_install
                sudo yum install -y powershell
                ;;
            *)
                echo "❌ Unsupported Linux distribution: $os_id"
                powershell_manual_install
                ;;
        esac
    else
        echo "❌ Unsupported operating system: $OSTYPE"
        powershell_manual_install
    fi
fi

# Check if Ollama is installed
if ! command -v ollama &> /dev/null; then
    echo "❌ Ollama is required but not installed."
    echo "📦 Installing Ollama..."

    if [[ "$OSTYPE" == "darwin"* ]] && command -v brew &> /dev/null; then
        brew install ollama
    else
        curl -fsSL https://ollama.com/install.sh | sh
    fi
fi

# Start Ollama service, unless it already answers
echo "🚀 Starting Ollama service..."
if ! ollama list &> /dev/null; then
    if [[ "$OSTYPE" != "darwin"* ]] && command -v systemctl &> /dev/null && sudo systemctl start ollama 2> /dev/null; then
        sleep 3
    else
        echo "Starting Ollama manually..."
        nohup ollama serve > /dev/null 2>&1 &
        sleep 3
    fi
fi

# Pull required model
echo "📥 Downloading AI model ($MODEL)..."
ollama pull "$MODEL"

# Install AI Terminal module (PowerShell honours the XDG base directories)
echo "📦 Installing AI Terminal module..."
MODULE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/powershell/Modules/AITerminal"
mkdir -p "$MODULE_DIR"
cp "$SCRIPT_DIR/NewTerminal-AI.psm1" "$MODULE_DIR/AITerminal.psm1"

# Add the import to the PowerShell profile. An existing profile is kept: the lines are appended,
# and only once. The module starts its prompt only in an interactive console.
PROFILE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/powershell"
PROFILE_PATH="$PROFILE_DIR/Microsoft.PowerShell_profile.ps1"
IMPORT_LINE="Import-Module AITerminal -Force"
mkdir -p "$PROFILE_DIR"
if ! grep -qF "$IMPORT_LINE" "$PROFILE_PATH" 2> /dev/null; then
    if [[ -s "$PROFILE_PATH" ]]; then
        echo "" >> "$PROFILE_PATH"
    fi
    echo "# AI Terminal Auto-Load" >> "$PROFILE_PATH"
    echo "$IMPORT_LINE" >> "$PROFILE_PATH"
fi

# Create launcher script
LAUNCHER_TMP="$(mktemp)"
cat > "$LAUNCHER_TMP" << 'EOF'
#!/bin/bash
# AI Terminal Launcher
if ! ollama list > /dev/null 2>&1; then
    echo "Starting Ollama service..."
    nohup ollama serve > /dev/null 2>&1 &
    sleep 2
fi
pwsh -NoExit -Command "Import-Module AITerminal -Force"
EOF
chmod 755 "$LAUNCHER_TMP"

BIN_DIR="${NEWTERMINAL_AI_BIN_DIR:-/usr/local/bin}"
if mkdir -p "$BIN_DIR" 2> /dev/null && [[ -w "$BIN_DIR" ]]; then
    mv "$LAUNCHER_TMP" "$BIN_DIR/ai-terminal"
elif [[ -z "$NEWTERMINAL_AI_BIN_DIR" ]] && command -v sudo &> /dev/null && sudo mkdir -p "$BIN_DIR" && sudo install -m 755 "$LAUNCHER_TMP" "$BIN_DIR/ai-terminal"; then
    rm -f "$LAUNCHER_TMP"
else
    # No write access and no sudo: fall back to a per-user directory
    BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
    mv "$LAUNCHER_TMP" "$BIN_DIR/ai-terminal"
    echo "ℹ️  Installed the launcher to $BIN_DIR. Add it to your PATH if it is not there yet."
fi

echo "✅ Installation complete!"
echo ""
echo "🚀 Usage:"
echo "   ai-terminal    # Start AI Terminal ($BIN_DIR/ai-terminal)"
echo "   pwsh           # Start PowerShell with AI Terminal loaded"
echo ""
echo "💡 The AI Terminal will start automatically in natural language mode."
echo "   Just describe what you want to do in plain English!"
