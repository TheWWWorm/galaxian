extends RefCounted
## Adapted from the Apache-2.0 licensed maintained DEEP remake (Abyssal).
## Writes the reference as a small website: an index page, its reader script
## and style, one content file of pages for each language (languages.js lists
## them) and images/ with the pictures from the imported art, enlarged without
## blurring, plus the ship renders (WikiSnapshots) when the game could draw
## them. It opens straight from the folder, with no server. The pages and
## pictures are the player's own imported content, so the folder is theirs to
## keep; nothing is sent anywhere.
const EngineLanguage = preload("res://src/presentation/engine_language.gd")
const WikiChart = preload("res://src/wiki/wiki_chart.gd")
## Pixel art is written this many times larger, so browsers need not scale it.
const ENLARGE := 4
## The project's source and the game in the browser, linked from the header.
const SOURCE_URL := "https://github.com/TheWWWorm/galaxian"
const PLAY_URL := "https://galaxian.wwworm.com/"


static func write(catalog, directory: String, renders := {}, languages: Array = []) -> Error:
	var made := DirAccess.make_dir_recursive_absolute(directory.path_join("images"))
	if made != OK:
		return made
	renders = renders.duplicate()
	# Pictures are the same in every language: written once, shared.
	var written := {}
	var icons := {}
	var media := {}
	for key: String in catalog.ordered:
		var icon := picture(catalog.icon(key), directory, written)
		if not icon.is_empty():
			icons[key] = icon
		var shown: Dictionary = catalog.media(key)
		var entry := {}
		# A picture drawn by an earlier export into this folder is kept, so an
		# export without a renderer still shows the models.
		var drawn := "images/render-%s.png" % key.replace("/", "-")
		if not renders.has(key) and FileAccess.file_exists(directory.path_join(drawn)):
			renders[key] = drawn
		if renders.has(key):
			entry["render"] = renders[key]
		var art := picture(shown.get("picture", {}), directory, written)
		if not art.is_empty():
			entry["image"] = art
		if shown.get("chart", false):
			entry["chart"] = [int(shown.get("station", -1)), int(shown.get("system", -1)), int(shown.get("quadrant", -1))]
		if not entry.is_empty():
			media[key] = entry
	var grid: Dictionary = catalog.library.content.map_ui.grid
	var map := {
		"points": catalog.chart_points(),
		"extent": [catalog.chart_extent().x, catalog.chart_extent().y],
		"system": float(grid.system_extent),
		"quadrant": float(grid.quadrant_extent),
		"columns": int(grid.quadrant_columns),
		"colors": WikiChart.RACE_COLORS.map(func(color: Color): return "#" + color.to_html(false))
	}
	var codes: Array = [catalog.language]
	for code in languages:
		if code in EngineLanguage.codes() and not code in codes:
			codes.append(code)
	var files := {
		"index.html": INDEX.replace("%PLAY%", PLAY_URL).replace("%SOURCE%", SOURCE_URL),
		"wiki.css": STYLE,
		"wiki.js": READER,
		"map.js": "window.GOF_WIKI_MAP=%s;\n" % JSON.stringify(map)
	}
	var listed: Array = []
	for code: String in codes:
		var edition = catalog if code == catalog.language else catalog.get_script().new(catalog.library, catalog.limit, code)
		files["content-%s.js" % code] = (
			"(window.GOF_WIKI_LANGS=window.GOF_WIKI_LANGS||{})[%s]=%s;\n"
			% [JSON.stringify(code), JSON.stringify(bundle(edition, icons, media))]
		)
		listed.append([code, EngineLanguage.native_name(code)])
	files["languages.js"] = "window.GOF_WIKI_LANGUAGES=%s;\n" % JSON.stringify(
		{"first": catalog.language, "list": listed, "label": catalog.translate("Language")}
	)
	for name: String in files:
		var file := FileAccess.open(directory.path_join(name), FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		file.store_string(files[name])
		file.close()
	return OK


## One language's pages, list and labels.
static func bundle(edition, icons: Dictionary, media: Dictionary) -> Dictionary:
	var index: Array = []
	var pages := {}
	for key: String in edition.ordered:
		var entry: Dictionary = edition.entries[key]
		var row := {"key": key, "title": entry.title, "category": entry.category, "subtitle": entry.subtitle}
		if icons.has(key):
			row["icon"] = icons[key]
		index.append(row)
		pages[key] = edition.page(key)
	return {
		"language": edition.language,
		"title": edition.translate("Reference"),
		"search": edition.translate("Search the reference"),
		"play": EngineLanguage.text_in(edition.language, "Play in your browser"),
		"browse": edition.translate("Browse"),
		"all": edition.all_sections(),
		"categories": edition.CATEGORIES.map(func(name): return [name, edition.category_name(name)]),
		"index": index,
		"pages": pages,
		"media": media,
		"names": range(edition.library.stations.size()).map(func(id): return edition.station_name(id))
	}


## Saves a picture once and returns its path in the site, or "".
static func picture(shown: Dictionary, directory: String, written: Dictionary) -> String:
	if shown.is_empty() or shown.get("texture") == null:
		return ""
	var path := "images/%s.png" % str(shown.name)
	if written.has(path):
		return path
	var pixels: Image = (shown.texture as Texture2D).get_image()
	if pixels == null:
		return ""
	pixels = pixels.duplicate()
	if pixels.is_compressed():
		pixels.decompress()
	pixels.convert(Image.FORMAT_RGBA8)
	pixels.resize(pixels.get_width() * ENLARGE, pixels.get_height() * ENLARGE, Image.INTERPOLATE_NEAREST)
	if pixels.save_png(directory.path_join(path)) != OK:
		return ""
	written[path] = true
	return path


const INDEX := """<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Galaxy on Fire</title>
<link rel="stylesheet" href="wiki.css">
</head>
<body>
<header><a class="brand" href="#home"><span>GALAXY ON FIRE</span> <b id="title"></b></a><input id="search" type="search" autocomplete="off"><select id="language"></select><nav id="links"><a id="play" href="%PLAY%"></a><a id="source" href="%SOURCE%">GitHub</a></nav><button id="browse" type="button"></button></header>
<main><nav id="side"><select id="categories"></select><ul id="results"></ul><p id="count"></p></nav>
<div id="sheet"><article id="page" tabindex="-1"></article><aside id="media"></aside></div></main>
<script src="languages.js"></script>
<script src="map.js"></script>
<script src="wiki.js"></script>
</body>
</html>
"""

const STYLE := """:root{--bg:#03080d;--glass:rgba(7,15,22,.94);--card:#10202f;--card-hi:#1d3949;--line:#29404e;--line-hi:#375766;--text:#dce9ed;--dim:#a4bac8;--faint:#6f8796;--accent:#f5d5a4;--focus:#ffca79;font-family:"Noto Sans",system-ui,-apple-system,"Segoe UI",sans-serif}
*{box-sizing:border-box}
html,body{margin:0;height:100%;color:var(--text);background:radial-gradient(ellipse at 50% -20%,#16304a 0,#071019 55%,var(--bg) 100%) fixed}
header{display:flex;gap:14px;align-items:center;padding:10px 18px;border-bottom:1px solid var(--line);background:var(--glass);position:sticky;top:0;z-index:2;height:60px}
.brand{color:var(--text);text-decoration:none;white-space:nowrap;letter-spacing:.14em;font-size:15px}
.brand span{color:var(--accent);font-weight:800}
.brand b{font-weight:500;color:var(--dim);text-transform:uppercase}
#search{flex:1;min-width:0;max-width:520px;margin-left:auto;padding:9px 12px;border-radius:6px;border:1px solid var(--line-hi);background:var(--card);color:var(--text);font:inherit}
#search:focus{outline:none;border-color:var(--focus)}
#browse{display:none;padding:8px 12px;border-radius:6px;border:1px solid var(--line-hi);background:var(--card);color:var(--text);font:inherit}
main{display:grid;grid-template-columns:320px 1fr;gap:16px;padding:16px;height:calc(100% - 60px)}
#side{display:flex;flex-direction:column;min-height:0;gap:8px}
#language,#categories{padding:8px 10px;border-radius:6px;border:1px solid var(--line-hi);background:var(--card);color:var(--text);font:inherit}
#language{max-width:170px}
#results{list-style:none;margin:0;padding:4px;overflow:auto;flex:1;border:1px solid var(--line);border-radius:6px;background:rgba(7,18,27,.7)}
#results li.section{color:var(--accent);font-size:12px;letter-spacing:.12em;text-transform:uppercase;padding:10px 8px 4px}
#results a{display:flex;gap:10px;align-items:center;padding:5px 8px;color:var(--text);text-decoration:none;border:1px solid transparent;border-radius:6px;min-height:44px}
#results a:hover{background:rgba(29,57,73,.55);border-color:var(--line-hi)}
#results a.current{background:var(--card-hi);border-color:var(--focus)}
#links{display:flex;gap:14px;white-space:nowrap;font-size:14px}
#links a{color:var(--dim);text-decoration:none}
#links a:hover{color:var(--accent)}
#results .icon{width:44px;height:32px;flex:none;display:flex;align-items:center;justify-content:center}
#results .icon img{max-width:44px;max-height:32px;image-rendering:pixelated}
#results .icon i{width:10px;height:10px;border:2px solid var(--line-hi);border-radius:50%}
#results small{display:block;color:var(--faint);font-size:12px}
#count{margin:0;color:var(--faint);font-size:13px}
#sheet{display:grid;grid-template-columns:minmax(0,860px) minmax(240px,420px);justify-content:center;gap:30px;min-height:0;overflow:auto;padding:22px 26px 60px;border:1px solid var(--line);border-radius:6px;background:rgba(7,15,22,.94)}
#page{outline:none;line-height:1.6;font-size:16.5px;min-width:0}
#page h1{margin:0 0 2px;font-size:30px;color:var(--accent);font-weight:600}
#page h1+p em{font-style:normal;color:var(--dim);text-transform:uppercase;letter-spacing:.1em;font-size:13px}
#page h2{margin-top:28px;font-size:19px;color:var(--accent);font-weight:600;border-bottom:1px solid var(--line);padding-bottom:4px}
#page a{color:var(--focus);text-decoration-color:rgba(255,202,121,.35)}
#page table{border-collapse:collapse;margin:12px 0;width:100%;font-size:14.5px}
#page th,#page td{border:1px solid var(--line);padding:6px 9px;text-align:left;vertical-align:top}
#page tr:nth-child(odd) td{background:rgba(29,57,73,.25)}
#page th{color:var(--dim);font-weight:600}
#page em{color:var(--dim)}
#media{position:sticky;top:0;align-self:start;display:flex;flex-direction:column;gap:10px}
#media .frame{border:1px solid var(--line);border-radius:6px;background:rgba(3,10,16,.8);padding:12px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px}
#media img{max-width:100%;max-height:280px;image-rendering:pixelated;object-fit:contain}
#media img.render{image-rendering:auto;width:100%;max-height:none}
#media svg{display:block;width:100%;height:auto;border:1px solid var(--line);border-radius:6px;background:rgba(3,10,16,.9)}
#media svg .grid{stroke:var(--line);stroke-width:.6;fill:none}
#media svg .quadrant{stroke:var(--line-hi);stroke-width:2.5;fill:none}
#media svg .marked{stroke:var(--focus);stroke-width:3;fill:rgba(255,202,121,.12)}
#media svg .here{stroke:var(--focus);stroke-width:3;fill:none}
@media (max-width:1100px){#sheet{grid-template-columns:1fr}#media{position:static;order:-1;max-width:520px}#media img{max-height:200px}}
@media (max-width:760px){
header{flex-wrap:wrap;height:112px;align-content:center;gap:8px 10px;padding:8px 12px}
.brand{margin-right:auto}
#search{order:3;flex:1 0 100%;max-width:none;margin:0;padding:11px 14px;font-size:16px}
#language{max-width:42vw}
main{grid-template-columns:1fr;padding:8px;height:calc(100% - 112px)}
#side{display:none;position:fixed;inset:112px 0 0 0;z-index:3;background:var(--bg);padding:8px}
body.browsing #side{display:flex}
#browse{display:block}
.brand b{display:none}
#links{display:none}
#sheet{padding:16px}
}
"""

const READER := """// Reader for an exported Galaxy on Fire reference. Pages are the exporter's
// escaped HTML; wiki:// links become in-page addresses, so Back and Forward
// work. Each language is its own content file, loaded when it is chosen.
(() => {
  const langs = window.GOF_WIKI_LANGUAGES, map = window.GOF_WIKI_MAP;
  const loaded = window.GOF_WIKI_LANGS = window.GOF_WIKI_LANGS || {};
  const $ = id => document.getElementById(id);
  const page = $('page'), media = $('media'), results = $('results'), search = $('search');
  const categories = $('categories'), language = $('language'), count = $('count');
  let data, byKey, label, order, category = 'all';
  const norm = s => s.toLowerCase().normalize('NFKD').replace(/[\\u0300-\\u036f]/g, '').replace(/ё/g, 'е');
  const score = (q, e) => {
    const t = norm(e.title), x = ' ' + norm(e.title + ' ' + e.subtitle).replace(/[^\\p{L}\\p{N}]+/gu, ' ');
    if (t === q) return 1000; if (t.startsWith(q)) return 800; if (t.includes(q)) return 600;
    return q.split(/\\s+/).every(w => x.includes(' ' + w)) ? 300 : -1;
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
    page.innerHTML = (data.pages[key] || data.pages.home).replace(/wiki:\\/\\//g, '#');
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
"""
