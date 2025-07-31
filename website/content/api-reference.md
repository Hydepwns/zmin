---
title: "API Reference"
description: "Complete API documentation for the zmin JSON minifier library"
layout: "api-reference"
url: "/api-reference-generated.html"
---

# zmin API Reference

This page provides the complete API reference for the zmin JSON minifier library. The library offers 513 functions and 149 types for JSON processing, validation, and minification.

## Quick Navigation

- [Functions](#functions) - Core minification and validation functions
- [Types](#types) - Data structures and configurations
- [JSON Reference](/docs/api-reference-generated.json) - Complete API in JSON format

## Getting Started

The main entry point for minification is the `minify` function:

```zig
pub fn minify(allocator: std.mem.Allocator, input: []const u8, mode: Mode) ![]u8
```

This function takes JSON input and returns minified output using the specified mode.
