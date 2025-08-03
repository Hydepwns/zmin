// Progressive disclosure for documentation sections
(function() {
    'use strict';
    
    const LEVELS = {
        beginner: { order: 1, label: 'Beginner', color: '#27ae60' },
        intermediate: { order: 2, label: 'Intermediate', color: '#f39c12' },
        advanced: { order: 3, label: 'Advanced', color: '#e74c3c' }
    };
    
    const STORAGE_KEY = 'zmin-doc-level';
    
    let currentLevel = 'beginner';
    
    // Initialize on DOM ready
    document.addEventListener('DOMContentLoaded', function() {
        initializeProgressiveDisclosure();
    });
    
    function initializeProgressiveDisclosure() {
        // Load saved level
        const savedLevel = localStorage.getItem(STORAGE_KEY);
        if (savedLevel && LEVELS[savedLevel]) {
            currentLevel = savedLevel;
        }
        
        // Create level selector
        createLevelSelector();
        
        // Apply initial level
        applyLevel(currentLevel);
        
        // Process content sections
        processContentSections();
    }
    
    function createLevelSelector() {
        // Check if we're on a documentation page
        const docContent = document.querySelector('.doc-content');
        if (!docContent) return;
        
        // Create level selector widget
        const selector = document.createElement('div');
        selector.className = 'level-selector';
        selector.innerHTML = `
            <div class="level-selector-header">
                <span class="level-selector-label">Content Level:</span>
                <div class="level-selector-buttons">
                    ${Object.entries(LEVELS).map(([key, config]) => `
                        <button class="level-button" data-level="${key}" style="--level-color: ${config.color}">
                            ${config.label}
                        </button>
                    `).join('')}
                </div>
            </div>
            <div class="level-indicator">
                <div class="level-indicator-bar">
                    <div class="level-indicator-fill"></div>
                </div>
                <p class="level-description"></p>
            </div>
        `;
        
        // Insert before doc content
        docContent.parentNode.insertBefore(selector, docContent);
        
        // Add event listeners
        selector.querySelectorAll('.level-button').forEach(button => {
            button.addEventListener('click', function() {
                const level = this.dataset.level;
                setLevel(level);
            });
        });
    }
    
    function setLevel(level) {
        if (!LEVELS[level]) return;
        
        currentLevel = level;
        localStorage.setItem(STORAGE_KEY, level);
        
        applyLevel(level);
        updateLevelIndicator(level);
    }
    
    function applyLevel(level) {
        const levelOrder = LEVELS[level].order;
        
        // Update active button
        document.querySelectorAll('.level-button').forEach(button => {
            const buttonLevel = button.dataset.level;
            button.classList.toggle('active', buttonLevel === level);
        });
        
        // Show/hide content based on level
        document.querySelectorAll('[data-level]').forEach(element => {
            const elementLevel = element.dataset.level;
            const elementOrder = LEVELS[elementLevel]?.order || 1;
            
            if (elementOrder <= levelOrder) {
                element.classList.remove('level-hidden');
                element.classList.add('level-visible');
            } else {
                element.classList.add('level-hidden');
                element.classList.remove('level-visible');
            }
        });
        
        // Update sections with mixed content
        updateMixedSections(levelOrder);
    }
    
    function updateLevelIndicator(level) {
        const indicator = document.querySelector('.level-indicator');
        if (!indicator) return;
        
        const config = LEVELS[level];
        const fill = indicator.querySelector('.level-indicator-fill');
        const description = indicator.querySelector('.level-description');
        
        // Update fill width and color
        const percentage = (config.order / Object.keys(LEVELS).length) * 100;
        fill.style.width = `${percentage}%`;
        fill.style.backgroundColor = config.color;
        
        // Update description
        const descriptions = {
            beginner: 'Showing essential concepts and basic usage. Perfect for getting started.',
            intermediate: 'Includes detailed explanations and common patterns. Recommended for regular users.',
            advanced: 'Full documentation with performance tips and edge cases. For power users.'
        };
        
        description.textContent = descriptions[level] || '';
    }
    
    function processContentSections() {
        // Auto-tag sections based on keywords
        const keywords = {
            beginner: ['basic', 'simple', 'getting started', 'introduction', 'overview'],
            intermediate: ['configuration', 'options', 'patterns', 'examples', 'usage'],
            advanced: ['performance', 'optimization', 'internals', 'architecture', 'edge cases', 'benchmarks']
        };
        
        // Process headings and their content
        document.querySelectorAll('.doc-content h2, .doc-content h3').forEach(heading => {
            const text = heading.textContent.toLowerCase();
            
            // Check if already has a level
            if (heading.dataset.level) return;
            
            // Auto-detect level based on keywords
            for (const [level, words] of Object.entries(keywords)) {
                if (words.some(word => text.includes(word))) {
                    tagSection(heading, level);
                    break;
                }
            }
        });
        
        // Process code blocks with complexity indicators
        document.querySelectorAll('.doc-content pre').forEach(pre => {
            const code = pre.textContent;
            const lines = code.split('\n').length;
            
            // Simple heuristic for code complexity
            if (lines > 50 || code.includes('async') || code.includes('parallel')) {
                pre.dataset.level = 'advanced';
            } else if (lines > 20) {
                pre.dataset.level = 'intermediate';
            }
        });
    }
    
    function tagSection(heading, level) {
        heading.dataset.level = level;
        
        // Add level badge
        const badge = document.createElement('span');
        badge.className = 'level-badge';
        badge.dataset.level = level;
        badge.style.backgroundColor = LEVELS[level].color;
        badge.textContent = LEVELS[level].label;
        heading.appendChild(badge);
        
        // Tag following content until next heading
        let sibling = heading.nextElementSibling;
        while (sibling && !sibling.matches('h1, h2, h3')) {
            if (!sibling.dataset.level) {
                sibling.dataset.level = level;
            }
            sibling = sibling.nextElementSibling;
        }
    }
    
    function updateMixedSections(maxOrder) {
        // Handle sections with mixed-level content
        document.querySelectorAll('.mixed-content').forEach(section => {
            let hasVisibleContent = false;
            
            section.querySelectorAll('[data-level]').forEach(element => {
                const elementOrder = LEVELS[element.dataset.level]?.order || 1;
                if (elementOrder <= maxOrder) {
                    hasVisibleContent = true;
                }
            });
            
            // Show/hide the entire section
            section.classList.toggle('has-visible-content', hasVisibleContent);
        });
    }
    
    // Add smooth transitions
    const style = document.createElement('style');
    style.textContent = `
        [data-level] {
            transition: opacity 0.3s, max-height 0.3s;
        }
        
        .level-hidden {
            opacity: 0;
            max-height: 0;
            overflow: hidden;
            margin: 0 !important;
            padding: 0 !important;
        }
        
        .level-visible {
            opacity: 1;
            max-height: none;
        }
        
        .mixed-content:not(.has-visible-content) {
            display: none;
        }
    `;
    document.head.appendChild(style);
})();