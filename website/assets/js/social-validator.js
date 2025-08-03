// Social Media Tags Validator
// This script helps validate that social media tags are properly set up

(function() {
    'use strict';
    
    // Only run in development mode or when explicitly requested
    if (!window.location.href.includes('validate-social=true')) {
        return;
    }
    
    console.group('Social Media Tags Validation');
    
    // Check Open Graph tags
    console.group('Open Graph Tags');
    const ogTags = [
        'og:title',
        'og:description',
        'og:image',
        'og:url',
        'og:type',
        'og:site_name',
        'og:locale',
        'og:image:width',
        'og:image:height'
    ];
    
    ogTags.forEach(tag => {
        const element = document.querySelector(`meta[property="${tag}"]`);
        if (element) {
            console.log(`✅ ${tag}: ${element.content}`);
        } else {
            console.warn(`❌ ${tag}: Missing`);
        }
    });
    console.groupEnd();
    
    // Check Twitter tags
    console.group('Twitter/X Tags');
    const twitterTags = [
        'twitter:card',
        'twitter:title',
        'twitter:description',
        'twitter:image',
        'twitter:site',
        'twitter:creator'
    ];
    
    twitterTags.forEach(tag => {
        const element = document.querySelector(`meta[name="${tag}"], meta[property="${tag}"]`);
        if (element) {
            console.log(`✅ ${tag}: ${element.content}`);
        } else {
            console.warn(`❌ ${tag}: Missing`);
        }
    });
    console.groupEnd();
    
    // Check image accessibility
    console.group('Image Validation');
    const ogImage = document.querySelector('meta[property="og:image"]');
    if (ogImage) {
        const img = new Image();
        img.onload = function() {
            console.log(`✅ Image loaded: ${this.width}x${this.height}`);
            if (this.width < 1200 || this.height < 630) {
                console.warn(`⚠️ Image dimensions should be at least 1200x630 for optimal display`);
            }
        };
        img.onerror = function() {
            console.error(`❌ Image failed to load: ${ogImage.content}`);
        };
        img.src = ogImage.content;
    }
    console.groupEnd();
    
    // Check structured data
    console.group('Structured Data');
    const ldJson = document.querySelector('script[type="application/ld+json"]');
    if (ldJson) {
        try {
            const data = JSON.parse(ldJson.textContent);
            console.log('✅ Valid JSON-LD:', data);
        } catch (e) {
            console.error('❌ Invalid JSON-LD:', e);
        }
    } else {
        console.warn('❌ No structured data found');
    }
    console.groupEnd();
    
    console.groupEnd();
    
    // Add preview button for testing
    if (document.querySelector('.doc-header')) {
        const previewButton = document.createElement('button');
        previewButton.textContent = 'Preview Social Card';
        previewButton.style.cssText = `
            position: fixed;
            bottom: 20px;
            right: 20px;
            padding: 10px 20px;
            background: #3498db;
            color: white;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            z-index: 9999;
        `;
        
        previewButton.onclick = function() {
            const url = encodeURIComponent(window.location.href);
            window.open(`https://www.opengraph.xyz/url/${url}`, '_blank');
        };
        
        document.body.appendChild(previewButton);
    }
})();