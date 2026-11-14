// components/graph.js
// Read-only lookups over a v2 model. Assumes nothing about validity: missing ids answer null.
const Graph = (() => {
  const S = typeof Schema !== 'undefined' ? Schema : require('./schema.js');
  const at = (obj, path) => path.split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj);

  function claimsOf(node) {
    const out = [];
    for (const path of S.CLAIM_FIELDS[node.kind] || []) {
      const v = at(node, path);
      for (const claim of Array.isArray(v) ? v : v ? [v] : []) out.push({ claim, path, owner: node.id });
    }
    // A journey map's cells are keyed "stage:row", so they can't be listed in CLAIM_FIELDS.
    for (const [key, list] of Object.entries(node.journeyMap?.cells || {})) {
      for (const claim of Array.isArray(list) ? list : []) out.push({ claim, path: `journeyMap.cells.${key}`, owner: node.id });
    }
    return out;
  }

  function createGraph(model) {
    const nodes = model.nodes || [];
    const edges = model.edges || [];
    const nodeById = new Map(nodes.map((n) => [n.id, n]));
    const edgeById = new Map(edges.map((e) => [e.id, e]));
    const claims = [];
    if (model.purpose) claims.push({ claim: model.purpose, path: 'purpose', owner: null });
    for (const n of nodes) claims.push(...claimsOf(n));
    for (const e of edges) if (e.claim) claims.push({ claim: e.claim, path: 'claim', owner: e.id });
    const claimById = new Map(claims.map((c) => [c.claim.id, c]));

    const lookup = (id) => {
      if (nodeById.has(id)) return { type: 'node', value: nodeById.get(id) };
      if (edgeById.has(id)) return { type: 'edge', value: edgeById.get(id) };
      if (claimById.has(id)) { const c = claimById.get(id); return { type: 'claim', value: c.claim, owner: c.owner, path: c.path }; }
      return null;
    };
    return {
      model,
      node: (id) => nodeById.get(id) || null,
      edge: (id) => edgeById.get(id) || null,
      nodes: () => nodes,
      edges: () => edges,
      nodesOfKind: (kind) => nodes.filter((n) => n.kind === kind),
      claimsOf,
      allClaims: () => claims,
      lookup,
      edgesFrom: (id) => edges.filter((e) => e.from === id),
      edgesTo: (id) => edges.filter((e) => e.to === id),
      // Claims citing a source, plus hypotheses (whose evidence is not a claim) as { claim: hypothesis, owner }.
      citationsOf: (sourceId) => [
        ...claims.filter((c) => (c.claim.evidence || []).some((ev) => ev.source === sourceId)),
        ...nodes.filter((n) => n.kind === 'hypothesis' && n.evidence.some((ev) => ev.source === sourceId)).map((n) => ({ claim: n, path: 'evidence', owner: n.id })),
        ...nodes.filter((n) => n.kind === 'product' && n.research === sourceId).map((n) => ({ claim: n, path: 'research', owner: n.id })),
      ],
      commentableIds: () => [...new Set([...nodes.map((n) => n.id), ...edges.map((e) => e.id), ...claims.map((c) => c.claim.id)])],
    };
  }
  return { createGraph, claimsOf };
})();
if (typeof module !== 'undefined') module.exports = Graph;
