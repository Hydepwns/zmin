/**
 * @zmin/cli - Ultra-high-performance JSON minifier
 * 
 * WebAssembly bindings for the zmin JSON minifier written in Zig.
 * Provides 3.5+ GB/s throughput with memory safety guarantees.
 */

export interface FormatOptions {
  /** Number of spaces for indentation (default: 2) */
  indent?: number;
  /** Sort object keys alphabetically (default: false) */
  sortKeys?: boolean;
}

export interface MinifyOptions {
  /** Processing mode: 'eco' | 'sport' | 'turbo' (default: 'sport') */
  mode?: 'eco' | 'sport' | 'turbo';
  /** Validate JSON before minifying (default: true) */
  validate?: boolean;
}

/**
 * WebAssembly module instance
 */
let wasmModule: any = null;

/**
 * Initialize the WebAssembly module
 */
async function initWasm(): Promise<void> {
  if (wasmModule) return;
  
  try {
    // In Node.js environment
    if (typeof process !== 'undefined' && process.versions && process.versions.node) {
      const fs = require('fs');
      const path = require('path');
      const wasmPath = path.join(__dirname, 'zmin.wasm');
      const wasmBuffer = fs.readFileSync(wasmPath);
      const wasmModule = await WebAssembly.instantiate(wasmBuffer);
      module.exports.wasmModule = wasmModule.instance;
    } else {
      // In browser environment
      const response = await fetch('/dist/zmin.wasm');
      const wasmBuffer = await response.arrayBuffer();
      wasmModule = await WebAssembly.instantiate(wasmBuffer);
    }
  } catch (error) {
    throw new Error(`Failed to initialize WebAssembly module: ${error}`);
  }
}

/**
 * Convert string to WebAssembly memory
 */
function stringToWasmMemory(str: string): { ptr: number; len: number } {
  const encoder = new TextEncoder();
  const bytes = encoder.encode(str);
  const ptr = wasmModule.exports.allocate(bytes.length);
  const memory = new Uint8Array(wasmModule.exports.memory.buffer, ptr, bytes.length);
  memory.set(bytes);
  return { ptr, len: bytes.length };
}

/**
 * Convert WebAssembly memory to string
 */
function wasmMemoryToString(ptr: number, len: number): string {
  const memory = new Uint8Array(wasmModule.exports.memory.buffer, ptr, len);
  const decoder = new TextDecoder();
  return decoder.decode(memory);
}

/**
 * Minify JSON string by removing unnecessary whitespace
 * 
 * @param input - JSON string to minify
 * @param options - Optional minification options
 * @returns Minified JSON string
 * @throws Error if input is invalid JSON
 * 
 * @example
 * ```typescript
 * const minified = await minify('{"key": "value", "array": [1, 2, 3]}');
 * console.log(minified); // {"key":"value","array":[1,2,3]}
 * ```
 */
export async function minify(input: string, options: MinifyOptions = {}): Promise<string> {
  await initWasm();
  
  const { mode = 'sport', validate = true } = options;
  
  if (validate && !isValidJson(input)) {
    throw new Error('Invalid JSON input');
  }
  
  const inputMem = stringToWasmMemory(input);
  const modeValue = mode === 'eco' ? 0 : mode === 'sport' ? 1 : 2;
  
  try {
    const resultPtr = wasmModule.exports.minify(inputMem.ptr, inputMem.len, modeValue);
    const resultLen = wasmModule.exports.get_result_length(resultPtr);
    const result = wasmMemoryToString(resultPtr, resultLen);
    
    // Clean up memory
    wasmModule.exports.deallocate(inputMem.ptr, inputMem.len);
    wasmModule.exports.deallocate(resultPtr, resultLen);
    
    return result;
  } catch (error) {
    wasmModule.exports.deallocate(inputMem.ptr, inputMem.len);
    throw new Error(`Minification failed: ${error}`);
  }
}

/**
 * Validate if a string is valid JSON
 * 
 * @param input - String to validate
 * @returns true if valid JSON, false otherwise
 * 
 * @example
 * ```typescript
 * console.log(await validate('{"valid": true}')); // true
 * console.log(await validate('invalid')); // false
 * ```
 */
export async function validate(input: string): Promise<boolean> {
  await initWasm();
  
  const inputMem = stringToWasmMemory(input);
  
  try {
    const isValid = wasmModule.exports.validate(inputMem.ptr, inputMem.len);
    wasmModule.exports.deallocate(inputMem.ptr, inputMem.len);
    return Boolean(isValid);
  } catch (error) {
    wasmModule.exports.deallocate(inputMem.ptr, inputMem.len);
    return false;
  }
}

/**
 * Format JSON with proper indentation
 * 
 * @param input - JSON string to format
 * @param options - Formatting options
 * @returns Formatted JSON string
 * @throws Error if input is invalid JSON
 * 
 * @example
 * ```typescript
 * const formatted = await formatJson('{"key":"value"}', { indent: 4 });
 * console.log(formatted);
 * // {
 * //     "key": "value"
 * // }
 * ```
 */
export async function formatJson(input: string, options: FormatOptions = {}): Promise<string> {
  const { indent = 2, sortKeys = false } = options;
  
  // For now, use native JSON.stringify for formatting
  // TODO: Implement WebAssembly formatting for better performance
  try {
    const parsed = JSON.parse(input);
    return JSON.stringify(parsed, sortKeys ? Object.keys(parsed).sort() : null, indent);
  } catch (error) {
    throw new Error(`Invalid JSON: ${error}`);
  }
}

/**
 * Get performance statistics for the last operation
 */
export async function getStats(): Promise<{
  lastOperationTime: number;
  totalOperations: number;
  averageThroughput: number;
}> {
  await initWasm();
  
  const stats = wasmModule.exports.get_stats();
  return {
    lastOperationTime: stats.last_operation_time,
    totalOperations: stats.total_operations,
    averageThroughput: stats.average_throughput,
  };
}

// Helper function for quick validation
function isValidJson(str: string): boolean {
  try {
    JSON.parse(str);
    return true;
  } catch {
    return false;
  }
}

// Synchronous versions (fallback to native JSON when WASM not available)
export const sync = {
  /**
   * Synchronous minify using native JSON (fallback)
   */
  minify(input: string): string {
    try {
      return JSON.stringify(JSON.parse(input));
    } catch (error) {
      throw new Error(`Invalid JSON: ${error}`);
    }
  },

  /**
   * Synchronous validate using native JSON
   */
  validate(input: string): boolean {
    return isValidJson(input);
  },

  /**
   * Synchronous format using native JSON
   */
  formatJson(input: string, options: FormatOptions = {}): string {
    const { indent = 2, sortKeys = false } = options;
    try {
      const parsed = JSON.parse(input);
      return JSON.stringify(parsed, sortKeys ? Object.keys(parsed).sort() : null, indent);
    } catch (error) {
      throw new Error(`Invalid JSON: ${error}`);
    }
  },
};

// Default export
export default {
  minify,
  validate,
  formatJson,
  getStats,
  sync,
};