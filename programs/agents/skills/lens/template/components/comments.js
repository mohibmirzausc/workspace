/* ── comment layer ─────────────────────────────────────────────────────────
   Every section, every object, and every view is commentable; each comment
   carries a verbatim capture of what it was written against, and exports as
   JSON or Markdown an agent can act on WITHOUT the page.

   A reusable comment layer for a static HTML page. Requires
   comment-layer.css. No dependencies.

   ── THE DESIGN RULE THAT MAKES THIS WORK ──
   A comment anchors on IDENTIFIERS the document already carries — the view name,
   the selection key that view uses, and a heading's TEXT. Never on DOM position.
   A rebuild moves every card on the canvas and renumbers every row, and none of
   that touches an anchor. Anchor on an index and every comment is wrong after
   the next regeneration.

   ── Mounting ──
     const C = mountComments({
       storageKey: 'my-doc-comments-v1',
       docTitle: 'My doc',
       docFile: 'docs/my-doc.html',        // shown in the export header
       build: { hash: 'abc1234' },         // optional; stamped on each comment
       views: [['graph','Graph'], ['list','List']],   // key, label — order is export order
       adapter: {
         currentView:      () => state.view,
         currentSelection: () => state.sel || null,
         selKind:  (v, k) => v === 'graph' ? 'node' : 'row',
         selTitle: (v, k) => titleOf(k),
         selExists:(v, k) => !!byKey[k],            // false ⇒ export says "anchor gone"
         goView:   v => { state.view = v; },
         applySel: (v, k) => { state.sel = k; },
         render:   () => render(),                  // MUST end by calling C.decorate()
         viewSummary: () => textOf('#sheet'),        // fallback capture for a whole view
       },
     });
   Then, at the END of your render(): C.decorate();
   ────────────────────────────────────────────────────────────────────────── */
