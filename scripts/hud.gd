extends CanvasLayer

const Minimap = preload("res://scripts/minimap.gd")
## HUD：状态行 + 足迹小地图 + 教学提示 + Tab 数据面板 + Esc 设置 + 结算面板 + 心跳音。
## 放在 CanvasLayer 上，所以不受 CanvasModulate 变暗影响。

var _hint: Label
var _alert: Label
var _tutorial: Label
var _panel: PanelContainer
var _stats: Label
var _show_stats := false

var _settings: PanelContainer
var _settings_text: Label
var _settings_open := false

var _pick: PanelContainer
var _pick_text: Label

var _result: PanelContainer
var _result_text: Label
var _shown_reason := ""

var _minimap: Control
var _player: Node2D
var _minimap_ready := false

var _beat_t := 0.0

func _ready() -> void:
	_hint = Label.new()
	_hint.position = Vector2(16, 10)
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
	add_child(_hint)

	# 左上角足迹小地图：只画走过的格子，不画没去过的墙
	_minimap = Minimap.new()
	_minimap.position = Vector2(16, 66)
	add_child(_minimap)
	# 地图要等 level._ready 才有（子节点 _ready 先于父节点），所以推迟到第一帧再 setup。

	# 「有东西听见了」：1.5 秒的红色提示。没有它，玩家根本不知道这一声暴露了自己。
	_alert = Label.new()
	_alert.position = Vector2(16, 40)
	_alert.add_theme_font_size_override("font_size", 18)
	_alert.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	_alert.visible = false
	add_child(_alert)

	# 第 1 关的操作提示：只在还没发声呐的前十几秒出现
	_tutorial = Label.new()
	_tutorial.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tutorial.position = Vector2(0, -70)
	_tutorial.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tutorial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial.add_theme_font_size_override("font_size", 17)
	_tutorial.add_theme_color_override("font_color", Color(0.62, 0.78, 0.95))
	_tutorial.text = "WASD 移动     空格 声呐     E 强声呐     Tab 数据     Esc 设置"
	_tutorial.visible = false
	add_child(_tutorial)

	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 168)
	_panel.visible = false
	_stats = Label.new()
	_stats.add_theme_font_size_override("font_size", 16)
	_panel.add_child(_stats)
	add_child(_panel)

	# 设置面板：Esc 开关，123 切换三项
	_settings = PanelContainer.new()
	_settings.set_anchors_preset(Control.PRESET_CENTER)
	_settings.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_settings.grow_vertical = Control.GROW_DIRECTION_BOTH
	_settings.visible = false
	_settings_text = Label.new()
	_settings_text.add_theme_font_size_override("font_size", 18)
	_settings_text.add_theme_color_override("font_color", Color(0.82, 0.92, 1.0))
	_settings_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings.add_child(_settings_text)
	add_child(_settings)

	# 词条面板：第 2 关起开局二选一，选完才能动
	_pick = PanelContainer.new()
	_pick.set_anchors_preset(Control.PRESET_CENTER)
	_pick.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pick.grow_vertical = Control.GROW_DIRECTION_BOTH
	_pick.visible = false
	_pick_text = Label.new()
	_pick_text.add_theme_font_size_override("font_size", 19)
	_pick_text.add_theme_color_override("font_color", Color(0.85, 0.94, 1.0))
	_pick_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pick.add_child(_pick_text)
	add_child(_pick)

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


