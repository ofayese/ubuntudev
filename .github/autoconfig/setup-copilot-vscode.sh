#!/usr/bin/env bash
# setup-copilot-vscode.sh - Enhanced GitHub Copilot VS Code configuration
#
# This script sets up GitHub Copilot integration for VS Code with:
# - Environment-aware configuration (WSL2/Desktop/Headless)
# - Workspace and user-level settings management
# - Extension installation and validation
# - Custom prompt and instruction file setup
#
# Usage:
#   ./setup-copilot-vscode.sh [--user] [--extensions] [--validate]
#  ./setup-copilot-vscode.sh --user --extensions --validate

# Options:
#   --user       Apply settings to user configuration
#   --extensions Install/update Copilot extensions
#   --validate   Validate Copilot setup and functionality
#
set -euo pipefail

# Source utility functions if available
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
workspace_root="$(cd "${script_dir}/../.." && pwd)"

# Try to source environment utilities
if [ -f "${workspace_root}/util-env.sh" ]; then
    source "${workspace_root}/util-env.sh"
elif [ -f "${workspace_root}/util-log.sh" ]; then
    source "${workspace_root}/util-log.sh"
fi

# Fallback environment detection functions
is_wsl2() {
    [ -f /proc/version ] && grep -qi microsoft /proc/version 2>/dev/null
}

is_desktop_environment() {
    [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]
}

has_internet() {
    timeout 5 wget -q --spider https://github.com 2>/dev/null || \
    timeout 5 curl -s --head https://github.com >/dev/null 2>&1
}

log_info() {
    echo "ℹ️  $*"
}

log_success() {
    echo "✅ $*"
}

log_warning() {
    echo "⚠️  $*"
}

log_error() {
    echo "❌ $*" >&2
}

# --- VS Code Detection and Path Management ---
get_vscode_commands() {
    local commands=()
    
    if is_wsl2; then
        # WSL2: Check for Windows VS Code installations
        if [ -f "/mnt/c/Program Files/Microsoft VS Code/bin/code.cmd" ]; then
            commands+=("/mnt/c/Program Files/Microsoft VS Code/bin/code.cmd")
        fi
        if [ -f "/mnt/c/Program Files/Microsoft VS Code Insiders/bin/code-insiders.cmd" ]; then
            commands+=("/mnt/c/Program Files/Microsoft VS Code Insiders/bin/code-insiders.cmd")
        fi
        # Also check for user installations
        if [ -f "/mnt/c/Users/${USER}/AppData/Local/Programs/Microsoft VS Code/bin/code.cmd" ]; then
            commands+=("/mnt/c/Users/${USER}/AppData/Local/Programs/Microsoft VS Code/bin/code.cmd")
        fi
        if [ -f "/mnt/c/Users/${USER}/AppData/Local/Programs/Microsoft VS Code Insiders/bin/code-insiders.cmd" ]; then
            commands+=("/mnt/c/Users/${USER}/AppData/Local/Programs/Microsoft VS Code Insiders/bin/code-insiders.cmd")
        fi
    else
        # Native Linux: Check for local VS Code installations
        if command -v code >/dev/null 2>&1; then
            commands+=("code")
        fi
        if command -v code-insiders >/dev/null 2>&1; then
            commands+=("code-insiders")
        fi
        # Check snap installations
        if [ -f "/snap/bin/code" ]; then
            commands+=("/snap/bin/code")
        fi
        if [ -f "/snap/bin/code-insiders" ]; then
            commands+=("/snap/bin/code-insiders")
        fi
    fi
    
    printf '%s\n' "${commands[@]}"
}

get_vscode_command() {
    local commands
    readarray -t commands < <(get_vscode_commands)
    
    if [ ${#commands[@]} -eq 0 ]; then
        echo ""
        return 1
    fi
    
    # Return the first available command
    echo "${commands[0]}"
}

get_vscode_settings_dirs() {
    local settings_type="$1"  # "user" or "workspace"
    local dirs=()
    
    case "${settings_type}" in
        "user")
            if is_wsl2; then
                # WSL2 uses Windows VS Code user settings
                dirs+=("/mnt/c/Users/${USER}/AppData/Roaming/Code/User")
                dirs+=("/mnt/c/Users/${USER}/AppData/Roaming/Code - Insiders/User")
            else
                dirs+=("${HOME}/.config/Code/User")
                dirs+=("${HOME}/.config/Code - Insiders/User")
                # Snap installations
                if [ -d "${HOME}/snap/code/current/.config/Code/User" ]; then
                    dirs+=("${HOME}/snap/code/current/.config/Code/User")
                fi
            fi
            ;;
        "workspace")
            dirs+=("${workspace_root}/.vscode")
            ;;
        *)
            log_error "Invalid settings type: ${settings_type}"
            return 1
            ;;
    esac
    
    printf '%s\n' "${dirs[@]}"
}

