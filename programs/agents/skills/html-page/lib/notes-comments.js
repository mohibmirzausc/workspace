// LLM comment surface + dev-server live reload.
//   Read mode  (any origin):  walks HTML comments matching `LLM: ...` and
//                              renders a left-margin ✎ marker next to the
//                              element that immediately follows the comment.
//                              Hover or focus to read the comment text.
//   Edit mode  (http origin): adds keyboard shortcut Cmd/Ctrl-Shift-C to
//                              enter "pick mode": click any element to
//                              attach an LLM comment to it. Persists via
//                              POST /api/comment to bin/notes-server.js.
//   Live reload (http origin): subscribes to /api/reload-events (SSE); reloads
//                              the page when the dev server detects any
//                              .html/.css/.js change in the directory.
(function () {
  const CAN_EDIT = location.protocol === 'http:' || location.protocol === 'https:';

  function init() {
    renderExistingComments();
    if (CAN_EDIT) {
      attachEditUI();
      attachLiveReload();
    }
  }

  function attachLiveReload() {
    if (typeof EventSource === 'undefined') return;
    const es = new EventSource('/api/reload-events');
    es.addEventListener('message', e => {
      if (e.data === 'reload') location.reload();
    });
    // EventSource auto-reconnects on transient failures; we don't need to handle
    // 'error' explicitly. On server stop, the page is harmless without it.
  }

  // ── Read mode ────────────────────────────────────────────────────────────
  function renderExistingComments() {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_COMMENT);
    const nodes = [];
    let n; while ((n = walker.nextNode())) nodes.push(n);

    nodes.forEach(node => {
      const m = node.nodeValue.trim().match(/^LLM:\s*([\s\S]*)$/);
      if (!m) return;
      const text = m[1].trim();

      let anchor = node.nextSibling;
      while (anchor && anchor.nodeType !== Node.ELEMENT_NODE) anchor = anchor.nextSibling;
      if (!anchor) return;

      attachMarker(anchor, text);
    });
  }

  function attachMarker(anchor, text) {
    if (getComputedStyle(anchor).position === 'static') {
      anchor.style.position = 'relative';
    }
    const wrap = document.createElement('span');
    wrap.className = 'llm-comment';
    wrap.innerHTML =
      '<button class="llm-comment-icon" type="button" aria-label="LLM comment">✎</button>' +
      '<span class="llm-comment-popover"></span>';
    wrap.querySelector('.llm-comment-popover').textContent = text;
    anchor.appendChild(wrap);
  }

  // ── Edit mode ────────────────────────────────────────────────────────────
  function attachEditUI() {
    document.addEventListener('keydown', e => {
      const triggered = (e.key === 'C' || e.key === 'c') && (e.metaKey || e.ctrlKey) && e.shiftKey;
      if (triggered) { e.preventDefault(); enterPickMode(); }
    });

    const hint = document.createElement('div');
    hint.className = 'llm-edit-hint';
    hint.textContent = '⌘⇧C — add LLM comment';
    document.body.appendChild(hint);
  }

  function enterPickMode() {
    document.body.classList.add('llm-pick-mode');
    const cancel = () => {
      document.body.classList.remove('llm-pick-mode');
      document.removeEventListener('click', onPick, true);
      document.removeEventListener('keydown', onEsc, true);
    };
    const onEsc = e => { if (e.key === 'Escape') cancel(); };
    const onPick = e => {
      const target = e.target.closest(
        'p, li, h2, h3, h4, pre, blockquote, ' +
        '.section, .callout, .notes-table tr, .notes-table th, .notes-table td, .notes-details'
      );
      if (!target || target.classList.contains('llm-comment') ||
          target.closest('.llm-comment, .llm-edit-hint, .llm-modal')) return;
      e.preventDefault(); e.stopPropagation();
      cancel();
      promptAndSave(target);
    };
    document.addEventListener('click', onPick, true);
    document.addEventListener('keydown', onEsc, true);
  }

  async function promptAndSave(target) {
    const text = await openModal(target);
    if (!text) return;

    const sig = makeSignature(target);
    try {
      const res = await fetch('/api/comment', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ file: location.pathname, signature: sig, comment: text }),
      });
      if (!res.ok) throw new Error(await res.text());
      location.reload();
    } catch (err) {
      alert('Could not save comment:\n' + (err.message || err));
    }
  }

  function makeSignature(el) {
    return {
      tag: el.tagName.toLowerCase(),
      text: (el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 80),
    };
  }

  function openModal(target) {
    return new Promise(resolve => {
      const modal = document.createElement('div');
      modal.className = 'llm-modal';
      modal.innerHTML = `
        <div class="llm-modal-card">
          <div class="llm-modal-title">Comment on <code>&lt;${target.tagName.toLowerCase()}&gt;</code></div>
          <div class="llm-modal-target"></div>
          <textarea class="llm-modal-input" rows="4" placeholder="LLM: …"></textarea>
          <div class="llm-modal-actions">
            <button type="button" class="llm-modal-cancel">cancel</button>
            <button type="button" class="llm-modal-save">save</button>
          </div>
        </div>`;
      modal.querySelector('.llm-modal-target').textContent =
        (target.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 120) + '…';
      document.body.appendChild(modal);

      const input = modal.querySelector('.llm-modal-input');
      input.focus();
      const cleanup = (val) => { modal.remove(); resolve(val); };
      modal.querySelector('.llm-modal-cancel').addEventListener('click', () => cleanup(null));
      modal.querySelector('.llm-modal-save').addEventListener('click', () => cleanup(input.value.trim()));
      modal.addEventListener('keydown', e => {
        if (e.key === 'Escape') cleanup(null);
        if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) cleanup(input.value.trim());
      });
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
