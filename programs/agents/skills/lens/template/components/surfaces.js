// Feature surfaces, shipped ones and ideas, each as one card: a screenshot carousel on the left and
// four headed sections on the right (Common Region, Proximity, Similarity). Ideas are dashed and
// tinted so they never read as shipped (Von Restorff).
const Surfaces = (() => {
  const U = typeof Ui !== 'undefined' ? Ui : require('./ui.js');
  const EL = typeof EvidenceList !== 'undefined' ? EvidenceList : require('./evidence-list.js');

  const avatarsServed = (g, id) => [...new Set(g.edgesFrom(id).filter((e) => e.relation === 'serves')
    .flatMap((e) => g.edgesTo(e.to).filter((x) => x.relation === 'has').map((x) => x.from)))];

  // A screenshot is stale when the surface's code changed after it was captured.
  const stale = (capturedAt, codeDate) => !!codeDate && codeDate > capturedAt;

  // Newest first by the latest dated source a note cites; undated notes keep their order at the end.
  const newest = (g, c) => (c.evidence || []).map((ev) => g.node(ev.source)?.date || '').sort().at(-1) || '';
  const heardInOrder = (g, list) => list.map((c, i) => ({ c, i, d: newest(g, c) })).sort((a, b) => b.d.localeCompare(a.d) || a.i - b.i).map((x) => x.c);

  function carousel(n, codeDate) {
    if (!n.screenshots.length) return `<div class="carousel empty">${n.shipped ? 'No screenshot yet' : 'No mockup yet'}</div>`;
    const slides = n.screenshots.map((s, i) => `<figure class="slide"${i ? ' hidden' : ''}><img src="${U.esc(s.file)}" alt="${U.esc(s.caption)}" loading="lazy"><figcaption><b>${U.esc(s.caption)}</b><span>${s.origin === 'design' ? 'Design' : 'App'} · captured ${U.esc(EL.fmtDate(s.capturedAt))}${s.version ? ` · ${U.esc(s.version)}` : ''}</span>${stale(s.capturedAt, codeDate) ? `<span class="stale">Code changed since this screenshot (${U.esc(EL.fmtDate(codeDate))})</span>` : ''}</figcaption></figure>`).join('');
    const nav = n.screenshots.length > 1 ? `<div class="carousel-nav"><button data-carousel-step="-1" aria-label="Previous screenshot">‹</button>${n.screenshots.map((_, i) => `<span class="dot${i ? '' : ' on'}"></span>`).join('')}<button data-carousel-step="1" aria-label="Next screenshot">›</button></div>` : '';
    return `<div class="carousel" data-carousel>${slides}${nav}</div>`;
  }

  // A permalink at the commit the lens was built from: folders open as a tree, files as a blob.
  // No GitHub remote (repo is null or has no url) means no link, just the path.
  const githubLink = (repo, p) => (repo?.url ? `${repo.url}/${p.endsWith('/') ? 'tree' : 'blob'}/${repo.sha}/${p}` : null);
  const ext = (href, label) => (href ? `<a href="${U.esc(href)}" target="_blank" rel="noopener">${label}</a>` : label);
  // "docs/adr/010-notes-sync-offline.md" → "ADR 010 · notes sync offline"
  const adrLabel = (p) => { const m = /(\d{3})-(.+)\.md$/.exec(p); return m ? `ADR ${m[1]} · ${m[2].replace(/-/g, ' ')}` : p; };
  const codeLinks = (n, repo) => n.code.map((p) => ext(githubLink(repo, p), `<code>${U.esc(p)}</code>`)).join(' ');
  const adrLinks = (n, repo) => n.adrs.map((p) => `<li>${ext(githubLink(repo, p), U.esc(adrLabel(p)))}</li>`).join('');
  const decisionLinks = (g, n, repo) => [
    adrLinks(n, repo),
    ...g.edgesTo(n.id).filter((e) => e.relation === 'shapes').map((e) => `<li>${U.chip(g, e.from)}</li>`),
  ].join('');

  const part = (title, body) => (body ? `<section class="part"><h4>${title}</h4>${body}</section>` : '');

  function card(g, n, codeDates, repo) {
    const heard = heardInOrder(g, n.heard);
    return `<article class="card surface${n.shipped ? '' : ' idea'}" data-node="${U.esc(n.id)}"><div class="row-head"><button class="card-title" data-node="${U.esc(n.id)}">${U.esc(n.title)}</button>${n.shipped ? '' : '<span class="pill idea">Idea · not built</span>'}<span class="chips">${avatarsServed(g, n.id).map((id) => U.chip(g, id)).join('')}</span></div><p class="lede">${U.esc(n.body)}</p><div class="cols">${carousel(n, codeDates[n.id])}<div class="parts">${part('What it does', n.unique.map((c) => U.claimBlock(g, c)).join(''))}${part('When it’s used', n.situations.map((c) => U.claimBlock(g, c)).join(''))}${part('What we’ve heard', heard.length ? `<ol class="heard">${heard.map((c) => `<li>${U.claimBlock(g, c, { bare: true })}</li>`).join('')}</ol>` : '')}${part('Code', codeLinks(n, repo))}${part('Decisions', (() => { const l = decisionLinks(g, n, repo); return l ? `<ul class="decision-links">${l}</ul>` : ''; })())}</div></div></article>`;
  }

  function view(g, { ideas, codeDates, repo }) {
    const list = g.nodesOfKind('surface').filter((n) => n.shipped === !ideas);
    const intro = ideas
      ? '<div class="eyebrow">Ideas · not built</div><h2>Surfaces we’ve talked about building</h2><p class="page-intro">Nothing here ships today. Mockups come from brainstorms.</p>'
      : `<div class="eyebrow">In ${U.esc(U.productName(g))} today</div><h2>What ${U.esc(U.productName(g))} offers</h2>`;
    return `${intro}<div class="surfaces">${list.map((n) => card(g, n, codeDates, repo)).join('')}</div>`;
  }
  return { view, avatarsServed, stale, heardInOrder, githubLink, codeLinks, adrLinks, decisionLinks };
})();
if (typeof module !== 'undefined') module.exports = Surfaces;
