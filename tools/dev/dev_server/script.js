// zmin Development Server JavaScript

document.addEventListener('DOMContentLoaded', function() {
    // Tab functionality
    const tabButtons = document.querySelectorAll('.tab-button');
    const tabContents = document.querySelectorAll('.tab-content');

    tabButtons.forEach(button => {
        button.addEventListener('click', () => {
            const tabName = button.getAttribute('data-tab');

            // Remove active class from all buttons and contents
            tabButtons.forEach(btn => btn.classList.remove('active'));
            tabContents.forEach(content => content.classList.remove('active'));

            // Add active class to clicked button and corresponding content
            button.classList.add('active');
            document.getElementById(tabName + '-tab').classList.add('active');
        });
    });

    // Minify functionality
    const minifyBtn = document.getElementById('minify-btn');
    const inputCode = document.getElementById('input-code');
    const outputCode = document.getElementById('output-code');
    const originalSize = document.getElementById('original-size');
    const minifiedSize = document.getElementById('minified-size');
    const compressionRatio = document.getElementById('compression-ratio');

    minifyBtn.addEventListener('click', async () => {
        const code = inputCode.value;
        const mode = document.getElementById('mode').value;

        if (!code.trim()) {
            showMessage('Please enter some code to minify', 'error');
            return;
        }

        // Show loading state
        minifyBtn.disabled = true;
        minifyBtn.innerHTML = '<span class="loading"></span> Minifying...';

        try {
            const response = await fetch('/api/minify', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    input: code,
                    mode: mode
                })
            });

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            const result = await response.json();

            // Update output
            outputCode.textContent = result.output;
            originalSize.textContent = formatBytes(result.original_size);
            minifiedSize.textContent = formatBytes(result.minified_size);
            compressionRatio.textContent = `${((1 - result.compression_ratio) * 100).toFixed(1)}%`;

            showMessage('Code minified successfully!', 'success');

        } catch (error) {
            console.error('Error:', error);
            showMessage('Error minifying code: ' + error.message, 'error');
        } finally {
            // Reset button state
            minifyBtn.disabled = false;
            minifyBtn.textContent = 'Minify';
        }
    });

    // Benchmark functionality
    const benchmarkBtn = document.getElementById('benchmark-btn');
    const benchmarkInput = document.getElementById('benchmark-input');
    const benchmarkTable = document.getElementById('benchmark-table');

    benchmarkBtn.addEventListener('click', async () => {
        const code = benchmarkInput.value;

        if (!code.trim()) {
            showMessage('Please enter some code to benchmark', 'error');
            return;
        }

        // Show loading state
        benchmarkBtn.disabled = true;
        benchmarkBtn.innerHTML = '<span class="loading"></span> Benchmarking...';

        try {
            const response = await fetch('/api/benchmark', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    input: code
                })
            });

            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }

            const result = await response.json();

            // Create benchmark table
            let tableHTML = `
                <div class="benchmark-row">
                    <div>Mode</div>
                    <div>Time (ms)</div>
                    <div>Size (bytes)</div>
                </div>
            `;

            result.results.forEach(item => {
                tableHTML += `
                    <div class="benchmark-row">
                        <div>${item.mode}</div>
                        <div>${item.time_ms.toFixed(2)}</div>
                        <div>${formatBytes(item.size)}</div>
                    </div>
                `;
            });

            benchmarkTable.innerHTML = tableHTML;
            showMessage('Benchmark completed successfully!', 'success');

        } catch (error) {
            console.error('Error:', error);
            showMessage('Error running benchmark: ' + error.message, 'error');
        } finally {
            // Reset button state
            benchmarkBtn.disabled = false;
            benchmarkBtn.textContent = 'Run Benchmark';
        }
    });

    // Utility functions
    function formatBytes(bytes) {
        if (bytes === 0) return '0 bytes';
        const k = 1024;
        const sizes = ['bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    function showMessage(message, type) {
        // Remove existing messages
        const existingMessages = document.querySelectorAll('.message');
        existingMessages.forEach(msg => msg.remove());

        // Create new message
        const messageDiv = document.createElement('div');
        messageDiv.className = `message ${type}`;
        messageDiv.textContent = message;

        // Insert message at the top of the active tab content
        const activeTab = document.querySelector('.tab-content.active');
        activeTab.insertBefore(messageDiv, activeTab.firstChild);

        // Auto-remove message after 5 seconds
        setTimeout(() => {
            if (messageDiv.parentNode) {
                messageDiv.remove();
            }
        }, 5000);
    }

    // Auto-resize textareas
    function autoResize(textarea) {
        textarea.style.height = 'auto';
        textarea.style.height = textarea.scrollHeight + 'px';
    }

    inputCode.addEventListener('input', () => autoResize(inputCode));
    benchmarkInput.addEventListener('input', () => autoResize(benchmarkInput));

    // Initialize textarea heights
    autoResize(inputCode);
    autoResize(benchmarkInput);

    // Keyboard shortcuts
    document.addEventListener('keydown', function(e) {
        // Ctrl+Enter to minify
        if (e.ctrlKey && e.key === 'Enter') {
            if (document.querySelector('#minify-tab').classList.contains('active')) {
                minifyBtn.click();
            }
        }

        // Ctrl+Shift+Enter to benchmark
        if (e.ctrlKey && e.shiftKey && e.key === 'Enter') {
            if (document.querySelector('#benchmark-tab').classList.contains('active')) {
                benchmarkBtn.click();
            }
        }
    });

    // Copy to clipboard functionality
    function addCopyButton(element) {
        const copyBtn = document.createElement('button');
        copyBtn.textContent = 'Copy';
        copyBtn.className = 'copy-btn';
        copyBtn.style.cssText = `
            position: absolute;
            top: 10px;
            right: 10px;
            padding: 5px 10px;
            background: #007bff;
            color: white;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 12px;
        `;

        copyBtn.addEventListener('click', async () => {
            const text = element.textContent;
            try {
                await navigator.clipboard.writeText(text);
                copyBtn.textContent = 'Copied!';
                setTimeout(() => {
                    copyBtn.textContent = 'Copy';
                }, 2000);
            } catch (err) {
                console.error('Failed to copy: ', err);
            }
        });

        element.style.position = 'relative';
        element.appendChild(copyBtn);
    }

    // Add copy buttons to output containers
    const outputContainers = document.querySelectorAll('.output-container');
    outputContainers.forEach(container => {
        addCopyButton(container);
    });

    // Real-time character count
    function updateCharCount(textarea, displayElement) {
        const count = textarea.value.length;
        displayElement.textContent = `${count} characters`;
    }

    // Add character count displays
    const inputSection = document.querySelector('.input-section');
    const charCountDiv = document.createElement('div');
    charCountDiv.style.cssText = 'text-align: right; color: #6c757d; font-size: 12px; margin-top: 5px;';
    inputSection.appendChild(charCountDiv);

    inputCode.addEventListener('input', () => {
        updateCharCount(inputCode, charCountDiv);
    });

    // Initialize character count
    updateCharCount(inputCode, charCountDiv);

    console.log('zmin Development Server loaded successfully!');
});