"""
Python bindings for zmin JSON minifier

This module provides Python bindings for the zmin high-performance JSON minifier
using ctypes to interface with the compiled shared library.
"""

import ctypes
import json
import os
import platform
from enum import IntEnum
from typing import Optional, Union


class ProcessingMode(IntEnum):
    """JSON processing modes"""
    ECO = 0    # Memory-efficient mode (64KB limit)
    SPORT = 1  # Balanced mode (default)
    TURBO = 2  # Maximum performance mode


class ZminError(Exception):
    """Base exception for zmin errors"""
    pass


class Zmin:
    """Python wrapper for zmin JSON minifier"""
    
    def __init__(self, lib_path: Optional[str] = None):
        """
        Initialize zmin wrapper
        
        Args:
            lib_path: Path to zmin shared library. If None, will search standard locations.
        """
        if lib_path is None:
            lib_path = self._find_library()
        
        # Load the shared library
        self._lib = ctypes.CDLL(lib_path)
        
        # Define function signatures
        self._setup_functions()
        
        # Initialize the library
        self._lib.zmin_init()
    
    def _find_library(self) -> str:
        """Find the zmin shared library"""
        system = platform.system()
        
        if system == "Linux":
            lib_names = ["libzmin.so", "./libzmin.so", "/usr/lib/libzmin.so", "/usr/local/lib/libzmin.so"]
        elif system == "Darwin":  # macOS
            lib_names = ["libzmin.dylib", "./libzmin.dylib", "/usr/lib/libzmin.dylib", "/usr/local/lib/libzmin.dylib"]
        elif system == "Windows":
            lib_names = ["zmin.dll", "./zmin.dll", "C:\\Program Files\\zmin\\zmin.dll"]
        else:
            raise ZminError(f"Unsupported platform: {system}")
        
        for lib_name in lib_names:
            if os.path.exists(lib_name):
                return lib_name
        
        raise ZminError("Could not find zmin library. Please specify lib_path.")
    
    def _setup_functions(self):
        """Setup ctypes function signatures"""
        # Result structure
        class ZminResult(ctypes.Structure):
            _fields_ = [
                ("data", ctypes.POINTER(ctypes.c_char)),
                ("size", ctypes.c_size_t),
                ("error_code", ctypes.c_int)
            ]
        
        self.ZminResult = ZminResult
        
        # zmin_init
        self._lib.zmin_init.argtypes = []
        self._lib.zmin_init.restype = None
        
        # zmin_minify
        self._lib.zmin_minify.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
        self._lib.zmin_minify.restype = ZminResult
        
        # zmin_minify_mode
        self._lib.zmin_minify_mode.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_int]
        self._lib.zmin_minify_mode.restype = ZminResult
        
        # zmin_validate
        self._lib.zmin_validate.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
        self._lib.zmin_validate.restype = ctypes.c_int
        
        # zmin_free_result
        self._lib.zmin_free_result.argtypes = [ctypes.POINTER(ZminResult)]
        self._lib.zmin_free_result.restype = None
        
        # zmin_get_version
        self._lib.zmin_get_version.argtypes = []
        self._lib.zmin_get_version.restype = ctypes.c_char_p
        
        # zmin_get_error_message
        self._lib.zmin_get_error_message.argtypes = [ctypes.c_int]
        self._lib.zmin_get_error_message.restype = ctypes.c_char_p
    
    def minify(self, input_json: Union[str, dict, list], mode: ProcessingMode = ProcessingMode.SPORT) -> str:
        """
        Minify JSON data
        
        Args:
            input_json: JSON string, dict, or list to minify
            mode: Processing mode (ECO, SPORT, or TURBO)
        
        Returns:
            Minified JSON string
        
        Raises:
            ZminError: If minification fails
        """
        # Convert input to string if needed
        if isinstance(input_json, (dict, list)):
            input_str = json.dumps(input_json, separators=(',', ':'))
        else:
            input_str = input_json
        
        # Encode to bytes
        input_bytes = input_str.encode('utf-8')
        
        # Call minify function
        result = self._lib.zmin_minify_mode(input_bytes, len(input_bytes), int(mode))
        
        try:
            # Check for errors
            if result.error_code != 0:
                error_msg = self._lib.zmin_get_error_message(result.error_code).decode('utf-8')
                raise ZminError(f"Minification failed: {error_msg}")
            
            # Extract output
            output = ctypes.string_at(result.data, result.size).decode('utf-8')
            return output
        finally:
            # Free the result
            self._lib.zmin_free_result(ctypes.byref(result))
    
    def validate(self, input_json: Union[str, dict, list]) -> bool:
        """
        Validate JSON data
        
        Args:
            input_json: JSON string, dict, or list to validate
        
        Returns:
            True if valid JSON, False otherwise
        """
        # Convert input to string if needed
        if isinstance(input_json, (dict, list)):
            input_str = json.dumps(input_json)
        else:
            input_str = input_json
        
        # Encode to bytes
        input_bytes = input_str.encode('utf-8')
        
        # Call validate function
        error_code = self._lib.zmin_validate(input_bytes, len(input_bytes))
        
        return error_code == 0
    
    def get_version(self) -> str:
        """Get zmin version string"""
        return self._lib.zmin_get_version().decode('utf-8')
    
    def minify_file(self, input_path: str, output_path: str, mode: ProcessingMode = ProcessingMode.SPORT):
        """
        Minify a JSON file
        
        Args:
            input_path: Path to input JSON file
            output_path: Path to output file
            mode: Processing mode
        """
        with open(input_path, 'r', encoding='utf-8') as f:
            input_json = f.read()
        
        output = self.minify(input_json, mode)
        
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(output)
    
    def validate_file(self, file_path: str) -> bool:
        """
        Validate a JSON file
        
        Args:
            file_path: Path to JSON file
        
        Returns:
            True if valid JSON, False otherwise
        """
        with open(file_path, 'r', encoding='utf-8') as f:
            input_json = f.read()
        
        return self.validate(input_json)


