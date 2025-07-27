---
title: "Real-World Integration Examples"
date: 2024-01-01
draft: false
weight: 7
---


This guide shows how to integrate zmin into common development workflows, CI/CD pipelines, and production systems.

## Web Frameworks

### Express.js (Node.js)

#### Basic Middleware

```javascript
// middleware/json-minifier.js
const { minify } = require('@zmin/cli');

function jsonMinifierMiddleware(options = {}) {
  const { 
    enabled = process.env.NODE_ENV === 'production',
    mode = 'sport',
    threshold = 1024 // Only minify responses > 1KB
  } = options;

  return (req, res, next) => {
    if (!enabled) return next();

    const originalSend = res.send;
    
    res.send = function(data) {
      if (typeof data === 'object' || (typeof data === 'string' && data.length > threshold)) {
        try {
          const jsonString = typeof data === 'string' ? data : JSON.stringify(data);
          if (this.get('Content-Type')?.includes('application/json')) {
            const minified = minify(jsonString);
            return originalSend.call(this, minified);
          }
        } catch (error) {
          console.warn('zmin minification failed:', error.message);
        }
      }
      return originalSend.call(this, data);
    };
    
    next();
  };
}

module.exports = jsonMinifierMiddleware;
```

#### Usage in Express App

```javascript
// app.js
const express = require('express');
const jsonMinifier = require('./middleware/json-minifier');

const app = express();

// Apply JSON minification middleware
app.use(jsonMinifier({
  enabled: process.env.NODE_ENV === 'production',
  mode: 'turbo',
  threshold: 500
}));

// API routes
app.get('/api/data', (req, res) => {
  const largeData = {
    users: generateLargeUserList(),
    metadata: getMetadata(),
    timestamp: new Date().toISOString()
  };
  
  res.json(largeData); // Automatically minified
});

// Performance monitoring
app.get('/api/health', (req, res) => {
  res.json({
    status: 'healthy',
    minifier: {
      enabled: !!res.locals.minifierEnabled,
      version: require('@zmin/cli').version()
    }
  });
});

app.listen(3000, () => {
  console.log('Server running with zmin integration');
});
```

### FastAPI (Python)

#### Custom Middleware

```python
# middleware/json_minifier.py
import zmin
from fastapi import Request, Response
from fastapi.responses import JSONResponse
import json
import time

class ZminMiddleware:
    def __init__(self, app, enabled: bool = True, mode: str = "sport", min_size: int = 1024):
        self.app = app
        self.enabled = enabled
        self.mode = getattr(zmin.ProcessingMode, mode.upper())
        self.min_size = min_size
        
    async def __call__(self, scope, receive, send):
        if not self.enabled or scope["type"] != "http":
            await self.app(scope, receive, send)
            return
            
        # Wrap send to intercept responses
        async def send_wrapper(message):
            if message["type"] == "http.response.body":
                body = message.get("body", b"")
                if len(body) > self.min_size:
                    try:
                        # Check if content is JSON
                        if b"application/json" in message.get("headers", []):
                            decoded_body = body.decode("utf-8")
                            minified = zmin.minify(decoded_body, mode=self.mode)
                            message["body"] = minified.encode("utf-8")
                    except Exception as e:
                        print(f"zmin minification failed: {e}")
                        
            await send(message)
            
        await self.app(scope, receive, send_wrapper)
```

#### FastAPI Application

