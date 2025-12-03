#!/bin/bash
set -e

# Configuration
APP_NAME="BiblioGenius"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Resolve backend path relative to script location (bibliogenius-app/macos/../../bibliogenius)
BACKEND_DIR="$SCRIPT_DIR/../../bibliogenius"
OUTPUT_DIR="Runner/Resources/backend"
BINARY_NAME="bibliogenius"

echo "🚀 Starting backend build for macOS..."

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Source cargo environment if available
if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
fi

# Explicitly add cargo bin to PATH (fallback)
export PATH="$HOME/.cargo/bin:$PATH"

# Check if cargo is installed
if ! command -v cargo &> /dev/null; then
    echo "❌ Cargo not found. Please install Rust (curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh)"
    exit 1
fi

cd "$BACKEND_DIR"

# Check for targets
echo "🔍 Checking Rust targets..."
rustup target add x86_64-apple-darwin
rustup target add aarch64-apple-darwin

# Build for Intel
echo "🏗️  Building for x86_64..."
cargo build --release --target x86_64-apple-darwin

# Build for Apple Silicon
echo "🏗️  Building for arm64..."
cargo build --release --target aarch64-apple-darwin

# Create Universal Binary (Lipofication)
echo "🔗 Creating Universal Binary..."
lipo -create \
    "target/x86_64-apple-darwin/release/$BINARY_NAME" \
    "target/aarch64-apple-darwin/release/$BINARY_NAME" \
    -output "$SCRIPT_DIR/Runner/Resources/backend/$BINARY_NAME"

# Make executable
chmod +x "$SCRIPT_DIR/Runner/Resources/backend/$BINARY_NAME"

echo "✅ Backend bundled successfully at macos/$OUTPUT_DIR/$BINARY_NAME"
