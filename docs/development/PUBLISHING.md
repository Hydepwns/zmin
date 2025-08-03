# Publishing Guide for zmin

This document outlines the publishing strategy and setup for distributing zmin - the world's fastest JSON minifier with 5+ GB/s throughput - across multiple package managers and platforms.

## Package Managers

### 1. Homebrew (macOS/Linux)

**Formula Location:** `homebrew/zmin.rb`

**Installation:**

```bash
brew install zmin
```

**Publishing Process:**

- Formula is automatically updated via GitHub Actions
- Uses `dawidd6/action-homebrew-bump-formula` action
- Requires `HOMEBREW_TOKEN` secret in repository settings

**Repository:** Will be submitted to homebrew-core after initial release

### 2. npm (Node.js/JavaScript)

**Package Name:** `@zmin/cli`
**Location:** `bindings/npm/`

**Installation:**

```bash
# Global CLI
npm install -g @zmin/cli

# Local dependency
npm install @zmin/cli
```

**Features:**

- WebAssembly-based implementation
- TypeScript definitions included
- Works in Node.js and browsers
- Command-line interface included

**Publishing Process:**

- Automated via GitHub Actions
- Requires `NPM_TOKEN` secret
- Publishes to npm registry with public access

### 3. PyPI (Python)

**Package Name:** `zmin`
**Location:** `bindings/python/`

**Installation:**

```bash
pip install zmin
```

**Features:**

- Native shared library bindings via ctypes
- Command-line interface
- Type hints included
- Cross-platform wheels

**Publishing Process:**

- Automated via GitHub Actions
- Uses `twine` for publishing
- Requires `PYPI_TOKEN` secret
- Builds wheels for multiple platforms

### 4. Docker Hub / GitHub Container Registry

**Images:**

- `zmin/zmin:latest`
- `ghcr.io/hydepwns/zmin:latest`

**Usage:**

```bash
# Docker Hub
docker run --rm -v $(pwd):/data zmin/zmin:latest /data/input.json /data/output.json

# GitHub Container Registry
docker run --rm -v $(pwd):/data ghcr.io/hydepwns/zmin:latest /data/input.json /data/output.json
```

**Publishing Process:**

- Multi-arch builds (linux/amd64, linux/arm64)
- Automated via GitHub Actions
- Published on every release

## Package Repositories

### APT (Debian/Ubuntu)

**Status:** Planned for future release

**Process:**

1. Create `.deb` packages
2. Set up APT repository
3. Submit to official Debian repositories

### RPM (Red Hat/Fedora/SUSE)

**Status:** Planned for future release

**Process:**

1. Create `.rpm` packages
2. Submit to distribution repositories
3. Set up Copr repository for Fedora

### AUR (Arch Linux)

**Status:** Planned for future release

**Process:**

1. Create PKGBUILD
2. Submit to AUR
3. Maintain both stable and git versions

### Chocolatey (Windows)

**Status:** Planned for future release

**Installation:**

```powershell
choco install zmin
```

## Release Process

### 1. Version Tagging

Create a new release by tagging:

```bash
git tag v1.0.0
git push origin v1.0.0
```

### 2. Automated Build and Release

The GitHub Actions workflow automatically:

1. **Builds** binaries for all platforms:
   - Linux (x64, ARM64, musl)
   - macOS (x64, ARM64)  
   - Windows (x64)

2. **Creates packages**:
   - npm package with WebAssembly
   - Python wheels
   - Docker images

3. **Publishes** to registries:
   - GitHub Releases with binaries
   - npm registry
   - PyPI
   - Docker Hub/GHCR
   - Updates Homebrew formula

4. **Generates** release notes with:
   - Changelog since last release
   - Performance benchmarks
   - SHA256 checksums

### 3. Manual Steps

After automated release:

1. **Verify packages** are published correctly
2. **Test installations** on different platforms
3. **Update documentation** if needed
4. **Announce release** on relevant channels

## Required Secrets

Configure these secrets in GitHub repository settings:

```
# Package registries
NPM_TOKEN          # npm publish token
PYPI_TOKEN         # PyPI API token
HOMEBREW_TOKEN     # GitHub token for Homebrew

# Docker registries  
DOCKER_USERNAME    # Docker Hub username
DOCKER_PASSWORD    # Docker Hub password
GITHUB_TOKEN       # Automatically provided by GitHub
```

## Distribution Statistics

Track package downloads and usage:

### npm

- Download stats available at: `https://npmjs.org/package/@zmin/cli`
- Weekly downloads tracked

### PyPI

- Download stats via: `https://pypistats.org/packages/zmin`
- Geographic distribution available

### Homebrew

- Analytics via: `brew analytics`
- Installation counts tracked

### Docker

- Pull statistics from Docker Hub dashboard
- GitHub Container Registry metrics

## Performance Benchmarks

Each release includes automated benchmarks:

### Test Data

- Small JSON (1KB): Simple object
- Medium JSON (100KB): Complex nested structure
- Large JSON (10MB): Array of objects
- Huge JSON (100MB): Real-world dataset

### Metrics Tracked

- Throughput (MB/s) per mode
- Memory usage (peak/average)
- CPU utilization
- Comparison with other minifiers

### Results Publishing

- Benchmark results in release notes
- Performance badges updated automatically
- Historical performance tracked

## Community Packages

### Third-party Distributions

**Conda/Conda-forge:**

- Status: Community maintained
- Installation: `conda install -c conda-forge zmin`

**Snap Package:**

- Status: Community maintained  
- Installation: `snap install zmin`

**Flatpak:**

- Status: Planned
- Distribution: Flathub

### Package Maintainers

We welcome community package maintainers for:

- Linux distributions
- BSD variants
- Alternative package managers

## Licensing and Legal

### License

- MIT License for maximum compatibility
- Compatible with all major package repositories

### Trademark

- "zmin" name is available for use
- Logo/branding assets in `/assets/`

### Security

- All packages signed where supported
- SHA256 checksums provided
- Reproducible builds where possible

## Support and Issues

### Package-specific Issues

- npm: Report at main repository
- PyPI: Report at main repository  
- Docker: Report at main repository
- Homebrew: Report at main repository

### General Support

- GitHub Issues for bugs/features
- GitHub Discussions for questions
- Documentation at `/docs/`

## Future Plans

### Q1 2024

- [ ] APT repository setup
- [ ] RPM packages for major distributions
- [ ] AUR package submission
- [ ] Chocolatey package

### Q2 2024

- [ ] Conda-forge submission
- [ ] Snap package
- [ ] Performance dashboard
- [ ] Download analytics integration

### Q3 2024

- [ ] Windows Store package
- [ ] Mac App Store evaluation
- [ ] Linux app image
- [ ] Portable/standalone releases
