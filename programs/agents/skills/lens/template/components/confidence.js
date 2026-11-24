// How sure we are of a focus hypothesis, computed from its evidence so it moves when evidence is
// logged. Only interviewees count toward the level: the owner's view and sources without people
// are counted as sources but cannot make a hypothesis stronger.
const Confidence = (() => {
  const LEVELS = ['untested', 'weak', 'emerging', 'strong'];

  function assess(g, h) {
    const owner = g.model.owner;
    const side = (stance) => {
      const evidence = h.evidence.filter((ev) => ev.stance === stance);
      const people = new Set(evidence.flatMap((ev) => g.node(ev.source)?.people || []).filter((p) => p !== owner));
      return { people: people.size, sources: new Set(evidence.map((ev) => ev.source)).size };
    };
    const pro = side('supports'); const con = side('contradicts');
    let level;
    if (con.people > 0 && con.people >= pro.people) level = 'contested';
    else {
      const step = Math.min(pro.people, 3) - (con.people > 0 ? 1 : 0);
      level = LEVELS[Math.max(step, 0)];
    }
    return { level, people: { for: pro.people, against: con.people }, sources: { for: pro.sources, against: con.sources } };
  }
  return { assess, LEVELS };
})();
if (typeof module !== 'undefined') module.exports = Confidence;
