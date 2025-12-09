#!/bin/bash
set -e

# Build script for TWS IO desktop application
# This script builds the Elixir backend and packages it with Tauri

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TAURI_DIR="$PROJECT_DIR/tauri/src-tauri"
BINARIES_DIR="$TAURI_DIR/binaries"

# Detect current platform
detect_platform() {
    case "$(uname -s)" in
        Darwin)
            case "$(uname -m)" in
                arm64) echo "aarch64-apple-darwin" ;;
                x86_64) echo "x86_64-apple-darwin" ;;
            esac
            ;;
        Linux)
            echo "x86_64-unknown-linux-gnu"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "x86_64-pc-windows-msvc"
            ;;
    esac
}

PLATFORM=$(detect_platform)
echo "Building for platform: $PLATFORM"

cd "$PROJECT_DIR"

# Step 1: Build Phoenix assets
echo "==> Building Phoenix assets..."
MIX_ENV=prod mix assets.deploy

# Step 2: Build Elixir release with Burrito
echo "==> Building Elixir release..."
MIX_ENV=prod mix release tsw_io_desktop

# Step 3: Copy binary to Tauri binaries folder with platform suffix
echo "==> Copying binary to Tauri..."
mkdir -p "$BINARIES_DIR"

# Find the burrito output
BURRITO_OUTPUT="$PROJECT_DIR/burrito_out"
if [ -d "$BURRITO_OUTPUT" ]; then
    # Find the built binary (name varies by platform)
    BINARY=$(find "$BURRITO_OUTPUT" -type f -name "tsw_io_desktop*" | head -1)
    if [ -n "$BINARY" ]; then
        TARGET="$BINARIES_DIR/tsw_io_backend-$PLATFORM"
        cp "$BINARY" "$TARGET"
        chmod +x "$TARGET"
        echo "Copied: $TARGET"
    else
        echo "Error: Could not find built binary in $BURRITO_OUTPUT"
        exit 1
    fi
else
    echo "Error: Burrito output directory not found"
    exit 1
fi

# Step 4: Build Tauri application
echo "==> Building Tauri application..."
cd "$TAURI_DIR"
cargo tauri build

echo "==> Build complete!"
echo "Output: $TAURI_DIR/target/release/bundle/"
