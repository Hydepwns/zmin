#!/bin/bash

# Cleanup script to remove duplicated documentation
set -e

echo "🧹 Cleaning up duplicated documentation..."

# Create backup directory
BACKUP_DIR="docs/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "📦 Creating backup in $BACKUP_DIR"

# Move duplicated markdown files to backup
echo "📄 Moving duplicated markdown files to backup..."
for file in docs/*.md; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        if [ "$filename" != "README.md" ]; then
            echo "  Moving $filename to backup"
            mv "$file" "$BACKUP_DIR/"
        fi
    fi
done

# Move old HTML files to backup
echo "🌐 Moving old HTML files to backup..."
for file in docs/*.html; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        echo "  Moving $filename to backup"
        mv "$file" "$BACKUP_DIR/"
    fi
done

# Move old CSS to backup
echo "🎨 Moving old CSS to backup..."
if [ -f "docs/terminal.css" ]; then
    echo "  Moving terminal.css to backup"
    mv "docs/terminal.css" "$BACKUP_DIR/"
fi

# Keep important files in docs directory
echo "✅ Keeping important files in docs directory..."

# Keep the README.md (updated with Hugo instructions)
echo "  Keeping docs/README.md (updated with Hugo instructions)"

# Keep API reference files (they might be useful)
echo "  Keeping API reference files..."
if [ -f "$BACKUP_DIR/api-reference.json" ]; then
    mv "$BACKUP_DIR/api-reference.json" "docs/"
fi
if [ -f "$BACKUP_DIR/api-reference.yaml" ]; then
    mv "$BACKUP_DIR/api-reference.yaml" "docs/"
fi

# Keep CNAME for GitHub Pages
echo "  Keeping CNAME for GitHub Pages..."
if [ -f "$BACKUP_DIR/CNAME" ]; then
    mv "$BACKUP_DIR/CNAME" "docs/"
fi

# Keep PUBLISHING.md if it contains useful deployment info
echo "  Keeping PUBLISHING.md..."
if [ -f "$BACKUP_DIR/PUBLISHING.md" ]; then
    mv "$BACKUP_DIR/PUBLISHING.md" "docs/"
fi

# Create a summary of what was cleaned up
echo "📋 Creating cleanup summary..."
cat > "docs/CLEANUP_SUMMARY.md" << EOF
# Documentation Cleanup Summary

This directory was cleaned up on $(date).

## What was moved to backup ($BACKUP_DIR):

### Markdown Files (now in Hugo content/)
- getting-started.md
- installation.md
- usage.md
- performance.md
- troubleshooting.md
- plugins.md
- integrations.md
- gpu.md
- comparisons.md
- STYLE_GUIDE.md
- mode-selection.md

### HTML Files (replaced by Hugo)
- index.html
- api-reference.html
- api-docs-interactive.html
- mode-selector.html

### CSS Files (integrated into Hugo theme)
- terminal.css

## What was kept:

- README.md - Updated with Hugo instructions
- api-reference.json - API specification
- api-reference.yaml - API specification
- CNAME - GitHub Pages configuration
- PUBLISHING.md - Deployment instructions
- og-image.png - Site image
- favicon.png - Site favicon

## New Hugo Structure:

- \`content/\` - Hugo content files
- \`assets/css/custom.css\` - Custom styling
- \`assets/static/\` - Static assets
- \`layouts/\` - Custom layouts
- \`public/\` - Built site

## To restore from backup:

\`\`\`bash
# Restore specific files
cp "$BACKUP_DIR/filename.md" docs/

# Restore everything
cp -r "$BACKUP_DIR"/* docs/
\`\`\`
EOF

echo "✅ Cleanup completed!"
echo ""
echo "📊 Summary:"
echo "  - Moved $(ls "$BACKUP_DIR"/*.md 2>/dev/null | wc -l) markdown files to backup"
echo "  - Moved $(ls "$BACKUP_DIR"/*.html 2>/dev/null | wc -l) HTML files to backup"
echo "  - Kept important configuration files"
echo "  - Created cleanup summary in docs/CLEANUP_SUMMARY.md"
echo ""
echo "🔄 Next steps:"
echo "  1. Review the backup in $BACKUP_DIR"
echo "  2. Test the Hugo site: ./scripts/serve-docs.sh"
echo "  3. Delete backup when satisfied: rm -rf $BACKUP_DIR"