```python
# main.py
from fastapi import FastAPI, HTTPException
from middleware.json_minifier import ZminMiddleware
import zmin
from typing import List, Dict, Any
import os

app = FastAPI(title="API with zmin Integration")

# Add zmin middleware
app.add_middleware(
    ZminMiddleware,
    enabled=os.getenv("MINIFY_JSON", "true").lower() == "true",
    mode="turbo",
    min_size=512
)

@app.get("/api/large-dataset")
async def get_large_dataset() -> Dict[str, Any]:
    """Returns a large dataset that benefits from minification."""
    return {
        "data": [{"id": i, "name": f"Item {i}", "value": i * 1.5} for i in range(10000)],
        "metadata": {
            "total_count": 10000,
            "generated_at": "2024-01-01T00:00:00Z",
            "version": "1.0.0"
        }
    }

@app.get("/api/config")
async def get_config():
    """API configuration including minification status."""
    return {
        "minification": {
            "enabled": True,
            "version": zmin.get_version(),
            "mode": "turbo"
        },
        "performance": {
            "average_response_time": "145ms",
            "compression_ratio": "23%"
        }
    }

# Batch processing endpoint
@app.post("/api/minify-batch")
async def minify_batch(data: List[Dict[str, Any]]):
    """Minify multiple JSON objects."""
    results = []
    for item in data:
        try:
            json_str = json.dumps(item)
            minified = zmin.minify(json_str, mode=zmin.ProcessingMode.TURBO)
            results.append({
                "original_size": len(json_str),
                "minified_size": len(minified),
                "compression_ratio": round((1 - len(minified) / len(json_str)) * 100, 2),
                "minified": minified
            })
        except Exception as e:
            results.append({"error": str(e)})
    
    return {"results": results}
```

### Spring Boot (Java via JNI)

```java
// ZminService.java
@Service
public class ZminService {
    
    static {
        System.loadLibrary("zmin");
    }
    
    public native String minify(String json, int mode);
    public native boolean validate(String json);
    public native String getVersion();
    
    @Value("${zmin.enabled:true}")
    private boolean enabled;
    
    @Value("${zmin.mode:sport}")
    private String mode;
    
    public String minifyJson(String json) {
        if (!enabled) return json;
        
        try {
            int modeValue = switch (mode) {
                case "eco" -> 0;
                case "sport" -> 1;
                case "turbo" -> 2;
                default -> 1;
            };
            
            return minify(json, modeValue);
        } catch (Exception e) {
            log.warn("JSON minification failed: {}", e.getMessage());
            return json;
        }
    }
}

// ResponseMinificationInterceptor.java
@Component
public class ResponseMinificationInterceptor implements HandlerInterceptor {
    
    @Autowired
    private ZminService zminService;
    
    @Override
    public void postHandle(HttpServletRequest request, 
                          HttpServletResponse response, 
                          Object handler, 
                          ModelAndView modelAndView) {
        
        String contentType = response.getContentType();
        if (contentType != null && contentType.contains("application/json")) {
            // Wrap response to minify JSON output
            response = new ZminResponseWrapper(response, zminService);
        }
    }
}
```

## CI/CD Pipeline Integration

### GitHub Actions

```yaml
# .github/workflows/minify-assets.yml
name: Minify JSON Assets

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  minify-json:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Setup zmin
      run: |
        wget https://github.com/hydepwns/zmin/releases/download/v1.0.0/zmin-linux-x64
        chmod +x zmin-linux-x64
        sudo mv zmin-linux-x64 /usr/local/bin/zmin
    
    - name: Validate JSON files
      run: |
        find . -name "*.json" | while read file; do
          echo "Validating $file"
          if ! zmin --validate "$file"; then
            echo "❌ Invalid JSON: $file"
            exit 1
          fi
        done
    
    - name: Minify JSON assets
      run: |
        find assets/ -name "*.json" | while read file; do
          echo "Minifying $file"
          zmin --mode turbo "$file" "$file.tmp"
          mv "$file.tmp" "$file"
        done
    
    - name: Generate minification report
      run: |
        echo "# JSON Minification Report" > minification-report.md
        echo "| File | Original Size | Minified Size | Savings |" >> minification-report.md
        echo "|------|---------------|---------------|---------|" >> minification-report.md
        
        find assets/ -name "*.json" | while read file; do
          original_size=$(wc -c < "$file.orig" 2>/dev/null || echo "N/A")
          current_size=$(wc -c < "$file")
          if [[ "$original_size" != "N/A" ]]; then
            savings=$(echo "scale=1; ($original_size - $current_size) * 100 / $original_size" | bc)
            echo "| $file | $original_size | $current_size | ${savings}% |" >> minification-report.md
          fi
        done
    
    - name: Commit minified files
      run: |
        git config --local user.email "action@github.com"
        git config --local user.name "GitHub Action"
        git add assets/
        git diff --staged --quiet || git commit -m "🗜️ Minify JSON assets [skip ci]"
        git push
```

### GitLab CI/CD

