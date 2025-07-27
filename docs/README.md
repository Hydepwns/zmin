# zmin Documentation

This directory contains the source documentation for zmin, built with Hugo and the Terminal theme.

## Structure

- `content/` - Hugo content files (markdown with front matter)
- `assets/css/custom.css` - Custom CSS styling
- `assets/static/` - Static assets (favicon, og-image)
- `layouts/` - Custom Hugo layouts
- `config.yaml` - Hugo configuration
- `public/` - Built site (generated)

## Building the Site

### Prerequisites

- Hugo (Extended version)
- Go (for Hugo modules)

### On NixOS

```bash
# Build the site
nix-shell -p hugo go --run "hugo --minify"

# Serve locally for development
nix-shell -p hugo go --run "hugo server --bind 0.0.0.0 --port 1313"
```

### On Other Systems

```bash
# Install Hugo (if not already installed)
# macOS: brew install hugo
# Linux: Download from https://gohugo.io/installation/

# Build the site
hugo --minify

# Serve locally
hugo server --bind 0.0.0.0 --port 1313
```

## Development

### Adding New Content

1. Create a new markdown file in `content/docs/`
2. Add Hugo front matter:

```markdown
---
title: "Your Title"
date: 2024-01-01
draft: false
weight: 5
---

# Your Title

Your content here...
```

### Customizing the Theme

- Edit `assets/css/custom.css` for custom styling
- Modify `config.yaml` for site configuration
- Update `assets/partials/head.html` for custom head content

### Assets

- `assets/static/favicon.png` - Site favicon
- `assets/static/og-image.png` - Open Graph image
- `assets/css/custom.css` - Custom CSS

## Deployment

The site is automatically deployed to GitHub Pages via GitHub Actions when changes are pushed to the main branch.

### Manual Deployment

```bash
# Build the site
hugo --minify

# Deploy to your hosting service
# The built site is in the `public/` directory
```

## Theme Features

- **Dark mode by default** - Perfect for technical documentation
- **Responsive design** - Works on all devices
- **Syntax highlighting** - For code examples
- **Search functionality** - Built-in search
- **Clean typography** - Monospace fonts for technical content
- **Fast loading** - Optimized for performance

## Customization

### Colors

The theme uses a black and white color scheme:

- Background: `#000000` (black)
- Text: `#ffffff` (white)
- Accent: `#77767b` (gray)
- Borders: `#333333` (dark gray)

### Fonts

- Primary: Monospace fonts (SF Mono, Monaco, etc.)
- Code: Same monospace stack

## Troubleshooting

### Common Issues

1. **Theme not found**: Run `hugo mod tidy` to update modules
2. **Build errors**: Check Hugo version (requires Extended version)
3. **Missing assets**: Ensure files are in the correct directories

### Getting Help

- [Hugo Documentation](https://gohugo.io/documentation/)
- [Terminal Theme](https://github.com/panr/hugo-theme-terminal)
- [GitHub Issues](https://github.com/hydepwns/zmin/issues)
