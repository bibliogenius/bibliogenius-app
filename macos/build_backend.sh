#!/bin/bash
set -e

# Configuration
APP_NAME="BiblioGenius"
BACKEND_DIR="../../bibliogenius"
OUTPUT_DIR="Runner/Resources/backend"
BINARY_NAME="bibliogenius"

echo "🚀 Starting backend build for macOS..."

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Check if cargo is installed
if ! command -v cargo &> /dev/null; then
    echo "❌ Cargo not found. Please install Rust."
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
    -output "../../bibliogenius-app/macos/$OUTPUT_DIR/$BINARY_NAME"

# Make executable
chmod +x "../../bibliogenius-app/macos/$OUTPUT_DIR/$BINARY_NAME"

echo "✅ Backend bundled successfully at macos/$OUTPUT_DIR/$BINARY_NAME"
