#!/usr/bin/env node

/**
 * Simple test for @zmin/cli npm package
 */

const { minify, validate, formatJson } = require('../dist/index.js');

async function testBasicFunctionality() {
    console.log("Testing basic functionality...");
    
    const testJson = `
    {
        "name": "John Doe",
        "age": 30,
        "city": "New York",
        "hobbies": ["reading", "swimming", "coding"]
    }
    `;
    
    try {
        // Test minification
        const minified = await minify(testJson);
        console.log(`✓ Minification successful: ${minified.substring(0, 50)}...`);
        
        // Test validation
        const isValid = await validate(testJson);
        console.log(`✓ Validation successful: ${isValid}`);
        
        // Test formatting
        const formatted = await formatJson(testJson, { indent: 2 });
        console.log(`✓ Formatting successful: ${formatted.substring(0, 50)}...`);
        
        return true;
    } catch (error) {
        console.error(`✗ Test failed: ${error.message}`);
        return false;
    }
}

async function testErrorHandling() {
    console.log("\nTesting error handling...");
    
    try {
        // Test invalid JSON
        await minify('{"invalid": json}');
        console.log("✗ Should have thrown an error for invalid JSON");
        return false;
    } catch (error) {
        console.log("✓ Properly handled invalid JSON");
        return true;
    }
}

async function testDifferentModes() {
    console.log("\nTesting different modes...");
    
    const testJson = '{"key": "value", "array": [1, 2, 3]}';
    
    try {
        const ecoResult = await minify(testJson, { mode: 'eco' });
        const sportResult = await minify(testJson, { mode: 'sport' });
        const turboResult = await minify(testJson, { mode: 'turbo' });
        
        console.log("✓ All processing modes work");
        return true;
    } catch (error) {
        console.error(`✗ Mode test failed: ${error.message}`);
        return false;
    }
}

async function main() {
    console.log("zmin npm package test");
    console.log("=" * 30);
    
    const tests = [
        testBasicFunctionality,
        testErrorHandling,
        testDifferentModes,
    ];
    
    let passed = 0;
    const total = tests.length;
    
    for (const test of tests) {
        if (await test()) {
            passed++;
        }
    }
    
    console.log(`\nResults: ${passed}/${total} tests passed`);
    
    if (passed === total) {
        console.log("✓ All tests passed!");
        process.exit(0);
    } else {
        console.log("✗ Some tests failed!");
        process.exit(1);
    }
}

// Handle unhandled promise rejections
process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled Rejection at:', promise, 'reason:', reason);
    process.exit(1);
});

main().catch(error => {
    console.error('Test runner failed:', error);
    process.exit(1);
}); 