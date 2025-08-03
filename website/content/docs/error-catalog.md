---
title: "Error Message Catalog"
description: "Comprehensive guide to zmin error messages and solutions"
weight: 80
---

# Error Message Catalog

This page provides detailed explanations for all zmin error messages, their causes, and solutions.

{{< error-catalog >}}

## Quick Error Search

Use `Ctrl+F` (or `Cmd+F` on Mac) to search for your specific error message or code.

## Error Categories

### Parse Errors (1xxx)

Errors that occur during JSON parsing.

{{< level "beginner" >}}
#### E1001: Unexpected Character
**Message**: `Unexpected character 'X' at line Y, column Z`

**Cause**: The JSON contains a character that isn't valid at that position.

**Common Examples**:
- Missing quotes around strings
- Trailing commas in objects or arrays
- Single quotes instead of double quotes

**Solution**:
```json
// ❌ Wrong
{ name: "value" }     // Missing quotes around key
{ "name": 'value' }   // Single quotes
{ "name": "value", }  // Trailing comma

// ✅ Correct
{ "name": "value" }
```
{{< /level >}}

{{< level "intermediate" >}}
#### E1002: Unterminated String
**Message**: `Unterminated string starting at line X`

**Cause**: A string is not properly closed with a matching quote.

**Solution**:
- Check for missing closing quotes
- Ensure escaped quotes are properly formatted (`\"`)
- Look for newlines in strings (use `\n` instead)
{{< /level >}}

### Memory Errors (2xxx)

Errors related to memory allocation and management.

{{< level "advanced" >}}
#### E2001: Out of Memory
**Message**: `Failed to allocate X bytes of memory`

**Cause**: The system doesn't have enough available memory.

**Solutions**:
1. Use streaming mode for large files: `zmin --streaming input.json`
2. Reduce buffer size: `zmin --buffer-size=1MB input.json`
3. Use Eco mode: `zmin -m eco input.json`
4. Process files in smaller chunks
{{< /level >}}

### I/O Errors (3xxx)

Errors related to file operations.

#### E3001: File Not Found
**Message**: `Cannot open file: X`

**Cause**: The specified input file doesn't exist or isn't accessible.

**Solutions**:
- Check the file path and spelling
- Ensure you have read permissions
- Use absolute paths if relative paths aren't working

#### E3002: Permission Denied
**Message**: `Permission denied: X`

**Cause**: Insufficient permissions to read input or write output.

**Solutions**:
```bash
# Check file permissions
ls -la input.json

# Fix read permissions
chmod +r input.json

# Fix write permissions for output directory
chmod +w output_directory/
```

### Validation Errors (4xxx)

Errors that occur during JSON validation.

#### E4001: Invalid Number Format
**Message**: `Invalid number format: X`

**Cause**: A number in the JSON doesn't conform to the JSON specification.

**Examples**:
```json
// ❌ Wrong
{ "value": 01 }      // Leading zeros not allowed
{ "value": .5 }      // Must be 0.5
{ "value": 1. }      // Must be 1.0
{ "value": +1 }      // Plus sign not allowed

// ✅ Correct
{ "value": 1 }
{ "value": 0.5 }
{ "value": 1.0 }
{ "value": -1 }
```

#### E4002: Invalid Unicode Escape
**Message**: `Invalid Unicode escape sequence: \uXXXX`

**Cause**: Malformed Unicode escape sequence in a string.

**Solution**:
- Unicode escapes must be exactly 4 hexadecimal digits
- Use `\uXXXX` format (e.g., `\u00A9` for ©)

### Configuration Errors (5xxx)

Errors related to zmin configuration and options.

#### E5001: Invalid Mode
**Message**: `Invalid performance mode: X`

**Cause**: Specified mode is not recognized.

**Valid modes**:
- `eco` - Balanced performance
- `sport` - Optimized (default)
- `turbo` - Maximum performance

#### E5002: Incompatible Options
**Message**: `Options X and Y cannot be used together`

**Common conflicts**:
- `--streaming` with `--validate-only`
- `--gpu` with `--memory-limit`

### System Errors (6xxx)

System-level errors and failures.

#### E6001: GPU Not Available
**Message**: `GPU acceleration requested but not available`

**Causes**:
- No compatible GPU found
- GPU drivers not installed
- Insufficient GPU memory

**Solutions**:
1. Install/update GPU drivers
2. Use CPU mode: remove `--gpu` flag
3. Check GPU compatibility with `zmin --gpu-info`

## Error Handling Best Practices

### 1. Enable Verbose Output
```bash
zmin --verbose input.json
```

### 2. Use Validation Mode First
```bash
zmin --validate-only input.json
```

### 3. Check Logs
```bash
zmin --log-level=debug input.json 2> error.log
```

### 4. Progressive Debugging
1. Validate JSON with external tool
2. Try with small subset of data
3. Use Eco mode to rule out performance issues
4. Enable detailed error reporting

## Common Error Patterns

### Large File Errors
**Symptoms**: Errors only occur with files >100MB

**Solutions**:
```bash
# Use streaming mode
zmin --streaming large.json

# Increase memory limit
zmin --memory-limit=2GB large.json

# Process in chunks
split -b 100M large.json chunk_
for chunk in chunk_*; do
    zmin "$chunk"
done
```

### Encoding Issues
**Symptoms**: Errors with non-ASCII characters

**Solutions**:
```bash
# Check file encoding
file -I input.json

# Convert to UTF-8
iconv -f ISO-8859-1 -t UTF-8 input.json > input-utf8.json

# Use zmin with UTF-8
zmin input-utf8.json
```

### Performance Errors
**Symptoms**: Timeouts or slow processing

**Solutions**:
```bash
# Profile performance
zmin --profile input.json

# Use appropriate mode
zmin -m turbo large.json  # For large files
zmin -m eco small.json    # For many small files

# Enable parallel processing
zmin --parallel input/*.json
```

## Getting Help

If you encounter an error not listed here:

1. Check the [GitHub Issues](https://github.com/hydepwns/zmin/issues)
2. Run with debug logging: `zmin --log-level=trace`
3. Create a minimal reproducible example
4. Report the issue with:
   - Error message and code
   - zmin version (`zmin --version`)
   - Operating system
   - Sample JSON that triggers the error