```yaml
# .gitlab-ci.yml
stages:
  - validate
  - build
  - deploy

variables:
  ZMIN_VERSION: "1.0.0"

before_script:
  - apt-get update -qq && apt-get install -qq -y wget
  - wget -O /usr/local/bin/zmin https://github.com/hydepwns/zmin/releases/download/v${ZMIN_VERSION}/zmin-linux-x64
  - chmod +x /usr/local/bin/zmin

validate-json:
  stage: validate
  script:
    - find . -name "*.json" -exec zmin --validate {} \;
  rules:
    - changes:
        - "**/*.json"

minify-configs:
  stage: build
  script:
    - |
      find config/ -name "*.json" | while read file; do
        echo "Processing $file"
        cp "$file" "$file.orig"
        zmin --mode sport "$file.orig" "$file"
        
        # Calculate savings
        original=$(wc -c < "$file.orig")
        minified=$(wc -c < "$file")
        savings=$((($original - $minified) * 100 / $original))
        echo "Saved ${savings}% on $file"
      done
  artifacts:
    paths:
      - config/
    expire_in: 1 hour

deploy-minified:
  stage: deploy
  script:
    - echo "Deploying minified configurations..."
    - rsync -av config/ $DEPLOY_TARGET/config/
  environment:
    name: production
  only:
    - main
```

### Jenkins Pipeline

```groovy
// Jenkinsfile
pipeline {
    agent any
    
    environment {
        ZMIN_VERSION = '1.0.0'
    }
    
    stages {
        stage('Setup') {
            steps {
                script {
                    sh '''
                        wget -O zmin https://github.com/hydepwns/zmin/releases/download/v${ZMIN_VERSION}/zmin-linux-x64
                        chmod +x zmin
                        sudo mv zmin /usr/local/bin/
                    '''
                }
            }
        }
        
        stage('Validate JSON') {
            steps {
                script {
                    sh '''
                        find . -name "*.json" | while read file; do
                            if ! zmin --validate "$file"; then
                                echo "Validation failed for $file"
                                exit 1
                            fi
                        done
                    '''
                }
            }
        }
        
        stage('Build and Minify') {
            parallel {
                stage('API Configs') {
                    steps {
                        sh '''
                            find api-configs/ -name "*.json" | while read file; do
                                zmin --mode sport "$file" "$file.min"
                                mv "$file.min" "$file"
                            done
                        '''
                    }
                }
                
                stage('Static Assets') {
                    steps {
                        sh '''
                            find public/data/ -name "*.json" | while read file; do
                                zmin --mode turbo "$file" "$file.min"
                                mv "$file.min" "$file"
                            done
                        '''
                    }
                }
            }
        }
        
        stage('Performance Test') {
            steps {
                script {
                    sh '''
                        # Test minification performance
                        echo '{"test": "large data set"}' > test.json
                        time zmin --mode turbo --stats test.json test.min.json
                        
                        # Verify output
                        if ! zmin --validate test.min.json; then
                            echo "Minified output validation failed"
                            exit 1
                        fi
                    '''
                }
            }
        }
    }
    
    post {
        always {
            archiveArtifacts artifacts: '**/*.json', fingerprint: true
        }
        success {
            echo 'JSON minification pipeline completed successfully!'
        }
        failure {
            emailext to: "${env.CHANGE_AUTHOR_EMAIL}",
                     subject: "JSON Minification Pipeline Failed: ${env.JOB_NAME} - ${env.BUILD_NUMBER}",
                     body: "The JSON minification pipeline failed. Please check the console output."
        }
    }
}
```

## Docker Integration

### Multi-stage Build

```dockerfile
# Dockerfile
FROM alpine:latest AS zmin-builder

# Install Zig and build zmin
RUN apk add --no-cache wget xz
RUN wget https://ziglang.org/download/0.14.1/zig-linux-x86_64-0.14.1.tar.xz && \
    tar -xf zig-linux-x86_64-0.14.1.tar.xz && \
    mv zig-linux-x86_64-0.14.1 /usr/local/zig

ENV PATH="/usr/local/zig:${PATH}"

COPY . /build
WORKDIR /build
RUN zig build --release=fast

# Production image
FROM node:18-alpine AS production

# Copy zmin binary
COPY --from=zmin-builder /build/zig-out/bin/zmin /usr/local/bin/

# Install application dependencies
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Copy application code
COPY . .

# Create JSON minification script
RUN cat > /usr/local/bin/minify-json-assets.sh << 'EOF'
#!/bin/sh
find /app/public/data -name "*.json" | while read file; do
    echo "Minifying $file"
    zmin --mode turbo "$file" "$file.tmp"
    mv "$file.tmp" "$file"
done
EOF

RUN chmod +x /usr/local/bin/minify-json-assets.sh

# Minify JSON assets during build
RUN minify-json-assets.sh

EXPOSE 3000
CMD ["node", "server.js"]
```

