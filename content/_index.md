---
title: "{{ .Site.Data.site.project.name }} - {{ .Site.Data.site.project.description }}"
description: "{{ .Site.Data.site.project.tagline }}. Up to {{ .Site.Data.site.project.performance.throughput }} throughput."
---

# {{ .Site.Data.site.project.name }}

**{{ .Site.Data.site.project.tagline }}** with GPU acceleration and parallel processing.

## 🚀 Performance

- **Up to {{ .Site.Data.site.project.performance.throughput }}** throughput
- **GPU acceleration** for massive datasets
- **Parallel processing** with NUMA awareness
- **Memory efficient** with streaming support

## 🎯 Features

{{< feature-list >}}

## 📦 Installation

{{< installation-steps >}}

## 🚀 Quick Start

```zig
const zmin = @import("zmin");

// Basic minification
const minified = try zmin.minify(allocator, json_input, .turbo);

// With validation
try zmin.validate(json_input);
const minified = try zmin.minify(allocator, json_input, .sport);
```

## 📚 Documentation

- [Getting Started]({{ .Site.Data.site.project.links.getting_started }}) - Quick setup guide
- [API Reference]({{ .Site.Data.site.project.links.api_reference }}) - Complete API docs
- [Performance Guide]({{ .Site.Data.site.project.links.performance }}) - Optimization tips
- [GPU Acceleration]({{ .Site.Data.site.project.links.gpu }}) - CUDA/OpenCL setup
- [Examples]({{ .Site.Data.site.project.links.examples }}) - Code examples

## 🔧 Development Tools

zmin includes a comprehensive set of development tools:

- **Dev Server**: Hot-reloading development server
- **Profiler**: Performance profiling and analysis
- **Debugger**: Interactive debugging tools
- **Plugin Registry**: Plugin management system
- **Config Manager**: Configuration management

## 🤝 Contributing

We welcome contributions! See our [Contributing Guide](https://github.com/hydepwns/zmin/blob/main/CONTRIBUTING.md) for details.

## 📄 License

MIT License - see [LICENSE](https://github.com/hydepwns/zmin/blob/main/LICENSE) for details.

---

**Ready to supercharge your JSON processing?** [Get started now](/docs/getting-started/)!
