// components/app.js
// Browser only: state in the URL, one render, and the comment layer. Everything it shows comes
// from the pure modules above.
(() => {
  if (typeof document === 'undefined') return;
  const g = Graph.createGraph(D);
  // View keys are part of comment anchors; renaming one orphans comments made on it.
  const VIEWS = [['home', '🏠 Home'], ['overview', '🧑‍🚀 Avatars'], ['product', '🧩 Surfaces'], ['ideas', '💡 Ideas'], ['alternatives', '↔️ Alternatives'], ['marketing', '📣 Marketing'], ['insights', '📈 Market insights'], ['people', '👥 Interviewees'], ['sources', '📚 Evidence'], ['decisions', '🧭 Decisions']];
  const TAGS = Schema.EVIDENCE_TAGS;
  const SORTS = EvidenceList.SORTS.map((s) => s[0]);
  const normalize = (s) => ({
    view: VIEWS.some((v) => v[0] === s.view) ? s.view : 'home',
    sel: s.sel && g.lookup(s.sel) ? s.sel : null,
    search: typeof s.search === 'string' ? s.search : '',
    tag: TAGS.includes(s.tag) ? s.tag : 'all',
    sort: SORTS.includes(s.sort) ? s.sort : 'newest',
  });
  const fromUrl = () => { const p = new URLSearchParams(location.hash.slice(1)); return normalize({ view: p.get('view'), sel: p.get('item'), search: p.get('q') || '', tag: p.get('tag'), sort: p.get('sort') }); };
  const toUrl = (s) => { const p = new URLSearchParams({ view: s.view }); if (s.sel) p.set('item', s.sel); if (s.search) p.set('q', s.search); if (s.tag !== 'all') p.set('tag', s.tag); if (s.sort !== 'newest') p.set('sort', s.sort); return `#${p}`; };
  let state = fromUrl();
  let C = null;

  const HOME = { avatar: 'overview', person: 'people', source: 'sources', decision: 'decisions', hypothesis: 'home', 'loop-step': 'home', alternative: 'alternatives', product: 'alternatives', channel: 'overview', pillar: 'marketing', 'content-idea': 'marketing', insight: 'insights' };
  const homeOf = (id) => { const hit = g.lookup(id); const n = hit.type === 'node' ? hit.value : hit.owner ? g.node(hit.owner) : null; if (n?.kind === 'surface') return n.shipped ? 'product' : 'ideas'; return (n && HOME[n.kind]) || state.view; };

  function navigate(next, { replace = false } = {}) {
    const clean = normalize({ ...state, ...next });
    if (JSON.stringify(clean) === JSON.stringify(state)) return;
    state = clean;
    if (replace) history.replaceState(null, '', toUrl(state)); else history.pushState(null, '', toUrl(state));
    render();
    if (!replace) window.scrollTo({ top: 0, behavior: 'instant' });
  }

  function sheet() {
    if (state.sel) return Detail.detail(g, state.sel, { images: D.images, repo: D.repo });
    switch (state.view) {
      case 'overview': return Avatars.view(g, { images: D.images });
      case 'product': return Surfaces.view(g, { ideas: false, codeDates: D.codeDates, repo: D.repo });
      case 'ideas': return Surfaces.view(g, { ideas: true, codeDates: D.codeDates, repo: D.repo });
      case 'alternatives': return Alternatives.view(g);
      case 'marketing': return Marketing.view(g);
      case 'insights': return Insights.view(g);
      case 'people': return Interviewees.view(g);
      case 'sources': return Evidence.view(g, state);
      case 'decisions': return Decisions.view(g);
      default: return Home.view(g);
    }
  }

  function render() {
    document.getElementById('nav').innerHTML = VIEWS.map(([v, t]) => `<button data-view="${v}" aria-pressed="${state.view === v && !state.sel}">${t}</button>`).join('');
    document.getElementById('sheet').innerHTML = sheet();
    document.getElementById('version').textContent = `${D.updated} · build ${D.build}`;
    document.getElementById('brandTitle').textContent = `${Ui.productName(g)} · Lens`;
    document.getElementById('ownerLine').textContent = `${Ui.ownerName(g)}’s current view`;
    document.title = `${Ui.productName(g)} · Lens`;
    if (C) C.decorate();
  }

  document.addEventListener('click', (ev) => {
    const step = ev.target.closest('[data-carousel-step]');
    if (step) { turn(step.closest('[data-carousel]'), Number(step.dataset.carouselStep)); return; }
    const t = ev.target.closest('[data-view],[data-node],[data-tag],[data-sort],#navBack,#navForward');
    if (!t || t.closest('#cmtLayer')) return;
    if (t.id === 'navBack') return history.back();
    if (t.id === 'navForward') return history.forward();
    if (t.dataset.view) return navigate({ view: t.dataset.view, sel: null, search: '', tag: 'all', sort: 'newest' });
    if (t.dataset.tag) return navigate({ tag: t.dataset.tag }, { replace: true });
    if (t.dataset.sort) return navigate({ sort: t.dataset.sort }, { replace: true });
    if (t.tagName === 'BUTTON' && t.dataset.node) { const id = t.dataset.claim || t.dataset.node; navigate({ view: homeOf(id), sel: id, search: '', tag: 'all' }); }
  });
  document.addEventListener('input', (ev) => {
    if (ev.target.id !== 'search') return;
    const pos = ev.target.selectionStart;
    navigate({ search: ev.target.value }, { replace: true });
    const box = document.getElementById('search'); box.focus(); box.setSelectionRange(pos, pos);
  });
  // Carousel: one slide visible at a time; arrows wrap; the dots follow.
  function turn(box, by) {
    const slides = [...box.querySelectorAll('.slide')];
    const now = slides.findIndex((s) => !s.hidden);
    const next = (now + by + slides.length) % slides.length;
    slides.forEach((s, i) => { s.hidden = i !== next; });
    box.querySelectorAll('.dot').forEach((d, i) => d.classList.toggle('on', i === next));
  }
  document.addEventListener('keydown', (ev) => {
    const box = document.activeElement?.closest?.('[data-carousel]');
    if (box && (ev.key === 'ArrowLeft' || ev.key === 'ArrowRight')) turn(box, ev.key === 'ArrowLeft' ? -1 : 1);
  });
  window.addEventListener('popstate', () => { state = fromUrl(); render(); });

  // One comment store per lens, keyed by its title, so two lenses served from one origin don't mix.
  const KEY = `lens-comments-v1:${D.title || 'lens'}`;
  C = mountComments({
    storageKey: KEY, objectPad: '#sheet .insp-pad', docTitle: D.title, docFile: D.lensDir ? `${D.lensDir}/index.html` : 'index.html', build: { hash: D.build }, views: VIEWS,
    headings: [{ where: 'sheet', sel: '#sheet .sect > h2, #sheet h3.section-label', container: '.sect' }, { where: 'sheet', sel: '#sheet .claim-head', container: '.claim' }, { where: 'inspector', sel: '#sheet .journey-map > h2, #sheet .journey-map tbody th, #sheet .journey-map td', container: '.journey-map', needsSelection: true }],
    adapter: {
      currentView: () => state.view, currentSelection: () => state.sel,
      selKind: (_v, k) => g.lookup(k)?.type || 'item',
      selTitle: (_v, k) => { const h = g.lookup(k); return h ? h.value.title || h.value.text || k : k; },
      selExists: (_v, k) => !!g.lookup(k),
      goView: (v) => { state.view = v; state.sel = null; },
      applySel: (_v, k) => { state.sel = k; history.pushState(null, '', toUrl(state)); },
      render,
      viewSummary: () => document.getElementById('sheet').innerText,
    },
  });
  render();
})();
