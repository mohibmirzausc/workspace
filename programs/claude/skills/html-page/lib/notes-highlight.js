// Lazy-loads highlight.js (common languages) and runs it on every <pre><code>.
// Token colors are themed in lib/notes-style.css via .hljs-* selectors,
// so we don't load any highlight.js theme stylesheet.
(function () {
  const HLJS_URL = 'https://cdn.jsdelivr.net/npm/highlight.js@11.10.0/lib/common.min.js';

  function run() {
    if (window.hljs) window.hljs.highlightAll();
  }

  const s = document.createElement('script');
  s.src = HLJS_URL;
  s.async = true;
  s.onload = run;
  document.head.appendChild(s);
})();