### Docker Compose for Development

```yaml
# docker-compose.yml
version: '3.8'

services:
  api:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    volumes:
      - ./config:/app/config
      - ./data:/app/data
    environment:
      - NODE_ENV=development
      - ZMIN_ENABLED=true
      - ZMIN_MODE=sport
    depends_on:
      - zmin-processor

  zmin-processor:
    image: zmin:latest
    volumes:
      - ./data:/data
      - ./processed:/processed
    command: >
      sh -c "
        while inotifywait -r -e modify /data; do
          find /data -name '*.json' -newer /tmp/last-run 2>/dev/null | while read file; do
            echo 'Processing: $$file'
            zmin --mode turbo \"$$file\" \"/processed/$$(basename \"$$file\")\"
          done
          touch /tmp/last-run
        done
      "

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
      - ./processed:/var/www/html/data
    depends_on:
      - api
```

## Monitoring and Observability

### Prometheus Metrics

```javascript
// metrics/zmin-metrics.js
const promClient = require('prom-client');
const { minify } = require('@zmin/cli');

// Create metrics
const minificationDuration = new promClient.Histogram({
  name: 'zmin_minification_duration_seconds',
  help: 'Duration of JSON minification operations',
  labelNames: ['mode', 'size_category']
});

const minificationRatio = new promClient.Histogram({
  name: 'zmin_compression_ratio',
  help: 'Compression ratio achieved by minification',
  labelNames: ['mode']
});

const minificationErrors = new promClient.Counter({
  name: 'zmin_errors_total',
  help: 'Total number of minification errors',
  labelNames: ['error_type']
});

// Wrapper function with metrics
function minifyWithMetrics(data, mode = 'sport') {
  const startTime = Date.now();
  const originalSize = JSON.stringify(data).length;
  
  try {
    const result = minify(JSON.stringify(data));
    const duration = (Date.now() - startTime) / 1000;
    const ratio = 1 - (result.length / originalSize);
    
    // Record metrics
    const sizeCategory = originalSize < 1024 ? 'small' : 
                        originalSize < 102400 ? 'medium' : 'large';
    
    minificationDuration
      .labels(mode, sizeCategory)
      .observe(duration);
    
    minificationRatio
      .labels(mode)
      .observe(ratio);
    
    return result;
  } catch (error) {
    minificationErrors
      .labels(error.constructor.name)
      .inc();
    throw error;
  }
}

module.exports = {
  minifyWithMetrics,
  register: promClient.register
};
```

### Health Check Endpoint

```javascript
// health/zmin-health.js
const { validate } = require('@zmin/cli');

class ZminHealthCheck {
  constructor() {
    this.lastCheck = null;
    this.isHealthy = null;
  }
  
  async checkHealth() {
    try {
      // Test basic functionality
      const testJson = '{"test": true, "timestamp": "' + new Date().toISOString() + '"}';
      const minified = require('@zmin/cli').minify(testJson);
      
      // Verify output
      const isValid = validate(minified);
      const parsedBack = JSON.parse(minified);
      
      const health = {
        status: isValid && parsedBack.test === true ? 'healthy' : 'unhealthy',
        timestamp: new Date().toISOString(),
        version: require('@zmin/cli').version(),
        performance: {
          test_size: testJson.length,
          minified_size: minified.length,
          compression_ratio: Math.round((1 - minified.length / testJson.length) * 100)
        }
      };
      
      this.lastCheck = health;
      this.isHealthy = health.status === 'healthy';
      
      return health;
    } catch (error) {
      const health = {
        status: 'unhealthy',
        timestamp: new Date().toISOString(),
        error: error.message
      };
      
      this.lastCheck = health;
      this.isHealthy = false;
      
      return health;
    }
  }
  
  getLastCheck() {
    return this.lastCheck;
  }
  
  isHealthyStatus() {
    return this.isHealthy;
  }
}

module.exports = ZminHealthCheck;
```

