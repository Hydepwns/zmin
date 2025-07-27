/**
 * TypeScript definitions for zmin
 */

declare module 'zmin' {
    /**
     * Processing modes for JSON minification
     */
    export enum ProcessingMode {
        /** Memory-efficient mode (64KB limit) */
        ECO = 0,
        /** Balanced mode (default) */
        SPORT = 1,
        /** Maximum performance mode */
        TURBO = 2
    }

    /**
     * Minify JSON data
     * @param input - JSON string or object to minify
     * @param mode - Processing mode (default: SPORT)
     * @returns Minified JSON string
     * @throws Error if minification fails
     */
    export function minify(input: string | object, mode?: ProcessingMode): string;

    /**
     * Minify JSON data asynchronously
     * @param input - JSON string or object to minify
     * @param mode - Processing mode (default: SPORT)
     * @returns Promise resolving to minified JSON string
     */
    export function minifyAsync(input: string | object, mode?: ProcessingMode): Promise<string>;

    /**
     * Validate JSON data
     * @param input - JSON string or object to validate
     * @returns True if valid JSON
     */
    export function validate(input: string | object): boolean;

    /**
     * Validate JSON data asynchronously
     * @param input - JSON string or object to validate
     * @returns Promise resolving to validation result
     */
    export function validateAsync(input: string | object): Promise<boolean>;

    /**
     * Get zmin version
     * @returns Version string
     */
    export function getVersion(): string;

    /**
     * Create a transform stream for minifying JSON
     * @param mode - Processing mode (default: SPORT)
     * @returns Transform stream
     */
    export function createMinifyStream(mode?: ProcessingMode): import('stream').Transform;

    /**
     * Minify a JSON file
     * @param inputPath - Path to input file
     * @param outputPath - Path to output file
     * @param mode - Processing mode (default: SPORT)
     */
    export function minifyFile(inputPath: string, outputPath: string, mode?: ProcessingMode): Promise<void>;

    /**
     * Validate a JSON file
     * @param filePath - Path to JSON file
     * @returns True if valid JSON
     */
    export function validateFile(filePath: string): Promise<boolean>;

    /**
     * Minify using ECO mode
     * @param input - JSON string or object to minify
     * @returns Minified JSON string
     */
    export function eco(input: string | object): string;

    /**
     * Minify using SPORT mode
     * @param input - JSON string or object to minify
     * @returns Minified JSON string
     */
    export function sport(input: string | object): string;

    /**
     * Minify using TURBO mode
     * @param input - JSON string or object to minify
     * @returns Minified JSON string
     */
    export function turbo(input: string | object): string;

    /**
     * Minify using ECO mode asynchronously
     * @param input - JSON string or object to minify
     * @returns Promise resolving to minified JSON string
     */
    export function ecoAsync(input: string | object): Promise<string>;

    /**
     * Minify using SPORT mode asynchronously
     * @param input - JSON string or object to minify
     * @returns Promise resolving to minified JSON string
     */
    export function sportAsync(input: string | object): Promise<string>;

    /**
     * Minify using TURBO mode asynchronously
     * @param input - JSON string or object to minify
     * @returns Promise resolving to minified JSON string
     */
    export function turboAsync(input: string | object): Promise<string>;
}