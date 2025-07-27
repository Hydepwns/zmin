# Mode Selection Guide

This interactive guide helps you choose the optimal zmin mode (ECO, SPORT, or TURBO) for your specific use case.

## Quick Decision Tree

```
Start Here
    │
    ├─► Is your file < 1 MB?
    │   │
    │   ├─► YES ─► Is memory extremely limited (< 1 MB)?
    │   │          │
    │   │          ├─► YES ─► Use ECO Mode (~312 MB/s, 64KB memory)
    │   │          │
    │   │          └─► NO ──► Use SPORT Mode (~555 MB/s, balanced)
    │   │
    │   └─► NO ──► Is your file > 100 MB?
    │              │
    │              ├─► YES ─► Do you have GPU available?
    │              │          │
    │              │          ├─► YES ─► Use GPU Mode (~2.0 GB/s)
    │              │          │
    │              │          └─► NO ──► Use TURBO Mode (~1.1 GB/s)
    │              │
    │              └─► NO ──► Use SPORT Mode (default, balanced)
```

## Interactive Mode Selector

### Step 1: What's Your Primary Concern?

<details>
<summary><b>🚀 Maximum Performance</b> - I need the fastest possible processing</summary>

#### For Maximum Performance:

**File Size Assessment:**
- **< 10 MB**: Use **SPORT mode** (overhead of TURBO not worth it)
- **10-100 MB**: Use **TURBO mode** for best CPU performance
- **> 100 MB**: Use **GPU mode** if available, otherwise TURBO

**Command:**
```bash
# For large files
zmin --mode turbo large-dataset.json output.json

# With GPU
zmin --gpu cuda massive-file.json output.json
```

**Performance Tips:**
- Pre-allocate output buffer for 5-10% speed boost
- Use NVMe SSD for I/O operations
- Ensure CPU governor is set to "performance"

</details>

<details>
<summary><b>💾 Memory Efficiency</b> - I have limited RAM available</summary>

#### For Memory Efficiency:

**Memory Constraints:**
- **< 100 KB available**: Use **ECO mode** (64 KB limit)
- **< 10 MB available**: Use **ECO mode** with streaming
- **< 100 MB available**: Use **SPORT mode** with chunking
- **> 100 MB available**: Any mode is fine

**Command:**
```bash
# Minimal memory usage
zmin --mode eco embedded-data.json minified.json

# With streaming for large files
cat huge-file.json | zmin --mode eco --stream > output.json
```

**Memory Optimization:**
- ECO mode uses fixed 64KB buffer
- Process files in chunks if needed
- Monitor with `zmin --mode eco --memory-stats`

</details>

<details>
<summary><b>⚖️ Balanced Approach</b> - I want good performance without extremes</summary>

#### For Balanced Performance:

**Default Recommendation**: **SPORT mode**
- Good performance (~555 MB/s)
- Moderate memory usage
- Works well for most files

**Command:**
```bash
# SPORT is the default
zmin input.json output.json

# Or explicitly
zmin --mode sport data.json minified.json
```

**When to adjust:**
- Switch to ECO if you see memory warnings
- Switch to TURBO for files > 50 MB
- Stay with SPORT for general use

</details>

<details>
<summary><b>🔄 Batch Processing</b> - I'm processing many files</summary>

#### For Batch Processing:

**Batch Size Considerations:**
- **Many small files (< 1 MB each)**: Use **ECO or SPORT mode**
- **Fewer large files (> 10 MB each)**: Use **TURBO mode**
- **Mixed sizes**: Use **adaptive mode** (see script below)

**Adaptive Batch Script:**
```bash
#!/bin/bash
# adaptive-batch.sh

for file in *.json; do
    size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file")
    
    if [ $size -lt 1048576 ]; then
        # < 1 MB: Use ECO
        mode="eco"
    elif [ $size -lt 104857600 ]; then
        # < 100 MB: Use SPORT
        mode="sport"
    else
        # >= 100 MB: Use TURBO
        mode="turbo"
    fi
    
    echo "Processing $file with $mode mode ($(( size / 1024 / 1024 )) MB)"
    zmin --mode $mode "$file" "minified/${file}"
done
```

