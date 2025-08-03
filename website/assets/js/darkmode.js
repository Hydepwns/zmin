// Dark mode toggle functionality
(function() {
    'use strict';
    
    // Theme constants
    const THEME_KEY = 'zmin-theme';
    const DARK_THEME = 'dark';
    const LIGHT_THEME = 'light';
    
    // Get stored theme or default to dark (since site is already dark)
    function getStoredTheme() {
        try {
            return localStorage.getItem(THEME_KEY) || DARK_THEME;
        } catch (e) {
            return DARK_THEME;
        }
    }
    
    // Store theme preference
    function storeTheme(theme) {
        try {
            localStorage.setItem(THEME_KEY, theme);
        } catch (e) {
            console.warn('Could not store theme preference:', e);
        }
    }
    
    // Apply theme to document
    function applyTheme(theme) {
        const html = document.documentElement;
        const body = document.body;
        
        if (theme === DARK_THEME) {
            html.setAttribute('data-theme', 'dark');
            body.classList.add('dark-theme');
            body.classList.remove('light-theme');
        } else {
            html.setAttribute('data-theme', 'light');
            body.classList.add('light-theme');
            body.classList.remove('dark-theme');
        }
        
        // Update toggle button if it exists
        updateToggleButton(theme);
    }
    
    // Update the toggle button appearance
    function updateToggleButton(theme) {
        const toggleButton = document.querySelector('.theme-toggle');
        if (!toggleButton) return;
        
        const isDark = theme === DARK_THEME;
        const icon = toggleButton.querySelector('.theme-icon');
        const text = toggleButton.querySelector('.theme-text');
        
        if (icon) {
            icon.innerHTML = isDark ? 
                // Sun icon for switching to light mode
                `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <circle cx="12" cy="12" r="5"></circle>
                    <line x1="12" y1="1" x2="12" y2="3"></line>
                    <line x1="12" y1="21" x2="12" y2="23"></line>
                    <line x1="4.22" y1="4.22" x2="5.64" y2="5.64"></line>
                    <line x1="18.36" y1="18.36" x2="19.78" y2="19.78"></line>
                    <line x1="1" y1="12" x2="3" y2="12"></line>
                    <line x1="21" y1="12" x2="23" y2="12"></line>
                    <line x1="4.22" y1="19.78" x2="5.64" y2="18.36"></line>
                    <line x1="18.36" y1="5.64" x2="19.78" y2="4.22"></line>
                </svg>` :
                // Moon icon for switching to dark mode  
                `<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"></path>
                </svg>`;
        }
        
        if (text) {
            text.textContent = isDark ? 'Light' : 'Dark';
        }
        
        toggleButton.setAttribute('aria-label', isDark ? 'Switch to light mode' : 'Switch to dark mode');
        toggleButton.setAttribute('title', isDark ? 'Switch to light mode' : 'Switch to dark mode');
    }
    
    // Toggle theme
    function toggleTheme() {
        const currentTheme = getStoredTheme();
        const newTheme = currentTheme === DARK_THEME ? LIGHT_THEME : DARK_THEME;
        
        storeTheme(newTheme);
        applyTheme(newTheme);
        
        // Smooth transition effect
        document.body.style.transition = 'background-color 0.3s ease, color 0.3s ease';
        setTimeout(() => {
            document.body.style.transition = '';
        }, 300);
    }
    
    // Create theme toggle button
    function createToggleButton() {
        const toggleButton = document.createElement('button');
        toggleButton.className = 'theme-toggle';
        toggleButton.innerHTML = `
            <span class="theme-icon"></span>
            <span class="theme-text"></span>
        `;
        toggleButton.setAttribute('type', 'button');
        
        toggleButton.addEventListener('click', toggleTheme);
        
        // Add keyboard support
        toggleButton.addEventListener('keydown', function(e) {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                toggleTheme();
            }
        });
        
        return toggleButton;
    }
    
    // Initialize dark mode
    function init() {
        // Apply stored theme immediately to prevent flash
        const theme = getStoredTheme();
        applyTheme(theme);
        
        // Add toggle button when DOM is ready
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', addToggleButton);
        } else {
            addToggleButton();
        }
    }
    
    // Add toggle button to header
    function addToggleButton() {
        const header = document.querySelector('.header') || document.querySelector('header');
        if (!header) return;
        
        // Check if button already exists
        if (header.querySelector('.theme-toggle')) return;
        
        const toggleButton = createToggleButton();
        
        // Try to add to existing nav or create a nav section
        const nav = header.querySelector('nav') || header.querySelector('.header__right');
        if (nav) {
            nav.appendChild(toggleButton);
        } else {
            // Create a simple container for the toggle
            const toggleContainer = document.createElement('div');
            toggleContainer.className = 'header__toggle';
            toggleContainer.appendChild(toggleButton);
            header.appendChild(toggleContainer);
        }
        
        // Update button appearance
        updateToggleButton(getStoredTheme());
    }
    
    // Listen for system theme changes
    if (window.matchMedia) {
        const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
        mediaQuery.addEventListener('change', function() {
            // Only apply system preference if user hasn't explicitly set a theme
            if (!localStorage.getItem(THEME_KEY)) {
                const theme = mediaQuery.matches ? DARK_THEME : LIGHT_THEME;
                applyTheme(theme);
            }
        });
    }
    
    // Keyboard shortcut (Ctrl/Cmd + Shift + D)
    document.addEventListener('keydown', function(e) {
        if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key === 'D') {
            e.preventDefault();
            toggleTheme();
        }
    });
    
    // Initialize immediately
    init();
})();