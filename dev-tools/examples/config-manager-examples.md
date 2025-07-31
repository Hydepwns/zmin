# Config Manager Examples

The config-manager tool provides centralized configuration management for all zmin tools and workflows.

## Basic Usage

### Configuration File Management

```bash
# Show current configuration
config-manager --show-config

# Load configuration from file
config-manager --load-config zmin.config.json

# Save current configuration to file
config-manager --save-config my-config.json

# Validate configuration file
config-manager --validate-config production.config.json
```

### Configuration Values

```bash
# Get specific configuration value
config-manager --get-value dev_server.port

# Set configuration value
config-manager --set-value dev_server.port 3000

# Remove configuration key
config-manager --remove-key profiler.enable_memory_tracking
```

## Configuration Examples

### Complete Configuration File

```json
{
  "global": {
    "log_level": "info",
    "temp_directory": "/tmp/zmin",
    "max_workers": 12,
    "enable_telemetry": false
  },
  "dev_server": {
    "port": 8080,
    "host": "localhost",
    "enable_debugging": true,
    "log_requests": true,
    "max_request_size": "10MB",
    "timeout": 30000,
    "cors_enabled": true,
    "static_files_path": "./static"
  },
  "debugger": {
    "debug_level": "basic",
    "enable_profiling": true,
    "enable_memory_tracking": true,
    "enable_stack_traces": true,
    "benchmark_iterations": 50,
    "stress_test_enabled": false,
    "log_file": null
  },
  "profiler": {
    "output_dir": "./profiles",
    "default_modes": ["eco", "sport", "turbo"],
    "default_iterations": 50,
    "warmup_iterations": 5,
    "enable_cpu_profiling": true,
    "enable_memory_profiling": true,
    "sample_rate": 1000,
    "output_format": "json",
    "save_raw_data": false
  },
  "plugin_registry": {
    "search_paths": [
      "/usr/local/lib/zmin/plugins",
      "/opt/zmin/plugins",
      "./plugins",
      "~/.zmin/plugins"
    ],
    "auto_discover": true,
    "enabled_plugins": [],
    "disabled_plugins": [],
    "plugin_timeout": 5000,
    "max_plugins": 50
  },
  "hot_reloading": {
    "watch_patterns": ["*.json", "*.zig"],
    "ignore_patterns": [".git", "node_modules", "zig-out", ".zig-cache"],
    "debounce_ms": 500,
    "recursive": true,
    "follow_symlinks": false,
    "max_files": 10000
  },
  "minifier": {
    "default_mode": "sport",
    "parallel_threshold": 1024,
    "memory_limit": "1GB",
    "timeout": 30000,
    "preserve_numbers": false,
    "validate_output": true
  }
}
```

### Environment-Specific Configurations

#### Development Configuration

```json
{
  "global": {
    "log_level": "debug",
    "enable_telemetry": false
  },
  "dev_server": {
    "port": 3000,
    "enable_debugging": true,
    "log_requests": true
  },
  "debugger": {
    "debug_level": "verbose",
    "enable_profiling": true,
    "benchmark_iterations": 20
  },
  "profiler": {
    "default_iterations": 10,
    "save_raw_data": true
  }
}
```

#### Production Configuration

```json
{
  "global": {
    "log_level": "warn",
    "enable_telemetry": true,
    "max_workers": 16
  },
  "dev_server": {
    "port": 8080,
    "host": "0.0.0.0",
    "enable_debugging": false,
    "log_requests": false,
    "max_request_size": "50MB"
  },
  "debugger": {
    "debug_level": "none",
    "enable_profiling": false,
    "benchmark_iterations": 100
  },
  "profiler": {
    "default_iterations": 100,
    "save_raw_data": false,
    "output_format": "summary"
  }
}
```

## Advanced Examples

### Configuration Management Scripts

```bash
#!/bin/bash
# setup-environment.sh

ENVIRONMENT=${1:-development}

echo "Setting up $ENVIRONMENT environment..."

case $ENVIRONMENT in
  "development")
    config-manager --load-config configs/development.json
    config-manager --set-value global.log_level debug
    config-manager --set-value dev_server.port 3000
    ;;
  "staging")
    config-manager --load-config configs/staging.json  
    config-manager --set-value global.log_level info
    config-manager --set-value dev_server.port 8080
    ;;
  "production")
    config-manager --load-config configs/production.json
    config-manager --set-value global.log_level warn
    config-manager --set-value dev_server.host "0.0.0.0"
    ;;
  *)
    echo "Unknown environment: $ENVIRONMENT"
    exit 1
    ;;
esac

echo "✅ Environment $ENVIRONMENT configured"
config-manager --show-config --format summary
```

### Configuration Validation

```bash
#!/bin/bash
# validate-configs.sh

CONFIGS=(
  "configs/development.json"
  "configs/staging.json"
  "configs/production.json"
)

echo "Validating configuration files..."

for config in "${CONFIGS[@]}"; do
  echo "Validating $config..."
  
  if config-manager --validate-config "$config"; then
    echo "✅ $config is valid"
  else
    echo "❌ $config has errors"
    exit 1
  fi
done

echo "✅ All configurations are valid"
```

### Dynamic Configuration Updates

