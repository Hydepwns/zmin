#!/bin/bash

# Create Debian package for zmin
set -e

# Configuration
PACKAGE_NAME="zmin"
VERSION=$(git describe --tags --always --dirty)
ARCHITECTURE=$(dpkg --print-architecture)
PACKAGE_DIR="${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}"

echo "Creating Debian package: ${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}.deb"

# Clean previous builds
rm -rf "${PACKAGE_DIR}"
rm -f "${PACKAGE_NAME}_${VERSION}_${ARCHITECTURE}.deb"

# Create package directory structure
mkdir -p "${PACKAGE_DIR}/DEBIAN"
mkdir -p "${PACKAGE_DIR}/usr/bin"
mkdir -p "${PACKAGE_DIR}/usr/lib"
mkdir -p "${PACKAGE_DIR}/usr/include"
mkdir -p "${PACKAGE_DIR}/usr/share/doc/${PACKAGE_NAME}"
mkdir -p "${PACKAGE_DIR}/usr/share/${PACKAGE_NAME}/examples"

# Build the project
zig build install-all

# Copy files from zig-out to package directory
cp -r zig-out/bin/* "${PACKAGE_DIR}/usr/bin/" 2>/dev/null || true
cp -r zig-out/lib/* "${PACKAGE_DIR}/usr/lib/" 2>/dev/null || true
cp -r zig-out/include/* "${PACKAGE_DIR}/usr/include/" 2>/dev/null || true
cp -r zig-out/share/doc/zmin/* "${PACKAGE_DIR}/usr/share/doc/${PACKAGE_NAME}/" 2>/dev/null || true
cp -r zig-out/share/zmin/examples/* "${PACKAGE_DIR}/usr/share/${PACKAGE_NAME}/examples/" 2>/dev/null || true

# Create control file
cat > "${PACKAGE_DIR}/DEBIAN/control" << EOF
Package: ${PACKAGE_NAME}
Version: ${VERSION}
Architecture: ${ARCHITECTURE}
Maintainer: zmin developers <dev@zmin.org>
Depends: libc6
Priority: optional
Section: utils
Description: High-performance Zig minifier
 zmin is a fast, memory-efficient minifier written in Zig.
 It supports multiple optimization modes and parallel processing.
 .
 Features:
  - Multiple optimization modes (eco, sport, turbo)
  - Parallel processing support
  - Memory-efficient streaming
  - Cross-platform compatibility
  - WebAssembly support
EOF

# Create postinst script
cat > "${PACKAGE_DIR}/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e

# Update shared library cache
if command -v ldconfig >/dev/null 2>&1; then
    ldconfig
fi

# Set executable permissions
chmod +x /usr/bin/zmin 2>/dev/null || true
chmod +x /usr/bin/zmin-* 2>/dev/null || true

echo "zmin package installed successfully!"
EOF

chmod +x "${PACKAGE_DIR}/DEBIAN/postinst"

# Create prerm script
cat > "${PACKAGE_DIR}/DEBIAN/prerm" << 'EOF'
#!/bin/bash
set -e

# Clean up any temporary files
rm -f /tmp/zmin-* 2>/dev/null || true

echo "zmin package removal in progress..."
EOF

chmod +x "${PACKAGE_DIR}/DEBIAN/prerm"

# Set proper permissions
find "${PACKAGE_DIR}" -type f -exec chmod 644 {} \;
find "${PACKAGE_DIR}" -type d -exec chmod 755 {} \;
chmod 755 "${PACKAGE_DIR}/usr/bin/"* 2>/dev/null || true
chmod 755 "${PACKAGE_DIR}/DEBIAN/"*

# Build the package
dpkg-deb --build "${PACKAGE_DIR}"

# Clean up
rm -rf "${PACKAGE_DIR}"

echo "Package created: ${PACKAGE_DIR}.deb"
echo "To install: sudo dpkg -i ${PACKAGE_DIR}.deb"
