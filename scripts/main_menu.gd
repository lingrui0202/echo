extends Control
## 首页：新存档 / 加载存档 / 测试 / 排行榜 / 设置 / 退出。
## 主菜单用 1–6；面板打开后 1–N 归面板用，Esc 关闭。

const ACCENT := Color(0.55, 0.80, 1.0)
const DIM := Color(0.55, 0.62, 0.72)

var _panel: PanelContainer
var _panel_text: Label
var _mode := ""
var _box: VBoxContainer
var _title: Label
var _sub: Label
var _hint: Label
var _was_pressed := {}
var _save_list: Array = []

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	_title = title
	title.text = "ECHO · 回 声"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", ACCENT)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-170, 60)
	add_child(title)

	var sub := Label.new()
	_sub = sub
	sub.text = "靠声呐在黑暗里探路"
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", DIM)
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(-90, 118)
	add_child(sub)

	var box := VBoxContainer.new()
	_box = box
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-150, -60)
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var items := [
		["新 存 档", "1", "_on_new"],
		["加 载 存 档", "2", "_on_load"],
		["测  试", "3", "_on_test"],
		["排 行 榜", "4", "_on_rank"],
		["设  置", "5", "_on_settings"],
		["退  出", "6", "_on_quit"],
	]
	for it in items:
		var b := Button.new()
		b.text = "%s    [%s]" % [it[0], it[1]]
		b.custom_minimum_size = Vector2(320, 44)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(Callable(self, it[2]))
		box.add_child(b)

	var hint := Label.new()
	_hint = hint
	hint.text = "按 1–6 选择   ·   面板里按 Esc 关闭"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", DIM)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-230, -50)
	add_child(hint)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.075, 0.105, 0.985)
	sb.border_color = Color(0.32, 0.48, 0.68, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel_text = Label.new()
	_panel_text.add_theme_font_size_override("font_size", 16)
	_panel_text.add_theme_color_override("font_color", Color(0.86, 0.93, 1.0))
	_panel.add_child(_panel_text)
	add_child(_panel)
	_ready_shot()

func _ready_shot() -> void:
	if not OS.get_cmdline_args().has("--shot"):
		return
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://_verify/menu.png")
	print("[menu] _verify/menu.png")
	_mode = "rank"
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://_verify/menu_rank.png")
	print("[menu] _verify/menu_rank.png")
	_mode = "save"
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://_verify/menu_save.png")
	print("[menu] _verify/menu_save.png")
	get_tree().quit()


func _process(_delta: float) -> void:
	if _mode != "":
		_panel.visible = true
		_set_menu_visible(false)
		if Input.is_action_just_pressed("settings"):
			_mode = ""
			_panel.visible = false
			return
		_refresh_panel()
		return

	_panel.visible = false
	_set_menu_visible(true)
	if Input.is_action_just_pressed("slot_1"):
		_on_new()
	elif Input.is_action_just_pressed("slot_2"):
		_on_load()
	elif Input.is_action_just_pressed("slot_3"):
		_on_test()
	elif Input.is_action_just_pressed("slot_4"):
		_on_rank()
	elif Input.is_action_just_pressed("slot_5"):
		_on_settings()
	elif Input.is_action_just_pressed("slot_6"):
		_on_quit()

func _set_menu_visible(v: bool) -> void:
	if _box != null:
		_box.visible = v
	if _title != null:
		_title.visible = v
	if _sub != null:
		_sub.visible = v
	if _hint != null:
		_hint.visible = v


func _on_new() -> void:
	Session.start_campaign(true)

func _on_load() -> void:
	_mode = "save"

func _on_test() -> void:
	_mode = "test"

func _on_rank() -> void:
	_mode = "rank"

func _on_settings() -> void:
	_mode = "settings"

func _on_quit() -> void:
	Session.quit_game()

func _when(ts: float) -> String:
	if ts <= 0.0:
		return "未知时间"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(int(ts) + bias)
	return "%02d-%02d %02d:%02d" % [d["month"], d["day"], d["hour"], d["minute"]]


## 加载存档：按下 1–N 载入第 N 个槽
func _pick_save() -> void:
	for k in mini(_save_list.size(), 9):
		if Input.is_action_just_pressed("slot_%d" % (k + 1)):
			var id := String((_save_list[k] as Dictionary)["id"])
			if Progress.load_save(id):
				Session.start_campaign(false)
			return


## 面板里按下 1–5 → 进对应关卡
func _pick_level(for_test: bool) -> bool:
	for k in Progress.TOTAL:
		if Input.is_action_just_pressed("slot_%d" % (k + 1)):
			if for_test:
				Session.start_test(k)
			else:
				Progress.select_level(k)
				Session.start_campaign(false)
			return true
	return false

func _refresh_panel() -> void:
	match _mode:
		"save":
			_save_list = Progress.list_saves()
			var lines := "加载存档（按最后保存时间，Esc 返回）\n\n"
			if _save_list.is_empty():
				lines += "还没有存档\n"
			for i in _save_list.size():
				var sv: Dictionary = _save_list[i]
				var tag := "已通 %d/%d 关" % [int(sv["cleared_count"]), Progress.TOTAL]
				if bool(sv["finished"]):
					tag = "已全部通关"
				lines += "[%d]  %s 创建   第 %d 关   %s\n" % [
					i + 1, _when(float(sv.get("created", sv["updated"]))), int(sv["level"]) + 1, tag]
			lines += "\n按 1–%d 载入对应存档" % maxi(_save_list.size(), 1)
			_panel_text.text = lines
			_pick_save()
		"test":
			_panel_text.text = ("测试模式（Esc 返回）\n\n" +
				"· 5 关全部开放\n" +
				"· 不发词条\n" +
				"· 不写存档、不影响正式进度\n\n" +
				"按 1–5 进入对应关卡")
			_pick_level(true)
		"rank":
			_panel_text.text = _rank_text()
		"settings":
			if Input.is_action_just_pressed("slot_1"):
				Settings.cycle_dark()
			elif Input.is_action_just_pressed("slot_2"):
				Settings.cycle_volume()
			elif Input.is_action_just_pressed("slot_3"):
				Settings.cycle_palette()
			_panel_text.text = "设置（Esc 返回）\n\n%s\n\n[1] 亮度   [2] 音量   [3] 声呐配色" % Settings.describe()

## 排行榜：每关分开，数据来自 runs.json（历史成绩），开新存档不会清空它。
## 存档里的「最好成绩」是这一份存档自己的记录，两者互不影响。
func _rank_text() -> String:
	var lines := "排行榜（每关分开 · 历史成绩，开新存档不受影响）\n"
	for i in Progress.TOTAL:
		lines += "\n第 %d 关\n" % (i + 1)
		var top: Array = GameLog.top_runs(i, 5)
		if top.is_empty():
			lines += "    还没有成绩\n"
			continue
		for k in top.size():
			var r: Dictionary = top[k]
			lines += "    %d.  %6.1f s   %s   （声呐 %d 次）\n" % [
				k + 1, float(r.get("duration_s", 0.0)), String(r.get("grade", "-")),
				int(r.get("sonar_presses", 0))]
	return lines
