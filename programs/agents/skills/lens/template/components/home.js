// Home: what the product is for, the hypotheses we are proving now, and the loop they sit in.
const Home = (() => {
  const U = typeof Ui !== 'undefined' ? Ui : require('./ui.js');
  const S = typeof Schema !== 'undefined' ? Schema : require('./schema.js');
  const CF = typeof Confidence !== 'undefined' ? Confidence : require('./confidence.js');
  const SHOWN = 3;
  const LEVEL_LABEL = { untested: 'Untested', weak: 'Weak', emerging: 'Emerging', strong: 'Strong', contested: 'Contested' };

  // Newest first: by the source's date, then by the order evidence was logged (later = newer).
  const newestFirst = (g, evidence) => evidence.map((ev, i) => ({ ev, i, date: g.node(ev.source)?.date || '' }))
    .sort((a, b) => b.date.localeCompare(a.date) || b.i - a.i).map((x) => x.ev);

  function meter(a) {
    const filled = a.level === 'contested' ? 0 : CF.LEVELS.indexOf(a.level);
    return `<div class="meter" data-level="${a.level}" title="Computed from the evidence"><span class="bars">${[1, 2, 3].map((i) => `<i class="${i <= filled ? 'on' : ''}"></i>`).join('')}</span><b>${LEVEL_LABEL[a.level]}</b></div>`;
  }

  function evidenceItem(g, ev) {
    const s = g.node(ev.source);
    return `<li class="${ev.stance}"><span class="stance" title="${ev.stance}">${ev.stance === 'supports' ? '＋' : '−'}</span><div><button class="ev" data-node="${U.esc(ev.source)}">📎 ${U.esc(s ? s.title : ev.source)} · ${U.esc(ev.at)}</button>${ev.note ? `<p class="ev-note">${U.esc(ev.note)}</p>` : ''}</div></li>`;
  }

  function focusCard(g, h) {
    const a = CF.assess(g, h);
    const all = newestFirst(g, h.evidence);
    const rest = all.slice(SHOWN);
    return `<article class="card focus" data-node="${U.esc(h.id)}"><div class="row-head"><span class="focus-no">${h.focus}</span>${meter(a)}</div><button class="card-title" data-node="${U.esc(h.id)}">${U.esc(h.title)}</button><p>${U.esc(h.body)}</p><p class="counts">${U.plural(a.people.for, 'person')} · ${U.plural(a.sources.for, 'source')} · ${a.sources.against} against</p><h4>Evidence so far</h4><ul class="ev-trail">${all.slice(0, SHOWN).map((ev) => evidenceItem(g, ev)).join('') || '<li class="muted">None logged yet.</li>'}</ul>${rest.length ? `<details><summary>+${rest.length} more</summary><ul class="ev-trail">${rest.map((ev) => evidenceItem(g, ev)).join('')}</ul></details>` : ''}${(h.next || []).length ? `<h4>Ask next</h4><ul class="asks">${h.next.map((q) => `<li>${U.esc(q)}</li>`).join('')}</ul>` : ''}</article>`;
  }

  function stepCard(g, step) {
    const surfaces = g.edgesTo(step.id).filter((e) => e.relation === 'implements').map((e) => U.chip(g, e.from)).join('');
    return `<article class="card step" data-node="${U.esc(step.id)}"><span class="step-no">${step.order}</span><button class="card-title" data-node="${U.esc(step.id)}">${U.esc(step.title)}</button><p>${U.esc(step.body)}</p><div class="claim-inline" data-claim="${U.esc(step.claim.id)}">${U.badge(step.claim, g)}</div><div class="chips">${surfaces}</div></article>`;
  }

  function others(g, list) {
    const groups = new Map();
    for (const h of list) { const k = h.group ? S.HYPOTHESIS_GROUPS[h.group] : 'Product'; if (!groups.has(k)) groups.set(k, []); groups.get(k).push(h); }
    return `<details class="disclosure"><summary>Other hypotheses (${list.length})</summary>${[...groups].map(([title, hs]) => `<h4>${U.esc(title)}</h4><ul class="others">${hs.map((h) => `<li data-node="${U.esc(h.id)}"><button data-node="${U.esc(h.id)}">🧪 ${U.esc(h.title)}</button> <small>${U.plural(new Set(h.evidence.map((ev) => ev.source)).size, 'source')}</small></li>`).join('')}</ul>`).join('')}</details>`;
  }

  function view(g) {
    const hs = g.nodesOfKind('hypothesis');
    const focus = hs.filter((h) => h.focus).sort((a, b) => a.focus - b.focus).slice(0, 3);
    const steps = [...g.nodesOfKind('loop-step')].sort((a, b) => a.order - b.order);
    return `<div class="eyebrow">What ${U.esc(U.productName(g))} is for</div><div class="purpose">${U.claimBlock(g, g.model.purpose)}</div>
<h3 class="section-label">What we’re proving now</h3><div class="focus-grid">${focus.map((h) => focusCard(g, h)).join('')}</div>
<h3 class="section-label">The loop · a hypothesis until the evidence says otherwise</h3><div class="loop">${steps.map((s) => stepCard(g, s)).join('<span class="arrow" aria-hidden="true">→</span>')}</div>
${others(g, hs.filter((h) => !focus.includes(h)))}`;
  }
  return { view, newestFirst, evidenceItem };
})();
if (typeof module !== 'undefined') module.exports = Home;
