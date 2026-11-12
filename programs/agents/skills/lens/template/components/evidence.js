// components/evidence.js
const Evidence = (() => {
  const U = typeof Ui !== 'undefined' ? Ui : require('./ui.js');
  const EL = typeof EvidenceList !== 'undefined' ? EvidenceList : require('./evidence-list.js');

  // One full-width row per source: the summary row scans as a table; opening it shows what the source
  // is and its takeaways, and only the button leaves the list.
  const item = (g, n, personTitle, cited) => `<li class="ev-item" data-node="${U.esc(n.id)}"><details><summary><span class="ev-date">${U.esc(EL.fmtDate(n.date))}</span><span class="ev-title">${U.esc(n.title)}</span><span class="ev-people">${U.esc((n.people || []).map(personTitle).join(', '))}</span><span class="ev-cited">${cited(n.id)}</span><span class="tag">${U.esc(n.tag)}</span></summary><div class="ev-body"><p>${U.esc(n.body)}</p>${(n.takeaways || []).length ? `<ul>${n.takeaways.map((t) => `<li>${U.esc(t)}</li>`).join('')}</ul>` : ''}<button class="ev-open" data-node="${U.esc(n.id)}">Open full evidence →</button></div></details></li>`;

  function view(g, state) {
    const personTitle = (id) => g.node(id)?.title || id;
    const { total, tagCounts, rows } = EL.evidenceView(g.nodesOfKind('source'), state, personTitle);
    const tags = [['all', total], ...tagCounts];
    const cited = (id) => { const n = g.citationsOf(id).length; return `cited by ${n} claim${n === 1 ? '' : 's'}`; };
    return `<h2>Evidence</h2><input id="search" type="search" placeholder="Search by title, person, tag or month…" value="${U.esc(state.search)}">
<div class="filters">${tags.map(([t, n]) => `<button data-tag="${U.esc(t)}" aria-pressed="${state.tag === t}">${t === 'all' ? 'All' : U.esc(t)} <small>${n}</small></button>`).join('')}</div>
<div class="filters">${EL.SORTS.map(([k, label]) => `<button data-sort="${k}" aria-pressed="${state.sort === k}">${label}</button>`).join('')}</div>
<ol class="ev-items">${rows.map((n) => item(g, n, personTitle, cited)).join('') || '<li class="muted">No matching evidence.</li>'}</ol>`;
  }

  // The detail panel's facts for one source, and the claims that lean on it.
  const facts = (g, n) => `${U.section('About this source', `<p>${U.esc(EvidenceList_fmt(n))}</p>${n.evidenceType ? `<p>${U.esc(n.evidenceType)}</p>` : ''}${n.population ? `<p class="muted">Population: ${U.esc(n.population)}</p>` : ''}${n.statistics ? `<table class="stats"><tbody>${n.statistics.map((r) => `<tr><td>${U.esc(r.platform)}</td><td>${r.percent}%</td></tr>`).join('')}</tbody></table>` : ''}${n.inspectedRevision ? `<p class="muted">Code inspected at <code>${U.esc(n.inspectedRevision)}</code></p>` : ''}${n.locator ? `<p><code>${U.esc(n.locator)}</code></p>` : ''}${n.referenceUrl ? `<p><a href="${U.esc(n.referenceUrl)}" target="_blank" rel="noopener">Open the original</a></p>` : ''}`)}
${U.section('What we heard', (n.takeaways || []).length ? `<ul>${n.takeaways.map((t) => `<li>${U.esc(t)}</li>`).join('')}</ul>` : '')}
${U.section('Claims that cite it', g.citationsOf(n.id).map((c) => U.claimBlock(g, c.claim)).join(''))}`;
  const EvidenceList_fmt = (n) => [EL.fmtDate(n.date), n.tag, n.author].filter(Boolean).join(' · ');
  return { view, facts };
})();
if (typeof module !== 'undefined') module.exports = Evidence;
