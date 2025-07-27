#!/bin/bash

# Build Hugo documentation site
set -e

echo "Building zmin documentation..."

# Check if Hugo is installed
if ! command -v hugo &> /dev/null; then
    echo "Hugo not found. Installing..."

    # Install Hugo (adjust for your system)
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        echo "Installing Hugo on Linux..."
        wget https://github.com/gohugoio/hugo/releases/download/v0.120.4/hugo_extended_0.120.4_linux-amd64.deb
        sudo dpkg -i hugo_extended_0.120.4_linux-amd64.deb
        rm hugo_extended_0.120.4_linux-amd64.deb
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        echo "Installing Hugo on macOS..."
        brew install hugo
    else
        echo "Please install Hugo manually: https://gohugo.io/installation/"
        exit 1
    fi
fi

echo "Hugo version: $(hugo version)"

# Initialize Hugo modules if not already done
if [ ! -f "go.mod" ]; then
    echo "Initializing Hugo modules..."
    hugo mod init zmin-docs
fi

# Get the Terminal theme
echo "Getting Hugo Terminal theme..."
hugo mod get github.com/panr/hugo-theme-terminal

# Build the site
echo "Building site..."
hugo --minify

echo "Documentation built successfully!"
echo "Site available at: ./public/"
echo "To serve locally: hugo server"
echo "To view the site: open ./public/index.html"
