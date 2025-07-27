#!/usr/bin/env node

/**
 * zmin CLI for Node.js
 * Ultra-high-performance JSON minifier
 */

const fs = require('fs');
const path = require('path');
const { minify, validate, formatJson, sync } = require('../dist/index.js');

function showHelp() {
  console.log(`
zmin - Ultra-high-performance JSON minifier

USAGE:
    zmin [OPTIONS] [INPUT] [OUTPUT]

ARGS:
    <INPUT>     Input JSON file (or stdin if not provided)
    <OUTPUT>    Output file (or stdout if not provided)

OPTIONS:
    -m, --mode <MODE>       Processing mode: eco, sport, turbo [default: sport]
    -p, --pretty            Pretty print with indentation
    -i, --indent <NUM>      Indentation spaces (with --pretty) [default: 2]
    -v, --validate          Validate JSON without minifying
    -s, --sync              Use synchronous processing (fallback)
    -q, --quiet             Suppress progress output
    -h, --help              Show this help message
    --version               Show version information

EXAMPLES:
    zmin input.json output.json          # Minify file
    zmin --mode turbo large.json min.json    # Use TURBO mode
    zmin --pretty ugly.json pretty.json      # Pretty format
    zmin --validate data.json                 # Validate only
    cat data.json | zmin                      # Pipe usage
    echo '{"key":"value"}' | zmin --pretty    # Pretty pipe
`);
}

function showVersion() {
  const packageJson = require('../package.json');
  console.log(`zmin v${packageJson.version}`);
  console.log('Ultra-high-performance JSON minifier');
  console.log('Written in Zig with WebAssembly bindings');
}

async function processInput(input, options) {
  try {
    if (options.validate) {
      const isValid = options.sync ? sync.validate(input) : await validate(input);
      return isValid ? 'Valid JSON' : 'Invalid JSON';
    }

    if (options.pretty) {
      const formatted = options.sync 
        ? sync.formatJson(input, { indent: options.indent })
        : await formatJson(input, { indent: options.indent });
      return formatted;
    }

    const minified = options.sync 
      ? sync.minify(input)
      : await minify(input, { mode: options.mode });
    return minified;
  } catch (error) {
    throw new Error(`Processing failed: ${error.message}`);
  }
}

async function main() {
  const args = process.argv.slice(2);
  
  // Parse options
  const options = {
    mode: 'sport',
    pretty: false,
    indent: 2,
    validate: false,
    sync: false,
    quiet: false,
    inputFile: null,
    outputFile: null,
  };

  let i = 0;
  while (i < args.length) {
    const arg = args[i];
    
    switch (arg) {
      case '-h':
      case '--help':
        showHelp();
        process.exit(0);
        break;
        
      case '--version':
        showVersion();
        process.exit(0);
        break;
        
      case '-m':
      case '--mode':
        if (i + 1 >= args.length) {
          console.error('Error: --mode requires a value (eco, sport, turbo)');
          process.exit(1);
        }
        const mode = args[i + 1];
        if (!['eco', 'sport', 'turbo'].includes(mode)) {
          console.error('Error: Invalid mode. Use eco, sport, or turbo');
          process.exit(1);
        }
        options.mode = mode;
        i += 2;
        break;
        
      case '-p':
      case '--pretty':
        options.pretty = true;
        i++;
        break;
        
      case '-i':
      case '--indent':
        if (i + 1 >= args.length) {
          console.error('Error: --indent requires a number');
          process.exit(1);
        }
        const indent = parseInt(args[i + 1], 10);
        if (isNaN(indent) || indent < 0) {
          console.error('Error: --indent must be a non-negative number');
          process.exit(1);
        }
        options.indent = indent;
        i += 2;
        break;
        
      case '-v':
      case '--validate':
        options.validate = true;
        i++;
        break;
        
      case '-s':
      case '--sync':
        options.sync = true;
        i++;
        break;
        
      case '-q':
      case '--quiet':
        options.quiet = true;
        i++;
        break;
        
      default:
        if (arg.startsWith('-')) {
          console.error(`Error: Unknown option ${arg}`);
          process.exit(1);
        }
        
        if (!options.inputFile) {
          options.inputFile = arg;
        } else if (!options.outputFile) {
          options.outputFile = arg;
        } else {
          console.error('Error: Too many arguments');
          process.exit(1);
        }
        i++;
        break;
    }
  }

  try {
    let input = '';
    
    // Read input
    if (options.inputFile) {
      if (!fs.existsSync(options.inputFile)) {
        console.error(`Error: Input file '${options.inputFile}' not found`);
        process.exit(1);
      }
      input = fs.readFileSync(options.inputFile, 'utf8');
    } else {
      // Read from stdin
      if (process.stdin.isTTY) {
        console.error('Error: No input file specified and stdin is empty');
        showHelp();
        process.exit(1);
      }
      
      const chunks = [];
      process.stdin.setEncoding('utf8');
      
      for await (const chunk of process.stdin) {
        chunks.push(chunk);
      }
      
      input = chunks.join('');
    }

    if (!input.trim()) {
      console.error('Error: Input is empty');
      process.exit(1);
    }

    // Process input
    const startTime = Date.now();
    const result = await processInput(input, options);
    const endTime = Date.now();

    // Write output
    if (options.outputFile) {
      fs.writeFileSync(options.outputFile, result);
      if (!options.quiet) {
        const inputSize = Buffer.byteLength(input, 'utf8');
        const outputSize = Buffer.byteLength(result, 'utf8');
        const ratio = ((1 - outputSize / inputSize) * 100).toFixed(1);
        const time = endTime - startTime;
        const throughput = (inputSize / 1024 / 1024 / (time / 1000)).toFixed(1);
        
        console.error(`✅ Processed ${inputSize} bytes in ${time}ms (${throughput} MB/s)`);
        if (!options.validate) {
          console.error(`📦 Output: ${outputSize} bytes (${ratio}% reduction)`);
        }
      }
    } else {
      process.stdout.write(result);
      if (!result.endsWith('\n')) {
        process.stdout.write('\n');
      }
    }

  } catch (error) {
    console.error(`Error: ${error.message}`);
    process.exit(1);
  }
}

// Handle uncaught errors
process.on('uncaughtException', (error) => {
  console.error(`Fatal error: ${error.message}`);
  process.exit(1);
});

process.on('unhandledRejection', (error) => {
  console.error(`Unhandled rejection: ${error}`);
  process.exit(1);
});

main().catch(error => {
  console.error(`Fatal error: ${error.message}`);
  process.exit(1);
});