## Database Integration

### MongoDB Aggregation Pipeline

```javascript
// mongodb/zmin-aggregation.js
const { minify } = require('@zmin/cli');

// Custom aggregation operator for MongoDB
function addZminStage(pipeline) {
  return [
    ...pipeline,
    {
      $addFields: {
        minified_data: {
          $function: {
            body: function(data) {
              // This would call zmin in a MongoDB context
              return JSON.stringify(data); // Simplified for example
            },
            args: ["$data"],
            lang: "js"
          }
        }
      }
    }
  ];
}

// Usage in application
async function getMinifiedDocuments(collection, query = {}) {
  return await collection.aggregate([
    { $match: query },
    {
      $project: {
        _id: 1,
        original_size: { $strLenBytes: { $toString: "$data" } },
        minified_data: {
          $function: {
            body: `function(doc) {
              const zmin = require('@zmin/cli');
              const jsonStr = JSON.stringify(doc);
              return zmin.minify(jsonStr);
            }`,
            args: ["$data"],
            lang: "js"
          }
        }
      }
    },
    {
      $addFields: {
        minified_size: { $strLenBytes: "$minified_data" },
        compression_ratio: {
          $multiply: [
            { $divide: [
              { $subtract: ["$original_size", "$minified_size"] },
              "$original_size"
            ]},
            100
          ]
        }
      }
    }
  ]).toArray();
}
```

### PostgreSQL Function

```sql
-- PostgreSQL extension for zmin
CREATE OR REPLACE FUNCTION minify_json(input_json text, mode text DEFAULT 'sport')
RETURNS text
AS $$
import subprocess
import json

def minify_json_py(input_json, mode):
    try:
        # Validate input
        json.loads(input_json)
        
        # Call zmin binary
        process = subprocess.run(
            ['zmin', '--mode', mode],
            input=input_json,
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if process.returncode == 0:
            return process.stdout.strip()
        else:
            plpy.warning(f"zmin failed: {process.stderr}")
            return input_json
    except Exception as e:
        plpy.warning(f"JSON minification error: {str(e)}")
        return input_json

return minify_json_py(input_json, mode)
$$ LANGUAGE plpython3u;

-- Usage example
SELECT 
    id,
    pg_column_size(data) as original_size,
    minify_json(data::text, 'turbo') as minified_data,
    pg_column_size(minify_json(data::text, 'turbo')) as minified_size
FROM json_documents 
WHERE pg_column_size(data) > 1024;
```

## Real-time Processing

### Apache Kafka Integration

```javascript
// kafka/zmin-processor.js
const kafka = require('kafkajs');
const { minify } = require('@zmin/cli');

class ZminKafkaProcessor {
  constructor(config) {
    this.kafka = kafka(config.kafka);
    this.consumer = this.kafka.consumer({ groupId: 'zmin-processor' });
    this.producer = this.kafka.producer();
    this.config = config;
  }
  
  async start() {
    await this.consumer.connect();
    await this.producer.connect();
    
    await this.consumer.subscribe({ 
      topic: this.config.inputTopic,
      fromBeginning: false 
    });
    
    await this.consumer.run({
      eachMessage: async ({ topic, partition, message }) => {
        try {
          const originalValue = message.value.toString();
          const minified = minify(originalValue, this.config.mode || 'sport');
          
          await this.producer.send({
            topic: this.config.outputTopic,
            messages: [{
              key: message.key,
              value: minified,
              headers: {
                ...message.headers,
                'zmin-processed': 'true',
                'original-size': Buffer.from(originalValue.length.toString()),
                'minified-size': Buffer.from(minified.length.toString()),
                'compression-ratio': Buffer.from(
                  ((1 - minified.length / originalValue.length) * 100).toFixed(2)
                )
              }
            }]
          });
          
          console.log(`Processed message: ${originalValue.length} -> ${minified.length} bytes`);
        } catch (error) {
          console.error('Processing error:', error);
          
          // Send to dead letter queue
          await this.producer.send({
            topic: this.config.deadLetterTopic,
            messages: [{
              key: message.key,
              value: message.value,
              headers: {
                ...message.headers,
                'error': Buffer.from(error.message),
                'error-timestamp': Buffer.from(new Date().toISOString())
              }
            }]
          });
        }
      }
    });
  }
  
  async stop() {
    await this.consumer.disconnect();
    await this.producer.disconnect();
  }
}

// Usage
const processor = new ZminKafkaProcessor({
  kafka: {
    clientId: 'zmin-processor',
    brokers: ['localhost:9092']
  },
  inputTopic: 'raw-json-data',
  outputTopic: 'minified-json-data',
  deadLetterTopic: 'processing-errors',
  mode: 'turbo'
});

processor.start().catch(console.error);
```

