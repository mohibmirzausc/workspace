// What people use instead of the product: kinds of alternative, each with when it would or wouldn't
// win, and the named products of that kind underneath as compact rows (full research opens in detail).
const Alternatives = (() => {
  const U = typeof Ui !== 'undefined' ? Ui : require('./ui.js');
  const LABEL = { active: '✓', none: '—', blocked: 'blocked', 'not-covered': 'not indexed' };
  const adChip = (name, a) => `<span class="ad-chip ${a.status}" title="${U.esc(a.text)}">${name} ${LABEL[a.status]}</span>`;

  const productsOf = (g, alt) => g.edgesTo(alt.id).filter((e) => e.relation === 'is-a').map((e) => g.node(e.from));

  // Counted from the research itself, so the headline moves when a product is added or re-checked.
  function adCounts(g) {
    const ps = g.nodesOfKind('product');
    return { products: ps.length, meta: ps.filter((p) => p.metaAds.status === 'active').length, tiktok: ps.filter((p) => p.tiktokAds.status === 'active').length };
  }

  const productRow = (p) => `<tr data-node="${U.esc(p.id)}"><th><button class="link" data-node="${U.esc(p.id)}">${U.esc(p.title)}</button></th><td>${U.esc(p.pitch.quote)}</td><td>${U.esc(p.pricing.entry)}</td><td>${U.esc(p.revenue.headline)}</td><td>${adChip('Meta', p.metaAds)} ${adChip('TikTok', p.tiktokAds)}</td></tr>`;

  function row(g, alt) {
    const ps = productsOf(g, alt);
    return `<section class="card alt" data-node="${U.esc(alt.id)}"><div class="row-head"><button class="card-title" data-node="${U.esc(alt.id)}">${U.esc(alt.title)}</button></div><p class="lede">${U.esc(alt.body)}</p><div class="cols2"><div><h4>When ${U.esc(U.productName(g))} wins</h4>${alt.wins.map((c) => U.claimBlock(g, c)).join('')}</div><div><h4>When it doesn’t</h4>${alt.loses.map((c) => U.claimBlock(g, c)).join('')}</div></div>${ps.length ? `<h4>Products</h4><div class="wrap"><table class="products"><thead><tr><th>Product</th><th>Pitch</th><th>Entry price</th><th>Revenue / funding</th><th>Ads</th></tr></thead><tbody>${ps.map(productRow).join('')}</tbody></table></div>` : ''}</section>`;
  }

  function view(g) {
    const c = adCounts(g);
    return `<div class="eyebrow">Alternatives</div><h2>Instead of…</h2><p class="page-intro">What people already use for the same job, where ${U.esc(U.productName(g))} would or wouldn’t win, and the named products in each kind.</p>
<div class="findings"><span><b>${c.meta} of ${c.products} products run Meta ads</b></span><span><b>${c.tiktok} of ${c.products} run TikTok ads</b></span></div>
<div class="alts-list">${g.nodesOfKind('alternative').map((a) => row(g, a)).join('')}</div>`;
  }
  return { view, adCounts, productsOf };
})();
if (typeof module !== 'undefined') module.exports = Alternatives;
