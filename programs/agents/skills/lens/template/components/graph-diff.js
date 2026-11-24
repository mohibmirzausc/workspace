// components/graph-diff.js
// What changed between two models, by id, and the review layer diff.mjs injects into index.html.
const GraphDiff = (() => {
  const G = typeof Graph !== 'undefined' ? Graph : require('./graph.js');
  const MARKER = '<!--LENS-V2-DIFF-->';

  // id → { type, title, value } with each node's claims replaced by their ids.
  function flatten(model) {
    const g = G.createGraph(model);
    const out = new Map();
    for (const n of g.nodes()) {
      const skeleton = JSON.parse(JSON.stringify(n));
      for (const { path } of g.claimsOf(n)) {
        const keys = path.split('.');
        const parent = keys.slice(0, -1).reduce((o, k) => o[k], skeleton);
        const last = keys.at(-1);
        // Claims are diffed on their own; an owner changes only when its own fields do.
        delete parent[last];
      }
      out.set(n.id, { type: 'node', title: n.title, value: skeleton });
    }
    for (const e of g.edges()) out.set(e.id, { type: 'edge', title: `${e.from} ${e.relation} ${e.to}`, value: { ...e, claim: e.claim?.id } });
    for (const { claim: c } of g.allClaims()) out.set(c.id, { type: 'claim', title: c.text, value: c });
    return out;
  }

  function diffGraphs(prev, next) {
    const a = flatten(prev); const b = flatten(next);
    const added = []; const changed = []; const removed = [];
    for (const [id, x] of b) {
      const old = a.get(id);
      if (!old) { added.push({ id, type: x.type, title: x.title }); continue; }
      const keys = [...new Set([...Object.keys(old.value), ...Object.keys(x.value)])];
      const fields = keys.filter((k) => JSON.stringify(old.value[k]) !== JSON.stringify(x.value[k]));
      if (fields.length) changed.push({ id, type: x.type, title: x.title, fields });
    }
    for (const [id, x] of a) if (!b.has(id)) removed.push({ id, type: x.type, title: x.title });
    return { added, changed, removed };
  }

  const summary = (d, rev) => `Changes since ${rev}: ${d.added.length} added, ${d.changed.length} changed, ${d.removed.length} removed\n${[
    ...d.added.map((x) => `  + ${x.type} ${x.id}`),
    ...d.changed.map((x) => `  ~ ${x.type} ${x.id} (${x.fields.join(', ')})`),
    ...d.removed.map((x) => `  - ${x.type} ${x.id} — ${x.title}`),
  ].map((l) => `${l}\n`).join('')}`;

  const esc = (v) => String(v ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);

  // The banner is plain HTML: each added or changed row is a button the lens's own click handler
  // opens (data-node); removed rows can't be opened, so they are text.
  function reviewLayer(d, rev) {
    const ids = JSON.stringify({ added: d.added.map((x) => x.id), changed: d.changed.map((x) => x.id) }).replaceAll('<', '\\u003c');
    const row = (cls, sign, x) => `<li class="${cls}"><button data-node="${esc(x.id)}"><span class="kind">${sign} ${esc(x.type)}</span> · ${esc(x.title)}</button></li>`;
    const rows = [...d.added.map((x) => row('added', '+', x)), ...d.changed.map((x) => row('changed', '~', x)), ...d.removed.map((x) => `<li class="removed"><span class="kind">− ${esc(x.type)}</span> · ${esc(x.title)}</li>`)].join('');
    return `${MARKER}
<style>.lens-added{outline:3px solid #2f9e5b!important;outline-offset:2px;border-radius:6px}.lens-changed{outline:3px solid #e0b100!important;outline-offset:2px;border-radius:6px}
#lens-diff-banner{position:fixed;bottom:12px;right:12px;z-index:99999;max-width:440px;max-height:45vh;overflow:auto;background:#242b29;color:#fff;font:12px/1.45 system-ui;padding:10px 14px;border-radius:8px}
#lens-diff-banner ol{list-style:none;margin:8px 0 0;padding:0}#lens-diff-banner li{margin:0 0 8px}
#lens-diff-banner button{all:unset;cursor:pointer;display:block}#lens-diff-banner button:hover{text-decoration:underline}
#lens-diff-banner .added .kind{color:#8fe0ad}#lens-diff-banner .changed .kind{color:#f5d76e}#lens-diff-banner .removed .kind{color:#ff8a80}</style>
<div id="lens-diff-banner"><b>Changes since ${esc(rev)}</b> · green added, yellow changed, red removed · rebuild to clear<ol>${rows}</ol></div>
<script>(()=>{const D=${ids};
const mark=()=>{for(const [cls,ids] of [['lens-added',D.added],['lens-changed',D.changed]])for(const id of ids)document.querySelectorAll('#sheet [data-node="'+id+'"],#sheet [data-claim="'+id+'"],#sheet [data-edge="'+id+'"]').forEach(el=>el.classList.add(cls))};
new MutationObserver(()=>{clearTimeout(window.__lensDiff);window.__lensDiff=setTimeout(mark,50)}).observe(document.getElementById('sheet'),{childList:true,subtree:true});
addEventListener('load',mark);})();</script>
`;
  }
  return { MARKER, diffGraphs, summary, reviewLayer };
})();
if (typeof module !== 'undefined') module.exports = GraphDiff;