# --- Extension Management ---
install_copilot_extensions() {
    local vscode_commands
    readarray -t vscode_commands < <(get_vscode_commands)
    
    if [ ${#vscode_commands[@]} -eq 0 ]; then
        log_error "VS Code not found. Please install VS Code or VS Code Insiders first."
        return 1
    fi
    
    log_info "Installing GitHub Copilot extensions..."
    
    local extensions=(
        "GitHub.copilot"
        "GitHub.copilot-chat"
        "GitHub.copilot-labs"
        "ms-vscode.vscode-json"  # Better JSON support for settings
        "ms-vscode-remote.remote-wsl"  # WSL extension for better integration
    )
    
    local success_count=0
    local total_installations=0
    
    for vscode_cmd in "${vscode_commands[@]}"; do
        local vscode_name
        vscode_name=$(basename "${vscode_cmd}" | sed 's/\.cmd$//')
        log_info "Installing extensions for ${vscode_name}..."
        
        for ext in "${extensions[@]}"; do
            ((total_installations++))
            log_info "Installing extension: ${ext} for ${vscode_name}"
            if "${vscode_cmd}" --install-extension "${ext}" --force >/dev/null 2>&1; then
                log_success "Extension ${ext} installed successfully for ${vscode_name}"
                ((success_count++))
            else
                log_warning "Failed to install extension: ${ext} for ${vscode_name}"
            fi
        done
        echo
    done
    
    log_info "Extension installation complete: ${success_count}/${total_installations} successful"
    return 0
}

validate_copilot_setup() {
    local vscode_commands
    readarray -t vscode_commands < <(get_vscode_commands)
    
    if [ ${#vscode_commands[@]} -eq 0 ]; then
        log_error "VS Code not found"
        return 1
    fi
    
    log_info "Validating GitHub Copilot setup..."
    
    # Check extensions for each VS Code installation
    local required_extensions=(
        "GitHub.copilot"
        "GitHub.copilot-chat"
    )
    
    for vscode_cmd in "${vscode_commands[@]}"; do
        local vscode_name
        vscode_name=$(basename "${vscode_cmd}" | sed 's/\.cmd$//')
        log_info "Checking extensions for ${vscode_name}..."
        
        for ext in "${required_extensions[@]}"; do
            if "${vscode_cmd}" --list-extensions 2>/dev/null | grep -q "${ext}"; then
                log_success "Extension ${ext} is installed for ${vscode_name}"
            else
                log_warning "Extension ${ext} is NOT installed for ${vscode_name}"
            fi
        done
        echo
    done
    
    # Check settings files
    local workspace_settings="${workspace_root}/.vscode/settings.json"
    if [ -f "${workspace_settings}" ]; then
        log_success "Workspace settings found"
        if grep -q "github.copilot.enable" "${workspace_settings}"; then
            log_success "Copilot is enabled in workspace settings"
        else
            log_warning "Copilot not configured in workspace settings"
        fi
    else
        log_warning "Workspace settings not found"
    fi
    
    # Check prompt and instruction files
    if [ -d "${workspace_root}/.github/prompts" ]; then
        local prompt_count
        prompt_count=$(find "${workspace_root}/.github/prompts" -name "*.prompt.md" | wc -l)
        log_success "Found ${prompt_count} prompt file(s)"
    else
        log_warning "Prompts directory not found"
    fi
    
    if [ -d "${workspace_root}/.github/instructions" ]; then
        local instruction_count
        instruction_count=$(find "${workspace_root}/.github/instructions" -name "*.md" | wc -l)
        log_success "Found ${instruction_count} instruction file(s)"
    else
        log_warning "Instructions directory not found"
    fi
}

setup_vscode_settings() {
    local vscode_dir="$1"
    local settings_file="${vscode_dir}/settings.json"
    
    # Ensure VS Code settings directory exists
    mkdir -p "${vscode_dir}"
    
    # Copy base settings if they don't exist or are outdated
    local source_settings="${workspace_root}/.github/.vscode/settings.json"
    if [ -f "${source_settings}" ]; then
        if [ ! -f "${settings_file}" ] || [ "${source_settings}" -nt "${settings_file}" ]; then
            # Backup existing settings if they exist
            if [ -f "${settings_file}" ]; then
                local backup_file="${settings_file}.backup.$(date +%Y%m%d_%H%M%S)"
                cp "${settings_file}" "${backup_file}"
                log_info "Backed up existing settings to ${backup_file}"
            fi
            
            cp "${source_settings}" "${settings_file}"
            log_success "VS Code Copilot settings applied to ${vscode_dir}"
        else
            log_info "Settings in ${vscode_dir} are already up to date"
        fi
    else
        log_error "Base settings file not found at ${source_settings}"
        return 1
    fi
}

# --- Main Setup Functions ---
setup_workspace_config() {
    log_info "Setting up workspace configuration..."
    setup_vscode_settings "$(get_vscode_settings_dir workspace)"
}

setup_user_config() {
    log_info "Setting up user configuration..."
    local user_settings_dir
    user_settings_dir="$(get_vscode_settings_dir user)"
    
    if is_wsl2; then
        log_info "WSL2 detected - checking Windows VS Code user settings"
        if [ ! -d "${user_settings_dir}" ]; then
            log_warning "Windows VS Code user directory not found: ${user_settings_dir}"
            log_info "User settings should be managed through Windows VS Code"
            return 0
        fi
    fi
    
    if [ -d "${user_settings_dir}" ]; then
        setup_vscode_settings "${user_settings_dir}"
    else
        log_warning "VS Code user directory not found at ${user_settings_dir}"
        log_info "Please run VS Code at least once to create the user directory"
    fi
}

# Setup for workspace
setup_vscode_settings ".vscode"

# Setup for user settings if requested
if [ "${1:-}" = "--user" ]; then
    if is_wsl2; then
        echo "ℹ️  WSL2 detected - user settings managed by Windows VS Code"
    else
        user_config="${HOME}/.config/Code/User"
        if [ -d "${user_config}" ]; then
            setup_vscode_settings "${user_config}"
        else
            echo "⚠️  VS Code user directory not found at ${user_config}"
        fi
    fi
fi

echo "✅ VS Code Copilot setup completed"
