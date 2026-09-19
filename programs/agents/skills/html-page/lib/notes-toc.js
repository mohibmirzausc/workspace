// Auto-builds a floating section index from `.section > h2` headings.
// Visible only on wide screens (CSS-gated). Highlights the section in view.
(function () {
  const sections = Array.from(document.querySelectorAll('.section'));
  if (sections.length < 3) return;

  const nav = document.createElement('nav');
  nav.className = 'notes-toc';
  nav.setAttribute('aria-label', 'Section index');

  const label = document.createElement('div');
  label.className = 'notes-toc-label';
  label.textContent = 'Contents';
  nav.appendChild(label);

  const list = document.createElement('ol');
  const items = [];

  sections.forEach((sec, i) => {
    const h2 = sec.querySelector(':scope > h2');
    if (!h2) return;
    if (!sec.id) {
      sec.id = h2.textContent.trim().toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/^-+|-+$/g, '') || `section-${i + 1}`;
    }
    const li = document.createElement('li');
    const a = document.createElement('a');
    a.href = `#${sec.id}`;
    a.textContent = h2.textContent.replace(/\s+/g, ' ').trim();
    a.title = a.textContent;
    li.appendChild(a);
    list.appendChild(li);
    items.push({ section: sec, link: a });
  });

  nav.appendChild(list);
  document.body.appendChild(nav);

  // Scroll-spy: highlight the section whose top is nearest the viewport top
  let ticking = false;
  function update() {
    ticking = false;
    const y = window.scrollY + 120;
    let active = items[0];
    for (const item of items) {
      if (item.section.offsetTop <= y) active = item;
      else break;
    }
    items.forEach(it => it.link.classList.toggle('is-active', it === active));
  }
  window.addEventListener('scroll', () => {
    if (!ticking) { requestAnimationFrame(update); ticking = true; }
  }, { passive: true });
  update();
})();
