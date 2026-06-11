// Lazy-loads Mermaid and themes it to match the earth-tone palette.
// Use:  <pre class="mermaid">flowchart TD\n  A --> B</pre>
//
// Mermaid is ~500KB over CDN — opt-in per page, NOT loaded by the default
// template. Add this <script> tag only on pages that contain a diagram.
(async function () {
  const m = await import('https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs');
  const mermaid = m.default;

  // Hex values mirror :root tokens in lib/notes-style.css. If the palette
  // changes there, update these too (Mermaid expects literal hex strings,
  // not CSS variables).
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'loose',
    theme: 'base',
    fontFamily: '"Newsreader", Georgia, serif',
    themeVariables: {
      primaryColor:           '#eee4c8',   // sand-2
      primaryTextColor:       '#2d2418',   // ink-0
      primaryBorderColor:     '#b57614',   // ochre
      secondaryColor:         '#f5ecd0',   // sand-1
      tertiaryColor:          '#fdf6e3',   // sand-0
      mainBkg:                '#eee4c8',
      secondBkg:              '#f5ecd0',
      tertiaryBkg:            '#fdf6e3',
      background:             '#fdf6e3',
      lineColor:              '#6d5f4d',   // ink-3
      defaultLinkColor:       '#6d5f4d',
      edgeLabelBackground:    '#fdf6e3',
      titleColor:             '#2d2418',
      nodeBorder:             '#b57614',
      clusterBkg:             '#f5ecd0',
      clusterBorder:          '#d8cdac',   // sand-3
      // Sequence diagrams
      actorBkg:               '#eee4c8',
      actorBorder:            '#b57614',
      actorTextColor:         '#2d2418',
      actorLineColor:         '#d8cdac',
      signalColor:            '#54483a',   // ink-2
      signalTextColor:        '#2d2418',
      labelBoxBkgColor:       '#eee4c8',
      labelBoxBorderColor:    '#b57614',
      labelTextColor:         '#2d2418',
      loopTextColor:          '#2d2418',
      noteBkgColor:           '#f5ecd0',
      noteBorderColor:        '#d8cdac',
      noteTextColor:          '#2d2418',
      activationBkgColor:     '#eee4c8',
      activationBorderColor:  '#b57614',
      // Gantt / state colors fall back to primary; keep sane defaults.
      taskTextColor:          '#2d2418',
      taskTextOutsideColor:   '#2d2418',
      taskBkgColor:            '#eee4c8',
      gridColor:              '#d8cdac',
      doneTaskBkgColor:       '#79740e',  // moss
      doneTaskBorderColor:    '#79740e',
      activeTaskBkgColor:     '#d79921',  // ochre-soft
      activeTaskBorderColor:  '#b57614',
      critBkgColor:           '#9d0006',  // burgundy
      critBorderColor:        '#9d0006',
    },
  });

  const run = () => mermaid.run();
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', run);
  } else {
    run();
  }
})();