func _process(delta: float) -> void:
	# 换场景那一帧 HUD 已经被移出树，get_tree() 会是 null —— 这里必须挡住
	if not is_inside_tree() or get_tree() == null:
		return
	_update_minimap()
	_update_tutorial()
	_update_heartbeat(delta)
	_update_settings_panel()
	_update_pick_panel()

	if Input.is_action_just_pressed("stats"):
		_show_stats = not _show_stats
		_panel.visible = _show_stats
		if _show_stats:
			_stats.text = GameLog.summary_text() + "\n已探索   %.0f %%   （%d 格）" % [
				_minimap.explored_ratio() * 100.0, _minimap.visited_count()
			]

	var reason := GameLog.last_reason
	var ended := reason == "win" or reason == "caught"
	if ended and reason != _shown_reason:
		_shown_reason = reason
		_show_result(reason)
	elif not ended:
		_shown_reason = ""
		_result.visible = false

	var tail := ""
	if reason == "win":
		tail = "    通关！"
	elif reason == "caught":
		tail = "    被听见了"
	_alert.visible = GameLog.alert_age() < 1.5 and not ended
	_alert.text = "！有东西听见了" if _alert.visible else ""

	# 强声呐的冷却直接写在提示里，差多少秒一目了然
	var strong_hint := "[E] 强声呐"
	var player := get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if player != null and player.has_method("cooldown_ratios"):
		var ratios: Vector2 = player.cooldown_ratios()
		if ratios.y > 0.0:
			strong_hint = "[E] 强声呐 %.1fs" % (ratios.y * player.call("strong_cooldown"))

	var lvl := get_parent()
	var lvl_no := 1
	var lvl_total := 1
	if lvl != null and lvl.has_method("level_no"):
		lvl_no = lvl.level_no()
		lvl_total = lvl.level_total()

	_hint.text = "第 %d/%d 关   %5.1f s    声呐 %d 次    [空格] 发声呐   %s   [Tab] 数据   [R] 重开%s" % [
		lvl_no, lvl_total, GameLog.elapsed(), GameLog.sonar_count, strong_hint, tail
	]


## 词条二选一：按 1 / 2 选，选完才允许移动（player 那边会卡住）
func _update_pick_panel() -> void:
	if not Mods.pending:
		_pick.visible = false
		return
	_pick.visible = true
	if Input.is_action_just_pressed("slot_1"):
		Mods.pick(0)
		return
	if Input.is_action_just_pressed("slot_2"):
		Mods.pick(1)
		return
	var lines := "本关词条（选一个，按 1 / 2）\n\n"
	for i in Mods.choices.size():
		var c: Dictionary = Mods.choices[i]
		lines += "[%d]  %s      %s\n" % [i + 1, String(c.get("title", "")), String(c.get("desc", ""))]
	_pick_text.text = lines


## 存档摘要：已解锁几关、每关最好成绩
func _save_summary() -> String:
	if Session.is_test():
		return "测试模式：不写存档、不发词条\n退出后正式进度不受影响" + \
			"\n\n[4] 上一关    [5] 下一关"

	var lines := "存档：已解锁 %d/%d 关，本次从第 %d 关开始" % [
		Progress.unlocked + 1, Progress.TOTAL, Progress.level_index + 1
	]
	for i in Progress.TOTAL:
		var mark := "○"
		if Progress.is_cleared(i):
			mark = "● %.1f s  %s" % [Progress.best_time(i), Progress.best_grade(i)]
		elif i <= Progress.unlocked:
			mark = "· 可进入"
		lines += "\n  第 %d 关  %s" % [i + 1, mark]
	return lines


## 亮度/配色即时生效：不动关卡，只改黑暗层、光圈和波场颜色
func _apply_visuals() -> void:
	var lv := get_parent()
	if lv == null:
		return
	var dark := lv.get_node_or_null("Darkness")
	if dark != null:
		dark.color = Settings.dark_color()
	var p := get_tree().get_first_node_in_group("player")
	if p != null:
		var ambient := p.get_node_or_null("AmbientLight")
		if ambient != null:
			ambient.energy = float(p.get("AMBIENT_ENERGY")) * Settings.light_mul()
	var wave: Variant = lv.get("_wave")
	if wave != null and wave.has_method("set_palette"):
		wave.set_palette(Settings.palette)


## 换关：原地重建（不再 reload 场景，否则游戏会退回编辑器）
func _reload_level() -> void:
	_settings_open = false
	_settings.visible = false
	_restart_level()


func _restart_level() -> void:
	var lv := get_parent()
	if lv != null and lv.has_method("restart"):
		lv.restart()


## 关卡被重建后：小地图要按新地图重来，结算面板收起来
func on_level_changed() -> void:
	_minimap_ready = false
	if _minimap != null:
		_minimap.call("clear")
	_player = null
	_shown_reason = ""
	_result.visible = false
	_panel.visible = false
	_show_stats = false


## 第 1 关、还没发声呐的前 12 秒：把操作提示摆出来
func _update_tutorial() -> void:
	var lvl := get_parent()
	var first: bool = lvl != null and lvl.has_method("level_no") and lvl.level_no() == 1
	_tutorial.visible = Session.tutorial and first and not Session.is_test() \
		and GameLog.elapsed() < 12.0 and GameLog.sonar_count == 0 and GameLog.last_reason == ""


