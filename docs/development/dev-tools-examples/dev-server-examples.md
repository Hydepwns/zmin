# Dev Server Examples

The dev-server provides a web interface and REST API for JSON minification and system monitoring.

## Basic Usage

### Starting the Server

```bash
# Start on default port 8080
dev-server

# Start on custom port
dev-server 3000

# Start with custom host (allows external connections)
dev-server 8080 0.0.0.0
```

### Web Interface

```bash
# Start server and open browser
dev-server 8080 &
open http://localhost:8080  # macOS
xdg-open http://localhost:8080  # Linux
```

## REST API Examples

### Minification API

```bash
# Basic minification
curl -X POST http://localhost:8080/api/minify \
  -H "Content-Type: application/json" \
  -d '{
    "input": "{\"users\": [{\"id\": 1, \"name\": \"John Doe\"}]}",
    "mode": "sport"
  }'

# Response:
{
  "output": "{\"users\":[{\"id\":1,\"name\":\"John Doe\"}]}",
  "original_size": 45,
  "minified_size": 37,
  "compression_ratio": 1.22
}
```

### Benchmark API

```bash
# Compare all modes
curl -X POST http://localhost:8080/api/benchmark \
  -H "Content-Type: application/json" \
  -d '{
    "input": "{\"test\": {\"data\": [1, 2, 3, 4, 5]}}"
  }'

# Response:
{
  "results": [
    {"mode": "eco", "time_ms": 0.12, "size": 25},
    {"mode": "sport", "time_ms": 0.08, "size": 24},
    {"mode": "turbo", "time_ms": 0.05, "size": 23}
  ]
}
```

### System Information APIs

```bash
# Current statistics
curl http://localhost:8080/api/stats

# Performance metrics
curl http://localhost:8080/api/metrics

# System information
curl http://localhost:8080/api/system

# Memory information
curl http://localhost:8080/api/memory
```

## Advanced Examples

### Batch Processing

```bash
# Process multiple files
for file in *.json; do
  echo "Processing $file..."
  
  curl -X POST http://localhost:8080/api/minify \
    -H "Content-Type: application/json" \
    -d "{\"input\": \"$(cat "$file" | sed 's/"/\\"/g')\", \"mode\": \"turbo\"}" \
    -o "minified-$file"
    
  echo "✅ Processed $file"
done
```

### Performance Monitoring

```bash
#!/bin/bash
# monitor-server.sh

echo "Monitoring dev-server performance..."

while true; do
  echo "$(date): Checking server stats..."
  
  # Get current stats
  curl -s http://localhost:8080/api/stats | jq '{
    requests: .requests_count,
    avg_response_time: .average_response_time,
    memory_usage: .memory_usage
  }'
  
  sleep 10
done
```

### Load Testing

```bash
#!/bin/bash
# load-test.sh

echo "Running load test against dev-server..."

# Test data
TEST_JSON='{"users": [{"id": 1, "name": "Test User", "data": {"preferences": {"theme": "dark", "language": "en"}}}]}'

# Run concurrent requests
for i in {1..100}; do
  {
    curl -X POST http://localhost:8080/api/minify \
      -H "Content-Type: application/json" \
      -d "{\"input\": \"$TEST_JSON\", \"mode\": \"sport\"}" \
      -w "%{time_total}\n" \
      -o /dev/null -s
  } &
done

wait
echo "Load test completed!"
```

## Integration Examples

### Node.js Integration

```javascript
// server-client.js
const axios = require('axios');

class ZminClient {
  constructor(baseURL = 'http://localhost:8080') {
    this.client = axios.create({ baseURL });
  }

  async minify(input, mode = 'sport') {
    try {
      const response = await this.client.post('/api/minify', {
        input: JSON.stringify(input),
        mode
      });
      return response.data;
    } catch (error) {
      throw new Error(`Minification failed: ${error.message}`);
    }
  }

  async benchmark(input) {
    const response = await this.client.post('/api/benchmark', {
      input: JSON.stringify(input)
    });
    return response.data;
  }

  async getStats() {
    const response = await this.client.get('/api/stats');
    return response.data;
  }
}

// Usage
const client = new ZminClient();

async function example() {
  const data = { users: [{ id: 1, name: 'John' }] };
  
  // Minify data
  const result = await client.minify(data, 'turbo');
  console.log('Minified:', result.output);
  
  // Get performance stats
  const stats = await client.getStats();
  console.log('Server stats:', stats);
}

example().catch(console.error);
```

### Python Integration

