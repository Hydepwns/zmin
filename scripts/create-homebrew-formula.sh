#!/bin/bash

# Create Homebrew formula for zmin
set -e

# Configuration
PACKAGE_NAME="zmin"
VERSION=$(git describe --tags --always --dirty | sed 's/^v//')
REPO_URL="https://github.com/hydepwns/zmin"
RELEASE_URL="${REPO_URL}/releases/download/v${VERSION}"

echo "Creating Homebrew formula for zmin v${VERSION}"

# Create formula directory
mkdir -p homebrew

# Determine architecture and OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    if [[ $(uname -m) == "arm64" ]]; then
        ARCH="arm64"
    else
        ARCH="x86_64"
    fi
else
    OS="linux"
    if [[ $(uname -m) == "aarch64" ]]; then
        ARCH="arm64"
    else
        ARCH="x86_64"
    fi
fi

# Create the Homebrew formula
cat > "homebrew/${PACKAGE_NAME}.rb" << EOF
class Zmin < Formula
  desc "High-performance Zig minifier"
  homepage "${REPO_URL}"
  version "${VERSION}"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "${RELEASE_URL}/zmin-${VERSION}-aarch64-apple-darwin.tar.gz"
      sha256 "PLACEHOLDER_SHA256_ARM64_MACOS"
    else
      url "${RELEASE_URL}/zmin-${VERSION}-x86_64-apple-darwin.tar.gz"
      sha256 "PLACEHOLDER_SHA256_X86_64_MACOS"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "${RELEASE_URL}/zmin-${VERSION}-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "PLACEHOLDER_SHA256_ARM64_LINUX"
    else
      url "${RELEASE_URL}/zmin-${VERSION}-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "PLACEHOLDER_SHA256_X86_64_LINUX"
    end
  end

  def install
    # Install binary
    bin.install "zmin"

    # Install library files
    lib.install Dir["lib/*"]

    # Install header files
    include.install Dir["include/*"]

    # Install documentation
    doc.install Dir["share/doc/zmin/*"]

    # Install examples
    pkgshare.install Dir["share/zmin/examples/*"]
  end

  test do
    system "#{bin}/zmin", "--version"
  end
end
EOF

# Create a script to update the formula with actual SHA256 hashes
cat > "homebrew/update-formula-sha256.sh" << 'EOF'
#!/bin/bash

# Update Homebrew formula with actual SHA256 hashes
set -e

FORMULA_FILE="zmin.rb"
VERSION=$(grep "version" "$FORMULA_FILE" | cut -d'"' -f2)

echo "Updating SHA256 hashes for version $VERSION"

# Function to calculate SHA256 for a URL
calculate_sha256() {
    local url="$1"
    echo "Downloading $url to calculate SHA256..."
    curl -L "$url" | shasum -a 256 | cut -d' ' -f1
}

# Update macOS ARM64 SHA256
if grep -q "PLACEHOLDER_SHA256_ARM64_MACOS" "$FORMULA_FILE"; then
    ARM64_MACOS_URL="https://github.com/hydepwns/zmin/releases/download/v${VERSION}/zmin-${VERSION}-aarch64-apple-darwin.tar.gz"
    ARM64_MACOS_SHA256=$(calculate_sha256 "$ARM64_MACOS_URL")
    sed -i.bak "s/PLACEHOLDER_SHA256_ARM64_MACOS/$ARM64_MACOS_SHA256/g" "$FORMULA_FILE"
fi

# Update macOS x86_64 SHA256
if grep -q "PLACEHOLDER_SHA256_X86_64_MACOS" "$FORMULA_FILE"; then
    X86_64_MACOS_URL="https://github.com/hydepwns/zmin/releases/download/v${VERSION}/zmin-${VERSION}-x86_64-apple-darwin.tar.gz"
    X86_64_MACOS_SHA256=$(calculate_sha256 "$X86_64_MACOS_URL")
    sed -i.bak "s/PLACEHOLDER_SHA256_X86_64_MACOS/$X86_64_MACOS_SHA256/g" "$FORMULA_FILE"
fi

# Update Linux ARM64 SHA256
if grep -q "PLACEHOLDER_SHA256_ARM64_LINUX" "$FORMULA_FILE"; then
    ARM64_LINUX_URL="https://github.com/hydepwns/zmin/releases/download/v${VERSION}/zmin-${VERSION}-aarch64-unknown-linux-gnu.tar.gz"
    ARM64_LINUX_SHA256=$(calculate_sha256 "$ARM64_LINUX_URL")
    sed -i.bak "s/PLACEHOLDER_SHA256_ARM64_LINUX/$ARM64_LINUX_SHA256/g" "$FORMULA_FILE"
fi

# Update Linux x86_64 SHA256
if grep -q "PLACEHOLDER_SHA256_X86_64_LINUX" "$FORMULA_FILE"; then
    X86_64_LINUX_URL="https://github.com/hydepwns/zmin/releases/download/v${VERSION}/zmin-${VERSION}-x86_64-unknown-linux-gnu.tar.gz"
    X86_64_LINUX_SHA256=$(calculate_sha256 "$X86_64_LINUX_URL")
    sed -i.bak "s/PLACEHOLDER_SHA256_X86_64_LINUX/$X86_64_LINUX_SHA256/g" "$FORMULA_FILE"
fi

# Clean up backup files
rm -f "$FORMULA_FILE.bak"

echo "SHA256 hashes updated successfully!"
echo "Formula file: $FORMULA_FILE"
EOF

chmod +x "homebrew/update-formula-sha256.sh"

# Create installation instructions
cat > "homebrew/INSTALL.md" << EOF
# Installing zmin via Homebrew

## Option 1: Install from local formula (for testing)

```bash
# Clone this repository
git clone ${REPO_URL}
cd zmin

# Create the formula
./scripts/create-homebrew-formula.sh

# Install from local formula
brew install --formula homebrew/zmin.rb
```

## Option 2: Install from tap (when available)

```bash
# Add the tap
brew tap hydepwns/zmin

# Install zmin
brew install zmin
```

## Option 3: Install from URL

```bash
# Install directly from GitHub
brew install ${REPO_URL}/blob/main/homebrew/zmin.rb
```

## Usage

After installation, you can use zmin:

```bash
# Check version
zmin --version

# Minify a file
zmin input.js -o output.js

# Use different modes
zmin input.js -m eco -o output.js
zmin input.js -m sport -o output.js
zmin input.js -m turbo -o output.js
```

## Updating

```bash
brew upgrade zmin
```

## Uninstalling

```bash
brew uninstall zmin
```
EOF

echo "Homebrew formula created in homebrew/${PACKAGE_NAME}.rb"
echo "Update script created in homebrew/update-formula-sha256.sh"
echo "Installation instructions created in homebrew/INSTALL.md"
echo ""
echo "To use the formula:"
echo "  brew install --formula homebrew/${PACKAGE_NAME}.rb"