### Redis Stream Processing

```python
# redis_stream_processor.py
import redis
import zmin
import json
import time
from typing import Dict, Any

class ZminRedisProcessor:
    def __init__(self, redis_url: str = "redis://localhost:6379"):
        self.redis = redis.from_url(redis_url)
        self.group_name = "zmin-processors"
        self.consumer_name = f"zmin-consumer-{int(time.time())}"
        
    def setup_streams(self, input_stream: str, output_stream: str):
        """Setup Redis streams and consumer group."""
        self.input_stream = input_stream
        self.output_stream = output_stream
        
        try:
            self.redis.xgroup_create(input_stream, self.group_name, id='0', mkstream=True)
        except redis.ResponseError:
            pass  # Group already exists
    
    def process_stream(self, mode: str = "sport"):
        """Process messages from Redis stream."""
        while True:
            try:
                messages = self.redis.xreadgroup(
                    self.group_name,
                    self.consumer_name,
                    {self.input_stream: '>'},
                    count=10,
                    block=1000
                )
                
                for stream_name, stream_messages in messages:
                    for message_id, fields in stream_messages:
                        self.process_message(message_id, fields, mode)
                        
            except KeyboardInterrupt:
                print("Shutting down processor...")
                break
            except Exception as e:
                print(f"Error processing stream: {e}")
                time.sleep(1)
    
    def process_message(self, message_id: bytes, fields: Dict[bytes, bytes], mode: str):
        """Process a single message."""
        try:
            # Decode message
            data = fields.get(b'data', b'').decode('utf-8')
            
            if not data:
                self.redis.xack(self.input_stream, self.group_name, message_id)
                return
            
            # Minify JSON
            processing_mode = getattr(zmin.ProcessingMode, mode.upper())
            minified = zmin.minify(data, mode=processing_mode)
            
            # Calculate metrics
            original_size = len(data)
            minified_size = len(minified)
            compression_ratio = (1 - minified_size / original_size) * 100
            
            # Send to output stream
            self.redis.xadd(self.output_stream, {
                'data': minified,
                'original_size': original_size,
                'minified_size': minified_size,
                'compression_ratio': f"{compression_ratio:.2f}",
                'mode': mode,
                'processed_at': int(time.time() * 1000),
                'source_message_id': message_id.decode('utf-8')
            })
            
            # Acknowledge message
            self.redis.xack(self.input_stream, self.group_name, message_id)
            
            print(f"Processed {message_id.decode('utf-8')}: {original_size} -> {minified_size} bytes ({compression_ratio:.1f}% saved)")
            
        except Exception as e:
            print(f"Error processing message {message_id.decode('utf-8')}: {e}")
            
            # Send to dead letter stream
            self.redis.xadd(f"{self.input_stream}:errors", {
                'original_data': fields.get(b'data', b''),
                'error': str(e),
                'error_time': int(time.time() * 1000),
                'source_message_id': message_id.decode('utf-8')
            })
            
            # Acknowledge to prevent reprocessing
            self.redis.xack(self.input_stream, self.group_name, message_id)

# Usage
if __name__ == "__main__":
    processor = ZminRedisProcessor()
    processor.setup_streams("json-input", "json-output")
    processor.process_stream(mode="turbo")
```

For more integration examples and patterns, visit [zmin.droo.foo/integrations](https://zmin.droo.foo/integrations).