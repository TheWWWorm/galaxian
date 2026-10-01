extends RefCounted
## The language of the engine's own text: menus, options, notices and help
## that the imported game does not provide. The game's text comes from the
## language files of the supplied IPA, chosen under Options; this picks the
## engine text to match it, or the language a player chose for the engine.
##
## Every catalog maps the English source text to its translation. Code marks
## engine text with tr() (or translate() where no Object is at hand); text
## without an entry stays English. tools/engine_text.py checks the catalogs
## against the code.

## Code, name in its own language, catalog script. English has no catalog.
const LANGUAGES := [
	["en", "English", ""],
	["ru", "Русский", "res://src/locale/ru.gd"],
	["uk", "Українська", "res://src/locale/uk.gd"],
	["de", "Deutsch", "res://src/locale/de.gd"],
	["fr", "Français", "res://src/locale/fr.gd"],
	["es", "Español", "res://src/locale/es.gd"],
	["pt", "Português (Brasil)", "res://src/locale/pt.gd"],
	["it", "Italiano", "res://src/locale/it.gd"],
	["pl", "Polski", "res://src/locale/pl.gd"],
	["tr", "Türkçe", "res://src/locale/tr.gd"],
	["id", "Bahasa Indonesia", "res://src/locale/id.gd"],
	["vi", "Tiếng Việt", "res://src/locale/vi.gd"],
	["zh", "简体中文", "res://src/locale/zh.gd"],
	["ja", "日本語", "res://src/locale/ja.gd"],
	["ko", "한국어", "res://src/locale/ko.gd"],
]

## The scalable font has no CJK glyphs and the web build has no system fonts,
## so these languages carry a subset of Noto Sans CJK with every character
## their catalog uses. tools/engine_text.py fonts writes them.
const FONTS := {
	"zh": "res://src/locale/noto_sans_sc.otf",
	"ja": "res://src/locale/noto_sans_jp.otf",
	"ko": "res://src/locale/noto_sans_kr.otf",
}

## The setting value when the engine follows the game's language.
const AUTO := "auto"

static var current := "en"
static var loaded := {}


static func codes() -> Array:
	return LANGUAGES.map(func(entry): return entry[0])


static func native_name(code: String) -> String:
	for entry in LANGUAGES:
		if entry[0] == code:
			return entry[1]
	return code


static func supported(code: String) -> String:
	"""The catalog for a locale such as pt_BR or zh-Hans, or "" when none fits."""
	var wanted := code.to_lower().replace("-", "_")
	if wanted in codes():
		return wanted
	var base := wanted.get_slice("_", 0)
	return base if base in codes() else ""


static func game_code(ipa_language: String) -> String:
	"""The engine code for an IPA language file name; the iPhone game names
	its English text gb."""
	return "en" if ipa_language.to_lower() == "gb" else ipa_language.to_lower()


static func resolve(setting: String, content_language: String) -> String:
	"""A chosen language wins. Auto follows the imported game, then the
	system, then English."""
	if setting != AUTO and setting in codes():
		return setting
	for candidate in [content_language, OS.get_locale()]:
		var found := supported(str(candidate))
		if not found.is_empty():
			return found
	return "en"


static func next_choice(setting: String) -> String:
	"""The setting after this one in the Options cycle: Auto, then each language."""
	var choices := [AUTO] + codes()
	var index := choices.find(setting)
	return choices[(maxi(index, 0) + 1) % choices.size()]


static func choice_name(setting: String, content_language: String) -> String:
	"""A setting as Options shows it; Auto names the language it resolves to."""
	if setting in codes():
		return native_name(setting)
	return translate("Auto · %s") % native_name(resolve(AUTO, content_language))


static func apply(code: String) -> void:
	if not code in codes():
		code = "en"
	catalog(code)
	current = code
	TranslationServer.set_locale(code)
	# The names in the language list need every script whatever the language.
	var fallbacks: Array[Font] = []
	for script_code in [code] + FONTS.keys().filter(func(other): return other != code):
		var font := cjk_font(script_code)
		if font != null:
			fallbacks.append(font)
	ThemeDB.fallback_font.fallbacks = fallbacks


static func catalog(code: String) -> Translation:
	"""A language's catalog, loaded once; null for English, the source text."""
	if code == "en" or not code in codes():
		return null
	if not loaded.has(code):
		var translation := Translation.new()
		translation.locale = code
		var source: Dictionary = load(LANGUAGES[codes().find(code)][2]).TEXT
		for key in source:
			translation.add_message(key, source[key])
		TranslationServer.add_translation(translation)
		loaded[code] = translation
	return loaded[code]


