extends Node
## 遥测：每局自动记一条记录，存到 user://runs.json
## 这是整份期末报告的地基 —— 报告的"证据"全部来自这里。

const SAVE_PATH := "user://runs.json"
const HISTORY := 10
const CELL := 64.0

var sonar_count := 0
var last_reason := ""

var _t0 := 0.0
var _frozen := 0.0
var _ended := true
var _samples := 0
var _cells := {}
var _runs: Array = []

func _ready() -> void:
	_load()

func start_session() -> void:
	sonar_count = 0
	last_reason = ""
	_samples = 0
	_cells.clear()
	_frozen = 0.0
	_ended = false
	_t0 = Time.get_ticks_msec() / 1000.0

func elapsed() -> float:
	if _ended:
		return _frozen
	return Time.get_ticks_msec() / 1000.0 - _t0

func note_sonar() -> void:
	sonar_count += 1

func note_position(p: Vector2) -> void:
	if _ended:
		return
	_samples += 1
	_cells[Vector2i((p / CELL).floor())] = true

func end_session(reason: String) -> void:
	if _ended:
		return
	_ended = true
	last_reason = reason
	_frozen = Time.get_ticks_msec() / 1000.0 - _t0
	var rec := {
		"when": Time.get_datetime_string_from_system(),
		"reason": reason,
		"duration_s": snappedf(_frozen, 0.01),
		"sonar_presses": sonar_count,
		"cells_visited": _cells.size(),
		"revisit_ratio": 0.0 if _samples == 0 else snappedf(1.0 - float(_cells.size()) / float(_samples), 0.001),
	}
	_runs.append(rec)
	_save()
	print("[GameLog] ", rec)

func summary_text() -> String:
	var n: int = mini(_runs.size(), HISTORY)
	if n == 0:
		return "还没有数据。跑一局，再按 Tab。"
	var recent: Array = _runs.slice(_runs.size() - n)
	var total_dur := 0.0
	var total_sonar := 0
	var total_cells := 0
	var total_revisit := 0.0
	var wins := 0
	for rec in recent:
		total_dur += float(rec.get("duration_s", 0.0))
		total_sonar += int(rec.get("sonar_presses", 0))
		total_cells += int(rec.get("cells_visited", 0))
		total_revisit += float(rec.get("revisit_ratio", 0.0))
		if String(rec.get("reason", "")) == "win":
			wins += 1
	var lines := PackedStringArray()
	lines.append("最近 %d 局统计" % n)
	lines.append("平均用时        %.1f s" % (total_dur / n))
	lines.append("平均声呐次数    %.1f 次" % (float(total_sonar) / n))
	lines.append("平均走过格子    %.0f" % (float(total_cells) / n))
	lines.append("平均重复率      %.0f %%" % (total_revisit / n * 100.0))
	lines.append("通关率          %d / %d" % [wins, n])
	lines.append("")
	lines.append("本局：%s   %.1f s   声呐 %d 次" % [last_reason, elapsed(), sonar_count])
	lines.append("（数据文件：user://runs.json）")
	return "\n".join(lines)

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Array:
		_runs = data

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_runs, "  "))
