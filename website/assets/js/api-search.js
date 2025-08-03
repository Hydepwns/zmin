// API-specific search functionality
(function() {
    'use strict';
    
    let apiData = null;
    let apiSearchIndex = null;
    let apiSearchInput = null;
    let apiResults = null;
    
    // Initialize API search when DOM is ready
    document.addEventListener('DOMContentLoaded', function() {
        // Only initialize on API reference page
        if (document.querySelector('.api-reference')) {
            initializeAPISearch();
        }
    });
    
    function initializeAPISearch() {
        // Create API search UI
        createAPISearchUI();
        
        // Load API data
        fetch('/api/api-reference.json')
            .then(response => response.json())
            .then(data => {
                apiData = data;
                buildAPIIndex(data);
            })
            .catch(err => console.error('Failed to load API data:', err));
    }
    
    function createAPISearchUI() {
        const apiContainer = document.querySelector('.api-reference');
        if (!apiContainer) return;
        
        // Insert search box at the top
        const searchBox = document.createElement('div');
        searchBox.className = 'api-search-box';
        searchBox.innerHTML = `
            <div class="api-search-wrapper">
                <input type="text" class="api-search-input" placeholder="Search functions, types, parameters..." autocomplete="off">
                <div class="api-search-filters">
                    <label class="api-filter">
                        <input type="checkbox" name="functions" checked> Functions
                    </label>
                    <label class="api-filter">
                        <input type="checkbox" name="types" checked> Types
                    </label>
                    <label class="api-filter">
                        <input type="checkbox" name="params" checked> Parameters
                    </label>
                </div>
            </div>
            <div class="api-search-results"></div>
        `;
        
        // Insert before first child
        apiContainer.insertBefore(searchBox, apiContainer.firstChild);
        
        // Get references
        apiSearchInput = searchBox.querySelector('.api-search-input');
        apiResults = searchBox.querySelector('.api-search-results');
        
        // Setup event listeners
        apiSearchInput.addEventListener('input', debounce(performAPISearch, 300));
        
        // Filter checkboxes
        const filters = searchBox.querySelectorAll('.api-filter input');
        filters.forEach(filter => {
            filter.addEventListener('change', performAPISearch);
        });
    }
    
    function buildAPIIndex(data) {
        apiSearchIndex = lunr(function() {
            this.ref('id');
            this.field('name', { boost: 10 });
            this.field('summary', { boost: 5 });
            this.field('description');
            this.field('params');
            this.field('returns');
            this.field('tags');
            
            let docId = 0;
            
            // Index all API endpoints
            if (data.paths) {
                Object.entries(data.paths).forEach(([path, methods]) => {
                    Object.entries(methods).forEach(([method, operation]) => {
                        const doc = {
                            id: docId++,
                            type: 'function',
                            name: operation.operationId || path,
                            summary: operation.summary || '',
                            description: operation.description || '',
                            params: extractParams(operation),
                            returns: extractReturns(operation),
                            tags: (operation.tags || []).join(' '),
                            path: path,
                            method: method.toUpperCase(),
                            operation: operation
                        };
                        
                        this.add(doc);
                        
                        // Store in apiData for retrieval
                        if (!apiData._indexed) apiData._indexed = [];
                        apiData._indexed[docId - 1] = doc;
                    });
                });
            }
            
            // Index components/schemas (types)
            if (data.components && data.components.schemas) {
                Object.entries(data.components.schemas).forEach(([name, schema]) => {
                    const doc = {
                        id: docId++,
                        type: 'type',
                        name: name,
                        summary: schema.description || '',
                        description: extractSchemaDescription(schema),
                        params: extractProperties(schema),
                        returns: '',
                        tags: 'type schema',
                        schema: schema
                    };
                    
                    this.add(doc);
                    
                    if (!apiData._indexed) apiData._indexed = [];
                    apiData._indexed[docId - 1] = doc;
                });
            }
        });
    }
    
    function performAPISearch() {
        const query = apiSearchInput.value.trim();
        
        if (!query) {
            apiResults.innerHTML = '';
            apiResults.style.display = 'none';
            return;
        }
        
        if (!apiSearchIndex || !apiData) {
            apiResults.innerHTML = '<div class="api-search-message">Loading API data...</div>';
            apiResults.style.display = 'block';
            return;
        }
        
        // Get active filters
        const filters = {
            functions: document.querySelector('input[name="functions"]').checked,
            types: document.querySelector('input[name="types"]').checked,
            params: document.querySelector('input[name="params"]').checked
        };
        
        try {
            const results = apiSearchIndex.search(query);
            const filteredResults = filterResults(results, filters);
            displayAPIResults(filteredResults, query);
        } catch (e) {
            console.error('API search error:', e);
            apiResults.innerHTML = '<div class="api-search-message">Search error occurred</div>';
            apiResults.style.display = 'block';
        }
    }
    
    function filterResults(results, filters) {
        return results.filter(result => {
            const doc = apiData._indexed[result.ref];
            if (!doc) return false;
            
            if (doc.type === 'function' && !filters.functions) return false;
            if (doc.type === 'type' && !filters.types) return false;
            
            return true;
        });
    }
    
    function displayAPIResults(results, query) {
        if (results.length === 0) {
            apiResults.innerHTML = `<div class="api-search-message">No results found for "${escapeHtml(query)}"</div>`;
            apiResults.style.display = 'block';
            return;
        }
        
        const html = results.slice(0, 10).map(result => {
            const doc = apiData._indexed[result.ref];
            if (!doc) return '';
            
            return createResultHTML(doc, query);
        }).join('');
        
        apiResults.innerHTML = html;
        apiResults.style.display = 'block';
    }
    
    function createResultHTML(doc, query) {
        const highlightedName = highlightText(doc.name, query);
        const highlightedSummary = highlightText(doc.summary, query);
        
        if (doc.type === 'function') {
            const signature = createFunctionSignature(doc);
            return `
                <div class="api-result api-result-function">
                    <div class="api-result-header">
                        <h4 class="api-result-name">${highlightedName}</h4>
                        <span class="api-result-type">Function</span>
                    </div>
                    <code class="api-result-signature">${signature}</code>
                    ${highlightedSummary ? `<p class="api-result-summary">${highlightedSummary}</p>` : ''}
                    <a href="#${doc.name}" class="api-result-link">View details →</a>
                </div>
            `;
        } else if (doc.type === 'type') {
            const typeInfo = createTypeInfo(doc);
            return `
                <div class="api-result api-result-type">
                    <div class="api-result-header">
                        <h4 class="api-result-name">${highlightedName}</h4>
                        <span class="api-result-type">Type</span>
                    </div>
                    ${typeInfo}
                    ${highlightedSummary ? `<p class="api-result-summary">${highlightedSummary}</p>` : ''}
                    <a href="#type-${doc.name}" class="api-result-link">View details →</a>
                </div>
            `;
        }
        
        return '';
    }
    
    function createFunctionSignature(doc) {
        let params = '';
        if (doc.operation && doc.operation.parameters) {
            params = doc.operation.parameters
                .map(p => `${p.name}: ${getParamType(p)}`)
                .join(', ');
        }
        
        let returnType = 'void';
        if (doc.operation && doc.operation.responses && doc.operation.responses['200']) {
            const response = doc.operation.responses['200'];
            if (response.content && response.content['application/json']) {
                returnType = 'JSON';
            }
        }
        
        return `${doc.name}(${params}) → ${returnType}`;
    }
    
    function createTypeInfo(doc) {
        if (!doc.schema) return '';
        
        if (doc.schema.type === 'object' && doc.schema.properties) {
            const propCount = Object.keys(doc.schema.properties).length;
            return `<code class="api-result-signature">struct { ${propCount} properties }</code>`;
        } else if (doc.schema.enum) {
            return `<code class="api-result-signature">enum { ${doc.schema.enum.length} values }</code>`;
        } else if (doc.schema.type) {
            return `<code class="api-result-signature">${doc.schema.type}</code>`;
        }
        
        return '';
    }
    
    function extractParams(operation) {
        if (!operation.parameters) return '';
        return operation.parameters.map(p => p.name).join(' ');
    }
    
    function extractReturns(operation) {
        if (!operation.responses || !operation.responses['200']) return '';
        return operation.responses['200'].description || '';
    }
    
    function extractSchemaDescription(schema) {
        let desc = schema.description || '';
        if (schema.properties) {
            const props = Object.keys(schema.properties).join(', ');
            desc += ` Properties: ${props}`;
        }
        return desc;
    }
    
    function extractProperties(schema) {
        if (!schema.properties) return '';
        return Object.keys(schema.properties).join(' ');
    }
    
    function getParamType(param) {
        if (param.schema) {
            return param.schema.type || 'any';
        }
        return 'any';
    }
    
    function highlightText(text, query) {
        if (!text || !query) return text;
        
        const regex = new RegExp(`(${escapeRegex(query)})`, 'gi');
        return text.replace(regex, '<mark>$1</mark>');
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