static func text_in(code: String, text: String) -> String:
	"""Engine text in a given language, whichever one is in use."""
	var translation := catalog(code)
	if translation == null:
		return text
	var found := String(translation.get_message(text))
	return text if found.is_empty() else found


static func catalog_text(code: String) -> String:
	"""Every translated text of a language, for glyph checks."""
	var translation := catalog(code)
	if translation == null:
		return ""
	return "".join(translation.get_translated_message_list())


static func cjk_font(code: String) -> Font:
	"""The bundled glyphs for a language, or null. An export keeps the file
	as it is, so the raw font is read in both a source run and a build."""
	if not FONTS.has(code):
		return null
	if loaded.has("font:" + code):
		return loaded["font:" + code]
	var font := FontFile.new()
	if font.load_dynamic_font(FONTS[code]) != OK:
		return null
	loaded["font:" + code] = font
	return font


static func translate(text: String) -> String:
	"""tr() for code with no Object at hand, such as a static function."""
	return String(TranslationServer.translate(text))


# ------------------------------------------------- the imported game's language

## Words common in running text of each Latin-script language and rare in the
## others. A fan translation often replaces the text of the gb file and keeps
## its name, so the text itself is read as well.
const COMMON_WORDS := {
	"en": ["the", "and", "you", "your", "to", "of", "is", "with"],
	"de": ["der", "die", "und", "das", "sie", "nicht", "mit", "ist"],
	"fr": ["le", "les", "des", "vous", "et", "est", "une", "pour"],
	"es": ["el", "los", "las", "que", "para", "una", "con", "del"],
	"it": ["il", "della", "che", "per", "una", "sono", "non", "gli"],
	"pt": ["os", "que", "para", "uma", "não", "você", "com", "seu"],
	"pl": ["się", "nie", "jest", "na", "że", "do", "jak", "przez"],
	"tr": ["ve", "bir", "bu", "için", "ile", "çok", "daha", "olarak"],
	"id": ["yang", "dan", "untuk", "dengan", "anda", "ini", "tidak", "dari"],
	"vi": ["và", "của", "bạn", "không", "có", "được", "những", "một"],
}


static func content_language(file_language: String, strings: Array) -> String:
	"""The language of an imported language file: its name, unless the text
	says otherwise. Fan translations commonly replace the English text but keep
	the gb file. "" when the text shows no language."""
	var named := game_code(file_language)
	var sample := ""
	for value in strings:
		sample += " " + str(value)
		if sample.length() > 20000:
			break
	var cyrillic := 0
	var han := 0
	var kana := 0
	var hangul := 0
	var latin := 0
	for character in sample:
		var c := character.unicode_at(0)
		if c >= 0x400 and c <= 0x4ff:
			cyrillic += 1
		elif c >= 0x3040 and c <= 0x30ff:
			kana += 1
		elif c >= 0xac00 and c <= 0xd7af:
			hangul += 1
		elif c >= 0x4e00 and c <= 0x9fff:
			han += 1
		elif (c >= 0x41 and c <= 0x5a) or (c >= 0x61 and c <= 0x7a):
			latin += 1
	if cyrillic > latin:
		# Ukrainian letters that Russian does not use.
		for letter in ["і", "ї", "є", "ґ"]:
			if sample.count(letter) > sample.length() / 2000:
				return "uk"
		return named if named in ["ru", "uk", "be", "bg", "sr"] else "ru"
	if kana > 0 and kana * 4 > han:
		return "ja"
	if hangul > latin:
		return "ko"
	if han > latin:
		return "zh"
	if named != "en" and not named.is_empty():
		return named
	var words := {}
	for word in sample.to_lower().replace("\n", " ").split(" ", false):
		var bare := word.strip_edges().trim_suffix(".").trim_suffix(",").trim_suffix("!").trim_suffix("?")
		words[bare] = int(words.get(bare, 0)) + 1
	# No telling word: unknown, so the system or browser language decides.
	var best := ""
	var best_score := 0
	for code in COMMON_WORDS:
		var score := 0
		for word in COMMON_WORDS[code]:
			score += int(words.get(word, 0))
		if score > best_score:
			best = code
			best_score = score
	return best
