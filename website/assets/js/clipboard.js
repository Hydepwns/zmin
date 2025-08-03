// Copy to clipboard functionality for code blocks
document.addEventListener('DOMContentLoaded', function() {
    // Add copy buttons to all code blocks
    const codeBlocks = document.querySelectorAll('pre code, .highlight pre');
    
    codeBlocks.forEach(function(codeBlock) {
        const pre = codeBlock.closest('pre');
        if (!pre) return;
        
        // Create copy button
        const copyButton = document.createElement('button');
        copyButton.className = 'copy-button';
        copyButton.innerHTML = `
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect>
                <path d="m5 15-2-2 2-2"></path>
                <path d="M9 3h6a2 2 0 0 1 2 2v6"></path>
            </svg>
            <span class="copy-text">Copy</span>
        `;
        copyButton.setAttribute('aria-label', 'Copy code to clipboard');
        copyButton.setAttribute('title', 'Copy code to clipboard');
        
        // Style the pre element to be relative for positioning
        pre.style.position = 'relative';
        
        // Add copy button to pre element
        pre.appendChild(copyButton);
        
        // Add click event
        copyButton.addEventListener('click', async function() {
            try {
                // Get the text content, preserving formatting
                const code = codeBlock.textContent || codeBlock.innerText;
                
                // Use the modern clipboard API if available
                if (navigator.clipboard && window.isSecureContext) {
                    await navigator.clipboard.writeText(code);
                } else {
                    // Fallback for older browsers
                    fallbackCopyTextToClipboard(code);
                }
                
                // Show success feedback
                const originalContent = copyButton.innerHTML;
                copyButton.innerHTML = `
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <polyline points="20,6 9,17 4,12"></polyline>
                    </svg>
                    <span class="copy-text">Copied!</span>
                `;
                copyButton.classList.add('copied');
                
                // Reset after 2 seconds
                setTimeout(() => {
                    copyButton.innerHTML = originalContent;
                    copyButton.classList.remove('copied');
                }, 2000);
                
            } catch (err) {
                console.error('Failed to copy text: ', err);
                
                // Show error feedback
                const originalContent = copyButton.innerHTML;
                copyButton.innerHTML = `
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                        <circle cx="12" cy="12" r="10"></circle>
                        <line x1="15" y1="9" x2="9" y2="15"></line>
                        <line x1="9" y1="9" x2="15" y2="15"></line>
                    </svg>
                    <span class="copy-text">Failed</span>
                `;
                copyButton.classList.add('error');
                
                setTimeout(() => {
                    copyButton.innerHTML = originalContent;
                    copyButton.classList.remove('error');
                }, 2000);
            }
        });
    });
});

// Fallback function for older browsers
function fallbackCopyTextToClipboard(text) {
    const textArea = document.createElement('textarea');
    textArea.value = text;
    
    // Avoid scrolling to bottom
    textArea.style.top = '0';
    textArea.style.left = '0';
    textArea.style.position = 'fixed';
    textArea.style.opacity = '0';
    
    document.body.appendChild(textArea);
    textArea.focus();
    textArea.select();
    
    try {
        document.execCommand('copy');
    } catch (err) {
        console.error('Fallback: Could not copy text: ', err);
        throw err;
    }
    
    document.body.removeChild(textArea);
}

// Keyboard shortcut for copying (Ctrl+C or Cmd+C when code block is focused)
document.addEventListener('keydown', function(e) {
    if ((e.ctrlKey || e.metaKey) && e.key === 'c') {
        const activeElement = document.activeElement;
        if (activeElement && activeElement.closest('pre')) {
            const codeBlock = activeElement.closest('pre').querySelector('code');
            if (codeBlock) {
                const copyButton = activeElement.closest('pre').querySelector('.copy-button');
                if (copyButton) {
                    e.preventDefault();
                    copyButton.click();
                }
            }
        }
    }
});