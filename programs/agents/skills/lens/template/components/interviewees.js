// components/interviewees.js
const Interviewees = (() => {
  const U = typeof Ui !== 'undefined' ? Ui : require('./ui.js');
  const EL = typeof EvidenceList !== 'undefined' ? EvidenceList : require('./evidence-list.js');

  const avatarsOf = (g, id) => g.edgesFrom(id).filter((e) => e.relation === 'fits').map((e) => U.chip(g, e.to)).join('');
  const conversations = (g, id) => `<ol class="conversations">${EL.interviewsOf(g.nodesOfKind('source'), id).map((s) => `<li><button data-node="${U.esc(s.id)}"><span class="ev-date">${U.esc(EL.fmtDate(s.date))}</span> ${U.esc(s.title)}</button>${(s.takeaways || []).length ? `<ul>${s.takeaways.map((t) => `<li>${U.esc(t)}</li>`).join('')}</ul>` : ''}</li>`).join('')}</ol>`;
  const card = (g, n) => `<article class="card person-card" data-node="${U.esc(n.id)}"><button class="card-title" data-node="${U.esc(n.id)}">👤 ${U.esc(n.title)}</button><p>${U.esc(n.body)}</p><div class="chips">${avatarsOf(g, n.id)}</div></article>`;
  const view = (g) => `<div class="eyebrow">The people we’ve talked to</div><h2>Interviewees</h2><div class="grid">${g.nodesOfKind('person').map((n) => card(g, n)).join('')}</div>`;
  return { view, conversations, avatarsOf };
})();
if (typeof module !== 'undefined') module.exports = Interviewees;
