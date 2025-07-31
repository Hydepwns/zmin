#!/bin/bash

# Create RPM package for zmin
set -e

# Configuration
PACKAGE_NAME="zmin"
VERSION=$(git describe --tags --always --dirty | sed 's/^v//')
RELEASE="1"
ARCHITECTURE=$(rpm --eval '%{_arch}')
PACKAGE_DIR="${PACKAGE_NAME}-${VERSION}"

echo "Creating RPM package: ${PACKAGE_NAME}-${VERSION}-${RELEASE}.${ARCHITECTURE}.rpm"

# Clean previous builds
rm -rf "${PACKAGE_DIR}"
rm -rf "rpmbuild"
rm -f "${PACKAGE_NAME}-${VERSION}-${RELEASE}.${ARCHITECTURE}.rpm"

# Create RPM build directory structure
mkdir -p rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Build the project
zig build install-all

# Create source tarball
tar -czf "rpmbuild/SOURCES/${PACKAGE_NAME}-${VERSION}.tar.gz" \
    --transform "s,^,${PACKAGE_NAME}-${VERSION}/," \
    zig-out/ \
    README.md \
    LICENSE \
    docs/ \
    examples/

# Create RPM spec file
cat > "rpmbuild/SPECS/${PACKAGE_NAME}.spec" << EOF
Name:           ${PACKAGE_NAME}
Version:        ${VERSION}
Release:        ${RELEASE}%{?dist}
Summary:        High-performance Zig minifier

License:        MIT
URL:            https://github.com/hydepwns/zmin
Source0:        %{name}-%{version}.tar.gz
BuildArch:      %{_arch}

Requires:       glibc

%description
zmin is a fast, memory-efficient minifier written in Zig.
It supports multiple optimization modes and parallel processing.

Features:
- Multiple optimization modes (eco, sport, turbo)
- Parallel processing support
- Memory-efficient streaming
- Cross-platform compatibility
- WebAssembly support

%prep
%autosetup

%build
# Build is done in the source tarball

%install
# Create directory structure
mkdir -p %{buildroot}%{_bindir}
mkdir -p %{buildroot}%{_libdir}
mkdir -p %{buildroot}%{_includedir}
mkdir -p %{buildroot}%{_docdir}/%{name}
mkdir -p %{buildroot}%{_datadir}/%{name}/examples

# Copy files
cp -r zig-out/bin/* %{buildroot}%{_bindir}/ 2>/dev/null || true
cp -r zig-out/lib/* %{buildroot}%{_libdir}/ 2>/dev/null || true
cp -r zig-out/include/* %{buildroot}%{_includedir}/ 2>/dev/null || true
cp -r zig-out/share/doc/zmin/* %{buildroot}%{_docdir}/%{name}/ 2>/dev/null || true
cp -r zig-out/share/zmin/examples/* %{buildroot}%{_datadir}/%{name}/examples/ 2>/dev/null || true

# Set permissions
chmod 755 %{buildroot}%{_bindir}/* 2>/dev/null || true

%files
%license LICENSE
%doc README.md
%doc %{_docdir}/%{name}/*
%{_bindir}/*
%{_libdir}/*
%{_includedir}/*
%{_datadir}/%{name}/examples/*

%post
# Update shared library cache
if command -v ldconfig >/dev/null 2>&1; then
    ldconfig
fi

echo "zmin package installed successfully!"

%preun
# Clean up any temporary files
rm -f /tmp/zmin-* 2>/dev/null || true

%changelog
* $(date '+%a %b %d %Y') zmin developers <dev@zmin.org> - ${VERSION}-${RELEASE}
- Initial RPM package
EOF

# Build the RPM
rpmbuild --define "_topdir $(pwd)/rpmbuild" -bb "rpmbuild/SPECS/${PACKAGE_NAME}.spec"

# Copy the built RPM to current directory
cp "rpmbuild/RPMS/${ARCHITECTURE}/${PACKAGE_NAME}-${VERSION}-${RELEASE}.${ARCHITECTURE}.rpm" .

# Clean up
rm -rf "rpmbuild"
rm -rf "${PACKAGE_DIR}"

echo "Package created: ${PACKAGE_NAME}-${VERSION}-${RELEASE}.${ARCHITECTURE}.rpm"
echo "To install: sudo rpm -i ${PACKAGE_NAME}-${VERSION}-${RELEASE}.${ARCHITECTURE}.rpm"
