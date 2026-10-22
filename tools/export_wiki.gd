extends SceneTree
## Writes the reference of an imported game as a web page folder:
##   godot-4 --path game --script ../tools/export_wiki.gd -- CONTENT OUTPUT [--chapter=N] [--language=CODE]
## (from the repository root; Godot finds the script from the game folder).
## CONTENT is the imported content folder the game keeps for an IPA. The
## pages hold that game's own text and art. The hosted edition in
## public/wiki is the full story written from the English iPhone release;
## keep any other output outside this repository. With --chapter the story stops there, as it does for a pilot
## who has reached that chapter. Without --headless a window opens briefly
## while the ships are drawn for their pages.
const Library = preload("res://src/content/library.gd")
const Catalog = preload("res://src/wiki/wiki_catalog.gd")
const WikiExport = preload("res://src/wiki/wiki_export.gd")
const WikiSnapshots = preload("res://src/wiki/wiki_snapshots.gd")
const EngineLanguage = preload("res://src/presentation/engine_language.gd")


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var paths: Array = []
	var chapter := -1
	var language := "en"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--chapter="):
			chapter = argument.trim_prefix("--chapter=").to_int()
		elif argument.begins_with("--language="):
			language = argument.trim_prefix("--language=")
		# --path moves Godot into the project; a relative path means the shell's.
		elif argument.is_relative_path() and not OS.get_environment("PWD").is_empty():
			paths.append(OS.get_environment("PWD").path_join(argument).simplify_path())
		else:
			paths.append(argument)
	if paths.size() != 2:
		printerr("Usage: -- CONTENT OUTPUT [--chapter=N] [--language=CODE]")
		quit(2)
		return
	var library := Library.new()
	if not library.open(paths[0], str(paths[0]).get_file()):
		printerr("Not an imported content folder: ", paths[0], " (", library.error, ")")
		quit(1)
		return
	EngineLanguage.apply(language if language in EngineLanguage.codes() else "en")
	var catalog := Catalog.new(library, chapter, language)
	var renders := {}
	if WikiSnapshots.available():
		var camera := WikiSnapshots.new()
		root.add_child(camera)
		renders = await camera.render(catalog, paths[1])
		print("Rendered %d ships" % renders.size())
	var result := WikiExport.write(catalog, paths[1], renders, EngineLanguage.codes())
	if result != OK:
		printerr("Could not write ", paths[1], ": ", error_string(result))
		quit(1)
		return
	print("Wrote %d pages in %d languages to %s" % [catalog.ordered.size(), EngineLanguage.codes().size(), paths[1]])
	quit(0)
