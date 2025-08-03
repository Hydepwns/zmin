// Keyboard shortcuts for better navigation
document.addEventListener('DOMContentLoaded', function() {
    'use strict';
    
    // Keyboard shortcut mappings
    const shortcuts = {
        '/': openSearch,
        '?': showHelp,
        'h': goHome,
        'd': toggleDarkMode,
        'g': {
            'h': goHome,
            'd': goDocs,
            'a': goAPI,
            'g': goGitHub
        }
    };
    
    let helpModalOpen = false;
    let sequenceMode = false;
    let currentSequence = '';
    
    // Search functionality
    function openSearch() {
        // Look for existing search input or create a simple one
        let searchInput = document.querySelector('#search-input') || 
                         document.querySelector('[type="search"]') ||
                         document.querySelector('input[placeholder*="search" i]');
        
        if (!searchInput) {
            // Create a simple search overlay if none exists
            createSearchOverlay();
        } else {
            searchInput.focus();
            searchInput.select();
        }
    }
    
    // Create simple search overlay
    function createSearchOverlay() {
        const overlay = document.createElement('div');
        overlay.className = 'search-overlay';
        overlay.innerHTML = `
            <div class="search-container">
                <input type="search" 
                       placeholder="Search documentation... (Press Escape to close)" 
                       class="search-input"
                       autocomplete="off">
                <div class="search-results"></div>
                <div class="search-footer">
                    <span>Press <kbd>↑</kbd><kbd>↓</kbd> to navigate, <kbd>Enter</kbd> to select, <kbd>Esc</kbd> to close</span>
                </div>
            </div>
        `;
        
        document.body.appendChild(overlay);
        
        const searchInput = overlay.querySelector('.search-input');
        const resultsContainer = overlay.querySelector('.search-results');
        
        // Focus the input
        setTimeout(() => searchInput.focus(), 100);
        
        // Close overlay handlers
        function closeOverlay() {
            document.body.removeChild(overlay);
        }
        
        // Escape key handler
        searchInput.addEventListener('keydown', function(e) {
            if (e.key === 'Escape') {
                closeOverlay();
            }
        });
        
        // Click outside to close
        overlay.addEventListener('click', function(e) {
            if (e.target === overlay) {
                closeOverlay();
            }
        });
        
        // Simple search implementation
        searchInput.addEventListener('input', function(e) {
            const query = e.target.value.toLowerCase().trim();
            
            if (query.length < 2) {
                resultsContainer.innerHTML = '';
                return;
            }
            
            // Search through page content
            const results = performSimpleSearch(query);
            displaySearchResults(results, resultsContainer, closeOverlay);
        });
    }
    
    // Simple search function
    function performSimpleSearch(query) {
        const results = [];
        
        // Search through headings
        const headings = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
        headings.forEach(heading => {
            if (heading.textContent.toLowerCase().includes(query)) {
                results.push({
                    type: 'heading',
                    title: heading.textContent,
                    element: heading,
                    url: '#' + (heading.id || '')
                });
            }
        });
        
        // Search through links
        const links = document.querySelectorAll('a[href]');
        links.forEach(link => {
            if (link.textContent.toLowerCase().includes(query)) {
                results.push({
                    type: 'link',
                    title: link.textContent,
                    url: link.href,
                    element: link
                });
            }
        });
        
        return results.slice(0, 10); // Limit to 10 results
    }
    
    // Display search results
    function displaySearchResults(results, container, closeCallback) {
        if (results.length === 0) {
            container.innerHTML = '<div class="search-no-results">No results found</div>';
            return;
        }
        
        const resultsList = document.createElement('div');
        resultsList.className = 'search-results-list';
        
        results.forEach((result, index) => {
            const resultItem = document.createElement('div');
            resultItem.className = 'search-result-item';
            resultItem.innerHTML = `
                <div class="search-result-title">${escapeHtml(result.title)}</div>
                <div class="search-result-type">${result.type}</div>
            `;
            
            resultItem.addEventListener('click', function() {
                if (result.url.startsWith('#') && result.element) {
                    result.element.scrollIntoView({ behavior: 'smooth' });
                } else {
                    window.location.href = result.url;
                }
                closeCallback();
            });
            
            resultsList.appendChild(resultItem);
        });
        
        container.innerHTML = '';
        container.appendChild(resultsList);
    }
    
    // Navigation functions
    function goHome() {
        window.location.href = '/';
    }
    
    function goDocs() {
        window.location.href = '/docs/';
    }
    
    function goAPI() {
        window.location.href = '/api-reference/';
    }
    
    function goGitHub() {
        window.open('https://github.com/hydepwns/zmin', '_blank');
    }
    
    function toggleDarkMode() {
        const toggleButton = document.querySelector('.theme-toggle');
        if (toggleButton) {
            toggleButton.click();
        }
    }
    
    // Show help modal
    function showHelp() {
        if (helpModalOpen) return;
        
        const helpModal = document.createElement('div');
        helpModal.className = 'help-modal-overlay';
        helpModal.innerHTML = `
            <div class="help-modal">
                <div class="help-header">
                    <h3>Keyboard Shortcuts</h3>
                    <button class="help-close" aria-label="Close help">&times;</button>
                </div>
                <div class="help-content">
                    <div class="help-section">
                        <h4>Navigation</h4>
                        <div class="help-shortcut">
                            <kbd>/</kbd> <span>Open search</span>
                        </div>
                        <div class="help-shortcut">
                            <kbd>h</kbd> <span>Go to homepage</span>
                        </div>
                        <div class="help-shortcut">
                            <kbd>d</kbd> <span>Toggle dark mode</span>
                        </div>
                        <div class="help-shortcut">
                            <kbd>?</kbd> <span>Show this help</span>
                        </div>
                    </div>
                    <div class="help-section">
                        <h4>Go to sections (press g then...)</h4>
                        <div class="help-shortcut">
                            <kbd>g</kbd> <kbd>h</kbd> <span>Homepage</span>
                        </div>
                        <div class="help-shortcut">
                            <kbd>g</kbd> <kbd>d</kbd> <span>Documentation</span>
                        </div>
                        <div class="help-shortcut">
                            <kbd>g</kbd> <kbd>a</kbd> <span>API Reference</span>
                        </div>
                        <div class="help-shortcut">
                            <kbd>g</kbd> <kbd>g</kbd> <span>GitHub (new tab)</span>
                        </div>
                    </div>
                    <div class="help-section">
                        <h4>Code blocks</h4>
                        <div class="help-shortcut">
                            <kbd>Ctrl/Cmd</kbd> <kbd>C</kbd> <span>Copy code (when focused)</span>
                        </div>
                        <div class="help-shortcut">
                            <kbd>Ctrl/Cmd</kbd> <kbd>Shift</kbd> <kbd>D</kbd> <span>Toggle dark mode</span>
                        </div>
                    </div>
                </div>
            </div>
        `;
        
        document.body.appendChild(helpModal);
        helpModalOpen = true;
        
        // Close handlers
        function closeHelp() {
            if (helpModalOpen) {
                document.body.removeChild(helpModal);
                helpModalOpen = false;
            }
        }
        
        helpModal.querySelector('.help-close').addEventListener('click', closeHelp);
        helpModal.addEventListener('click', function(e) {
            if (e.target === helpModal) closeHelp();
        });
        
        // Close on escape
        function handleEscape(e) {
            if (e.key === 'Escape') {
                closeHelp();
                document.removeEventListener('keydown', handleEscape);
            }
        }
        document.addEventListener('keydown', handleEscape);
    }
    
    // Main keyboard event handler
    document.addEventListener('keydown', function(e) {
        // Ignore if user is typing in an input field
        if (e.target.matches('input, textarea, select, [contenteditable]')) {
            return;
        }
        
        // Ignore if modifier keys are pressed (except for specific combos)
        if (e.ctrlKey || e.metaKey || e.altKey) {
            return;
        }
        
        const key = e.key.toLowerCase();
        
        // Handle sequence mode (like "g h" for go home)
        if (sequenceMode) {
            e.preventDefault();
            
            const sequenceShortcut = shortcuts[currentSequence];
            if (sequenceShortcut && typeof sequenceShortcut === 'object' && sequenceShortcut[key]) {
                sequenceShortcut[key]();
            }
            
            // Reset sequence mode
            sequenceMode = false;
            currentSequence = '';
            return;
        }
        
        // Handle single key shortcuts
        if (shortcuts[key]) {
            e.preventDefault();
            
            if (typeof shortcuts[key] === 'function') {
                shortcuts[key]();
            } else if (typeof shortcuts[key] === 'object') {
                // Enter sequence mode
                sequenceMode = true;
                currentSequence = key;
                
                // Reset sequence mode after 2 seconds if no key is pressed
                setTimeout(() => {
                    sequenceMode = false;
                    currentSequence = '';
                }, 2000);
            }
        }
    });
    
    // Utility function to escape HTML
    function escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
});