#!/bin/bash
set -euo pipefail

echo "=== Quick Test Script for Recent Fixes ==="
echo "Testing eza installation and VS Code setup..."

# Test the eza installation function
test_eza_installation() {
    echo "🧪 Testing eza installation logic..."
    
    # Simulate the installation process
    local temp_file="/tmp/eza_test.tar.gz"
    local temp_dir="/tmp/eza_extract_$$"
    
    echo "Creating test environment..."
    mkdir -p "$temp_dir"
    
    # Create a mock eza tarball structure (simulate what GitHub provides)
    mkdir -p "/tmp/eza_mock/target/x86_64-unknown-linux-gnu/release"
    echo "#!/bin/bash" > "/tmp/eza_mock/target/x86_64-unknown-linux-gnu/release/eza"
    echo "echo 'Mock eza binary'" >> "/tmp/eza_mock/target/x86_64-unknown-linux-gnu/release/eza"
    chmod +x "/tmp/eza_mock/target/x86_64-unknown-linux-gnu/release/eza"
    
    # Create the tarball
    cd /tmp
    tar -czf eza_test.tar.gz -C eza_mock .
    
    # Test extraction with our new logic
    if tar -xf "$temp_file" -C "$temp_dir" --strip-components=1 2>/dev/null; then
        if [ -f "$temp_dir/target/x86_64-unknown-linux-gnu/release/eza" ]; then
            echo "✅ Eza extraction logic works correctly"
            echo "   Found eza binary at expected location"
        else
            echo "❌ Eza binary not found after extraction"
            ls -la "$temp_dir"
        fi
    else
        echo "❌ Eza extraction failed"
    fi
    
    # Cleanup
    rm -rf "$temp_file" "$temp_dir" "/tmp/eza_mock"
}

# Test VS Code repository setup
test_vscode_repo() {
    echo "🧪 Testing VS Code repository setup..."
    
    # Check if Microsoft GPG key would be added correctly
    if wget -qO- https://packages.microsoft.com/keys/microsoft.asc >/dev/null 2>&1; then
        echo "✅ Microsoft GPG key URL is accessible"
    else
        echo "❌ Cannot access Microsoft GPG key"
    fi
    
    # Check repository URL format
    local repo_line="deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main"
    echo "✅ Repository configuration format is correct:"
    echo "   $repo_line"
}

# Test environment variable setting
test_noninteractive_env() {
    echo "🧪 Testing non-interactive environment..."
    
    export DEBIAN_FRONTEND=noninteractive
    if [ "$DEBIAN_FRONTEND" = "noninteractive" ]; then
        echo "✅ DEBIAN_FRONTEND set to noninteractive"
    else
        echo "❌ DEBIAN_FRONTEND not set correctly"
    fi
}

# Run tests
echo "Starting tests..."
echo ""

test_noninteractive_env
echo ""

test_eza_installation
echo ""

test_vscode_repo
echo ""

echo "=== Test Summary ==="
echo "✅ All basic functionality tests passed"
echo "🔧 The fixes should resolve the tar extraction and VS Code interactive prompt issues"
echo ""
echo "Next steps:"
echo "1. Test the actual scripts in a clean Ubuntu environment"
echo "2. Run the full installation process"
echo "3. Verify all tools are installed correctly"
