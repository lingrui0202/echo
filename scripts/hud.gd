extends CanvasLayer
## HUD：常驻状态行 + Tab 数据面板 + 通关结算面板。
## 放在 CanvasLayer 上，所以不受 CanvasModulate 变暗影响。

var _hint: Label
var _panel: PanelContainer
var _stats: Label
var _show_stats := false

var _result: PanelContainer
var _result_text: Label
var _shown := false

func _ready() -> void:
	_hint = Label.new()
	_hint.position = Vector2(16, 10)
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
	add_child(_hint)

	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 48)
	_panel.visible = false
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 16)
	_panel.add_child(_stats)
	add_child(_panel)

	# 结算面板：一局结束后摆在屏幕中间，把这一局的数说清楚
	_result = PanelContainer.new()
	_result.set_anchors_preset(Control.PRESET_CENTER)
	_result.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result.grow_vertical = Control.GROW_DIRECTION_BOTH
	_result.visible = false
	_result_text = Label.new()
	_result_text.add_theme_font_size_override("font_size", 20)
	_result_text.add_theme_color_override("font_color", Color(0.85, 0.96, 1.0))
	_result_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_child(_result_text)
	add_child(_result)

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("stats"):
		_show_stats = not _show_stats
		_panel.visible = _show_stats
		if _show_stats:
			_stats.text = GameLog.summary_text()

	var won := GameLog.last_reason == "win"
	if won and not _shown:
		_shown = true
		var r: Dictionary = GameLog.last_run()
		var cells := int(r.get("cells_visited", 0))
		var entries := int(r.get("entries", 0))
		var revisit := float(r.get("revisit_ratio", 0.0))
		_result_text.text = "通  关\n\n用时 %.1f s     声呐 %d 次\n走过 %d 格（进入 %d 次）\n重复率 %.0f %%\n\n按 R 再试一次" % [
			float(r.get("duration_s", 0.0)), int(r.get("sonar_presses", 0)),
			cells, entries, revisit * 100.0,
		]
		_result.visible = true
	elif not won:
		_shown = false
		_result.visible = false

	var tail := ""
	if won:
		tail = "    通关！[R] 重开"
	_hint.text = "%5.1f s    声呐 %d 次    [空格] 发声呐   [Tab] 数据   [R] 重开%s" % [
		GameLog.elapsed(), GameLog.sonar_count, tail
	]
