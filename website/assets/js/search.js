// Documentation search implementation using Lunr.js
(function() {
    'use strict';
    
    let searchIndex = null;
    let searchData = null;
    let searchInput = null;
    let searchResults = null;
    let searchOverlay = null;
    
    // Initialize search when DOM is ready
    document.addEventListener('DOMContentLoaded', function() {
        initializeSearch();
        setupKeyboardShortcuts();
    });
    
    function initializeSearch() {
        // Create search UI elements
        createSearchUI();
        
        // Load search index
        fetch('/search-index.json')
            .then(response => response.json())
            .then(data => {
                searchData = data;
                searchIndex = lunr(function() {
                    this.ref('url');
                    this.field('title', { boost: 10 });
                    this.field('content');
                    this.field('excerpt', { boost: 5 });
                    
                    data.forEach(function(doc) {
                        this.add(doc);
                    }, this);
                });
            })
            .catch(err => console.error('Failed to load search index:', err));
    }
    
    function createSearchUI() {
        // Create search overlay
        searchOverlay = document.createElement('div');
        searchOverlay.className = 'search-overlay';
        searchOverlay.innerHTML = `
            <div class="search-modal">
                <div class="search-header">
                    <input type="text" class="search-input" placeholder="Search documentation..." autocomplete="off">
                    <button class="search-close" aria-label="Close search">
                        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <line x1="18" y1="6" x2="6" y2="18"></line>
                            <line x1="6" y1="6" x2="18" y2="18"></line>
                        </svg>
                    </button>
                </div>
                <div class="search-results"></div>
                <div class="search-footer">
                    <span class="search-hint">Press <kbd>/</kbd> to search, <kbd>Esc</kbd> to close</span>
                </div>
            </div>
        `;
        
        document.body.appendChild(searchOverlay);
        
        // Get references to elements
        searchInput = searchOverlay.querySelector('.search-input');
        searchResults = searchOverlay.querySelector('.search-results');
        
        // Setup event listeners
        searchOverlay.querySelector('.search-close').addEventListener('click', closeSearch);
        searchOverlay.addEventListener('click', function(e) {
            if (e.target === searchOverlay) {
                closeSearch();
            }
        });
        
        searchInput.addEventListener('input', debounce(performSearch, 300));
        searchInput.addEventListener('keydown', handleSearchKeydown);
    }
    
    function setupKeyboardShortcuts() {
        document.addEventListener('keydown', function(e) {
            // Press '/' to open search
            if (e.key === '/' && !isInputElement(e.target)) {
                e.preventDefault();
                openSearch();
            }
            
            // Press 'Esc' to close search
            if (e.key === 'Escape' && searchOverlay.classList.contains('active')) {
                closeSearch();
            }
        });
    }
    
    function openSearch() {
        searchOverlay.classList.add('active');
        searchInput.focus();
        document.body.style.overflow = 'hidden';
    }
    
    function closeSearch() {
        searchOverlay.classList.remove('active');
        searchInput.value = '';
        searchResults.innerHTML = '';
        document.body.style.overflow = '';
    }
    
    function performSearch() {
        const query = searchInput.value.trim();
        
        if (!query) {
            searchResults.innerHTML = '';
            return;
        }
        
        if (!searchIndex || !searchData) {
            searchResults.innerHTML = '<div class="search-message">Loading search index...</div>';
            return;
        }
        
        try {
            const results = searchIndex.search(query);
            displayResults(results, query);
        } catch (e) {
            console.error('Search error:', e);
            searchResults.innerHTML = '<div class="search-message">Search error occurred</div>';
        }
    }
    
    function displayResults(results, query) {
        if (results.length === 0) {
            searchResults.innerHTML = `<div class="search-message">No results found for "${escapeHtml(query)}"</div>`;
            return;
        }
        
        const html = results.map((result, index) => {
            const doc = searchData.find(d => d.url === result.ref);
            if (!doc) return '';
            
            const highlightedTitle = highlightText(doc.title, query);
            const highlightedExcerpt = highlightText(doc.excerpt || '', query);
            const typeLabel = getTypeLabel(doc.type);
            
            return `
                <a href="${doc.url}" class="search-result" data-index="${index}">
                    <div class="search-result-header">
                        <h3 class="search-result-title">${highlightedTitle}</h3>
                        ${typeLabel ? `<span class="search-result-type">${typeLabel}</span>` : ''}
                    </div>
                    ${highlightedExcerpt ? `<p class="search-result-excerpt">${highlightedExcerpt}</p>` : ''}
                    <span class="search-result-url">${doc.url}</span>
                </a>
            `;
        }).join('');
        
        searchResults.innerHTML = html;
        
        // Focus first result
        const firstResult = searchResults.querySelector('.search-result');
        if (firstResult) {
            firstResult.classList.add('active');
        }
    }
    
    function handleSearchKeydown(e) {
        const results = searchResults.querySelectorAll('.search-result');
        const activeResult = searchResults.querySelector('.search-result.active');
        
        if (results.length === 0) return;
        
        let currentIndex = -1;
        if (activeResult) {
            currentIndex = parseInt(activeResult.dataset.index);
        }
        
        switch (e.key) {
            case 'ArrowDown':
                e.preventDefault();
                navigateResults(results, currentIndex, 1);
                break;
            case 'ArrowUp':
                e.preventDefault();
                navigateResults(results, currentIndex, -1);
                break;
            case 'Enter':
                e.preventDefault();
                if (activeResult) {
                    window.location.href = activeResult.href;
                }
                break;
        }
    }
    
    function navigateResults(results, currentIndex, direction) {
        results.forEach(r => r.classList.remove('active'));
        
        let newIndex = currentIndex + direction;
        if (newIndex < 0) newIndex = results.length - 1;
        if (newIndex >= results.length) newIndex = 0;
        
        results[newIndex].classList.add('active');
        results[newIndex].scrollIntoView({ block: 'nearest' });
    }
    
    function highlightText(text, query) {
        if (!text || !query) return text;
        
        const regex = new RegExp(`(${escapeRegex(query)})`, 'gi');
        return text.replace(regex, '<mark>$1</mark>');
    }
    
    function getTypeLabel(type) {
        const labels = {
            'docs': 'Documentation',
            'api': 'API Reference',
            'examples': 'Example',
            'guide': 'Guide'
        };
        return labels[type] || '';
    }
    
    function isInputElement(element) {
        return element.tagName === 'INPUT' || 
               element.tagName === 'TEXTAREA' || 
               element.tagName === 'SELECT' ||
               element.isContentEditable;
    }
    
    function debounce(func, wait) {
        let timeout;
        return function executedFunction(...args) {
            const later = () => {
                clearTimeout(timeout);
                func(...args);
            };
            clearTimeout(timeout);
            timeout = setTimeout(later, wait);
        };
    }
    
    function escapeHtml(text) {
        const map = {
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#039;'
        };
        return text.replace(/[&<>"']/g, m => map[m]);
    }
    
    function escapeRegex(text) {
        return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    }
})();