## 心跳：最近的敌人越近，跳得越快。黑暗里这是唯一"不用看"的危险提示。
func _update_heartbeat(delta: float) -> void:
	if not is_inside_tree():
		return
	var lvl := get_parent()
	if lvl == null:
		return
	var box := lvl.get_node_or_null("Enemies")
	if box == null or box.get_child_count() == 0 or _player == null:
		return
	var best := INF
	for e in box.get_children():
		best = minf(best, _player.global_position.distance_to(e.global_position))
	if best > 520.0:
		_beat_t = 0.0
		return
	var interval := lerpf(1.25, 0.32, 1.0 - best / 520.0)
	_beat_t += delta
	if _beat_t >= interval:
		_beat_t = 0.0
		Sfx.heart()


func _update_settings_panel() -> void:
	if Input.is_action_just_pressed("settings"):
		_settings_open = not _settings_open
		_settings.visible = _settings_open
	if not _settings_open:
		return
	if Input.is_action_just_pressed("slot_1"):
		Settings.cycle_dark()
		_apply_visuals()
	elif Input.is_action_just_pressed("slot_2"):
		Settings.cycle_volume()
	elif Input.is_action_just_pressed("slot_3"):
		Settings.cycle_palette()
		_apply_visuals()
	elif Input.is_action_just_pressed("slot_4"):
		if Progress.select_level(Progress.prev_index()):
			_reload_level()
	elif Input.is_action_just_pressed("slot_5"):
		if Progress.select_level(Progress.next_index()):
			_reload_level()
	elif Input.is_action_just_pressed("slot_6"):
		Progress.reset()
		_reload_level()
	elif Input.is_action_just_pressed("slot_7"):
		Session.quit_to_menu()
	_settings_text.text = "设  置\n\n%s\n\n[1] 亮度    [2] 音量    [3] 声呐配色\n\n%s\n\n[4] 上一关    [5] 下一关    [6] 重置进度    [7] 回主菜单\n\n按 Esc 关闭" % [
		Settings.describe(), _save_summary()
	]


## 每帧把玩家所在格喂给小地图（重复的格子内部会忽略）
func _update_minimap() -> void:
	if not _minimap_ready:
		var lvl := get_parent()
		if lvl == null or not lvl.has_method("map_rows"):
			return
		var rows: Array = lvl.map_rows()
		if rows.is_empty():
			return
		_minimap.setup(rows, lvl.goal_cell())
		_minimap_ready = true

	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	var cell := Vector2i((_player.global_position / 64.0).floor())
	_minimap.visit(cell)
	_minimap.set_player(cell)


## 通关 / 被抓共用一套结算，只改标题和颜色。
func _show_result(reason: String) -> void:
	var r: Dictionary = GameLog.last_run()
	var cells := int(r.get("cells_visited", 0))
	var entries := int(r.get("entries", 0))
	var revisit := float(r.get("revisit_ratio", 0.0))
	var grade := String(r.get("grade", "-"))
	var title := "通  关" if reason == "win" else "被 听 见 了"
	if reason == "win":
		var lv := get_parent()
		if lv != null and lv.has_method("level_no") and lv.level_no() >= lv.level_total():
			title = "全 部 通 关"

	var extra := ""
	var best := GameLog.best_duration(true)
	var mine := float(r.get("duration_s", 0.0))
	if reason == "win":
		if best < INF and best > 0.0:
			var diff := mine - best
			extra = "新纪录！比之前快 %.1f s" % -diff if diff < 0.0 else "比最好成绩慢 %.1f s" % diff
		else:
			extra = "这是第一条通关记录"
	if extra != "":
		extra = "\n" + extra

	var par := GameLog.par_seconds(int((r.get("config", {}) as Dictionary).get("route_len", 120)))
	_result_text.text = "%s        评价 %s\n\n用时 %.1f s（目标 %.0f s）  声呐 %d 次  被听见 %d 次\n走过 %d 格（进入 %d 次）\n重复率 %.0f %%\n%s\n\n按 R 再试一次" % [
		title, grade, mine, par, int(r.get("sonar_presses", 0)), int(r.get("alerts", 0)),
		cells, entries, revisit * 100.0, extra,
	]
	_result_text.add_theme_color_override("font_color",
		Color(0.85, 0.96, 1.0) if reason == "win" else Color(1.0, 0.62, 0.55))
	_result.visible = true
