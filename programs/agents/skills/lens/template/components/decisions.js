const Decisions = (() => {
  const U = typeof Ui !== 'undefined' ? Ui : require('./ui.js');
  const card = (d) => `<article class="card decision-card" data-node="${U.esc(d.id)}"><div class="eyebrow">${U.esc(d.date)}</div><button class="card-title" data-node="${U.esc(d.id)}">${U.esc(d.title)}</button><dl><dt>Now</dt><dd>${U.esc(d.current)}</dd><dt>Before</dt><dd>${U.esc(d.previous)}</dd><dt>Why</dt><dd>${U.esc(d.rationale)}</dd></dl></article>`;
  const view = (g) => `<div class="eyebrow">Decisions &amp; point of view</div><h2>What we’ve decided, and why</h2><div class="decisions">${[...g.nodesOfKind('decision')].sort((a, b) => b.date.localeCompare(a.date)).map(card).join('')}</div>`;
  return { view };
})();
if (typeof module !== 'undefined') module.exports = Decisions;
