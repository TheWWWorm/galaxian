extends "res://src/presentation/choice_window.gd"
## The original survival summary over an owner-paused flight or resumed receipt.
## Confirmation requests menu flow; score submission belongs to the archive.


func present_result(archive, appearance: Dictionary) -> bool:
	var summary: Dictionary = archive.result_summary()
	if summary.is_empty():
		hide()
		return false
	var rules: Dictionary = archive.declarations.scores
	present(
		archive.library,
		appearance,
		result_text(archive.library, rules, summary),
		[archive.library.text(int(rules.labels.main_menu))]
	)
	return true


static func result_text(data, rules: Dictionary, summary: Dictionary) -> String:
	var labels: Dictionary = rules.labels
	var format: Dictionary = rules.format
	var title: String = data.text(int(labels.defeat))
	if summary.score < rules.minimum_result_score:
		return title + str(format.zero_suffix)
	var fields: Array[String] = [title]
	var values := {
		"kills": str(int(summary.kills)),
		"time": duration(float(summary.elapsed)),
		"score": str(int(summary.score))
	}
	for field in ["kills", "time", "score"]:
		fields.append(
			(
				data.text(int(labels[field]))
				+ str(format.label_suffix)
				+ str(format.value_break)
				+ values[field]
			)
		)
	return str(format.paragraph).join(fields)


static func duration(seconds: float) -> String:
	var whole := maxi(0, int(seconds))
	var minutes := (whole / 60) % 60
	var remainder := whole % 60
	var hours := whole / 3600
	return (
		"%02d:%02d:%02d" % [hours, minutes, remainder]
		if hours > 0
		else "%02d:%02d" % [minutes, remainder]
	)
