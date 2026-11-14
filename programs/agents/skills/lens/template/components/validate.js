// components/validate.js
// The integrity rules (spec §1). Each error starts with the id it concerns so it can be found.
const Validate = (() => {
  const S = typeof Schema !== 'undefined' ? Schema : require('./schema.js');
  const G = typeof Graph !== 'undefined' ? Graph : require('./graph.js');
  const ID = /^[a-z][a-z0-9-]*$/;
  const DATE = /^\d{4}(-\d{2}(-\d{2})?)?$/;
  const blank = (v) => typeof v !== 'string' || !v.trim();

  // fileExists takes a path relative to the repo root; lensDir is the lens folder relative to that root.
  function validate(model, { fileExists, lensDir = '.' }) {
    const inLens = (rel) => (lensDir === '.' || lensDir === '' ? rel : `${lensDir}/${rel}`);
    const errors = [];
    const err = (id, msg) => errors.push(`${id}: ${msg}`);
    const g = G.createGraph(model);
    const nodes = g.nodes();
    const OWNER = model.owner;
    if (g.node(OWNER)?.kind !== 'person') err('owner', 'owner must name the person whose views the lens records');

    // 1. ids
    const seen = new Set();
    for (const id of [...nodes.map((n) => n.id), ...g.edges().map((e) => e.id), ...g.allClaims().map((c) => c.claim.id)]) {
      if (typeof id !== 'string' || !ID.test(id)) err(id, 'id must match ^[a-z][a-z0-9-]*$');
      else if (seen.has(id)) err(id, 'duplicate id');
      seen.add(id);
    }

    // 3. fields per kind
    for (const n of nodes) {
      const spec = S.KINDS[n.kind];
      if (!spec) { err(n.id, `unknown kind ${n.kind}`); continue; }
      for (const f of spec.required) {
        if (n[f] === undefined || (typeof n[f] === 'string' && blank(n[f]))) err(n.id, `missing ${f}`);
      }
      for (const f of Object.keys(n)) if (!spec.required.includes(f) && !spec.optional.includes(f)) err(n.id, `unexpected field ${f}`);
      if (n.kind === 'surface' && n.shipped !== undefined && typeof n.shipped !== 'boolean') err(n.id, 'shipped must be true or false');
      if (n.kind === 'channel' && n.phase !== undefined && !S.CHANNEL_PHASES.includes(n.phase)) err(n.id, `phase must be one of ${S.CHANNEL_PHASES.join(', ')}`);
      if (n.kind === 'avatar' && n.personaMap) {
        for (const k of S.PERSONA_SECTIONS) {
          const v = n.personaMap[k];
          const many = ['goals', 'frustrations', 'behaviors'].includes(k);
          if (many ? !Array.isArray(v) || !v.length : !v || Array.isArray(v)) err(n.id, `personaMap.${k} must be ${many ? 'a non-empty list of claims' : 'one claim'}`);
        }
      }
      if (n.kind === 'avatar' && n.journeyMap !== undefined) {
        const jm = n.journeyMap;
        const ids = {};
        for (const axis of ['stages', 'rows']) {
          ids[axis] = new Set();
          for (const x of Array.isArray(jm[axis]) ? jm[axis] : []) {
            if (ids[axis].has(x.id)) err(n.id, `journey ${axis.slice(0, -1)} ${x.id} is duplicated`);
            if (blank(x.title)) err(n.id, `journey ${axis.slice(0, -1)} ${x.id} needs a title`);
            ids[axis].add(x.id);
          }
        }
        for (const key of Object.keys(jm.hints || {})) {
          const [stage, row] = key.split(':');
          if (!ids.stages.has(stage) || !ids.rows.has(row)) err(n.id, `journey hint ${key} names an unknown stage or row`);
        }
        for (const [key, list] of Object.entries(jm.cells || {})) {
          const [stage, row] = key.split(':');
          if (!ids.stages.has(stage) || !ids.rows.has(row)) err(n.id, `journey cell ${key} names an unknown stage or row`);
          if (!Array.isArray(list)) err(n.id, `journey cell ${key} must be a list of claims`);
        }
      }
      if (n.notes !== undefined && (!Array.isArray(n.notes) || n.notes.some((x) => blank(x.title) || !Array.isArray(x.items)))) err(n.id, 'notes must be a list of { title, items }');
    }

    // claims (rules 2–6)
    const sourceById = new Map(nodes.filter((n) => n.kind === 'source').map((n) => [n.id, n]));
    for (const { claim: c } of g.allClaims()) {
      if (blank(c.text)) err(c.id, 'missing text');
      if (!S.CLAIM_KINDS.includes(c.kind)) err(c.id, `kind must be one of ${S.CLAIM_KINDS.join(', ')}`);
      for (const k of Object.keys(c)) if (!S.CLAIM_FIELDS_ALLOWED.includes(k)) err(c.id, `unexpected claim field ${k}`);
      if (c.next !== undefined && blank(c.next)) err(c.id, 'next must be a question');
      const evidence = Array.isArray(c.evidence) ? c.evidence : [];
      if (!Array.isArray(c.evidence)) err(c.id, 'evidence must be a list');
      for (const ev of evidence) {
        if (!sourceById.has(ev.source)) err(c.id, `unknown source ${ev.source}`);
        else if (c.kind === 'observed' && blank(ev.at)) err(c.id, `evidence from ${ev.source} needs "at"`);
      }
      if (c.kind === 'observed' && !evidence.length) err(c.id, 'observed claim needs evidence');
      if (c.kind === 'view' && !evidence.some((ev) => (sourceById.get(ev.source)?.people || []).includes(OWNER))) err(c.id, `owner’s view needs a source whose people include ${OWNER}`);
    }

    // hypotheses: their evidence carries a stance; at most one hypothesis per focus slot
    const focus = {};
    for (const h of nodes.filter((n) => n.kind === 'hypothesis')) {
      for (const ev of Array.isArray(h.evidence) ? h.evidence : []) {
        if (!sourceById.has(ev.source)) err(h.id, `unknown source ${ev.source}`);
        else if (blank(ev.at)) err(h.id, `evidence from ${ev.source} needs "at"`);
        if (!S.STANCES.includes(ev.stance)) err(h.id, 'evidence stance must be supports or contradicts');
      }
      if (h.focus !== undefined) {
        if (![1, 2, 3].includes(h.focus)) err(h.id, 'focus must be 1, 2 or 3');
        else if (focus[h.focus]) err(h.id, `focus ${h.focus} is already taken by ${focus[h.focus]}`);
        else focus[h.focus] = h.id;
      }
      if (h.group !== undefined && !Object.hasOwn(S.HYPOTHESIS_GROUPS, h.group)) err(h.id, `group must be one of ${Object.keys(S.HYPOTHESIS_GROUPS).join(', ')}`);
      if (h.next !== undefined && (!Array.isArray(h.next) || h.next.some(blank))) err(h.id, 'next must be a list of questions');
    }

    for (const dn of nodes.filter((x) => x.kind === 'decision')) {
      for (const e of dn.evidenceNotes || []) if (!sourceById.has(e.sourceId)) err(dn.id, `evidence note names unknown source ${e.sourceId}`);
    }

    // products: every market fact carries a URL; ad findings use a closed status
    const url = (v) => typeof v === 'string' && /^https?:\/\//.test(v);
    for (const p of nodes.filter((n) => n.kind === 'product')) {
      if (sourceById.get(p.research) === undefined) err(p.id, 'research must name a source');
      if (!url(p.url)) err(p.id, 'url must be an http(s) URL');
      if (!url(p.pitch?.source) || blank(p.pitch?.quote)) err(p.id, 'pitch needs a quote and an http(s) URL source');
      if (!url(p.pricing?.source)) err(p.id, 'pricing.source must be an http(s) URL');
      if (blank(p.pricing?.entry)) err(p.id, 'pricing needs a short entry price');
      if (blank(p.revenue?.headline)) err(p.id, 'revenue needs a short headline');
      const rev = p.revenue || {};
      if (rev.text !== 'Not public' && !(Array.isArray(rev.sources) && rev.sources.length && rev.sources.every(url))) err(p.id, 'revenue needs a source unless it is "Not public"');
      for (const k of ['metaAds', 'tiktokAds']) {
        const a = p[k] || {};
        if (!S.AD_STATUSES.includes(a.status)) err(p.id, `${k}.status must be one of ${S.AD_STATUSES.join(', ')}`);
        const ranks = new Set();
        const ranked = (a.ads || []).filter((x) => x.rank !== undefined).length;
        if (ranked && ranked !== a.ads.length) err(p.id, `${k} ranks every ad by impressions or none`);
        for (const ad of Array.isArray(a.ads) ? a.ads : []) {
          const who = `ad ${ad.id}`;
          // Rank = position in the library's highest-impressions-first order, the one ordering every ad has.
          if (ad.rank !== undefined) {
            if (!Number.isInteger(ad.rank) || ad.rank < 1) err(p.id, `${who} rank by impressions must be a positive whole number`);
            else if (ranks.has(ad.rank)) err(p.id, `${who} shares rank ${ad.rank} with another ad`);
            ranks.add(ad.rank);
          }
          if (typeof ad.url !== 'string' || !/^https:\/\/(www\.facebook\.com\/ads\/library\/\?id=\d+|library\.tiktok\.com\/ads\/detail\/\?ad_id=\d+)/.test(ad.url)) err(p.id, `${who} needs its own library permalink`);
          if (blank(ad.text)) err(p.id, `${who} needs its exact text`);
          if (typeof ad.image !== 'string' || !ad.image.startsWith('assets/') || ad.image.includes('..')) err(p.id, `${who} image must be under assets/`);
          else if (!fileExists(inLens(ad.image))) err(p.id, `${who} image ${ad.image} does not exist`);
          // Videos are gitignored (local playback only), so only their place is checked, not their presence.
          if (ad.video !== undefined && (typeof ad.video !== 'string' || !/^assets\/ads\/[^.]+\.mp4$/.test(ad.video))) err(p.id, `${who} video must be an .mp4 under assets/ads/`);
          const an = ad.analysis || {};
          if (blank(an.hook) || blank(an.framing) || blank(an.why)) err(p.id, `${who} analysis needs a hook, framing and why`);
          if (!Array.isArray(an.themes) || !an.themes.length || an.themes.some((t) => !S.AD_THEMES.includes(t))) err(p.id, `${who} themes must come from ${S.AD_THEMES.join(', ')}`);
          if (g.node(an.avatar)?.kind !== 'avatar') err(p.id, `${who} must name the avatar it appeals to`);
        }
      }
      for (const x of Array.isArray(p.notable) ? p.notable : []) if (!url(x.source)) err(p.id, 'notable.source must be an http(s) URL');
    }

    // 2 + 7. edges
    for (const e of g.edges()) {
      const from = g.node(e.from); const to = g.node(e.to);
      if (!from) err(e.id, `unknown node ${e.from}`);
      if (!to) err(e.id, `unknown node ${e.to}`);
      if (!e.claim) err(e.id, 'missing claim');
      if (from && to && !S.relationAllowed(from.kind, e.relation, to.kind)) err(e.id, `${from.kind} —${e.relation}→ ${to.kind} is not allowed`);
    }

    // 2. people and ask
    for (const n of nodes) {
      if (n.people !== undefined && (!Array.isArray(n.people) || n.people.some((p) => g.node(p)?.kind !== 'person'))) err(n.id, 'people must name interviewees');
      if (n.ask !== undefined && !['person', 'avatar'].includes(g.node(n.ask)?.kind)) err(n.id, 'ask must name a person or avatar');
    }

    // 8. repo paths and screenshots
    for (const n of nodes.filter((x) => x.kind === 'surface')) {
      const shots = Array.isArray(n.screenshots) ? n.screenshots : [];
      if (n.shipped === true && !shots.length) err(n.id, 'a shipped surface needs at least one screenshot');
      for (const sh of shots) {
        if (typeof sh.file !== 'string' || !sh.file.startsWith('assets/') || sh.file.includes('..')) err(n.id, `screenshot ${sh.file} must be under assets/`);
        else if (!fileExists(inLens(sh.file))) err(n.id, `screenshot ${sh.file} does not exist`);
        if (typeof sh.capturedAt !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(sh.capturedAt)) err(n.id, 'screenshot capturedAt must be YYYY-MM-DD');
        if (!S.SCREENSHOT_ORIGINS.includes(sh.origin)) err(n.id, 'screenshot origin must be app or design');
        if (blank(sh.caption)) err(n.id, 'screenshot needs a caption');
      }
      for (const field of ['code', 'adrs']) {
        if (!Array.isArray(n[field])) { err(n.id, `${field} must be a list`); continue; }
        for (const p of n[field]) if (typeof p !== 'string' || p.split('/').includes('..') || !fileExists(p)) err(n.id, `${field} path ${p} does not exist`);
      }
    }

    // A content idea outside a pillar would not appear on the Marketing tab.
    for (const n of nodes.filter((x) => x.kind === 'content-idea')) {
      if (!g.edgesFrom(n.id).some((e) => e.relation === 'under')) err(n.id, 'a content idea must sit under a pillar');
    }
    // 9. orphans
    const connected = new Set(g.edges().flatMap((e) => [e.from, e.to]));
    for (const n of nodes) {
      if (n.kind === 'source') {
        if (!g.citationsOf(n.id).length) err(n.id, 'no claim cites this source');
      } else if (!connected.has(n.id)) err(n.id, 'not connected to anything');
    }

    // 10. loop order
    const orders = g.nodesOfKind('loop-step').map((n) => n.order).sort((a, b) => a - b);
    if (orders.some((o, i) => o !== i + 1)) err('loop', `order must run 1..${orders.length}`);

    // 11. sources
    for (const n of sourceById.values()) {
      if (!S.EVIDENCE_TAGS.includes(n.tag)) err(n.id, `tag must be one of ${S.EVIDENCE_TAGS.join(', ')}`);
      if (n.date !== undefined && (typeof n.date !== 'string' || !DATE.test(n.date))) err(n.id, 'date must be YYYY, YYYY-MM or YYYY-MM-DD');
      if (n.snapshot !== undefined && (typeof n.snapshot !== 'string' || !n.snapshot.startsWith('sources/') || n.snapshot.includes('..'))) err(n.id, 'snapshot must be under sources/');
      if (n.statistics !== undefined && (!Array.isArray(n.statistics) || n.statistics.some((r) => blank(r.platform) || !Number.isFinite(r.percent) || r.percent < 0 || r.percent > 100))) err(n.id, 'statistics need a platform and a percent from 0 to 100');
      if (n.referenceUrl !== undefined && !/^https?:\/\//.test(n.referenceUrl)) err(n.id, 'referenceUrl must be http or https');
    }
    return errors;
  }

  // A commentable id that existed at the last build must still exist, or be mapped in `renamed`.
  function checkIdContinuity(lockIds, model) {
    const g = G.createGraph(model);
    const now = new Set(g.commentableIds());
    const renamed = model.renamed || {};
    const errors = [];
    for (const id of lockIds) {
      if (now.has(id)) continue;
      if (!Object.hasOwn(renamed, id)) errors.push(`${id}: id disappeared; add it to "renamed" (new id, or null if removed on purpose)`);
      else if (renamed[id] !== null && !now.has(renamed[id])) errors.push(`${id}: renamed to ${renamed[id]}, which does not exist`);
    }
    return errors;
  }
  return { validate, checkIdContinuity };
})();
if (typeof module !== 'undefined') module.exports = Validate;
