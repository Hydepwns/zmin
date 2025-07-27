/**
 * Node.js bindings for zmin JSON minifier
 */

const binding = require('bindings')('zmin');

/**
 * Processing modes for JSON minification
 */
const ProcessingMode = {
    ECO: 0,    // Memory-efficient mode (64KB limit)
    SPORT: 1,  // Balanced mode (default)
    TURBO: 2   // Maximum performance mode
};

/**
 * Minify JSON data
 * @param {string|object} input - JSON string or object to minify
 * @param {number} mode - Processing mode (default: SPORT)
 * @returns {string} Minified JSON string
 * @throws {Error} If minification fails
 */
function minify(input, mode = ProcessingMode.SPORT) {
    // Convert object to string if needed
    const jsonString = typeof input === 'string' ? input : JSON.stringify(input);
    
    // Validate mode
    if (!Object.values(ProcessingMode).includes(mode)) {
        throw new Error(`Invalid mode: ${mode}`);
    }
    
    // Call native function
    const result = binding.minify(jsonString, mode);
    
    if (result.error) {
        throw new Error(result.error);
    }
    
    return result.output;
}

/**
 * Minify JSON data asynchronously
 * @param {string|object} input - JSON string or object to minify
 * @param {number} mode - Processing mode (default: SPORT)
 * @returns {Promise<string>} Promise resolving to minified JSON string
 */
function minifyAsync(input, mode = ProcessingMode.SPORT) {
    return new Promise((resolve, reject) => {
        // Convert object to string if needed
        const jsonString = typeof input === 'string' ? input : JSON.stringify(input);
        
        // Validate mode
        if (!Object.values(ProcessingMode).includes(mode)) {
            reject(new Error(`Invalid mode: ${mode}`));
            return;
        }
        
        // Call native async function
        binding.minifyAsync(jsonString, mode, (err, result) => {
            if (err) {
                reject(err);
            } else {
                resolve(result);
            }
        });
    });
}

/**
 * Validate JSON data
 * @param {string|object} input - JSON string or object to validate
 * @returns {boolean} True if valid JSON
 */
function validate(input) {
    // Convert object to string if needed
    const jsonString = typeof input === 'string' ? input : JSON.stringify(input);
    
    return binding.validate(jsonString);
}

/**
 * Validate JSON data asynchronously
 * @param {string|object} input - JSON string or object to validate
 * @returns {Promise<boolean>} Promise resolving to validation result
 */
function validateAsync(input) {
    return new Promise((resolve, reject) => {
        // Convert object to string if needed
        const jsonString = typeof input === 'string' ? input : JSON.stringify(input);
        
        binding.validateAsync(jsonString, (err, result) => {
            if (err) {
                reject(err);
            } else {
                resolve(result);
            }
        });
    });
}

/**
 * Get zmin version
 * @returns {string} Version string
 */
function getVersion() {
    return binding.getVersion();
}

/**
 * Create a transform stream for minifying JSON
 * @param {number} mode - Processing mode (default: SPORT)
 * @returns {Transform} Transform stream
 */
function createMinifyStream(mode = ProcessingMode.SPORT) {
    const { Transform } = require('stream');
    
    return new Transform({
        transform(chunk, encoding, callback) {
            try {
                const input = chunk.toString();
                const output = minify(input, mode);
                callback(null, output);
            } catch (err) {
                callback(err);
            }
        }
    });
}

/**
 * Minify a JSON file
 * @param {string} inputPath - Path to input file
 * @param {string} outputPath - Path to output file
 * @param {number} mode - Processing mode (default: SPORT)
 * @returns {Promise<void>}
 */
async function minifyFile(inputPath, outputPath, mode = ProcessingMode.SPORT) {
    const fs = require('fs').promises;
    
    const input = await fs.readFile(inputPath, 'utf8');
    const output = await minifyAsync(input, mode);
    await fs.writeFile(outputPath, output, 'utf8');
}

/**
 * Validate a JSON file
 * @param {string} filePath - Path to JSON file
 * @returns {Promise<boolean>} True if valid JSON
 */
async function validateFile(filePath) {
    const fs = require('fs').promises;
    
    const input = await fs.readFile(filePath, 'utf8');
    return validateAsync(input);
}

// Export API
module.exports = {
    minify,
    minifyAsync,
    validate,
    validateAsync,
    getVersion,
    createMinifyStream,
    minifyFile,
    validateFile,
    ProcessingMode,
    
    // Convenience methods
    eco: (input) => minify(input, ProcessingMode.ECO),
    sport: (input) => minify(input, ProcessingMode.SPORT),
    turbo: (input) => minify(input, ProcessingMode.TURBO),
    
    // Async convenience methods
    ecoAsync: (input) => minifyAsync(input, ProcessingMode.ECO),
    sportAsync: (input) => minifyAsync(input, ProcessingMode.SPORT),
    turboAsync: (input) => minifyAsync(input, ProcessingMode.TURBO),
};