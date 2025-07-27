#!/usr/bin/env python3

import os
try:
    from setuptools import setup, find_packages  # type: ignore
except ImportError:
    print("setuptools is required. Install with: pip install setuptools")
    exit(1)

# Read version from package
here = os.path.abspath(os.path.dirname(__file__))

# Read the README file
with open(os.path.join(here, "README.md"), "r", encoding="utf-8") as f:
    long_description = f.read()

# Read requirements
install_requires = []
if os.path.exists(os.path.join(here, "requirements.txt")):
    with open(os.path.join(here, "requirements.txt"), "r", encoding="utf-8") as f:
        install_requires = [line.strip() for line in f if line.strip() and not line.startswith("#")]

setup(
    name="zmin",
    version="1.0.0",
    author="zmin contributors",
    author_email="",
    description="Ultra-high-performance JSON minifier with up to 1.1 GB/s throughput",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/hydepwns/zmin",
    project_urls={
        "Bug Reports": "https://github.com/hydepwns/zmin/issues",
        "Source": "https://github.com/hydepwns/zmin",
        "Documentation": "https://github.com/hydepwns/zmin#readme",
    },
    packages=find_packages(),
    package_data={
        "zmin": ["*.so", "*.dll", "*.dylib"],
    },
    include_package_data=True,
    classifiers=[
        # Development status
        "Development Status :: 4 - Beta",
        
        # Intended audience
        "Intended Audience :: Developers",
        "Intended Audience :: Information Technology",
        "Intended Audience :: System Administrators",
        
        # License
        "License :: OSI Approved :: MIT License",
        
        # Programming language
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Programming Language :: Python :: Implementation :: CPython",
        "Programming Language :: Python :: Implementation :: PyPy",
        
        # Topics
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Text Processing",
        "Topic :: Utilities",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: System :: Systems Administration",
        
        # Operating systems
        "Operating System :: OS Independent",
        "Operating System :: POSIX :: Linux",
        "Operating System :: MacOS :: MacOS X",
        "Operating System :: Microsoft :: Windows",
        
        # Other
        "Environment :: Console",
        "Natural Language :: English",
        "Typing :: Typed",
    ],
    keywords=[
        "json", "minify", "minifier", "performance", "parsing", 
        "optimization", "zig", "native", "fast", "compress",
        "utilities", "cli", "command-line"
    ],
    python_requires=">=3.8",
    install_requires=install_requires,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-benchmark>=4.0.0",
            "black>=22.0.0",
            "isort>=5.0.0",
            "mypy>=1.0.0",
            "flake8>=5.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-benchmark>=4.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "zmin=zmin.cli:main",
            "pyzmin=zmin.cli:main",
        ],
    },
    zip_safe=False,
    platforms=["any"],
)