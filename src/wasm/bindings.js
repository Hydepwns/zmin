/**
 * JavaScript bindings for zmin WebAssembly module
 * 
 * This provides a high-level JavaScript API for the zmin WASM module
 */

class ZminWasm {
    constructor() {
        this.instance = null;
        this.memory = null;
        this.initialized = false;
    }

    /**
     * Initialize the WebAssembly module
     * @param {WebAssembly.Instance | string} wasmSource - WASM instance or URL to .wasm file
     */
    async init(wasmSource) {
        if (typeof wasmSource === 'string') {
            // Load from URL
            const response = await fetch(wasmSource);
            const buffer = await response.arrayBuffer();
            const module = await WebAssembly.compile(buffer);
            this.instance = await WebAssembly.instantiate(module, {
                env: {
                    // Add any imports if needed
                }
            });
        } else {
            // Use provided instance
            this.instance = wasmSource;
        }

        this.memory = this.instance.exports.memory;
        this.exports = this.instance.exports;
        
        // Initialize the WASM module
        this.exports.zmin_init();
        this.initialized = true;
    }

    /**
     * Check if the module is initialized
     */
    checkInitialized() {
        if (!this.initialized) {
            throw new Error('ZminWasm not initialized. Call init() first.');
        }
    }

    /**
     * Get version string
     * @returns {string} Version string
     */
    getVersion() {
        this.checkInitialized();
        const ptr = this.exports.zmin_version();
        return this.readCString(ptr);
    }

    /**
     * Processing modes
     */
    static Mode = {
        ECO: 0,
        SPORT: 1,
        TURBO: 2
    };

    /**
     * Minify JSON string
     * @param {string} input - JSON string to minify
     * @param {number} mode - Processing mode (optional, defaults to SPORT)
     * @returns {string} Minified JSON
     */
    minify(input, mode = ZminWasm.Mode.SPORT) {
        this.checkInitialized();

        // Convert string to UTF-8 bytes
        const encoder = new TextEncoder();
        const inputBytes = encoder.encode(input);

        // Allocate memory for input
        const inputPtr = this.exports.zmin_alloc(inputBytes.length);
        if (!inputPtr) {
            throw new Error('Failed to allocate memory for input');
        }

        // Copy input to WASM memory
        new Uint8Array(this.memory.buffer, inputPtr, inputBytes.length).set(inputBytes);

        // Call minify function
        const result = this.exports.zmin_minify_mode(inputPtr, inputBytes.length, mode);

        // Free input memory
        this.exports.zmin_free(inputPtr, inputBytes.length);

        // Check for errors
        if (result.error_code !== 0) {
            const errorMsg = this.getErrorMessage(result.error_code);
            throw new Error(`Minification failed: ${errorMsg}`);
        }

        // Read output
        const output = this.readString(result.ptr, result.len);

        // Free output memory
        this.exports.zmin_free(result.ptr, result.len);

        return output;
    }

    /**
     * Validate JSON string
     * @param {string} input - JSON string to validate
     * @returns {boolean} True if valid, false otherwise
     */
    validate(input) {
        this.checkInitialized();

        // Convert string to UTF-8 bytes
        const encoder = new TextEncoder();
        const inputBytes = encoder.encode(input);

        // Allocate memory for input
        const inputPtr = this.exports.zmin_alloc(inputBytes.length);
        if (!inputPtr) {
            throw new Error('Failed to allocate memory for input');
        }

        // Copy input to WASM memory
        new Uint8Array(this.memory.buffer, inputPtr, inputBytes.length).set(inputBytes);

        // Call validate function
        const errorCode = this.exports.zmin_validate(inputPtr, inputBytes.length);

        // Free input memory
        this.exports.zmin_free(inputPtr, inputBytes.length);

        return errorCode === 0;
    }

    /**
     * Get memory usage statistics
     * @returns {object} Memory usage info
     */
    getMemoryStats() {
        this.checkInitialized();
        return {
            used: this.exports.zmin_get_memory_usage(),
            max: this.exports.zmin_get_max_memory()
        };
    }

    /**
     * Get error message for error code
     * @param {number} errorCode - Error code
     * @returns {string} Error message
     */
    getErrorMessage(errorCode) {
        this.checkInitialized();
        const ptr = this.exports.zmin_get_error_message(errorCode);
        return this.readCString(ptr);
    }

    /**
     * Estimate output size for given input size
     * @param {number} inputSize - Input size in bytes
     * @returns {number} Estimated output size
     */
    estimateOutputSize(inputSize) {
        this.checkInitialized();
        return this.exports.zmin_estimate_output_size(inputSize);
    }

    /**
     * Read a null-terminated C string from WASM memory
     * @private
     */
    readCString(ptr) {
        const memory = new Uint8Array(this.memory.buffer);
        let end = ptr;
        while (memory[end] !== 0) end++;
        return this.readString(ptr, end - ptr);
    }

    /**
     * Read a string from WASM memory
     * @private
     */
    readString(ptr, len) {
        const memory = new Uint8Array(this.memory.buffer, ptr, len);
        const decoder = new TextDecoder();
        return decoder.decode(memory);
    }
}

// Export for different module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = ZminWasm;
} else if (typeof define === 'function' && define.amd) {
    define([], function() { return ZminWasm; });
} else if (typeof window !== 'undefined') {
    window.ZminWasm = ZminWasm;
}