# Scripts Directory

This directory contains various utility scripts for the Zmin project.

## CI/CD Testing Scripts

### `test-ci.sh`

Comprehensive CI/CD pipeline testing script that runs:

- Zig installation check
- Project build
- Test suite execution
- Performance benchmarks
- Badge generation
- Security analysis
- **Version management testing** (new)
- Performance regression testing
- Complete CI pipeline simulation
- Artifact validation

**Usage:**

```bash
./scripts/test-ci.sh
```

### `test-versions.sh`

Dedicated version management testing script that validates:

- Basic version reading from `.github/versions.json`
- JSON structure validation
- Required field presence (`zig`, `zmin`)
- Version format validation
- Sparse checkout simulation
- GitHub Actions output format
- Error scenario handling

**Usage:**

```bash
# Using nix-shell (recommended for NixOS)
nix-shell -p jq bash --run "bash scripts/test-versions.sh"

# Or if jq is available system-wide
./scripts/test-versions.sh
```

### `test-versions-only.sh`

Minimal version testing script that only tests version management without requiring a full build:

- Basic version reading validation
- Quick verification that the read-versions workflow would work

**Usage:**

```bash
nix-shell -p jq bash --run "bash scripts/test-versions-only.sh"
```

## Quick Version Testing

For a quick test of version reading:

```bash
nix-shell -p jq --run 'echo "zig=$(jq -r ".zig" .github/versions.json)" && echo "zmin=$(jq -r ".zmin" .github/versions.json)"'
```

## Other Scripts

- `common.sh` - Common functions used by other scripts
- `update-versions.sh` - Update version information
- `status.sh` - Show project status
- `organize.sh` - Organize project files
- `cleanup.sh` - Clean up build artifacts
- `serve-docs.sh` - Serve documentation locally
- `benchmark-single.sh` - Run single benchmark
- `update-performance-data.sh` - Update performance data
- `create-*.sh` - Package creation scripts for different platforms

## Dependencies

Most scripts require:

- `bash` - Shell environment
- `jq` - JSON processing (for version testing)
- `zig` - Zig compiler (for build and test scripts)

Use `nix-shell` to ensure all dependencies are available:

```bash
nix-shell -p jq bash zig --run "bash scripts/test-ci.sh"
```