</details>

## Detailed Mode Comparison

### Decision Matrix

| Scenario | File Size | Memory Available | CPU Cores | Recommended Mode | Expected Performance |
|----------|-----------|------------------|-----------|------------------|---------------------|
| IoT Device | < 1 MB | < 1 MB | 1 | **ECO** | ~312 MB/s |
| Web API | 1-10 MB | > 100 MB | 2-4 | **SPORT** | ~555 MB/s |
| Data Pipeline | 10-100 MB | > 1 GB | 4-8 | **TURBO** | ~1.1 GB/s |
| Big Data | > 100 MB | > 4 GB | 8+ | **GPU/TURBO** | ~2.0 GB/s |
| Edge Computing | < 10 MB | < 100 MB | 1-2 | **ECO** | ~312 MB/s |
| CI/CD Pipeline | Mixed | > 500 MB | 4+ | **Adaptive** | Varies |
| Lambda Function | < 5 MB | 128-512 MB | 1-2 | **SPORT** | ~555 MB/s |
| Kubernetes Pod | Variable | Limited | 1-4 | **SPORT** | ~555 MB/s |

## Mode Selection by Use Case

### Web Services

<details>
<summary><b>REST API Responses</b></summary>

**Typical Characteristics:**
- Response size: 1-50 KB
- Frequency: High (1000s/second)
- Memory: Shared with application

**Recommendation**: **SPORT mode**

```javascript
// Express.js middleware
app.use((req, res, next) => {
    // SPORT mode for API responses
    res.json = function(data) {
        const minified = zmin.minify(JSON.stringify(data), 'sport');
        res.type('application/json').send(minified);
    };
    next();
});
```

</details>

<details>
<summary><b>Static Asset Optimization</b></summary>

**Typical Characteristics:**
- File size: 100 KB - 10 MB
- Frequency: Build time only
- Memory: Build server resources

**Recommendation**: **TURBO mode**

```bash
# Build script
find public/data -name "*.json" -size +1M -exec \
    zmin --mode turbo {} {}.min \;
```

</details>

### Data Processing

<details>
<summary><b>ETL Pipelines</b></summary>

**Typical Characteristics:**
- File size: 100 MB - 10 GB
- Frequency: Scheduled batches
- Memory: Dedicated processing nodes

**Recommendation**: **TURBO or GPU mode**

```python
def process_large_dataset(filepath):
    size = os.path.getsize(filepath)
    
    if size > 1e9:  # > 1 GB
        # Try GPU first
        try:
            return zmin.minify_file(filepath, mode="gpu")
        except zmin.GPUNotAvailable:
            return zmin.minify_file(filepath, mode="turbo")
    else:
        return zmin.minify_file(filepath, mode="turbo")
```

</details>

<details>
<summary><b>Stream Processing</b></summary>

**Typical Characteristics:**
- Continuous data flow
- Unknown total size
- Real-time requirements

**Recommendation**: **ECO or SPORT mode with streaming**

```bash
# Kafka consumer -> zmin -> Kafka producer
kafka-console-consumer --topic raw-json | \
    zmin --mode sport --stream | \
    kafka-console-producer --topic minified-json
```

</details>

### Embedded Systems

<details>
<summary><b>Resource-Constrained Devices</b></summary>

**Typical Characteristics:**
- Memory: < 10 MB available
- CPU: Single core, low power
- Storage: Limited

**Recommendation**: **ECO mode**

```c
// Embedded C integration
#define ZMIN_MODE_ECO 0
#define MAX_JSON_SIZE 65536  // 64KB

int minify_sensor_data(const char* input, char* output) {
    size_t output_len = MAX_JSON_SIZE;
    return zmin_minify(input, strlen(input), 
                      output, &output_len, 
                      ZMIN_MODE_ECO);
}
```

</details>

## Interactive Command Builder

### Build Your Perfect Command

