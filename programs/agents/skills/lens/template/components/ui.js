// components/ui.js
// Small HTML helpers shared by every view. The claim badge is the lens's one visual rule:
// observed solid, view outlined, hypothesis dashed, confidence as dots.
const Ui = (() => {
  const S = typeof Schema !== 'undefined' ? Schema : require('./schema.js');
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  // The product and the owner come from model.json (`title`, and the `owner` person's title).
  const productName = (g) => g?.model?.title || 'the product';
  const ownerName = (g) => (g && g.node(g.model.owner)?.title) || 'Owner';
  const claimLabel = (kind, g) => (kind === 'view' && g ? `${ownerName(g)}’s view` : S.CLAIM_LABELS[kind] || kind);
  const claimHint = (kind, g) => (kind === 'view' && g ? `${ownerName(g)}’s interpretation, not yet checked with anyone` : S.CLAIM_HINTS[kind] || '');
  const badge = (c, g) => `<span class="claim-badge" data-claim-kind="${esc(c.kind)}" title="${esc(claimHint(c.kind, g))}">${esc(claimLabel(c.kind, g))}</span>`;
  const PLURALS = { person: 'people' };
  const plural = (n, word) => `${n} ${n === 1 ? word : PLURALS[word] || `${word}s`}`;
  // Evidence sits behind a count, so a page of claims stays readable.
  const sources = (g, evidence) => { const n = new Set(evidence.map((ev) => ev.source)).size; return n ? `<details class="sources"><summary>Evidence (${plural(n, 'source')})</summary><div class="evidence">${evidence.map((ev) => evidenceLine(g, ev)).join('')}</div></details>` : ''; };
  const icon = (kind) => (S.KIND_META[kind] || ['•'])[0];
  const chip = (g, id) => { const n = g.node(id); return n ? `<button class="chip" data-node="${esc(id)}">${icon(n.kind)} ${esc(n.title)}</button>` : ''; };
  const evidenceLine = (g, ev) => { const s = g.node(ev.source); return `<button class="ev" data-node="${esc(ev.source)}">📎 ${esc(s ? s.title : ev.source)}${ev.at ? ` · ${esc(ev.at)}` : ''}</button>`; };
  const claimBlock = (g, c, { focused = false, bare = false } = {}) => `<div class="claim${focused ? ' focused' : ''}${bare ? ' bare' : ''}" data-claim="${esc(c.id)}"><span class="claim-head" data-cmt-key="claim:${esc(c.id)}">${bare ? '' : badge(c, g)}</span><p>${esc(c.text)}</p>${sources(g, c.evidence || [])}${c.next ? `<p class="next">❓ Next: ${esc(c.next)}</p>` : ''}</div>`;
  const section = (title, body) => (body ? `<section class="sect"><h2>${esc(title)}</h2>${body}</section>` : '');
  return { esc, badge, productName, ownerName, claimLabel, plural, icon, chip, evidenceLine, claimBlock, section };
})();
if (typeof module !== 'undefined') module.exports = Ui;
