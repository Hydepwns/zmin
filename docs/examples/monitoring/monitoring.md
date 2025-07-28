# zmin Monitoring and Observability

This directory contains configuration and tools for monitoring zmin performance and usage in production environments.

## Overview

zmin includes optional telemetry and monitoring capabilities designed for:

- **Performance tracking** - Monitor throughput, latency, and resource usage
- **Error monitoring** - Track parsing errors and failure rates  
- **Usage analytics** - Understand processing patterns and workloads
- **System health** - Monitor memory usage and system resource consumption

## Features

### 1. Built-in Metrics Collection

**Location:** `src/telemetry/metrics.zig`

**Capabilities:**

- Performance metrics (throughput, latency, memory usage)
- Error tracking and categorization
- System information collection
- Configurable sampling rates
- Privacy-respecting anonymous data collection

**Configuration:**

```bash
# Enable telemetry (opt-in)
export ZMIN_TELEMETRY_ENABLE=1

# Set metrics file path
export ZMIN_METRICS_FILE=/var/log/zmin/metrics.jsonl

# Configure sampling rate (0.0 to 1.0)
export ZMIN_SAMPLE_RATE=0.1

# Enable anonymous usage statistics
export ZMIN_ANONYMOUS_STATS=1

# Disable telemetry completely
export ZMIN_TELEMETRY_DISABLE=1
```

### 2. OpenTelemetry Integration

**Status:** Planned for v1.1.0

**Features:**

- OTLP (OpenTelemetry Protocol) export
- Distributed tracing support
- Custom metrics and spans
- Integration with popular observability platforms

**Configuration Example:**

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
export OTEL_SERVICE_NAME=zmin
export OTEL_RESOURCE_ATTRIBUTES=service.version=1.0.0
```

### 3. Prometheus Metrics

**Endpoint:** `http://localhost:9090/metrics` (when enabled)

**Metrics Exported:**

```
# Processing metrics
zmin_operations_total{mode="turbo",status="success"} 1234
zmin_processing_duration_seconds{mode="turbo"} 0.001
zmin_throughput_bytes_per_second{mode="turbo"} 3500000000

# Resource metrics  
zmin_memory_usage_bytes 52428800
zmin_cpu_usage_ratio 0.85

# Error metrics
zmin_errors_total{type="invalid_json"} 5
zmin_errors_total{type="memory_error"} 0
```

### 4. Grafana Dashboard

**Location:** `monitoring/grafana/zmin-dashboard.json`

**Panels:**

- Throughput over time (by mode)
- Processing latency percentiles
- Error rate and types
- Memory usage trends
- CPU utilization
- Input/output size distributions

**Installation:**

1. Import `zmin-dashboard.json` into Grafana
2. Configure Prometheus data source
3. Set up alerts for high error rates

### 5. Log Analysis

**Format:** Structured JSON logging

**Example Log Entry:**

```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "level": "INFO",
  "operation": "minify",
  "mode": "turbo",
  "input_size": 1048576,
  "output_size": 524288,
  "duration_ms": 2.5,
  "throughput_mbps": 419.4,
  "memory_peak_mb": 12.5,
  "simd_features": "avx2",
  "thread_count": 8,
  "success": true
}
```

## Deployment Configurations

### Docker with Monitoring

```yaml
version: '3.8'
services:
  zmin:
    image: zmin/zmin:latest
    environment:
      - ZMIN_TELEMETRY_ENABLE=1
      - ZMIN_METRICS_FILE=/metrics/zmin.jsonl
    volumes:
      - ./metrics:/metrics
    ports:
      - "9090:9090"  # Prometheus metrics
      
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./monitoring/prometheus:/etc/prometheus
    ports:
      - "9091:9090"
      
  grafana:
    image: grafana/grafana:latest
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - ./monitoring/grafana:/var/lib/grafana
    ports:
      - "3000:3000"
```

### Kubernetes Monitoring

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: zmin-config
data:
  ZMIN_TELEMETRY_ENABLE: "1"
  ZMIN_SAMPLE_RATE: "0.1"
  OTEL_EXPORTER_OTLP_ENDPOINT: "http://jaeger-collector:14268/api/traces"

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zmin
spec:
  replicas: 3
  selector:
    matchLabels:
      app: zmin
  template:
    metadata:
      labels:
        app: zmin
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"
    spec:
      containers:
      - name: zmin
        image: zmin/zmin:latest
        envFrom:
        - configMapRef:
            name: zmin-config
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "1000m"
```

### AWS CloudWatch Integration

```bash
# Install CloudWatch agent
aws logs create-log-group --log-group-name /aws/ec2/zmin

