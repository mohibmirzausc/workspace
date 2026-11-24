// The Evidence view's search, tag filters and ordering, as pure functions. build.mjs inlines
// this file into index.html; tests/evidence-list.test.mjs requires it directly.
const EvidenceList = (() => {
  const SORTS = [
    ['newest', 'Newest first'],
    ['oldest', 'Oldest first'],
    ['title', 'A–Z'],
  ];

  function fmtDate(date) {
    if (!date) return 'Undated';
    const [y, m, d] = date.split('-');
    if (!m) return y;
    const month = new Date(Date.UTC(+y, +m - 1, 1)).toLocaleString('en', { month: 'short', timeZone: 'UTC' });
    return d ? `${month} ${+d}, ${y}` : `${month} ${y}`;
  }

  // Undated items sort last in both date orders: an unknown date is neither new nor old.
  const byDate = (a, b) => (!a.date - !b.date) || (a.date || '').localeCompare(b.date || '');
  const ORDERS = {
    newest: (a, b) => (!a.date - !b.date) || (b.date || '').localeCompare(a.date || ''),
    oldest: byDate,
    title: (a, b) => a.title.localeCompare(b.title),
  };

  // The full month name too, so "October" finds what the list shows as "Oct".
  const monthName = (date) => {
    const m = date && date.split('-')[1];
    return m ? new Date(Date.UTC(2000, +m - 1, 1)).toLocaleString('en', { month: 'long', timeZone: 'UTC' }) : '';
  };

  function searchableText(n, personTitle) {
    return [n.title, n.body, n.evidenceType, n.author, n.locator, n.tag, n.date, fmtDate(n.date), monthName(n.date),
      ...(n.people || []).map(personTitle), ...(n.takeaways || [])].join(' ').toLowerCase();
  }

  // Tag counts are taken after the search and before the tag filter, so selecting a tag
  // always shows exactly the number its button showed.
  function evidenceView(items, { search = '', tag = 'all', sort = 'newest' }, personTitle) {
    const words = search.toLowerCase().split(/\s+/).filter(Boolean);
    const found = items
      .filter((n) => words.every((w) => searchableText(n, personTitle).includes(w)))
      .sort(ORDERS[sort] || ORDERS.newest);
    const counts = new Map();
    for (const n of found) counts.set(n.tag, (counts.get(n.tag) || 0) + 1);
    return {
      total: found.length,
      tagCounts: [...counts].sort((a, b) => a[0].localeCompare(b[0])),
      rows: tag === 'all' ? found : found.filter((n) => n.tag === tag),
    };
  }

  function interviewsOf(items, personId) {
    return items.filter((n) => (n.people || []).includes(personId)).sort(ORDERS.oldest);
  }

  return { SORTS, fmtDate, evidenceView, interviewsOf };
})();
if (typeof module !== 'undefined') module.exports = EvidenceList;
