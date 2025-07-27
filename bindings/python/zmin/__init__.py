"""
zmin - High-performance JSON minifier for Python

This package provides Python bindings for the zmin high-performance JSON minifier
using ctypes to interface with the compiled shared library.
"""

from ..zmin import (
    Zmin,
    ZminError,
    ProcessingMode,
    minify,
    validate,
    minify_file,
    validate_file,
    get_default_instance,
    get_version,
    eco,
    sport,
    turbo,
    minify_async,
    validate_async,
    eco_async,
    sport_async,
    turbo_async,
)

__version__ = "1.0.0"
__author__ = "zmin contributors"
__email__ = ""
__url__ = "https://github.com/hydepwns/zmin"

__all__ = [
    "Zmin",
    "ZminError", 
    "ProcessingMode",
    "minify",
    "validate",
    "minify_file",
    "validate_file",
    "get_default_instance",
    "get_version",
    "eco",
    "sport",
    "turbo",
    "minify_async",
    "validate_async",
    "eco_async",
    "sport_async",
    "turbo_async",
] 