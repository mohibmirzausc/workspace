// components/detail.js
// The one detail panel. Selecting a node, a claim or an edge all land here.
const Detail = (() => {
  const U = typeof Ui !== 'undefined' ? Ui : require('./ui.js');
  const S = typeof Schema !== 'undefined' ? Schema : require('./schema.js');
  const A = typeof Avatars !== 'undefined' ? Avatars : require('./avatars.js');
  const I = typeof Interviewees !== 'undefined' ? Interviewees : require('./interviewees.js');
  const E = typeof Evidence !== 'undefined' ? Evidence : require('./evidence.js');
  const H = typeof Home !== 'undefined' ? Home : require('./home.js');
  const SF = typeof Surfaces !== 'undefined' ? Surfaces : require('./surfaces.js');

  const claims = (g, list, focus) => list.map((c) => U.claimBlock(g, c, { focused: c.id === focus })).join('');

  function body(g, n, focus, images, repo) {
    switch (n.kind) {
      case 'avatar': return `${A.art(n, images)}${A.personaMap(g, n, focus)}${A.journeyMap(g, n, focus)}`;
      case 'person': return `${U.section('Background', claims(g, n.background, focus))}${U.section('Conversations', I.conversations(g, n.id))}`;
      case 'surface': return `<p><span class="pill ${n.shipped ? 'shipped' : 'idea'}">${n.shipped ? 'Shipped' : 'Idea · not built'}</span></p>${U.section('What it does', claims(g, n.unique, focus))}${U.section('When it’s used', claims(g, n.situations, focus))}${U.section('What we’ve heard', claims(g, n.heard, focus))}${U.section('Code', SF.codeLinks(n, repo))}${U.section('ADRs', n.adrs.length ? `<ul class="decision-links">${SF.adrLinks(n, repo)}</ul>` : '')}`;
      case 'product': {
        const src = (u) => `<a href="${U.esc(u)}" target="_blank" rel="noopener">source</a>`;
        const fmt = (dt) => (typeof EvidenceList !== 'undefined' ? EvidenceList : require('./evidence-list.js')).fmtDate(dt);
        // Left: the creative (a playable video when downloaded locally, else the still). Right: the ad's
        // exact words, then our interpretation, kept visibly apart from what the ad says.
        const adCard = (x) => `<article class="ad-card" data-ad="${U.esc(x.id)}">${x.video ? `<video controls preload="none" poster="${U.esc(x.image)}" src="${U.esc(x.video)}"></video>` : `<img class="ad-media" src="${U.esc(x.image)}" alt="Ad ${U.esc(x.id)}" loading="lazy">`}<div class="ad-copy">${x.rank ? `<span class="ad-rank">#${x.rank} by impressions${x.impressions ? ` · ${U.esc(x.impressions)}` : ''}</span>` : ''}<blockquote class="ad-text">${U.esc(x.text)}</blockquote><p class="ad-meta">${x.headline ? `<b>${U.esc(x.headline)}</b> · ` : ''}${x.cta ? `${U.esc(x.cta)} · ` : ''}${x.started ? `started ${U.esc(fmt(x.started))}` : ''}</p><p><a href="${U.esc(x.url)}" target="_blank" rel="noopener">View this ad in the library ↗</a></p><div class="ad-read"><h4>Our read</h4><p><b>Hook:</b> ${U.esc(x.analysis.hook)}</p><p>${x.analysis.themes.map((t) => `<span class="theme">${U.esc(t)}</span>`).join(' ')}</p><p><b>Framing:</b> ${U.esc(x.analysis.framing)}</p><p><b>Appeals most to</b> ${U.chip(g, x.analysis.avatar)} ${U.esc(x.analysis.why)}</p></div></div></article>`;
        const ads = (a) => `<p>${U.esc(a.text)} <span class="muted">(${U.esc(a.status)})</span></p>${a.ads.length ? `<div class="ad-cards">${[...a.ads].sort((p, q) => (p.rank ?? Infinity) - (q.rank ?? Infinity)).map(adCard).join('')}</div>` : ''}${a.source ? `<p class="muted">${src(a.source)}</p>` : ''}`;
        return `<p><a href="${U.esc(n.url)}" target="_blank" rel="noopener">${U.esc(n.url)}</a> · researched in ${U.chip(g, n.research)}</p>${U.section('Pitch', `<blockquote>“${U.esc(n.pitch.quote)}”</blockquote><p class="muted">${src(n.pitch.source)}</p>`)}${U.section('Pricing', `<p><b>${U.esc(n.pricing.entry)}</b></p><p>${U.esc(n.pricing.text)}</p><p class="muted">Checked ${U.esc(n.pricing.checked || '')} · ${src(n.pricing.source)}</p>`)}${U.section('Revenue', `<p><b>${U.esc(n.revenue.headline)}</b></p><p>${U.esc(n.revenue.text)}</p>${(n.revenue.sources || []).map((u) => `<p class="muted">${src(u)}</p>`).join('')}`)}${U.section('Meta ads', ads(n.metaAds))}${U.section('TikTok ads', ads(n.tiktokAds))}${U.section('Notable', n.notable.length ? `<ul>${n.notable.map((x) => `<li>${U.esc(x.text)} <span class="muted">${src(x.source)}</span></li>`).join('')}</ul>` : '')}${U.section(`Compared with ${U.productName(g)}`, claims(g, n.vs, focus))}`;
      }
      case 'hypothesis': return `${U.section('Evidence', `<ul class="ev-trail">${H.newestFirst(g, n.evidence).map((ev) => H.evidenceItem(g, ev)).join('')}</ul>`)}${U.section('Ask next', (n.next || []).length ? `<ul>${n.next.map((q) => `<li>${U.esc(q)}</li>`).join('')}</ul>` : '')}`;
      case 'alternative': return `${U.section(`When ${U.productName(g)} wins`, claims(g, n.wins, focus))}${U.section('When it doesn’t', claims(g, n.loses, focus))}`;
      case 'source': return E.facts(g, n);
      case 'decision': return `${U.section('Why this evidence', (n.evidenceNotes || []).map((e) => `<div class="relation">${U.chip(g, e.sourceId)} <span>${U.esc(e.note)}</span></div>`).join(''))}${U.section('Decision', `<dl><dt>Now</dt><dd>${U.esc(n.current)}</dd><dt>Before</dt><dd>${U.esc(n.previous)}</dd><dt>Why</dt><dd>${U.esc(n.rationale)}</dd><dt>Revisit when</dt><dd>${U.esc(n.revisitWhen)}</dd><dt>Date</dt><dd>${U.esc(n.date)}</dd></dl>`)}${U.section('Claim', claims(g, [n.claim], focus))}`;
      case 'insight': return U.section('Findings', claims(g, n.findings, focus));
      case 'content-idea': return `<p><span class="pill">${U.esc(n.format)}</span></p>${U.section('Why it could work', claims(g, [n.claim], focus))}`;
      case 'channel': return `${U.section('Experiment', `<p>${U.esc(n.experiment)}</p>`)}${U.section('Claim', claims(g, [n.claim], focus))}`;
      case 'question': return `${n.ask ? `<p>Ask: ${U.chip(g, n.ask)}</p>` : ''}${U.section('Ask', n.prompt ? `<blockquote>${U.esc(n.prompt)}</blockquote>` : '')}${U.section('A useful answer', n.answerShape ? `<p>${U.esc(n.answerShape)}</p>` : '')}`;
      default: return n.claim ? U.section('Claim', claims(g, [n.claim], focus)) : '';
    }
  }

  function connections(g, id) {
    const groups = new Map();
    for (const e of [...g.edgesFrom(id), ...g.edgesTo(id)]) {
      if (e.relation === 'shapes') continue;
      const raw = S.RELATION_LABELS[e.relation];
      const label = raw[0].toUpperCase() + raw.slice(1);
      if (!groups.has(label)) groups.set(label, []);
      const other = e.from === id ? e.to : e.from;
      groups.get(label).push(`<div class="relation" data-edge="${U.esc(e.id)}">${U.chip(g, other)} ${U.badge(e.claim, g)} <button class="why" data-node="${U.esc(e.id)}">why?</button></div>`);
    }
    return [...groups].map(([label, rows]) => U.section(label, rows.join(''))).join('');
  }

  const decisions = (g, id) => U.section('Decisions that shape it', g.edgesTo(id).filter((e) => e.relation === 'shapes').map((e) => `<div class="relation" data-edge="${U.esc(e.id)}">${U.chip(g, e.from)}</div>`).join(''));
  const notes = (n) => (n.notes || []).map((x) => U.section(x.title, `<ul>${x.items.map((i) => `<li>${U.esc(i)}</li>`).join('')}</ul>`)).join('');

  function nodePage(g, n, focus, images, repo) {
    const [ic, label] = S.KIND_META[n.kind];
    return `<div class="insp-pad" data-node="${U.esc(n.id)}"><div class="eyebrow">${ic} ${U.esc(label)}</div><h1>${U.esc(n.title)}</h1><p class="lede">${U.esc(n.body)}</p>${body(g, n, focus, images, repo)}${connections(g, n.id)}${decisions(g, n.id)}${notes(n)}</div>`;
  }

  function edgePage(g, e) {
    return `<div class="insp-pad" data-edge="${U.esc(e.id)}"><div class="eyebrow">🔗 Connection</div><h1>${U.chip(g, e.from)} ${U.esc(S.RELATION_LABELS[e.relation])} ${U.chip(g, e.to)}</h1>${U.claimBlock(g, e.claim)}</div>`;
  }

  function detail(g, id, { images, repo = { url: '', sha: '' } }) {
    const hit = g.lookup(id);
    if (!hit) return `<div class="insp-pad"><p>“${U.esc(id)}” isn’t in the lens any more.</p></div>`;
    if (hit.type === 'node') return nodePage(g, hit.value, null, images, repo);
    if (hit.type === 'edge') return edgePage(g, hit.value);
    if (hit.owner === null) return `<div class="insp-pad"><div class="eyebrow">🎯 Purpose</div>${U.claimBlock(g, hit.value, { focused: true })}</div>`;
    const owner = g.lookup(hit.owner);
    return owner.type === 'edge' ? edgePage(g, owner.value) : nodePage(g, owner.value, id, images, repo);
  }
  return { detail };
})();
if (typeof module !== 'undefined') module.exports = Detail;
