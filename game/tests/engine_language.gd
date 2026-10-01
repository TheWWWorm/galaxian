extends SceneTree
## Focused checks for the remake's own interface text: Auto follows the imported
## game's language, then the system language; every catalog loads, and Chinese,
## Japanese and Korean draw with their bundled glyphs. Needs no imported content.
const EngineLanguage = preload("res://src/presentation/engine_language.gd")
var failures := 0
var checks := 0

func _initialize(): call_deferred("run")

func check(ok: bool, description: String):
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + description)

func run():
	check(EngineLanguage.game_code("gb") == "en", "The iPhone gb language is English")
	check(EngineLanguage.content_language("gb", ["New Game", "Options", "Resume", "Are you sure you want to quit?"]) == "en", "English text in gb reads as English")
	var russian := ["Новая игра", "Настройки", "Вы уверены, что хотите выйти?"]
	check(EngineLanguage.content_language("ru", russian) == "ru", "A ru file reads as Russian")
	check(EngineLanguage.content_language("gb", russian) == "ru", "Russian text in a gb file reads as Russian")
	check(EngineLanguage.content_language("gb", ["Розпочати нову гру", "Налаштування", "Ви впевнені?"]) == "uk", "Ukrainian letters read as Ukrainian")
	check(EngineLanguage.content_language("de", ["Neues Spiel", "Optionen"]) == "de", "A de file reads as German")
	check(EngineLanguage.content_language("gb", ["新しいゲームを始める", "設定"]) == "ja", "Kana read as Japanese")
	check(EngineLanguage.content_language("gb", ["开始新游戏", "设置"]) == "zh", "Han without kana reads as Chinese")
	check(EngineLanguage.content_language("gb", ["새 게임 시작", "설정"]) == "ko", "Hangul reads as Korean")
	check(EngineLanguage.resolve(EngineLanguage.AUTO, "") == EngineLanguage.resolve(EngineLanguage.AUTO, OS.get_locale()), "An unknown game language falls back to the system language")
	check(EngineLanguage.resolve(EngineLanguage.AUTO, "ru") == "ru", "Auto follows the game")
	check(EngineLanguage.resolve("", "fr") == "fr", "An unanswered setting follows the game")
	check(EngineLanguage.resolve("de", "ru") == "de", "A chosen language wins over the game's")
	check(EngineLanguage.resolve("xx", "ru") == "ru", "An unknown setting is Auto")
	check(EngineLanguage.supported("pt_BR") == "pt" and EngineLanguage.supported("zh-Hans") == "zh" and EngineLanguage.supported("nl").is_empty(), "Regional locales find their language")
	var choice := EngineLanguage.AUTO
	for _i in EngineLanguage.codes().size() + 1:
		choice = EngineLanguage.next_choice(choice)
	check(choice == EngineLanguage.AUTO, "Interface language choices cycle back to Auto")
	for code in EngineLanguage.codes():
		EngineLanguage.apply(code)
		check(EngineLanguage.current == code and TranslationServer.get_locale() == code, "%s applies" % code)
		var resume := EngineLanguage.translate("Resume")
		check((resume == "Resume") == (code == "en"), "%s translates interface text" % code)
		var question := EngineLanguage.text_in(code, "Which language should this remake's own menus and messages use? You can change it later under Options.")
		check(code == "en" or not question.begins_with("Which language"), "%s asks the first-start question in its own language" % code)
		if EngineLanguage.FONTS.has(code):
			var font: Font = EngineLanguage.cjk_font(code)
			check(font != null, "%s has its bundled font" % code)
			if font != null:
				for character in resume + question + EngineLanguage.native_name(code):
					if character.unicode_at(0) >= 0x1100:
						check(font.has_char(character.unicode_at(0)), "%s font draws %s" % [code, character])
			check(ThemeDB.fallback_font.fallbacks.size() == EngineLanguage.FONTS.size(), "%s keeps every CJK font as a fallback" % code)
	EngineLanguage.apply("en")
	check(EngineLanguage.translate("Resume") == "Resume", "English is the source text")
	print("ENGINE_LANGUAGE %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