```bash
#!/bin/bash
# update-runtime-config.sh

echo "Updating runtime configuration..."

# Update server configuration
config-manager --set-value dev_server.max_request_size "20MB"
config-manager --set-value profiler.default_iterations 75

# Enable debug mode temporarily
config-manager --set-value global.log_level debug
config-manager --set-value debugger.debug_level verbose

echo "Configuration updated. Restart services to apply changes."

# Show updated values
echo "Current settings:"
config-manager --get-value dev_server.max_request_size
config-manager --get-value profiler.default_iterations
config-manager --get-value global.log_level
```

## Integration Examples

### Docker Configuration

```dockerfile
FROM ubuntu:latest

# Copy configuration files
COPY configs/production.json /etc/zmin/config.json
COPY tools/config-manager /usr/local/bin/

# Set up configuration
RUN config-manager --load-config /etc/zmin/config.json

# Set environment-specific overrides
ENV ZMIN_CONFIG=/etc/zmin/config.json
ENV ZMIN_LOG_LEVEL=info
ENV ZMIN_DEV_SERVER_PORT=8080

CMD ["dev-server"]
```

### Kubernetes ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: zmin-config
data:
  zmin.config.json: |
    {
      "global": {
        "log_level": "info",
        "max_workers": 8
      },
      "dev_server": {
        "port": 8080,
        "host": "0.0.0.0",
        "enable_debugging": false
      },
      "profiler": {
        "default_iterations": 50,
        "output_format": "json"
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zmin-dev-server
spec:
  template:
    spec:
      containers:
      - name: zmin
        image: zmin:latest
        volumeMounts:
        - name: config
          mountPath: /etc/zmin
        command: ["config-manager", "--load-config", "/etc/zmin/zmin.config.json", "&&", "dev-server"]
      volumes:
      - name: config
        configMap:
          name: zmin-config
```

### CI/CD Configuration Management

```yaml
# .github/workflows/config-management.yml
name: Configuration Management

on:
  push:
    paths:
      - 'configs/**'
  pull_request:
    paths:
      - 'configs/**'

jobs:
  validate-configs:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    
    - name: Build config-manager
      run: zig build tools
    
    - name: Validate all configurations
      run: |
        for config in configs/*.json; do
          echo "Validating $config..."
          ./zig-out/bin/config-manager --validate-config "$config"
        done
    
    - name: Test configuration loading
      run: |
        ./zig-out/bin/config-manager --load-config configs/production.json
        ./zig-out/bin/config-manager --show-config --format json > test-config.json
        
        # Verify critical settings
        jq -e '.dev_server.port == 8080' test-config.json
        jq -e '.global.log_level == "warn"' test-config.json
```

## Configuration Schema Examples

### JSON Schema for Validation

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "zmin Configuration",
  "type": "object",
  "properties": {
    "global": {
      "type": "object",
      "properties": {
        "log_level": {
          "type": "string",
          "enum": ["debug", "info", "warn", "error"]
        },
        "max_workers": {
          "type": "integer",
          "minimum": 1,
          "maximum": 256
        },
        "enable_telemetry": {
          "type": "boolean"
        }
      }
    },
    "dev_server": {
      "type": "object",
      "properties": {
        "port": {
          "type": "integer",
          "minimum": 1,
          "maximum": 65535
        },
        "host": {
          "type": "string",
          "format": "hostname"
        },
        "enable_debugging": {
          "type": "boolean"
        }
      },
      "required": ["port"]
    },
    "debugger": {
      "type": "object",
      "properties": {
        "debug_level": {
          "type": "string", 
          "enum": ["none", "basic", "verbose", "trace"]
        },
        "benchmark_iterations": {
          "type": "integer",
          "minimum": 1,
          "maximum": 10000
        }
      }
    }
  }
}
```

## Command Line Usage Examples

### Interactive Configuration

```bash
# Interactive configuration wizard
config-manager --interactive

# Sample interactive session:
# > Select configuration section: [global, dev_server, debugger, profiler]
# > dev_server
# > Set port (current: 8080): 3000
# > Enable debugging (current: true): true
# > Set host (current: localhost): 0.0.0.0
# > Save changes? [y/N]: y
```

### Batch Configuration Updates

```bash
# Batch update multiple values
config-manager --batch-update << EOF
dev_server.port=3000
dev_server.host=0.0.0.0
debugger.debug_level=verbose
profiler.default_iterations=25
EOF

# From file
cat > updates.txt << EOF
global.log_level=debug
dev_server.enable_debugging=true
profiler.save_raw_data=true
EOF

config-manager --batch-update-file updates.txt
```

### Configuration Comparison

```bash
# Compare two configuration files
config-manager --compare configs/staging.json configs/production.json

# Output differences
config-manager --diff configs/old.json configs/new.json

# Show only changed values
config-manager --diff --changes-only configs/before.json configs/after.json
```

### Configuration Export/Import

```bash
# Export configuration to different formats
config-manager --export --format json > current-config.json
config-manager --export --format yaml > current-config.yaml
config-manager --export --format toml > current-config.toml

# Import from different formats
config-manager --import config.yaml
config-manager --import config.toml
```

## Best Practices

1. **Version Control Configurations**: Keep configuration files in version control
2. **Environment-Specific Configs**: Separate configurations for different environments
3. **Validate Before Deploy**: Always validate configurations before deployment
4. **Document Changes**: Use clear commit messages for configuration changes
5. **Backup Configurations**: Keep backups of working configurations
6. **Use Templates**: Create configuration templates for common setups
7. **Monitor Configuration**: Track configuration changes in production
8. **Secure Sensitive Data**: Use environment variables or secret management for sensitive values