**1. Select your file size:**
- [ ] < 1 MB → Continue to memory check
- [ ] 1-10 MB → Recommend SPORT
- [ ] 10-100 MB → Recommend TURBO
- [ ] > 100 MB → Check for GPU

**2. Check your memory:**
- [ ] < 100 KB → Force ECO
- [ ] 100 KB - 10 MB → Allow ECO/SPORT
- [ ] > 10 MB → All modes available

**3. Special requirements:**
- [ ] Real-time processing → Prefer ECO/SPORT
- [ ] Batch processing → Prefer TURBO/GPU
- [ ] Streaming needed → Add --stream flag
- [ ] Multiple files → Create batch script

**Generated Command:**
```bash
# Based on your selections:
zmin --mode [calculated_mode] [additional_flags] input.json output.json
```

## Performance Calculator

### Estimate Processing Time

```javascript
// Interactive calculator (paste into browser console)
function calculateProcessingTime(fileSizeMB, mode) {
    const throughput = {
        'eco': 312,    // MB/s
        'sport': 555,  // MB/s
        'turbo': 1100, // MB/s
        'gpu': 2000    // MB/s
    };
    
    const speed = throughput[mode] || throughput.sport;
    const timeSeconds = fileSizeMB / speed;
    
    return {
        mode: mode,
        fileSizeMB: fileSizeMB,
        throughputMBs: speed,
        processingTime: timeSeconds,
        formattedTime: timeSeconds < 1 ? 
            `${(timeSeconds * 1000).toFixed(0)}ms` : 
            `${timeSeconds.toFixed(2)}s`
    };
}

// Example usage:
console.table([
    calculateProcessingTime(1, 'eco'),
    calculateProcessingTime(1, 'sport'),
    calculateProcessingTime(1, 'turbo'),
    calculateProcessingTime(100, 'eco'),
    calculateProcessingTime(100, 'sport'),
    calculateProcessingTime(100, 'turbo'),
    calculateProcessingTime(1000, 'turbo'),
    calculateProcessingTime(1000, 'gpu')
]);
```

## Mode Selection Script

### Automated Mode Selection Tool

Save this as `zmin-auto`:

```bash
#!/bin/bash
# zmin-auto - Intelligent mode selection for zmin

# Default thresholds (customizable)
SMALL_FILE_THRESHOLD=$((1 * 1024 * 1024))      # 1 MB
LARGE_FILE_THRESHOLD=$((100 * 1024 * 1024))    # 100 MB
MIN_MEMORY_FOR_SPORT=$((100 * 1024 * 1024))    # 100 MB
MIN_MEMORY_FOR_TURBO=$((500 * 1024 * 1024))    # 500 MB

# Parse arguments
INPUT_FILE="$1"
OUTPUT_FILE="$2"

if [ -z "$INPUT_FILE" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "Usage: zmin-auto <input.json> <output.json>"
    exit 1
fi

# Get file size
FILE_SIZE=$(stat -c%s "$INPUT_FILE" 2>/dev/null || stat -f%z "$INPUT_FILE")

# Get available memory (Linux/macOS compatible)
if command -v free >/dev/null 2>&1; then
    # Linux
    AVAILABLE_MEM=$(free -b | awk '/^Mem:/{print $7}')
else
    # macOS
    AVAILABLE_MEM=$(vm_stat | awk '/free/ {print $3}' | sed 's/\.//')
    AVAILABLE_MEM=$((AVAILABLE_MEM * 4096))  # Convert pages to bytes
fi

# Determine optimal mode
select_mode() {
    # Check GPU availability
    if zmin --gpu-info >/dev/null 2>&1 && [ $FILE_SIZE -gt $LARGE_FILE_THRESHOLD ]; then
        echo "gpu"
        return
    fi
    
    # Memory-constrained environment
    if [ $AVAILABLE_MEM -lt $MIN_MEMORY_FOR_SPORT ]; then
        echo "eco"
        return
    fi
    
    # Small files
    if [ $FILE_SIZE -lt $SMALL_FILE_THRESHOLD ]; then
        if [ $AVAILABLE_MEM -lt $MIN_MEMORY_FOR_TURBO ]; then
            echo "sport"
        else
            echo "sport"  # SPORT is optimal for small files
        fi
        return
    fi
    
    # Large files
    if [ $FILE_SIZE -gt $LARGE_FILE_THRESHOLD ]; then
        if [ $AVAILABLE_MEM -gt $MIN_MEMORY_FOR_TURBO ]; then
            echo "turbo"
        else
            echo "sport"
        fi
        return
    fi
    
    # Medium files - default to SPORT
    echo "sport"
}

# Select mode
MODE=$(select_mode)

# Convert file size to human readable
if [ $FILE_SIZE -gt $((1024 * 1024 * 1024)) ]; then
    SIZE_HUMAN="$(( FILE_SIZE / 1024 / 1024 / 1024 )) GB"
elif [ $FILE_SIZE -gt $((1024 * 1024)) ]; then
    SIZE_HUMAN="$(( FILE_SIZE / 1024 / 1024 )) MB"
else
    SIZE_HUMAN="$(( FILE_SIZE / 1024 )) KB"
fi

# Show decision reasoning
echo "═══════════════════════════════════════"
echo "zmin Auto Mode Selection"
echo "═══════════════════════════════════════"
echo "File: $INPUT_FILE"
echo "Size: $SIZE_HUMAN"
echo "Available Memory: $(( AVAILABLE_MEM / 1024 / 1024 )) MB"
echo "Selected Mode: ${MODE^^}"
echo "═══════════════════════════════════════"

# Execute zmin with selected mode
if [ "$MODE" = "gpu" ]; then
    exec zmin --gpu auto "$INPUT_FILE" "$OUTPUT_FILE"
else
    exec zmin --mode "$MODE" "$INPUT_FILE" "$OUTPUT_FILE"
fi
```