# Convenience functions
_default_instance = None


def get_default_instance() -> Zmin:
    """Get or create default zmin instance"""
    global _default_instance
    if _default_instance is None:
        _default_instance = Zmin()
    return _default_instance


def minify(input_json: Union[str, dict, list], mode: ProcessingMode = ProcessingMode.SPORT) -> str:
    """
    Minify JSON data using default instance
    
    Args:
        input_json: JSON string, dict, or list to minify
        mode: Processing mode
    
    Returns:
        Minified JSON string
    """
    return get_default_instance().minify(input_json, mode)


def validate(input_json: Union[str, dict, list]) -> bool:
    """
    Validate JSON data using default instance
    
    Args:
        input_json: JSON string, dict, or list to validate
    
    Returns:
        True if valid JSON, False otherwise
    """
    return get_default_instance().validate(input_json)


def minify_file(input_path: str, output_path: str, mode: ProcessingMode = ProcessingMode.SPORT):
    """Minify a JSON file using default instance"""
    get_default_instance().minify_file(input_path, output_path, mode)


def validate_file(file_path: str) -> bool:
    """Validate a JSON file using default instance"""
    return get_default_instance().validate_file(file_path)


# CLI interface
def main():
    """Command-line interface"""
    import argparse
    import sys
    import time
    
    parser = argparse.ArgumentParser(description='zmin JSON minifier')
    parser.add_argument('input', nargs='?', help='Input JSON file (default: stdin)')
    parser.add_argument('output', nargs='?', help='Output file (default: stdout)')
    parser.add_argument('-m', '--mode', choices=['eco', 'sport', 'turbo'], default='sport',
                        help='Processing mode (default: sport)')
    parser.add_argument('-v', '--validate', action='store_true',
                        help='Validate only, do not minify')
    parser.add_argument('--version', action='store_true',
                        help='Show version and exit')
    parser.add_argument('--stats', action='store_true',
                        help='Show statistics')
    
    args = parser.parse_args()
    
    try:
        zmin = Zmin()
        
        if args.version:
            print(f"zmin version {zmin.get_version()}")
            return
        
        # Read input
        if args.input:
            with open(args.input, 'r', encoding='utf-8') as f:
                input_data = f.read()
        else:
            input_data = sys.stdin.read()
        
        # Validate only
        if args.validate:
            if zmin.validate(input_data):
                print("Valid JSON", file=sys.stderr)
                sys.exit(0)
            else:
                print("Invalid JSON", file=sys.stderr)
                sys.exit(1)
        
        # Get mode
        mode_map = {
            'eco': ProcessingMode.ECO,
            'sport': ProcessingMode.SPORT,
            'turbo': ProcessingMode.TURBO
        }
        mode = mode_map[args.mode]
        
        # Minify
        start_time = time.time()
        output = zmin.minify(input_data, mode)
        elapsed = time.time() - start_time
        
        # Write output
        if args.output:
            with open(args.output, 'w', encoding='utf-8') as f:
                f.write(output)
        else:
            print(output, end='')
        
        # Show stats
        if args.stats:
            input_size = len(input_data.encode('utf-8'))
            output_size = len(output.encode('utf-8'))
            reduction = (input_size - output_size) / input_size * 100
            throughput = input_size / elapsed / 1024 / 1024
            
            print(f"\nStatistics:", file=sys.stderr)
            print(f"  Input size:  {input_size:,} bytes", file=sys.stderr)
            print(f"  Output size: {output_size:,} bytes", file=sys.stderr)
            print(f"  Reduction:   {reduction:.1f}%", file=sys.stderr)
            print(f"  Time:        {elapsed*1000:.2f} ms", file=sys.stderr)
            print(f"  Throughput:  {throughput:.1f} MB/s", file=sys.stderr)
    
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()