// Reader for an exported Galaxy on Fire reference. Pages are the exporter's
// escaped HTML; wiki:// links become in-page addresses, so Back and Forward
// work. Each language is its own content file, loaded when it is chosen.
(() => {
  const langs = window.GOF_WIKI_LANGUAGES, map = window.GOF_WIKI_MAP;
  const loaded = window.GOF_WIKI_LANGS = window.GOF_WIKI_LANGS || {};
  const $ = id => document.getElementById(id);
  const page = $('page'), media = $('media'), results = $('results'), search = $('search');
  const categories = $('categories'), language = $('language'), count = $('count');
  let data, byKey, label, order, category = 'all';
  const norm = s => s.toLowerCase().normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/ё/g, 'е');
  const score = (q, e) => {
    const t = norm(e.title), x = ' ' + norm(e.title + ' ' + e.subtitle).replace(/[^\p{L}\p{N}]+/gu, ' ');
    if (t === q) return 1000; if (t.startsWith(q)) return 800; if (t.includes(q)) return 600;
    return q.split(/\s+/).every(w => x.includes(' ' + w)) ? 300 : -1;
  };
  const byTitle = (a, b) => a.title.localeCompare(b.title, data.language, {numeric: true});
  const current = () => decodeURIComponent(location.hash.slice(1)) || 'home';
  const position = new Map();
  function row(e, q) {
    const li = document.createElement('li'), a = document.createElement('a'), icon = document.createElement('span'), text = document.createElement('span');
    a.href = '#' + e.key; icon.className = 'icon';
    if (e.icon) { const img = document.createElement('img'); img.src = e.icon; img.alt = ''; img.loading = 'lazy'; icon.append(img); } else icon.append(document.createElement('i'));
    text.textContent = e.title;
    const note = e.subtitle || (q || category === 'all' ? label.get(e.category) : '');
    if (note) { const s = document.createElement('small'); s.textContent = note; text.append(s); }
    if (e.key === current()) a.className = 'current';
    a.append(icon, text); li.append(a); return li;
  }
  function list() {
    const q = norm(search.value.trim());
    let rows = data.index.filter(e => e.category);
    if (q) rows = rows.map(e => [score(q, e), e]).filter(r => r[0] >= 0).sort((a, b) => b[0] - a[0] || byTitle(a[1], b[1])).map(r => r[1]);
    else {
      if (category !== 'all') rows = rows.filter(e => e.category === category);
      rows = [...rows].sort((a, b) => order.indexOf(a.category) - order.indexOf(b.category) || (['story', 'galaxy'].includes(a.category) ? position.get(a.key) - position.get(b.key) : byTitle(a, b)));
    }
    const items = []; let section = '';
    for (const e of rows) {
      if (!q && category === 'all' && e.category !== section) {
        section = e.category; const h = document.createElement('li'); h.className = 'section'; h.textContent = label.get(section); items.push(h);
      }
      items.push(row(e, q));
    }
    results.replaceChildren(...items);
    count.textContent = rows.length + ' / ' + data.index.filter(e => e.category).length;
    const here = results.querySelector('a.current'); if (here) here.scrollIntoView({block: 'nearest'});
  }
  // The galaxy map: quadrants, systems and every place coloured by its
  // people, solid where it trades; the page's place, system or quadrant marked.
  function chart([station, system, quadrant]) {
    const ns = 'http://www.w3.org/2000/svg', svg = document.createElementNS(ns, 'svg');
    const [w, h] = map.extent, per = map.quadrant / map.system, add = (tag, attrs) => {
      const node = document.createElementNS(ns, tag); for (const k in attrs) node.setAttribute(k, attrs[k]); svg.append(node); return node;
    };
    svg.setAttribute('viewBox', `0 0 ${w} ${h}`);
    const quadrants = (w / map.quadrant) * (h / map.quadrant);
    for (let q = 0; q < quadrants; q++) {
      const x = (q % map.columns) * map.quadrant, y = Math.floor(q / map.columns) * map.quadrant;
      for (let s = 1; s < per; s++) {
        add('line', {x1: x + s * map.system, y1: y, x2: x + s * map.system, y2: y + map.quadrant, class: 'grid'});
        add('line', {x1: x, y1: y + s * map.system, x2: x + map.quadrant, y2: y + s * map.system, class: 'grid'});
      }
      add('rect', {x, y, width: map.quadrant, height: map.quadrant, class: q === quadrant ? 'marked' : 'quadrant'});
    }
    if (station >= 0) system = Math.floor(station / (map.points.length / (quadrants * per * per)));
    if (system >= 0) {
      const q = Math.floor(system / (per * per)), inner = system % (per * per);
      add('rect', {x: (q % map.columns) * map.quadrant + (inner % per) * map.system, y: Math.floor(q / map.columns) * map.quadrant + Math.floor(inner / per) * map.system, width: map.system, height: map.system, class: 'marked'});
    }
    map.points.forEach(([x, y, race, shop], id) => {
      const a = document.createElementNS(ns, 'a'), dot = document.createElementNS(ns, 'circle'), name = document.createElementNS(ns, 'title');
      a.setAttribute('href', '#station/' + id);
      const color = map.colors[race % map.colors.length];
      dot.setAttribute('cx', x); dot.setAttribute('cy', y); dot.setAttribute('r', 4);
      dot.setAttribute('fill', shop ? color : 'none'); dot.setAttribute('stroke', color); dot.setAttribute('stroke-width', 1.5);
      name.textContent = data.names[id] || ''; dot.append(name); a.append(dot); svg.append(a);
    });
    if (station >= 0) add('circle', {cx: map.points[station][0], cy: map.points[station][1], r: 13, class: 'here'});
    return svg;
  }
  function show() {
    const key = current(), entry = byKey.get(key), shown = data.media[key] || {};
    page.innerHTML = (data.pages[key] || data.pages.home).replace(/wiki:\/\//g, '#');
    media.replaceChildren();
    if (shown.render || shown.image) {
      const frame = document.createElement('div'); frame.className = 'frame';
      for (const [src, kind] of [[shown.render, 'render'], [shown.image, 'art']]) {
        if (!src) continue;
        const img = document.createElement('img'); img.src = src; img.alt = entry ? entry.title : ''; img.className = kind; frame.append(img);
      }
      media.append(frame);
    }
    if (shown.chart) media.append(chart(shown.chart));
    media.hidden = !media.childElementCount;
    document.title = (entry ? entry.title + ' · ' : '') + 'Galaxy on Fire ' + data.title;
    document.body.classList.remove('browsing');
    list(); $('sheet').scrollTop = 0; page.focus({preventScroll: true});
  }
  function load(code, then) {
    if (loaded[code]) return then(code);
    const script = document.createElement('script');
    script.src = 'content-' + code + '.js';
    script.onload = () => then(loaded[code] ? code : langs.first);
    script.onerror = () => code === langs.first ? null : load(langs.first, then);
    document.head.append(script);
  }
  function use(code) {
    load(code, found => {
      data = loaded[found]; language.value = found;
      try { localStorage.setItem('gof-reference-language', found); } catch (e) {}
      byKey = new Map(data.index.map(e => [e.key, e]));
      position.clear(); data.index.forEach((e, i) => position.set(e.key, i));
      label = new Map(data.categories); order = data.categories.map(c => c[0]);
      document.documentElement.lang = found;
      $('title').textContent = data.title;
      search.placeholder = data.search; search.setAttribute('aria-label', data.search);
      $('browse').textContent = data.browse;
      $('play').textContent = data.play;
      const options = [];
      for (const [name, title] of [['all', data.all], ...data.categories]) {
        if (name !== 'all' && !data.index.some(e => e.category === name)) continue;
        const o = document.createElement('option'); o.value = name; o.textContent = title; options.push(o);
      }
      categories.replaceChildren(...options);
      if (!options.some(o => o.value === category)) category = 'all';
      categories.value = category;
      show();
    });
  }
  for (const [code, name] of langs.list) {
    const o = document.createElement('option'); o.value = code; o.textContent = name; language.append(o);
  }
  language.setAttribute('aria-label', langs.label); language.title = langs.label;
  language.hidden = langs.list.length < 2;
  language.onchange = () => use(language.value);
  categories.onchange = () => { category = categories.value; search.value = ''; list(); };
  search.addEventListener('input', () => { document.body.classList.add('browsing'); list(); });
  $('browse').onclick = () => document.body.classList.toggle('browsing');
  window.addEventListener('hashchange', show);
  let stored = null;
  try { stored = localStorage.getItem('gof-reference-language'); } catch (e) {}
  use(langs.list.some(l => l[0] === stored) ? stored : langs.first);
})();
