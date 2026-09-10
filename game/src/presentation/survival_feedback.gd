extends RefCounted
## Cosmetic notifications use the simulation clock. Keep this state on the live
## session so rebuilding its HUD during pause cannot replay already-seen notices.


static func initialize(score: int, combo: int, now_ms: float, rules: Dictionary) -> Dictionary:
	return {
		"clock": now_ms,
		"score": score,
		"combo": combo,
		"combo_until": now_ms,
		"notice_until": now_ms,
		"notice": -1,
		"queue": [],
		"seen": rules.notices.map(func(row): return score > int(row.above))
	}


static func advance(
	state: Dictionary, rules: Dictionary, score: int, combo: int, now_ms: float
) -> void:
	if now_ms < float(state.clock):
		return
	state.clock = now_ms
	for index in rules.notices.size():
		if not state.seen[index] and score > int(rules.notices[index].above):
			state.seen[index] = true
			state.queue.append(int(rules.notices[index].text))
	if score != int(state.score) and combo >= int(rules.combo_minimum):
		state.combo_until = now_ms + float(rules.combo_ms)
	state.combo = combo
	state.score = score
	if now_ms >= float(state.notice_until):
		state.notice = -1
		if not state.queue.is_empty():
			state.notice = state.queue.pop_front()
			state.notice_until = now_ms + float(rules.notice_ms)


static func combo_text(state: Dictionary, rules: Dictionary, library) -> String:
	if state.clock >= state.combo_until or state.combo < rules.combo_minimum:
		return ""
	var index := mini(int(state.combo) - int(rules.combo_minimum), rules.combo_text.size() - 1)
	return (
		(
			library.text(int(rules.combo_text[index]))
			+ str(rules.combo_separator)
			+ str(int(state.combo))
		)
		. to_upper()
	)


static func notice_text(state: Dictionary, library) -> String:
	return (
		library.text(int(state.notice))
		if state.notice >= 0 and state.clock < state.notice_until
		else ""
	)
