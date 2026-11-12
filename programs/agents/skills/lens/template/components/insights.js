// Market insights: what outside research says about the product's market, each finding labelled like any
// claim, and the avatars, problems, pillars or hypotheses it bears on.
const Insights = (() => {
  const U = typeof Ui !== 'undefined' ? Ui : require('./ui.js');

  function card(g, n) {
    const on = g.edgesFrom(n.id).filter((e) => e.relation === 'bears-on').map((e) => U.chip(g, e.to)).join('');
    return `<section class="card alt" data-node="${U.esc(n.id)}"><div class="row-head"><button class="card-title" data-node="${U.esc(n.id)}">${U.esc(n.title)}</button></div><p class="lede">${U.esc(n.body)}</p>${n.findings.map((c) => U.claimBlock(g, c)).join('')}${on ? `<p class="chips"><span class="muted">Bears on</span> ${on}</p>` : ''}</section>`;
  }

  function view(g) {
    return `<div class="eyebrow">Market insights</div><h2>Market insights</h2><p class="page-intro">What outside research says about the people ${U.esc(U.productName(g))} is for, and what in the lens it bears on. A trend in the news is not evidence that our avatars feel it.</p>
<div class="alts-list">${g.nodesOfKind('insight').map((n) => card(g, n)).join('')}</div>`;
  }
  return { view };
})();
if (typeof module !== 'undefined') module.exports = Insights;
