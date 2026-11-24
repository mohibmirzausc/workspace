// What the product's marketing says: content pillars, each with why it should work and who it speaks
// to, and the content ideas under it with the surfaces they show and competitors on a similar angle.
const Marketing = (() => {
  const U = typeof Ui !== 'undefined' ? Ui : require('./ui.js');

  const linked = (g, id, relation, dir = 'from') => (dir === 'from'
    ? g.edgesFrom(id).filter((e) => e.relation === relation).map((e) => e.to)
    : g.edgesTo(id).filter((e) => e.relation === relation).map((e) => e.from));
  const chips = (g, label, ids) => (ids.length ? `<p class="chips"><span class="muted">${label}</span> ${ids.map((id) => U.chip(g, id)).join('')}</p>` : '');

  const idea = (g, n) => `<article class="card idea" data-node="${U.esc(n.id)}"><div class="row-head"><button class="card-title" data-node="${U.esc(n.id)}">${U.esc(n.title)}</button><span class="pill">${U.esc(n.format)}</span></div><p class="lede">${U.esc(n.body)}</p>${U.claimBlock(g, n.claim)}${chips(g, 'Speaks to', linked(g, n.id, 'speaks-to'))}${chips(g, 'Shows', linked(g, n.id, 'features'))}${chips(g, 'Like', linked(g, n.id, 'like'))}</article>`;

  function pillar(g, p) {
    const ideas = linked(g, p.id, 'under', 'to').map((id) => g.node(id));
    return `<section class="card alt" data-node="${U.esc(p.id)}"><div class="row-head"><button class="card-title" data-node="${U.esc(p.id)}">${U.esc(p.title)}</button><span class="chips">${linked(g, p.id, 'speaks-to').map((id) => U.chip(g, id)).join('')}</span></div><p class="lede">${U.esc(p.body)}</p>${U.claimBlock(g, p.claim)}<h4>Ideas</h4>${ideas.length ? ideas.map((n) => idea(g, n)).join('') : '<p class="muted">No ideas yet.</p>'}</section>`;
  }

  function view(g) {
    return `<div class="eyebrow">Marketing</div><h2>Content pillars</h2><p class="page-intro">The themes ${U.esc(U.productName(g))}’s content returns to, and the ideas under each. Every one is untested until it has reached people.</p>
<div class="alts-list">${g.nodesOfKind('pillar').map((p) => pillar(g, p)).join('')}</div>`;
  }
  return { view };
})();
if (typeof module !== 'undefined') module.exports = Marketing;
