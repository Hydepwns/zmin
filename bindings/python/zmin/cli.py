#!/usr/bin/env python3
"""
zmin CLI - Ultra-high-performance JSON minifier command-line interface
"""

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Optional

from ..zmin import minify, validate, format_json, ZminError


def create_parser() -> argparse.ArgumentParser:
    """Create and configure the argument parser."""
    parser = argparse.ArgumentParser(
        prog="zmin",
        description="Ultra-high-performance JSON minifier with 3.5+ GB/s throughput",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  zmin input.json output.json           # Minify file
  zmin --mode turbo large.json min.json     # Use TURBO mode
  zmin --pretty ugly.json pretty.json       # Pretty format
  zmin --validate data.json                  # Validate only
  cat data.json | zmin                       # Pipe usage
  echo '{"key":"value"}' | zmin --pretty     # Pretty pipe

Performance modes:
  eco    - 580 MB/s, minimal memory usage
  sport  - 850 MB/s, balanced performance (default)
  turbo  - 3.5+ GB/s, maximum speed with SIMD
        """
    )

    # Positional arguments
    parser.add_argument(
        "input",
        nargs="?",
        help="Input JSON file (or stdin if not provided)"
    )
    parser.add_argument(
        "output",
        nargs="?",
        help="Output file (or stdout if not provided)"
    )

    # Mode options
    parser.add_argument(
        "-m", "--mode",
        choices=["eco", "sport", "turbo"],
        default="sport",
        help="Processing mode (default: %(default)s)"
    )

    # Formatting options
    parser.add_argument(
        "-p", "--pretty",
        action="store_true",
        help="Pretty print with indentation"
    )
    parser.add_argument(
        "-i", "--indent",
        type=int,
        default=2,
        metavar="N",
        help="Indentation spaces (with --pretty, default: %(default)s)"
    )
    parser.add_argument(
        "--sort-keys",
        action="store_true",
        help="Sort object keys alphabetically"
    )

    # Validation options
    parser.add_argument(
        "-v", "--validate",
        action="store_true",
        help="Validate JSON without minifying"
    )

    # Output options
    parser.add_argument(
        "-q", "--quiet",
        action="store_true",
        help="Suppress progress output"
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Show performance statistics"
    )

    # Version
    parser.add_argument(
        "--version",
        action="version",
        version="%(prog)s 0.1.0"
    )

    return parser


def read_input(input_path: Optional[str]) -> str:
    """Read input from file or stdin."""
    if input_path:
        if input_path == "-":
            return sys.stdin.read()
        
        path = Path(input_path)
        if not path.exists():
            raise FileNotFoundError(f"Input file '{input_path}' not found")
        
        return path.read_text(encoding="utf-8")
    else:
        # Read from stdin
        if sys.stdin.isatty():
            raise ValueError("No input file specified and stdin is empty")
        return sys.stdin.read()


def write_output(output_path: Optional[str], content: str) -> None:
    """Write output to file or stdout."""
    if output_path and output_path != "-":
        Path(output_path).write_text(content, encoding="utf-8")
    else:
        sys.stdout.write(content)
        if not content.endswith("\n"):
            sys.stdout.write("\n")


def format_size(size_bytes: int) -> str:
    """Format byte size for human readability."""
    for unit in ["B", "KB", "MB", "GB"]:
        if size_bytes < 1024:
            return f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024
    return f"{size_bytes:.1f} TB"


def format_duration(seconds: float) -> str:
    """Format duration for human readability."""
    if seconds < 1:
        return f"{seconds * 1000:.1f}ms"
    elif seconds < 60:
        return f"{seconds:.2f}s"
    else:
        minutes = int(seconds // 60)
        seconds = seconds % 60
        return f"{minutes}m {seconds:.1f}s"


def calculate_throughput(size_bytes: int, duration_seconds: float) -> str:
    """Calculate and format throughput."""
    if duration_seconds <= 0:
        return "N/A"
    
    bytes_per_second = size_bytes / duration_seconds
    return f"{format_size(int(bytes_per_second))}/s"


def process_json(
    input_text: str,
    mode: str,
    pretty: bool = False,
    indent: int = 2,
    sort_keys: bool = False,
    validate_only: bool = False
) -> str:
    """Process JSON according to the specified options."""
    if validate_only:
        is_valid = validate(input_text)
        return "✅ Valid JSON" if is_valid else "❌ Invalid JSON"
    
    if pretty:
        return format_json(input_text, indent=indent, sort_keys=sort_keys)
    else:
        return minify(input_text, mode=mode)


def main() -> None:
    """Main CLI entry point."""
    parser = create_parser()
    args = parser.parse_args()

    try:
        # Read input
        start_time = time.time()
        input_text = read_input(args.input)
        read_time = time.time() - start_time

        if not input_text.strip():
            print("Error: Input is empty", file=sys.stderr)
            sys.exit(1)

        input_size = len(input_text.encode("utf-8"))

        # Process JSON
        process_start = time.time()
        try:
            result = process_json(
                input_text,
                mode=args.mode,
                pretty=args.pretty,
                indent=args.indent,
                sort_keys=args.sort_keys,
                validate_only=args.validate
            )
        except ZminError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
        except json.JSONDecodeError as e:
            print(f"JSON Error: {e}", file=sys.stderr)
            sys.exit(1)
        
        process_time = time.time() - process_start

        # Write output
        write_start = time.time()
        write_output(args.output, result)
        write_time = time.time() - write_start

        total_time = time.time() - start_time

        # Show statistics if requested
        if not args.quiet and args.output and args.output != "-":
            output_size = len(result.encode("utf-8"))
            
            if not args.validate:
                reduction = ((input_size - output_size) / input_size * 100) if input_size > 0 else 0
                throughput = calculate_throughput(input_size, process_time)
                
                print(f"✅ Processed {format_size(input_size)} in {format_duration(total_time)}", file=sys.stderr)
                print(f"📊 Throughput: {throughput} ({args.mode.upper()} mode)", file=sys.stderr)
                print(f"📦 Output: {format_size(output_size)} ({reduction:.1f}% reduction)", file=sys.stderr)
            else:
                print(f"✅ Validated {format_size(input_size)} in {format_duration(total_time)}", file=sys.stderr)

        # Show detailed stats if requested
        if args.stats:
            print(f"\n📈 Performance Statistics:", file=sys.stderr)
            print(f"   Read time:    {format_duration(read_time)}", file=sys.stderr)
            print(f"   Process time: {format_duration(process_time)}", file=sys.stderr)
            print(f"   Write time:   {format_duration(write_time)}", file=sys.stderr)
            print(f"   Total time:   {format_duration(total_time)}", file=sys.stderr)
            if not args.validate:
                print(f"   Throughput:   {calculate_throughput(input_size, process_time)}", file=sys.stderr)

    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nInterrupted", file=sys.stderr)
        sys.exit(130)
    except Exception as e:
        print(f"Fatal error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()