function mountComments(opt) {
  const A = opt.adapter || {};
  /* Fail at mount, by name. Without this a missing #cmtLayer renders a comment
     button that invites the click and does nothing (drawLayer guards, openComposer
     does not), and a half-built adapter throws "A.selKind is not a function" from
     inside a click handler — after the reviewer has already typed their comment. */
  (function assertHost() {
    const ids = ['cmtLayer', 'cmtCount', 'cmtOpen', 'cmtNew'];
    const fns = ['currentView', 'currentSelection', 'selKind', 'selTitle',
                 'selExists', 'goView', 'applySel', 'render'];
    const missing = [
      ...ids.filter(i => !document.getElementById(i)).map(i => '#' + i),
      ...fns.filter(f => typeof A[f] !== 'function').map(f => 'adapter.' + f + '()'),
    ];
    if (missing.length) {
      throw new Error('[comment-layer] host is missing: ' + missing.join(', ') +
        '. See the Mounting block at the top of this file; the ids come from ' +
        'components/shell.html. Comments also need #sheet and/or #inspector with ' +
        '`.sect > h2` headings and an `.insp-pad` for the per-object control.');
    }
  })();
  const VIEW_LABEL = {}; const VIEW_ORDER = [];
  for (const [k, label] of opt.views) { VIEW_LABEL[k] = label; VIEW_ORDER.push(k); }

  const INTENTS = opt.intents || [
    ['question', 'Question', 'Unclear. Someone has to answer it before anything is written.'],
    ['defect', 'Defect', 'The document says something wrong, stale, or contradicted elsewhere.'],
    ['change', 'Change', 'A deliberate change to what the product does.'],
    ['architectural', 'Architectural',
     'May move the schema, a decision or the roadmap, not a local edit. Routed for a full pass.'],
  ];

  const esc = s => String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

  /* Where the commentable headings are. The default is the v1 shell; a v2 shell
     (one pane, no inspector) passes its own. `container` means "capture the whole
     enclosing box"; without it, capture walks siblings to the next heading.
       headings: [{ where:'pane', sel:'#pane h3' }]
       objectPad: '#pane'      // where the per-thing control is appended
       captureRoot: '#pane'    // fallback capture for a whole view */
  const HEADS = opt.headings || [
    { where: 'sheet', sel: '#sheet h3' },
    { where: 'inspector', sel: '#inspector .sect > h2', container: '.sect', needsSelection: true },
  ];
  const headsFor = w => HEADS.find(h => h.where === w) || HEADS[0];
  const OBJ_PAD = opt.objectPad || '#inspector .insp-pad';
  const CAP_ROOT = opt.captureRoot || '#sheet';

  let CM = { v: 1, comments: [] };
  try {
    const raw = JSON.parse(localStorage.getItem(opt.storageKey) || 'null');
    if (raw && Array.isArray(raw.comments)) CM = raw;
  } catch (e) {}
  const saveCm = () => { try { localStorage.setItem(opt.storageKey, JSON.stringify(CM)); } catch (e) {} };
  const unexported = () => CM.comments.filter(c => !c.exported).length;

  let S = { cmt: null, panel: false, del: null };

  // `where` is in the key: a sheet dot and an inspector dot can carry the same
  // section text, and findHead/jumpTo both branch on it. They only failed to
  // collide before by the incidental habit of sheet dots having sel:null.
  const anchorKey = a => [a.kind, a.view, a.sel || '', a.section || '', a.where || ''].join('|');
  /* A view- or section-anchored comment carries sel:null, and an adapter written
     to the documented contract (`!!byKey[k]`) returns FALSE for null — so every
     one of them exported as "anchor gone" about a view that plainly exists.
     Normalise here rather than asking every host to remember the null case. */
  const stillResolves = a => !a || !a.sel || !!A.selExists(a.view, a.sel);
  const cmtsFor = a => CM.comments.filter(c => anchorKey(c.anchor) === anchorKey(a));

  function pathOf(a) {
    const out = [VIEW_LABEL[a.view] || a.view];
    if (a.sel) out.push(A.selKind(a.view, a.sel) + ' ' + a.sel);
    if (a.section) out.push(a.section);
    return out.join(' › ');
  }

  /* A heading carries a live count — "Fields · 14" becomes "Fields · 15" the day
     the data changes. The key is the text BEFORE the count, so the anchor
     survives it. An author-set data-cmt-key beats both. */
  const sectKeyOf = t => String(t).split('·')[0].replace(/\s+/g, ' ').trim();
  /* Derive a heading's key from its OWN words only. A heading carrying a citation
     chip or an already-injected comment button would otherwise fold those into the
     key — "The worst gaps" plus a MODEL chip becomes "The worst gapsMODEL", and
     re-citing the section to a different source silently moves every anchor on it.
     Both readers below go through here, so they cannot drift apart. */
  function headKey(h) {
    if (h.dataset.cmtKey) return h.dataset.cmtKey;
    let t = '';
    for (const n of h.childNodes) {
      if (n.nodeType === 3) { t += n.nodeValue; continue; }
      if (n.nodeType !== 1) continue;
      if (n.classList.contains('src-chip') || n.classList.contains('cmt-dot')) continue;
      t += n.textContent;
    }
    return sectKeyOf(t);
  }
  const clip = (t, n) => {
    const s = String(t == null ? '' : t).replace(/\r/g, '')
      .replace(/[ \t]+/g, ' ').replace(/ *\n */g, '\n').replace(/\n{3,}/g, '\n\n').trim();
    if (s.length <= n) return s;
    // Slice by code POINT: cutting mid-surrogate leaves a lone \ud83d, which is not
    // valid UTF-8 and gets replaced or rejected wherever the export lands.
    return Array.from(s).slice(0, n).join('').trim() + ' …';
  };
  function textOf(el) {
    if (typeof el === 'string') el = document.querySelector(el);
    if (!el) return '';
    const root = document.documentElement;
    root.classList.add('cmt-capture');
    /* On a NON-RENDERED element innerText falls back to textContent, which ignores
       display:none and every rule .cmt-capture depends on — so the capture comes
       back with headings fused to their injected control labels and chips run
       together. `.sheet` is display:none on any graph view, which is exactly when
       the default viewSummary reads it. Force it rendered for the read. */
    const hidden = el.offsetParent === null && getComputedStyle(el).display === 'none';
    const prev = hidden ? el.style.display : null;
    if (hidden) el.style.display = 'block';
    const t = el.innerText || el.textContent || '';   // forces the recalc, then reads
    if (hidden) el.style.display = prev;
    root.classList.remove('cmt-capture');
    return t;
  }
  function findHead(a) {
    const g = headsFor(a.where);
    return [...document.querySelectorAll(g.sel)].find(h => headKey(h) === a.section) || null;
  }
  function sectionText(a) {
    const h = findHead(a);
    if (!h) return '';
    const g = headsFor(a.where);
    if (g.container) return textOf(h.closest(g.container));
    // No container: a heading owns everything up to the next heading of its kind.
    let t = textOf(h) + '\n';
    let n = h.nextElementSibling;
    while (n && n.tagName !== h.tagName) { t += textOf(n) + '\n'; n = n.nextElementSibling; }
    return t;
  }
  /* The export has to stand alone — an agent routing a comment must not need the page. */
  function captureFor(a) {
    if (a.kind === 'section') return clip(sectionText(a), 1400);
    /* An inline thread captures the block it sits in, minus itself — the thread
       is display:none for the duration of the read. Without this branch an
       inline anchor falls through to the object pad, which a one-pane page does
       not have, and every inline comment exports an empty context. */
    if (a.where === 'inline') {
      const el = inlineEl(a);
      return clip(el && el.parentElement ? textOf(el.parentElement) : '', 1800);
    }
    if (a.kind === 'object') return clip(textOf(OBJ_PAD), 1800);
    return clip(A.viewSummary ? A.viewSummary() : textOf(CAP_ROOT), 1800);
  }

  /* ── inline threads ─────────────────────────────────────────────────────────────
     A comment block rendered INSIDE the thing it is about, instead of a dot that
     opens a modal over it. Same store, same anchors, same export — the only
     difference is where the composer lives.

       ${C.inline({ view: 'blockers', sel: 'b:B1' })}     // in your template

     Anchored kind:'object' where:'inline', so a thread and the modal object
     control on the same selection stay distinct rather than merging.

     The draft lives here and not in the DOM: the host repaints its pane whole
     after every save, and half-typed text in a block the reviewer had not
     finished would go with it. */
  const DRAFTS = new Map();
  const inlineAnchor = o => ({ kind: 'object', view: o.view, sel: o.sel, section: null, where: 'inline' });
  const inlineTag = a => a.view + '|' + a.sel;
  function draftOf(a) {
    const k = anchorKey(a);
    if (!DRAFTS.has(k)) DRAFTS.set(k, { intent: INTENTS[0][0], body: '' });
    return DRAFTS.get(k);
  }
  const inlineEl = a => [...document.querySelectorAll('.cmt-inline')]
    .find(el => el.dataset.cmtInline === inlineTag(a)) || null;
  function anchorOfEl(el) {
    const raw = (el && el.dataset.cmtInline) || '';
    const i = raw.indexOf('|');
    return inlineAnchor({ view: raw.slice(0, i), sel: raw.slice(i + 1) });
  }
  function syncInline(el) {
    if (!el) return;
    const ta = el.querySelector('[data-cmt-inline-ta]');
    if (ta) draftOf(anchorOfEl(el)).body = ta.value;
  }
  function inlineHtml(o) {
    const a = inlineAnchor(o);
    const d = draftOf(a);
    const mine = cmtsFor(a);
    const hint = (INTENTS.find(i => i[0] === d.intent) || [])[2] || '';
    return `<div class="cmt-inline" data-cmt-inline="${esc(inlineTag(a))}">
      ${mine.length ? `<p class="cmt-lbl">${mine.length} comment${mine.length === 1 ? '' : 's'} here</p>
      ${mine.map(c => itemHtml(c)).join('')}` : ''}
      <div class="cmt-int">${INTENTS.map(i => `<button data-cmt-inline-int="${i[0]}"
        class="${d.intent === i[0] ? 'on' : ''}">${esc(i[1])}</button>`).join('')}</div>
      <p class="cmt-hint">${esc(hint)}</p>
      <textarea class="cmt-ta" data-cmt-inline-ta rows="3"
        placeholder="What is wrong, unclear, or should be different, and why.">${esc(d.body)}</textarea>
      <div class="cmt-inline-foot">
        <span class="cmt-hint">⌘↵ saves</span>
        <span class="sp"></span>
        <button class="cmt-btn pri" data-cmt-inline-save>Add comment</button>
      </div></div>`;
  }
  function refreshInline(el) {
    if (!el || !el.parentNode) return;
    const a = anchorOfEl(el);
    const tmp = document.createElement('div');
    tmp.innerHTML = inlineHtml({ view: a.view, sel: a.sel });
    el.replaceWith(tmp.firstElementChild);
  }
  const refreshInlines = () => [...document.querySelectorAll('.cmt-inline')].forEach(refreshInline);
  function saveInline(el) {
    if (!el) return;
    const a = anchorOfEl(el);
    syncInline(el);
    const d = draftOf(a);
    const body = (d.body || '').trim();
    if (!body) { const ta = el.querySelector('[data-cmt-inline-ta]'); if (ta) ta.focus(); return; }
    /* Capture BEFORE the host repaints: A.render() replaces the pane, and the
       block this was written against stops existing halfway through. */
    const context = captureFor(a);
    const now = new Date().toISOString();
    CM.comments.push({
      id: 'c' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
      createdAt: now, updatedAt: now, build: (opt.build && opt.build.hash) || null,
      intent: d.intent, anchor: a, selTitle: a.sel ? A.selTitle(a.view, a.sel) : null,
      path: pathOf(a), context, body, exported: false,
    });
    DRAFTS.delete(anchorKey(a));
    saveCm();
    A.render();
  }

  // ── composing ────────────────────────────────────────────────────────────
  function openComposer(anchor, id) {
    const ex = id ? CM.comments.find(c => c.id === id) : null;
    document.getElementById('cmtLayer').innerHTML = '';   // so the sync below finds nothing
    S.cmt = ex
      ? { id: ex.id, anchor: ex.anchor, intent: ex.intent, body: ex.body,
          context: ex.context, selTitle: ex.selTitle || null }
      : { id: null, anchor, intent: INTENTS[0][0], body: '', context: captureFor(anchor),
          selTitle: anchor.sel ? A.selTitle(anchor.view, anchor.sel) : null };
    drawLayer();
    const ta = document.getElementById('cmtTa');
    if (ta) { ta.focus(); ta.setSelectionRange(ta.value.length, ta.value.length); }
  }
  function syncComposer() {
    const ta = document.getElementById('cmtTa');
    if (ta && S.cmt) S.cmt.body = ta.value;
  }
  function saveComposer() {
    syncComposer();
    const c = S.cmt;
    if (!c) return;
    const body = (c.body || '').trim();
    if (!body) { const ta = document.getElementById('cmtTa'); if (ta) ta.focus(); return; }
    const now = new Date().toISOString();
    if (c.id) {
      const ex = CM.comments.find(x => x.id === c.id);
      // An edited comment is unexported again — the version already handed over is stale.
      if (ex) { ex.body = body; ex.intent = c.intent; ex.updatedAt = now; ex.exported = false; }
    } else {
      CM.comments.push({
        id: 'c' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6),
        createdAt: now, updatedAt: now, build: (opt.build && opt.build.hash) || null,
        intent: c.intent, anchor: c.anchor, selTitle: c.selTitle,
        path: pathOf(c.anchor), context: c.context, body, exported: false,
      });
    }
    saveCm();
    S.cmt = null;
    A.render();
  }

  // ── jumping back ─────────────────────────────────────────────────────────
  function flash(el) {
    if (!el) return;
    el.classList.remove('cmt-flash');
    void el.offsetWidth;                       // forces the restart; without it the 2nd jump is silent
    el.classList.add('cmt-flash');
    setTimeout(() => el.classList.remove('cmt-flash'), 1700);
  }
  function jumpTo(c) {
    const a = c.anchor;
    S.panel = false; S.cmt = null; S.del = null;
    A.goView(a.view);
    // A doc change can delete the thing a comment points at. The view still opens
    // and selects nothing, rather than throwing.
    A.applySel(a.view, stillResolves(a) ? a.sel : null);
    A.render();
    if (a.section) {
      const h = findHead(a);
      if (h) { for (let el = h.parentElement; el; el = el.parentElement) { if (el.tagName === 'DETAILS') el.open = true; } h.scrollIntoView({ block: 'center' }); flash(a.where === 'inspector' ? h.closest('.sect') : h); }
    } else if (a.sel) {
      const n = document.getElementById('n-' + a.sel);
      if (n) { n.scrollIntoView({ block: 'center', inline: 'center' }); flash(n); }
      else flash(document.querySelector('#inspector .insp-h'));
    }
  }

  /* ── the controls, injected after each render ────────────────────────────
     Injected rather than written into every template: there are dozens of
     headings across the views, and threading a button through each one is dozens
     of places to get the escaping wrong. */
  function addDot(h, where, seen) {
    if (h.querySelector('.cmt-dot')) return;
    // An author-set data-cmt-key wins. findHead already prefers it; this line used
    // to overwrite it with the heading text before findHead ever saw it — so a key
    // set deliberately to survive a heading rewrite never survived anything.
    let key = headKey(h);
    /* Two headings sharing a key is not exotic — `sectKeyOf` truncates at the first
       `·`, so "Read · write splits" and "Read · only" both key as "Read". Both dots
       then resolve to the FIRST heading, so a comment on the second ships the
       first one's text as "what it was written against" — the one guarantee this
       component makes. Disambiguate by order of appearance. */
    if (seen) {
      const n = (seen.get(key) || 0) + 1;
      seen.set(key, n);
      if (n > 1) {
        key = key + ' #' + n;
        if (!seen.warned) {
          seen.warned = true;
          console.warn('[comment-layer] duplicate heading key "' + headKey(h) +
            '" — suffixed to keep anchors distinct. `·` is reserved: it separates a ' +
            'heading from its count. Set data-cmt-key to pin a stable key.');
        }
      }
    }
    h.dataset.cmtKey = key;
    const n = cmtsFor({ kind: 'section', view: A.currentView(),
      sel: where === 'inspector' ? (A.currentSelection() || null) : null,
      section: key, where }).length;
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'cmt-dot' + (n ? ' has' : '');
    b.dataset.cmtSect = key;
    b.dataset.cmtWhere = where;
    b.textContent = n ? 'comment · ' + n : 'comment';
    b.title = (n ? n + ' comment' + (n === 1 ? '' : 's') + ' on ' : 'Comment on ') + key;
    h.appendChild(b);
  }
  function decorate() {
    const k = A.currentSelection();
    for (const g of HEADS) {
      // An inspector-style group is scoped to a selection; a pane/sheet group is not.
      if (g.needsSelection && !k) continue;
      const seen = new Map();
      for (const h of document.querySelectorAll(g.sel)) addDot(h, g.where, seen);
    }
    {
      const pad = document.querySelector(OBJ_PAD);
      if (pad) {
        const old = pad.querySelector('.cmt-obj');
        if (old) old.remove();
        if (k) {
          const n = cmtsFor({ kind: 'object', view: A.currentView(), sel: k,
            section: null, where: 'inspector' }).length;
          const b = document.createElement('button');
          b.type = 'button'; b.id = 'cmtObj';
          b.className = 'cmt-obj' + (n ? ' has' : '');
          b.textContent = n ? 'comment · ' + n : 'comment';
          b.title = 'Comment on this ' + A.selKind(A.currentView(), k);
          pad.appendChild(b);
        }
      }
    }
    const all = CM.comments.length, un = unexported();
    const cn = document.getElementById('cmtCount');
    if (cn) { cn.textContent = un || all; cn.className = 'n' + (un ? ' un' : ''); }
    const co = document.getElementById('cmtOpen');
    if (co) co.title = all + ' comment' + (all === 1 ? '' : 's') + ' · ' + un + ' not yet exported';
    drawLayer();
  }

  // ── composer + review panel ──────────────────────────────────────────────
  function composerHtml() {
    const c = S.cmt, a = c.anchor;
    const what = a.kind === 'view' ? 'the whole ' + (VIEW_LABEL[a.view] || a.view) + ' view'
      : a.kind === 'section' ? 'a section'
      : 'this ' + A.selKind(a.view, a.sel);
    const hint = (INTENTS.find(i => i[0] === c.intent) || [])[2] || '';
    return `<div class="cmt-scrim" data-cmt-scrim><div class="cmt-card" role="dialog" aria-label="Comment">
      <div class="cmt-head">
        <span class="k">${c.id ? 'Edit comment' : 'Comment on ' + esc(what)}</span>
        <b>${esc(pathOf(a))}</b>
      </div>
      <div class="cmt-body">
        <p class="cmt-lbl">Intent: what the reviewers do with it</p>
        <div class="cmt-int">${INTENTS.map(i => `<button data-int="${i[0]}"
          class="${c.intent === i[0] ? 'on' : ''}">${esc(i[1])}</button>`).join('')}</div>
        <p class="cmt-hint">${esc(hint)}</p>
        <p class="cmt-lbl">Comment</p>
        <textarea class="cmt-ta" id="cmtTa"
          placeholder="What is wrong, unclear, or should be different, and why.">${esc(c.body)}</textarea>
        <details class="cmt-ctx"${c.id ? '' : ' open'}>
          <summary>Context captured · ${c.context.length} characters, exported with the comment</summary>
          <pre>${esc(c.context || '(nothing rendered here)')}</pre>
        </details>
      </div>
      <div class="cmt-foot">
        <span class="cmt-hint" style="margin:0">⌘↵ saves · Esc cancels</span>
        <span class="sp"></span>
        <button class="cmt-btn" id="cmtCancel">Cancel</button>
        <button class="cmt-btn pri" id="cmtSave">${c.id ? 'Save' : 'Add comment'}</button>
      </div></div></div>`;
  }
  function when(iso) {
    const d = new Date(iso);
    return isNaN(d) ? iso : d.toLocaleString(undefined,
      { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
  }
  function itemHtml(c) {
    const arm = S.del === c.id;
    const gone = !stillResolves(c.anchor);
    return `<div class="cmt-item ${c.exported ? '' : 'un'}">
      <div class="top">
        <span class="ipill ${c.intent}">${esc(c.intent)}</span>
        <span class="path">${esc(c.path)}</span>
        ${gone ? '<span class="ipill defect" title="The doc no longer carries it">anchor gone</span>' : ''}
        <span class="when">${esc(when(c.updatedAt || c.createdAt))}</span>
      </div>
      <p>${esc(c.body)}</p>
      <div class="acts">
        <button data-cmt-jump="${c.id}">jump to it</button>
        <button data-cmt-edit="${c.id}">edit</button>
        <button class="del" data-cmt-del="${c.id}">${arm ? 'really delete?' : 'delete'}</button>
        ${c.exported ? '<span class="tag">exported</span>' : ''}
      </div></div>`;
  }
  function panelHtml() {
    const all = CM.comments, un = unexported();
    const groups = VIEW_ORDER.map(v => [v, all.filter(c => c.anchor.view === v)])
      .filter(gp => gp[1].length);
    return `<div class="cmt-scrim" data-cmt-scrim><div class="cmt-card wide" role="dialog"
      aria-label="Review comments">
      <div class="cmt-head">
        <span class="k">Review</span>
        <b>${all.length} comment${all.length === 1 ? '' : 's'} · ${un} not yet exported</b>
      </div>
      <div class="cmt-body">${all.length
        ? groups.map(gp => `<p class="cmt-grp">${esc(VIEW_LABEL[gp[0]])} · ${gp[1].length}</p>` +
            gp[1].map(itemHtml).join('')).join('')
        : `<p class="cmt-hint" style="margin:0">Nothing yet. Hover any heading for its comment
           control, use the button at the top of the inspector for whatever is selected, or
           <b>+ comment</b> for the whole view. <code>c</code> comments on the current selection,
           <code>r</code> opens this panel.</p>`}</div>
      <div class="cmt-foot">
        <button class="cmt-btn pri" id="cmtCopy" ${all.length ? '' : 'disabled'}>Copy for an agent</button>
        <button class="cmt-btn" id="cmtJson" ${all.length ? '' : 'disabled'}>Copy JSON</button>
        <span class="cmt-hint" style="margin:0">Copy is the only path that can confirm
          it worked, so only Copy marks these handed over. Downloads do nothing at all
          inside a published artifact.</span>
        <span class="sp"></span>
        <button class="cmt-btn" id="cmtClose">Close</button>
      </div></div></div>`;
  }
  function drawLayer() {
    syncComposer();
    const el = document.getElementById('cmtLayer');
    if (el) el.innerHTML = (S.panel ? panelHtml() : '') + (S.cmt ? composerHtml() : '');
  }

  // ── export ───────────────────────────────────────────────────────────────
  function markExported() { CM.comments.forEach(c => { c.exported = true; }); saveCm(); }
  /* There is no download path here, deliberately. A published artifact runs in a
     sandbox that never grants download permission, so `a[download]` and every
     blob save are inert AND SILENT — the reviewer clicks, nothing happens, and
     the reasonable conclusion is that the review was lost. Two buttons that work
     when you open the file locally and do nothing when you open the published
     link are worse than one button that always works. Both exports copy. */
  function exportJson() {
    const byIntent = {};
    for (const i of INTENTS) byIntent[i[0]] = CM.comments.filter(c => c.intent === i[0]).length;
    const byView = {};
    for (const v of VIEW_ORDER) {
      const n = CM.comments.filter(c => c.anchor.view === v).length;
      if (n) byView[v] = n;
    }
    return JSON.stringify({
      schema: 'artifact-shapes.comments/1',
      exportedAt: new Date().toISOString(),
      doc: { title: opt.docTitle || document.title, file: opt.docFile || null, build: opt.build || null },
      counts: { total: CM.comments.length, byIntent, byView },
      comments: CM.comments.map(c => ({
        id: c.id, intent: c.intent, createdAt: c.createdAt, updatedAt: c.updatedAt,
        docBuild: c.build || null, location: c.path,
        anchor: {
          kind: c.anchor.kind, view: c.anchor.view,
          selection: c.anchor.sel || null,
          selectionKind: c.anchor.sel ? A.selKind(c.anchor.view, c.anchor.sel) : null,
          selectionTitle: c.selTitle || null,
          section: c.anchor.section || null, pane: c.anchor.where || null,
          // False means the doc moved under the comment since it was written. The
          // captured context below is then the only record of what it was written against.
          stillResolves: stillResolves(c.anchor),
        },
        body: c.body, context: c.context,
      })),
    }, null, 2);
  }
  function exportMd() {
    const all = CM.comments, L = [];
    const p = t => L.push(t);
    p('# Review · ' + (opt.docTitle || document.title));
    p('');
    p(all.length + ' comment' + (all.length === 1 ? '' : 's') +
      (opt.docFile ? ', left while reading `' + opt.docFile + '`' : '') +
      (opt.build && opt.build.hash ? ' · build `' + opt.build.hash + '`' : '') + '.');
    p('');
    p('Each comment carries the text it was written against, so it can be acted on');
    p('without opening the document.');
    for (const v of VIEW_ORDER) {
      const list = all.filter(c => c.anchor.view === v);
      if (!list.length) continue;
      p(''); p('## ' + (VIEW_LABEL[v] || v) + ' · ' + list.length);
      for (const c of list) {
        p('');
        p('### ' + c.path);
        p('');
        p('- **Intent:** ' + c.intent);
        p('- **Written:** ' + (c.updatedAt || c.createdAt));
        if (!stillResolves(c.anchor)) {
          p('- **Anchor:** GONE. The document no longer carries this. The captured');
          p('  context below is the only record of what it was written against.');
        }
        p('');
        p(c.body);
        p('');
        p('<details><summary>Context captured at the time</summary>');
        p('');
        p('```');
        p(c.context || '(nothing rendered here)');
        p('```');
        p('');
        p('</details>');
      }
    }
    return L.join('\n');
  }

  // ── events, delegated once ───────────────────────────────────────────────
  document.addEventListener('click', ev => {
    const t = ev.target.closest('button, [data-cmt-scrim]');
    if (!t) return;
    const view = A.currentView(), sel = A.currentSelection();

    if (t.classList.contains('cmt-dot')) {
      openComposer({ kind: 'section', view,
        sel: t.dataset.cmtWhere === 'inspector' ? (sel || null) : null,
        section: t.dataset.cmtSect, where: t.dataset.cmtWhere });
      return;
    }
    if (t.id === 'cmtObj') {
      openComposer({ kind: 'object', view, sel, section: null, where: 'inspector' }); return;
    }
    if (t.id === 'cmtNew') {
      openComposer({ kind: 'view', view, sel: null, section: null, where: 'view' }); return;
    }
    if (t.id === 'cmtOpen') { S.panel = true; S.del = null; drawLayer(); return; }
    if (t.id === 'cmtClose' || t.hasAttribute('data-cmt-scrim')) {
      // A click on the scrim behind the composer must not silently discard a draft.
      if (S.cmt) { syncComposer(); if ((S.cmt.body || '').trim()) return; }
      S.cmt = null; S.panel = false; S.del = null; drawLayer(); return;
    }
    if (t.id === 'cmtCancel') { S.cmt = null; drawLayer(); return; }
    if (t.id === 'cmtSave') { saveComposer(); return; }
    if (t.dataset.int) { syncComposer(); S.cmt.intent = t.dataset.int; drawLayer(); return; }
    if (t.dataset.cmtInlineInt) {
      const el = t.closest('.cmt-inline');
      syncInline(el);
      draftOf(anchorOfEl(el)).intent = t.dataset.cmtInlineInt;
      refreshInline(el);
      return;
    }
    if (t.hasAttribute('data-cmt-inline-save')) { saveInline(t.closest('.cmt-inline')); return; }
    if (t.dataset.cmtJump) { jumpTo(CM.comments.find(c => c.id === t.dataset.cmtJump)); return; }
    if (t.dataset.cmtEdit) { S.panel = false; openComposer(null, t.dataset.cmtEdit); return; }
    if (t.dataset.cmtDel) {
      const id = t.dataset.cmtDel;
      // Two clicks to delete. drawLayer only touches the modal layer, so an item
      // shown inline armed invisibly and went on what read as a single click.
      if (S.del !== id) { S.del = id; drawLayer(); refreshInlines(); return; }
      CM.comments = CM.comments.filter(c => c.id !== id);
      S.del = null; saveCm(); A.render(); return;
    }
    /* Marking on a COPY is safe in a way marking on a download was not: the clipboard
       write reports success, a sandboxed save does not. Over-marking loses the
       reviewer's work; under-marking only costs a duplicate export. */
    if (t.id === 'cmtCopy' || t.id === 'cmtJson') {
      const text = t.id === 'cmtJson' ? exportJson() : exportMd();
      // navigator.clipboard is unavailable on file:// in some browsers; fall back
      // rather than failing silently on the one gesture the user most expects to work.
      const done = () => { t.textContent = 'copied ✓'; markExported(); setTimeout(() => A.render(), 900); };
      const fallback = () => { if (legacyCopy(text)) done(); else { t.textContent = 'Copy failed — select export below'; const ta = document.createElement('textarea'); ta.className = 'cmt-ta'; ta.readOnly = true; ta.value = text; t.closest('.cmt-card').appendChild(ta); ta.focus(); ta.select(); } };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(done, fallback);
      } else { fallback(); }
      return;
    }
  });
  document.addEventListener('input', ev => {
    const t = ev.target;
    if (t && t.closest && t.closest('[data-cmt-inline-ta]')) syncInline(t.closest('.cmt-inline'));
  });
  function legacyCopy(text) {
    const ta = document.createElement('textarea');
    ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.appendChild(ta); ta.select();
    let copied = false;
    try { copied = document.execCommand('copy'); } catch (e) {}
    ta.remove();
    return copied;
  }
  document.addEventListener('keydown', ev => {
    const ae = document.activeElement;
    const inField = !!ae && (/^(INPUT|TEXTAREA|SELECT)$/.test(ae.tagName) || ae.isContentEditable);
    if (ev.key === 'Escape') {
      if (S.cmt) { S.cmt = null; drawLayer(); ev.preventDefault(); }
      else if (S.panel) { S.panel = false; drawLayer(); ev.preventDefault(); }
      return;
    }
    if (S.cmt && (ev.metaKey || ev.ctrlKey) && ev.key === 'Enter') { saveComposer(); ev.preventDefault(); return; }
    if ((ev.metaKey || ev.ctrlKey) && ev.key === 'Enter' && ae && ae.closest && ae.closest('.cmt-inline')) {
      saveInline(ae.closest('.cmt-inline')); ev.preventDefault(); return;
    }
    if (inField || S.cmt) return;
    /* Never claim a modified key. Bare `c` and `r` are the shortcuts; Cmd/Ctrl+C is
       the reader copying a quote out of the document and Cmd/Ctrl+R is reload, and
       preventDefault on either takes away the two things a reference document must
       never take away. */
    if (ev.metaKey || ev.ctrlKey || ev.altKey) return;
    if (ev.key === 'c') {
      const sel = A.currentSelection();
      openComposer(sel
        ? { kind: 'object', view: A.currentView(), sel, section: null, where: 'inspector' }
        : { kind: 'view', view: A.currentView(), sel: null, section: null, where: 'view' });
      ev.preventDefault();
    } else if (ev.key === 'r') { S.panel = true; drawLayer(); ev.preventDefault(); }
  });

  return { decorate, count: () => CM.comments.length, exportJson, exportMd,
           all: () => CM.comments.slice(), inline: inlineHtml };
}