```python
# server_client.py
import requests
import json

class ZminClient:
    def __init__(self, base_url='http://localhost:8080'):
        self.base_url = base_url
    
    def minify(self, data, mode='sport'):
        response = requests.post(f'{self.base_url}/api/minify', json={
            'input': json.dumps(data),
            'mode': mode
        })
        response.raise_for_status()
        return response.json()
    
    def benchmark(self, data):
        response = requests.post(f'{self.base_url}/api/benchmark', json={
            'input': json.dumps(data)
        })
        response.raise_for_status()
        return response.json()
    
    def get_stats(self):
        response = requests.get(f'{self.base_url}/api/stats')
        response.raise_for_status()
        return response.json()

# Usage
client = ZminClient()

data = {'users': [{'id': 1, 'name': 'Alice', 'active': True}]}

# Minify
result = client.minify(data, 'turbo')
print(f"Original: {result['original_size']} bytes")
print(f"Minified: {result['minified_size']} bytes")
print(f"Ratio: {result['compression_ratio']:.2f}x")

# Benchmark
benchmark = client.benchmark(data)
for mode_result in benchmark['results']:
    print(f"{mode_result['mode']}: {mode_result['time_ms']:.2f}ms")
```

### Docker Integration

```dockerfile
# Dockerfile
FROM ubuntu:latest

# Install zmin and dev-server
COPY zig-out/bin/dev-server /usr/local/bin/
COPY tools/dev_server/ /app/static/

EXPOSE 8080

CMD ["dev-server", "8080", "0.0.0.0"]
```

```bash
# Docker usage
docker build -t zmin-dev-server .
docker run -p 8080:8080 zmin-dev-server

# Test the containerized server
curl http://localhost:8080/api/stats
```

## Configuration Examples

### Custom Server Configuration

```json
{
  "dev_server": {
    "port": 3000,
    "host": "0.0.0.0",
    "enable_cors": true,
    "max_request_size": "10MB",
    "timeout": 30000,
    "static_files": "./static",
    "enable_logging": true,
    "log_level": "info"
  }
}
```

### Reverse Proxy Setup (Nginx)

```nginx
# nginx.conf
server {
    listen 80;
    server_name api.example.com;
    
    location /zmin/ {
        proxy_pass http://localhost:8080/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

## Monitoring and Debugging

### Server Health Check

```bash
#!/bin/bash
# health-check.sh

check_server() {
    local url="http://localhost:8080"
    
    # Check if server is responding
    if curl -f -s "$url/api/stats" > /dev/null; then
        echo "✅ Server is healthy"
        return 0
    else
        echo "❌ Server is not responding"
        return 1
    fi
}

# Run health check
if check_server; then
    # Get detailed stats
    echo "Server statistics:"
    curl -s http://localhost:8080/api/stats | jq '.'
else
    echo "Server needs attention!"
    exit 1
fi
```

### Performance Monitoring

```bash
#!/bin/bash
# performance-monitor.sh

echo "Starting performance monitoring..."

while true; do
    STATS=$(curl -s http://localhost:8080/api/stats)
    
    REQUESTS=$(echo "$STATS" | jq -r '.requests_count')
    AVG_TIME=$(echo "$STATS" | jq -r '.average_response_time')
    MEMORY=$(echo "$STATS" | jq -r '.memory_usage')
    
    echo "$(date): Requests: $REQUESTS, Avg Time: ${AVG_TIME}ms, Memory: ${MEMORY} bytes"
    
    sleep 5
done
```

## Sample Server Responses

### Stats API Response
```json
{
  "cpu_usage": 15.2,
  "memory_usage": 52428800,
  "memory_total": 34359738368,
  "uptime": 3600,
  "requests_count": 1250,
  "active_connections": 3,
  "average_response_time": 2.45
}
```

### Metrics API Response
```json
{
  "minify_count": 856,
  "benchmark_count": 45,
  "total_bytes_processed": 15728640,
  "average_minify_time": 1.23,
  "cpu_features": "SSE SSE2 AVX AVX2",
  "numa_nodes": 1
}
```

## Best Practices

1. **Use appropriate ports**: Avoid conflicts with other services
2. **Enable CORS for web apps**: Configure cross-origin requests properly
3. **Monitor performance**: Use stats API to track server health
4. **Implement health checks**: Regular monitoring for production deployments
5. **Secure the server**: Use reverse proxy and authentication for production
6. **Handle errors gracefully**: Implement proper error handling in client code
7. **Use connection pooling**: For high-volume API usage