// components/avatars.js
const Avatars = (() => {
  const U = typeof Ui !== 'undefined' ? Ui : require('./ui.js');
  const S = typeof Schema !== 'undefined' ? Schema : require('./schema.js');
  const TITLES = { background: 'Background', context: 'Context', goals: 'Goals', frustrations: 'Frustrations', behaviors: 'Behaviors' };

  const art = (n, images) => (images[n.id]
    ? `<img class="avatar-art" src="${U.esc(images[n.id])}" alt="${U.esc(n.imageAlt || n.title)}">`
    : `<div class="avatar-art avatar-symbol" role="img" aria-label="${U.esc(n.title)}">${U.esc(n.avatarIcon || '🧑‍🚀')}</div>`);

  function card(g, n, images) {
    const problems = g.edgesFrom(n.id).filter((e) => e.relation === 'has').map((e) => U.chip(g, e.to)).join('');
    const people = g.edgesTo(n.id).filter((e) => e.relation === 'fits').map((e) => U.chip(g, e.from)).join('');
    return `<article class="card avatar-card" data-node="${U.esc(n.id)}">${art(n, images)}<div class="avatar-copy"><button class="card-title" data-node="${U.esc(n.id)}">${U.esc(n.title)}</button><p>${U.esc(n.body)}</p><div class="chips">${problems}</div><div class="chips people">${people}</div></div></article>`;
  }

  function personaMap(g, n, focus) {
    return `<div class="persona-map">${S.PERSONA_SECTIONS.map((k) => {
      const v = n.personaMap[k];
      return U.section(TITLES[k], (Array.isArray(v) ? v : [v]).map((c) => U.claimBlock(g, c, { focused: c.id === focus })).join(''));
    }).join('')}</div>`;
  }

  // The journey grid: stages across, experience rows down. Blank cells are a scaffold until evidence
  // fills them; each row heading is commentable (app.js registers `.journey-map tbody th`).
  function journeyMap(g, n, focus) {
    const jm = n.journeyMap;
    if (!jm) return '';
    const cell = (s, r) => {
      const key = `${s.id}:${r.id}`;
      const list = jm.cells?.[key] || [];
      const anchor = `data-cmt-key="journey:${U.esc(key)}"`;
      return list.length ? `<td ${anchor}>${list.map((c) => U.claimBlock(g, c, { focused: c.id === focus })).join('')}</td>` : `<td class="unmapped" ${anchor}>${U.esc(jm.hints?.[key] || '—')}</td>`;
    };
    const mapped = Object.values(jm.cells || {}).some((l) => l.length);
    return `<section class="journey-map"><h2>🗺️ Journey</h2><p class="muted">${mapped ? 'Partly mapped from evidence · stage labels are proposed.' : 'Not mapped yet · stage labels are proposed. We’ll use this to develop onboarding together.'}</p><div class="journey-scroll"><table><caption>Journey for ${U.esc(n.title)} · blank cells have not been researched or agreed</caption><thead><tr><th scope="col">Experience</th>${jm.stages.map((st) => `<th scope="col">${U.esc(st.title)}</th>`).join('')}</tr></thead><tbody>${jm.rows.map((r) => `<tr><th scope="row">${U.esc(r.title)}</th>${jm.stages.map((st) => cell(st, r)).join('')}</tr>`).join('')}</tbody></table></div></section>`;
  }

  const view = (g, { images }) => `<div class="eyebrow">Working avatars · still evolving</div><h2>Who are we building for?</h2><div class="grid">${g.nodesOfKind('avatar').map((n) => card(g, n, images)).join('')}</div>`;
  return { view, personaMap, journeyMap, art };
})();
if (typeof module !== 'undefined') module.exports = Avatars;
