#!/bin/bash
# Update version in all project files from a given version string
# Usage: ./scripts/update-version.sh 0.1.2
#
# Run this script before creating a release tag to ensure all version
# files are in sync.

set -e

VERSION="$1"

if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 0.1.2"
  exit 1
fi

# Remove 'v' prefix if present
VERSION="${VERSION#v}"

# Validate version format (semver)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: Invalid version format '$VERSION'. Expected format: X.Y.Z"
  exit 1
fi

echo "Updating all files to version $VERSION"

# Update files using perl for cross-platform in-place editing
# perl -pi -e works the same on macOS and Linux

# 1. Update mix.exs
echo "  - mix.exs"
perl -pi -e "s/version: \"[0-9]+\.[0-9]+\.[0-9]+\"/version: \"$VERSION\"/" mix.exs

# 2. Update tauri/src-tauri/tauri.conf.json
echo "  - tauri/src-tauri/tauri.conf.json"
perl -pi -e "s/\"version\": \"[0-9]+\.[0-9]+\.[0-9]+\"/\"version\": \"$VERSION\"/" tauri/src-tauri/tauri.conf.json

# 3. Update tauri/src-tauri/Cargo.toml (only the package version line)
echo "  - tauri/src-tauri/Cargo.toml"
perl -pi -e "s/^version = \"[0-9]+\.[0-9]+\.[0-9]+\"/version = \"$VERSION\"/" tauri/src-tauri/Cargo.toml

# 4. Update tauri/package.json
echo "  - tauri/package.json"
perl -pi -e "s/\"version\": \"[0-9]+\.[0-9]+\.[0-9]+\"/\"version\": \"$VERSION\"/" tauri/package.json

# 5. Update tauri/src-tauri/splash.html
echo "  - tauri/src-tauri/splash.html"
perl -pi -e "s/>v[0-9]+\.[0-9]+\.[0-9]+</>v$VERSION</" tauri/src-tauri/splash.html

# 6. Update Cargo.lock if cargo is available
if command -v cargo &> /dev/null && [ -f "tauri/src-tauri/Cargo.lock" ]; then
  echo "  - tauri/src-tauri/Cargo.lock (via cargo update)"
  (cd tauri/src-tauri && cargo update --package tsw-io 2>/dev/null) || true
fi

echo ""
echo "Done! Version updated to $VERSION in all files."
echo ""
echo "Next steps:"
echo "  1. Review changes: git diff"
echo "  2. Commit: git add -A && git commit -m \"Bump version to $VERSION\""
echo "  3. Tag: git tag v$VERSION"
echo "  4. Push: git push && git push --tags"