# Configure log shipping
export ZMIN_METRICS_FILE=/var/log/zmin/metrics.jsonl
export AWS_LOG_GROUP=/aws/ec2/zmin
```

## Performance Benchmarking

### Automated Benchmarks

**Schedule:** Every release and nightly builds

**Test Suite:**

- Small files (1KB - 100KB)
- Medium files (1MB - 100MB)  
- Large files (100MB - 1GB)
- Various JSON structures (nested, arrays, strings)

**Metrics Tracked:**

- Throughput (MB/s) per mode
- Memory usage (peak and average)
- CPU utilization
- Error rates
- Comparison with competing tools

### Performance Dashboard

Real-time performance tracking at: `https://perf.zmin.dev`

**Features:**

- Historical performance trends
- Regression detection
- Platform comparisons
- Interactive charts
- Download links for test data

## Alerting

### Critical Alerts

**High Error Rate:**

```
alert: ZminHighErrorRate
expr: rate(zmin_errors_total[5m]) > 0.1
for: 2m
annotations:
  summary: "zmin error rate is above 10%"
```

**Low Throughput:**

```
alert: ZminLowThroughput  
expr: avg(zmin_throughput_bytes_per_second) < 100000000
for: 5m
annotations:
  summary: "zmin throughput below 100 MB/s"
```

**High Memory Usage:**

```
alert: ZminHighMemoryUsage
expr: zmin_memory_usage_bytes > 1000000000
for: 1m
annotations:
  summary: "zmin memory usage above 1GB"
```

### Notification Channels

- **Slack:** `#zmin-alerts`
- **Email:** `ops@zmin.dev`
- **PagerDuty:** Critical production issues
- **GitHub Issues:** Automatic issue creation for regressions

## Privacy and Data Handling

### Data Collection Principles

1. **Opt-in by default** - No telemetry without explicit consent
2. **Anonymous data** - No personally identifiable information
3. **Minimal collection** - Only essential performance metrics
4. **Local storage** - Option to keep metrics locally only
5. **Transparent processing** - Open source metrics collection code

### Data Retention

- **Local metrics:** Managed by user/administrator
- **Anonymous aggregates:** 90 days maximum
- **Performance benchmarks:** Retained indefinitely for historical analysis
- **Error logs:** 30 days for debugging purposes

### GDPR Compliance

- Data processing lawful basis: Legitimate interest (performance optimization)
- Right to opt-out: `ZMIN_TELEMETRY_DISABLE=1`
- Data portability: JSON export available
- Right to deletion: Contact maintainers

## Troubleshooting

### Common Issues

**No Metrics Being Collected:**

```bash
# Check if telemetry is enabled
echo $ZMIN_TELEMETRY_ENABLE

# Verify file permissions
ls -la $ZMIN_METRICS_FILE

# Check for environment variable conflicts
env | grep ZMIN
```

**High Memory Usage in Metrics:**

```bash
# Reduce sampling rate
export ZMIN_SAMPLE_RATE=0.01

# Use remote endpoint instead of file
export ZMIN_REMOTE_ENDPOINT=http://localhost:4317
```

**Metrics Not Appearing in Grafana:**

1. Check Prometheus is scraping zmin endpoint
2. Verify time range in Grafana queries
3. Confirm metric names match dashboard queries

### Debug Logging

```bash
# Enable debug logging
export ZMIN_LOG_LEVEL=debug

# Log to file
export ZMIN_LOG_FILE=/var/log/zmin/debug.log

# Structured logging format
export ZMIN_LOG_FORMAT=json
```

## Contributing

### Adding New Metrics

1. Define metric in `src/telemetry/metrics.zig`
2. Update Prometheus exports
3. Add to Grafana dashboard
4. Document in this README
5. Add tests for metric collection

### Performance Testing

```bash
# Run performance benchmarks
zig build benchmark:all

# Generate performance report
./tools/performance_monitor.exe --output report.json

# Compare with baseline
./tools/performance_compare.exe baseline.json report.json
```

### Monitoring Infrastructure

Test monitoring setup:

```bash
# Start monitoring stack
docker-compose -f monitoring/docker-compose.yml up

# Generate test data
./scripts/generate_test_metrics.sh

# Verify metrics collection
curl http://localhost:9090/metrics | grep zmin
```

## Future Enhancements

### Planned Features

- **Real-time dashboards** - Live performance monitoring
- **Anomaly detection** - ML-based performance regression detection
- **Custom alerts** - User-configurable alerting rules
- **Multi-tenant metrics** - Separate metrics per application/user
- **Cost tracking** - Monitor compute costs in cloud environments

### Integration Roadmap

- **APM Tools:** New Relic, Datadog, AppDynamics, Signoz
- **Log Aggregation:** ELK Stack, Splunk, Fluentd
- **Cloud Platforms:** AWS CloudWatch, Google Cloud Monitoring, Azure Monitor
- **Service Mesh:** Istio, Linkerd observability integration