Make it executable:
```bash
chmod +x zmin-auto
sudo mv zmin-auto /usr/local/bin/
```

## Visual Mode Selector (HTML)

Create this as `mode-selector.html` for an interactive web-based selector:

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>zmin Mode Selector</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            border-radius: 10px;
            padding: 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            text-align: center;
        }
        .question {
            margin: 20px 0;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 8px;
            border: 2px solid transparent;
            transition: all 0.3s;
        }
        .question.active {
            border-color: #007bff;
            background: #e7f3ff;
        }
        .options {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 10px;
            margin-top: 15px;
        }
        button {
            padding: 12px 20px;
            border: 2px solid #ddd;
            background: white;
            border-radius: 6px;
            cursor: pointer;
            transition: all 0.2s;
            font-size: 16px;
        }
        button:hover {
            border-color: #007bff;
            background: #f0f8ff;
        }
        button.selected {
            background: #007bff;
            color: white;
            border-color: #007bff;
        }
        .result {
            margin-top: 30px;
            padding: 20px;
            background: #d4edda;
            border: 1px solid #c3e6cb;
            border-radius: 8px;
            display: none;
        }
        .result.show {
            display: block;
        }
        .command {
            font-family: 'Courier New', monospace;
            background: #333;
            color: #fff;
            padding: 15px;
            border-radius: 5px;
            margin: 10px 0;
            position: relative;
        }
        .copy-btn {
            position: absolute;
            top: 10px;
            right: 10px;
            padding: 5px 10px;
            font-size: 12px;
            background: #555;
            border: none;
            color: white;
        }
        .copy-btn:hover {
            background: #666;
        }
        .mode-badge {
            display: inline-block;
            padding: 5px 15px;
            border-radius: 20px;
            font-weight: bold;
            margin: 5px;
        }
        .mode-eco { background: #28a745; color: white; }
        .mode-sport { background: #ffc107; color: black; }
        .mode-turbo { background: #dc3545; color: white; }
        .mode-gpu { background: #6610f2; color: white; }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .stat {
            text-align: center;
            padding: 10px;
            background: #f8f9fa;
            border-radius: 5px;
        }
        .stat-value {
            font-size: 24px;
            font-weight: bold;
            color: #007bff;
        }
        .stat-label {
            font-size: 14px;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 zmin Mode Selector</h1>
        
        <div id="q1" class="question active">
            <h3>What's your file size?</h3>
            <div class="options">
                <button onclick="setFileSize('tiny')">< 1 MB</button>
                <button onclick="setFileSize('small')">1-10 MB</button>
                <button onclick="setFileSize('medium')">10-100 MB</button>
                <button onclick="setFileSize('large')">> 100 MB</button>
            </div>
        </div>

        <div id="q2" class="question">
            <h3>How much memory is available?</h3>
            <div class="options">
                <button onclick="setMemory('minimal')">< 100 MB</button>
                <button onclick="setMemory('limited')">100-500 MB</button>
                <button onclick="setMemory('moderate')">500 MB - 2 GB</button>
                <button onclick="setMemory('plenty')">> 2 GB</button>
            </div>
        </div>

        <div id="q3" class="question">
            <h3>What's your priority?</h3>
            <div class="options">
                <button onclick="setPriority('speed')">Maximum Speed</button>
                <button onclick="setPriority('memory')">Memory Efficiency</button>
                <button onclick="setPriority('balanced')">Balanced</button>
                <button onclick="setPriority('batch')">Batch Processing</button>
            </div>
        </div>

        <div id="result" class="result">
            <h2>Recommended Configuration</h2>
            <div id="mode-recommendation"></div>
            <div class="command" id="command-output">
                <span id="command-text"></span>
                <button class="copy-btn" onclick="copyCommand()">Copy</button>
            </div>
            <div class="stats" id="performance-stats"></div>
            <div id="explanation"></div>
        </div>
    </div>

    <script>
        let selection = {
            fileSize: null,
            memory: null,
            priority: null
        };

        function setFileSize(size) {
            selection.fileSize = size;
            markSelected('q1', size);
            activateQuestion('q2');
            checkComplete();
        }

        function setMemory(mem) {
            selection.memory = mem;
            markSelected('q2', mem);
            activateQuestion('q3');
            checkComplete();
        }

        function setPriority(pri) {
            selection.priority = pri;
            markSelected('q3', pri);
            checkComplete();
        }

        function markSelected(questionId, value) {
            const buttons = document.querySelectorAll(`#${questionId} button`);
            buttons.forEach(btn => {
                if (btn.textContent.toLowerCase().includes(value) || 
                    btn.onclick.toString().includes(value)) {
                    btn.classList.add('selected');
                } else {
                    btn.classList.remove('selected');
                }
            });
        }

        function activateQuestion(questionId) {
            document.querySelectorAll('.question').forEach(q => {
                q.classList.remove('active');
            });
            document.getElementById(questionId).classList.add('active');
        }

        function checkComplete() {
            if (selection.fileSize && selection.memory && selection.priority) {
                showRecommendation();
            }
        }

        function determineMode() {
            const { fileSize, memory, priority } = selection;
            
            // GPU mode for large files with plenty of memory
            if (fileSize === 'large' && memory === 'plenty') {
                return 'gpu';
            }
            
            // ECO mode for minimal memory
            if (memory === 'minimal' || priority === 'memory') {
                return 'eco';
            }
            
            // TURBO mode for speed priority with adequate resources
            if (priority === 'speed' && 
                (fileSize === 'medium' || fileSize === 'large') &&
                (memory === 'moderate' || memory === 'plenty')) {
                return 'turbo';
            }
            
            // TURBO for batch processing of larger files
            if (priority === 'batch' && fileSize !== 'tiny') {
                return 'turbo';
            }
            
            // Default to SPORT for balanced approach
            return 'sport';
        }

        function getPerformanceStats(mode) {
            const stats = {
                eco: { throughput: '~312 MB/s', memory: '64 KB', cpu: '1 core' },
                sport: { throughput: '~555 MB/s', memory: '128 MB', cpu: '4 cores' },
                turbo: { throughput: '~1.1 GB/s', memory: '256 MB', cpu: '8 cores' },
                gpu: { throughput: '~2.0 GB/s', memory: '2 GB', cpu: 'GPU' }
            };
            return stats[mode];
        }

        function getExplanation(mode) {
            const explanations = {
                eco: `ECO mode is perfect for your use case because it uses minimal memory (only 64KB) 
                      while still providing good performance. This mode is ideal for embedded systems, 
                      IoT devices, or any memory-constrained environment.`,
                sport: `SPORT mode offers the best balance between performance and resource usage. 
                        It's the default mode because it works well for most use cases, providing 
                        ~555 MB/s throughput with moderate memory usage.`,
                turbo: `TURBO mode maximizes CPU utilization across multiple cores to achieve 
                        ~1.1 GB/s throughput. This is ideal for processing large files when 
                        performance is critical and resources are available.`,
                gpu: `GPU mode leverages CUDA or OpenCL acceleration to achieve ~2.0 GB/s throughput. 
                      This is optimal for very large files (>100MB) when GPU resources are available.`
            };
            return explanations[mode];
        }

        function showRecommendation() {
            const mode = determineMode();
            const stats = getPerformanceStats(mode);
            const explanation = getExplanation(mode);
            
            // Update mode recommendation
            document.getElementById('mode-recommendation').innerHTML = `
                <h3>Recommended Mode: <span class="mode-badge mode-${mode}">${mode.toUpperCase()}</span></h3>
            `;
            
            // Update command
            const command = mode === 'gpu' 
                ? 'zmin --gpu auto input.json output.json'
                : `zmin --mode ${mode} input.json output.json`;
            document.getElementById('command-text').textContent = command;
            
            // Update performance stats
            document.getElementById('performance-stats').innerHTML = `
                <div class="stat">
                    <div class="stat-value">${stats.throughput}</div>
                    <div class="stat-label">Throughput</div>
                </div>
                <div class="stat">
                    <div class="stat-value">${stats.memory}</div>
                    <div class="stat-label">Memory Usage</div>
                </div>
                <div class="stat">
                    <div class="stat-value">${stats.cpu}</div>
                    <div class="stat-label">CPU Usage</div>
                </div>
            `;
            
            // Update explanation
            document.getElementById('explanation').innerHTML = `
                <h3>Why ${mode.toUpperCase()}?</h3>
                <p>${explanation}</p>
            `;
            
            // Show result
            document.getElementById('result').classList.add('show');
            document.getElementById('result').scrollIntoView({ behavior: 'smooth' });
        }

        function copyCommand() {
            const commandText = document.getElementById('command-text').textContent;
            navigator.clipboard.writeText(commandText).then(() => {
                const btn = document.querySelector('.copy-btn');
                btn.textContent = 'Copied!';
                setTimeout(() => {
                    btn.textContent = 'Copy';
                }, 2000);
            });
        }
    </script>
</body>
</html>
```

## Quick Reference Card

### Mode Selection Cheat Sheet

```
┌─────────────────────────────────────────────────────────────┐
│                   zmin Mode Selection Guide                  │
├─────────────────────────────────────────────────────────────┤
│ File Size │ Memory    │ Priority   │ Mode   │ Command      │
├───────────┼───────────┼────────────┼────────┼──────────────┤
│ < 1 MB    │ < 100 MB  │ Any        │ ECO    │ --mode eco   │
│ < 1 MB    │ > 100 MB  │ Any        │ SPORT  │ (default)    │
│ 1-10 MB   │ Any       │ Balanced   │ SPORT  │ (default)    │
│ 10-100 MB │ > 500 MB  │ Speed      │ TURBO  │ --mode turbo │
│ > 100 MB  │ > 2 GB    │ Speed      │ GPU    │ --gpu auto   │
│ Any       │ < 100 MB  │ Memory     │ ECO    │ --mode eco   │
│ Streaming │ Any       │ Real-time  │ ECO    │ --mode eco   │
│ Batch     │ > 1 GB    │ Throughput │ TURBO  │ --mode turbo │
└───────────┴───────────┴────────────┴────────┴──────────────┘
```

Save this as a reference card or print it for quick access.

For an interactive online version, visit [zmin.droo.foo/mode-selector](https://zmin.droo.foo/mode-selector).