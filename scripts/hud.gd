extends CanvasLayer
## HUD：常驻状态行 + Tab 唤出的数据面板。
## 放在 CanvasLayer 上，所以不受 CanvasModulate 变暗影响。

var _hint: Label
var _panel: PanelContainer
var _stats: Label
var _show_stats := false

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

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("stats"):
		_show_stats = not _show_stats
		_panel.visible = _show_stats
		if _show_stats:
			_stats.text = GameLog.summary_text()

	var tail := ""
	if GameLog.last_reason == "win":
		tail = "    通关！[R] 重开"
	_hint.text = "%5.1f s    声呐 %d 次    [空格] 发声呐   [Tab] 数据   [R] 重开%s" % [
		GameLog.elapsed(), GameLog.sonar_count, tail
	]
