// components/schema.js
// The closed sets the lens is built from. validate.js enforces them; render modules read labels.
const Schema = (() => {
  const COMMON = ['id', 'kind', 'title', 'body'];
  const KINDS = {
    'loop-step': { required: [...COMMON, 'order', 'claim'], optional: ['notes'] },
    avatar: { required: [...COMMON, 'personaMap'], optional: ['image', 'imageAlt', 'avatarIcon', 'journeyMap', 'notes'] },
    person: { required: [...COMMON, 'background'], optional: ['notes'] },
    problem: { required: [...COMMON, 'claim'], optional: ['notes'] },
    surface: { required: [...COMMON, 'unique', 'situations', 'heard', 'screenshots', 'code', 'adrs', 'shipped'], optional: ['notes'] },
    alternative: { required: [...COMMON, 'wins', 'loses'], optional: ['notes'] },
    hypothesis: { required: [...COMMON, 'evidence'], optional: ['focus', 'group', 'next', 'notes'] },
    product: { required: [...COMMON, 'url', 'research', 'pitch', 'pricing', 'revenue', 'metaAds', 'tiktokAds', 'notable', 'vs'], optional: ['notes'] },
    source: {
      required: [...COMMON, 'tag', 'author'],
      optional: ['date', 'people', 'takeaways', 'locator', 'snapshot', 'repoPath', 'referenceUrl', 'evidenceType', 'population', 'statistics', 'sourceItems', 'inspectedRevision', 'notes'],
    },
    question: { required: COMMON, optional: ['ask', 'prompt', 'answerShape', 'notes'] },
    decision: { required: [...COMMON, 'current', 'previous', 'rationale', 'revisitWhen', 'date', 'claim'], optional: ['evidenceNotes', 'notes'] },
    channel: { required: [...COMMON, 'phase', 'experiment', 'claim'], optional: ['notes'] },
    pillar: { required: [...COMMON, 'claim'], optional: ['notes'] },
    'content-idea': { required: [...COMMON, 'format', 'claim'], optional: ['notes'] },
    insight: { required: [...COMMON, 'findings'], optional: ['notes'] },
  };
  // Where claims live inside each kind. A path names one claim, or an array of claims.
  const CLAIM_FIELDS = {
    'loop-step': ['claim'],
    avatar: ['personaMap.background', 'personaMap.context', 'personaMap.goals', 'personaMap.frustrations', 'personaMap.behaviors'],
    person: ['background'],
    problem: ['claim'],
    surface: ['unique', 'situations', 'heard'],
    alternative: ['wins', 'loses'],
    hypothesis: [],
    product: ['vs'],
    source: [],
    question: [],
    decision: ['claim'],
    channel: ['claim'],
    pillar: ['claim'],
    'content-idea': ['claim'],
    insight: ['findings'],
  };
  const PERSONA_SECTIONS = ['background', 'context', 'goals', 'frustrations', 'behaviors'];
  const CLAIM_KINDS = ['observed', 'view', 'hypothesis'];
  const CLAIM_FIELDS_ALLOWED = ['id', 'text', 'kind', 'evidence', 'next'];
  const STANCES = ['supports', 'contradicts'];
  const AD_STATUSES = ['active', 'none', 'blocked', 'not-covered'];
  const AD_THEMES = ['social proof', 'founder story', 'pain agitation', 'aspiration', 'urgency', 'free trial', 'comparison', 'authority', 'humor', 'demo'];
  const SCREENSHOT_ORIGINS = ['app', 'design'];
  const HYPOTHESIS_GROUPS = { trust: 'Trust & failure' };
  const EVIDENCE_TAGS = ['Interview', 'Owner view', 'Synthesis', 'Market research', 'Architecture & code', 'Reference'];
  const CHANNEL_PHASES = ['discovery', 'evaluation', 'trust', 'experiment'];
  const NOT_SOURCE = '*';
  const RELATIONS = [
    { from: 'person', relation: 'fits', to: 'avatar' },
    { from: 'avatar', relation: 'has', to: 'problem' },
    { from: 'person', relation: 'reports', to: 'problem' },
    { from: 'surface', relation: 'serves', to: 'problem' },
    { from: 'surface', relation: 'implements', to: 'loop-step' },
    { from: 'surface', relation: 'depends-on', to: 'surface' },
    { from: 'question', relation: 'tests', to: NOT_SOURCE },
    { from: 'decision', relation: 'shapes', to: NOT_SOURCE },
    { from: 'avatar', relation: 'may-reach-through', to: 'channel' },
    { from: 'alternative', relation: 'also-serves', to: 'problem' },
    { from: 'hypothesis', relation: 'about', to: NOT_SOURCE },
    { from: 'product', relation: 'is-a', to: 'alternative' },
    { from: 'content-idea', relation: 'under', to: 'pillar' },
    { from: 'pillar', relation: 'speaks-to', to: 'avatar' },
    { from: 'content-idea', relation: 'speaks-to', to: 'avatar' },
    { from: 'content-idea', relation: 'features', to: 'surface' },
    { from: 'content-idea', relation: 'like', to: 'product' },
    { from: 'insight', relation: 'bears-on', to: NOT_SOURCE },
  ];
  const relationAllowed = (fromKind, relation, toKind) =>
    RELATIONS.some((r) => r.from === fromKind && r.relation === relation && (r.to === toKind || (r.to === NOT_SOURCE && toKind !== 'source')));
  const KIND_META = {
    'loop-step': ['🔁', 'Loop step'], avatar: ['🧑‍🚀', 'Avatar'], person: ['👤', 'Interviewee'],
    problem: ['😣', 'Problem'], surface: ['🧩', 'Surface'], alternative: ['↔️', 'Alternative'],
    hypothesis: ['🧪', 'Hypothesis'], product: ['🏷️', 'Product'], source: ['📎', 'Evidence'], question: ['❓', 'Open question'],
    decision: ['🧭', 'Decision'], channel: ['📣', 'Channel'], pillar: ['🏛️', 'Content pillar'], 'content-idea': ['🎬', 'Content idea'], insight: ['📈', 'Market insight'],
  };
  // Where a statement comes from, in words a reader needs no legend for.
  const CLAIM_LABELS = { observed: 'Heard / seen', view: 'Owner’s view', hypothesis: 'Untested' };
  const CLAIM_HINTS = {
    observed: 'Someone said or did this; open the evidence to check',
    view: 'The owner’s interpretation, not yet checked with anyone',
    hypothesis: 'A guess no evidence backs yet',
  };
  const RELATION_LABELS = {
    fits: 'fits', has: 'has', reports: 'reports', serves: 'serves', implements: 'implements',
    'depends-on': 'depends on', tests: 'tests', shapes: 'shapes', 'may-reach-through': 'may reach through',
    'also-serves': 'also serves', about: 'about', 'is-a': 'is a',
    under: 'under', 'speaks-to': 'speaks to', features: 'shows', like: 'like', 'bears-on': 'bears on',
  };
  return { KINDS, CLAIM_FIELDS, CLAIM_FIELDS_ALLOWED, STANCES, AD_STATUSES, AD_THEMES, SCREENSHOT_ORIGINS, HYPOTHESIS_GROUPS, PERSONA_SECTIONS, CLAIM_KINDS, EVIDENCE_TAGS, CHANNEL_PHASES, RELATIONS, relationAllowed, KIND_META, CLAIM_LABELS, CLAIM_HINTS, RELATION_LABELS };
})();
if (typeof module !== 'undefined') module.exports = Schema;
