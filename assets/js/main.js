// Main JavaScript for zmin documentation site

document.addEventListener('DOMContentLoaded', function() {
  // Add copy buttons to code blocks
  addCopyButtons();

  // Add syntax highlighting
  addSyntaxHighlighting();

  // Add basic interactive features
  addBasicFeatures();
});

// Add copy buttons to code blocks
function addCopyButtons() {
  const codeBlocks = document.querySelectorAll('pre code, .highlight pre');

  codeBlocks.forEach((block, index) => {
    const wrapper = block.closest('pre') || block.parentElement;
    if (!wrapper.querySelector('.copy-btn')) {
      const copyBtn = document.createElement('button');
      copyBtn.className = 'copy-btn';
      copyBtn.textContent = 'Copy';
      copyBtn.setAttribute('data-code-index', index);

      copyBtn.addEventListener('click', function() {
        const code = block.textContent || block.innerText;
        copyToClipboard(code, copyBtn);
      });

      wrapper.style.position = 'relative';
      wrapper.appendChild(copyBtn);
    }
  });
}

// Copy text to clipboard
function copyToClipboard(text, button) {
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(text).then(() => {
      showCopySuccess(button);
    }).catch(() => {
      fallbackCopyTextToClipboard(text, button);
    });
  } else {
    fallbackCopyTextToClipboard(text, button);
  }
}

// Fallback copy method
function fallbackCopyTextToClipboard(text, button) {
  const textArea = document.createElement('textarea');
  textArea.value = text;
  textArea.style.top = '0';
  textArea.style.left = '0';
  textArea.style.position = 'fixed';
  document.body.appendChild(textArea);
  textArea.focus();
  textArea.select();

  try {
    const successful = document.execCommand('copy');
    if (successful) {
      showCopySuccess(button);
    } else {
      showCopyError(button);
    }
  } catch (err) {
    showCopyError(button);
  }

  document.body.removeChild(textArea);
}

// Show copy success
function showCopySuccess(button) {
  const originalText = button.textContent;
  button.textContent = 'Copied!';
  button.classList.add('copy-btn--success');

  setTimeout(() => {
    button.textContent = originalText;
    button.classList.remove('copy-btn--success');
  }, 2000);
}

// Show copy error
function showCopyError(button) {
  const originalText = button.textContent;
  button.textContent = 'Failed';
  button.classList.add('copy-btn--error');

  setTimeout(() => {
    button.textContent = originalText;
    button.classList.remove('copy-btn--error');
  }, 2000);
}

// Add syntax highlighting
function addSyntaxHighlighting() {
  // This would integrate with a syntax highlighting library
  // For now, we'll just add basic styling
  const codeBlocks = document.querySelectorAll('pre code');
  codeBlocks.forEach(block => {
    block.classList.add('highlighted');
  });
}

// Add basic interactive features
function addBasicFeatures() {
  // Add smooth scrolling for anchor links
  const anchorLinks = document.querySelectorAll('a[href^="#"]');
  anchorLinks.forEach(link => {
    link.addEventListener('click', function(e) {
      const href = this.getAttribute('href');
      if (href !== '#') {
        const target = document.querySelector(href);
        if (target) {
          e.preventDefault();
          target.scrollIntoView({
            behavior: 'smooth',
            block: 'start'
          });
        }
      }
    });
  });

  // Add loading states for links
  const links = document.querySelectorAll('a[href]');
  links.forEach(link => {
    link.addEventListener('click', function() {
      if (this.href && !this.href.startsWith('#')) {
        this.classList.add('loading');
      }
    });
  });
}

// Utility function to save to localStorage
function saveToLocalStorage(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch (e) {
    console.warn('Could not save to localStorage:', e);
  }
}

// Utility function to load from localStorage
function loadFromLocalStorage(key, defaultValue = null) {
  try {
    const item = localStorage.getItem(key);
    return item ? JSON.parse(item) : defaultValue;
  } catch (e) {
    console.warn('Could not load from localStorage:', e);
    return defaultValue;
  }
}
