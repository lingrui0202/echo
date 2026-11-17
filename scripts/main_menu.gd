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
var _last_mode := ""
var _page := 0
var _delete_mode := false
var _delete_armed := ""
var _sel := 0          # 当前光标（存档列表内 / 测试关卡号）

func _ready() -> void:
	# 背景：上深下更深的线性渐变 + 四周暗角
	var bg := TextureRect.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.055, 0.075, 0.105), Color(0.015, 0.02, 0.032)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	bg.texture = gt
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vig := TextureRect.new()
	var vg := Gradient.new()
	vg.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	vg.colors = PackedColorArray([
		Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0.85)])
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.45)
	vt.fill_to = Vector2(1.05, 1.0)
	vig.texture = vt
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)

	var title := Label.new()
	_title = title
	title.text = "ECHO · 回 声"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", ACCENT)
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.12, 0.22, 0.9))
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-170, 18)
	add_child(title)

	var sub := Label.new()
	_sub = sub
	sub.text = "全黑的地下，用回声当眼睛 —— 但声音也会被听见"
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", DIM)
	sub.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(-200, 96)
	add_child(sub)

	var box := VBoxContainer.new()
	_box = box
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-150, -118)
	box.add_theme_constant_override("separation", 7)
	add_child(box)

	var items := [
		["新 存 档", "1", "_on_new"],
		["加 载 存 档", "2", "_on_load"],
		["测  试", "3", "_on_test"],
		["排 行 榜", "4", "_on_rank"],
		["设  置", "5", "_on_settings"],
		["成  就", "6", "_on_achv"],
		["每日挑战", "7", "_on_daily"],
		["退  出", "8", "_on_quit"],
	]
	for it in items:
		var b := Button.new()
		b.text = "%s    [%s]" % [it[0], it[1]]
		b.custom_minimum_size = Vector2(320, 38)
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_stylebox_override("normal", _btn_style(false))
		b.add_theme_stylebox_override("hover", _btn_style(true))
		b.add_theme_stylebox_override("pressed", _btn_style(true))
		b.add_theme_stylebox_override("focus", _btn_style(true))
		b.add_theme_color_override("font_color", Color(0.86, 0.93, 1.0))
		b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		b.pressed.connect(Callable(self, it[2]))
		box.add_child(b)

	var hint := Label.new()
	_hint = hint
	hint.text = "按 1–8 选择   ·   面板里按 Esc 关闭"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", DIM)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-230, -40)
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
	_panel_text.add_theme_font_size_override("font_size", 15)
	_panel_text.add_theme_color_override("font_color", Color(0.86, 0.93, 1.0))
	# 图鉴/排行榜内容会长过屏幕，包一层滚动区
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(_panel_text)
	_panel.add_child(scroll)
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
	_mode = "test"
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://_verify/menu_test.png")
	print("[menu] _verify/menu_test.png")
	_mode = "codex"
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://_verify/menu_codex.png")
	print("[menu] _verify/menu_codex.png")
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
		_on_achv()
	elif Input.is_action_just_pressed("slot_7"):
		_on_daily()
	elif Input.is_action_just_pressed("slot_8"):
		_on_quit()

## 按钮样式：平时半透明深色，悬浮时高亮描边
func _btn_style(hot: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.13, 0.19, 0.92) if not hot else Color(0.14, 0.24, 0.36, 0.96)
	sb.border_color = Color(0.30, 0.45, 0.62, 0.7) if not hot else Color(0.55, 0.80, 1.0, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(8)
	return sb


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
	_page = 0
	_delete_mode = false
	_delete_armed = ""

func _on_test() -> void:
	_mode = "test"

func _on_rank() -> void:
	_mode = "rank"

func _on_settings() -> void:
	_mode = "settings"

func _on_achv() -> void:
	_mode = "achv"

func _on_daily() -> void:
	_mode = "daily"

func _on_quit() -> void:
	Session.quit_game()

func _when(ts: float) -> String:
	if ts <= 0.0:
		return "未知时间"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(int(ts) + bias)
	return "%02d-%02d %02d:%02d" % [d["month"], d["day"], d["hour"], d["minute"]]


## 加载存档：↑↓ 选、回车载入；数字键作为快捷方式
func _pick_save() -> void:
	var start := _page * 9
	var count := clampi(_save_list.size() - start, 0, 9)
	for k in 9:
		var i := start + k
		if i >= _save_list.size():
			break
		if Input.is_action_just_pressed("slot_%d" % (k + 1)):
			_sel = k
			_do_load(i)
			return
	if count == 0:
		return
	_sel = clampi(_sel, 0, count - 1)
	if Input.is_action_just_pressed("move_up"):
		_sel = (_sel - 1 + count) % count
	if Input.is_action_just_pressed("move_down"):
		_sel = (_sel + 1) % count
	if Input.is_action_just_pressed("confirm"):
		_do_load(start + _sel)


func _do_load(i: int) -> void:
	if i < 0 or i >= _save_list.size():
		return
	var id := String((_save_list[i] as Dictionary)["id"])
	if Progress.load_save(id):
		Session.start_campaign(false)


## 删除模式：光标 + 回车，连按两次回车才删（防手滑）
func _pick_delete() -> void:
	var start := _page * 9
	var count := clampi(_save_list.size() - start, 0, 9)
	for k in 9:
		var i := start + k
		if i >= _save_list.size():
			break
		if Input.is_action_just_pressed("slot_%d" % (k + 1)):
			_sel = k
			_arm_delete(i)
			return
	if count == 0:
		return
	_sel = clampi(_sel, 0, count - 1)
	if Input.is_action_just_pressed("move_up"):
		_sel = (_sel - 1 + count) % count
	if Input.is_action_just_pressed("move_down"):
		_sel = (_sel + 1) % count
	if Input.is_action_just_pressed("confirm"):
		_arm_delete(start + _sel)


func _arm_delete(i: int) -> void:
	if i < 0 or i >= _save_list.size():
		return
	var id := String((_save_list[i] as Dictionary)["id"])
	if _delete_armed == id:
		Progress.delete_save(id)
		_delete_armed = ""
		_sel = 0
	else:
		_delete_armed = id


## 选关：↑↓ 或 ←→ 选、回车开始；数字 1–9 直接进对应关，0 = 第 10 关
func _pick_level(for_test: bool) -> bool:
	var total := Progress.TOTAL
	for k in 9:
		if Input.is_action_just_pressed("slot_%d" % (k + 1)):
			return _start_level(k, for_test)
	if Input.is_action_just_pressed("slot_0"):
		return _start_level(9, for_test)

	_sel = clampi(_sel, 0, total - 1)
	if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("page_prev"):
		_sel = (_sel - 1 + total) % total
	if Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("page_next"):
		_sel = (_sel + 1) % total
	if Input.is_action_just_pressed("confirm"):
		return _start_level(_sel, for_test)
	return false


func _start_level(idx: int, for_test: bool) -> bool:
	if idx < 0 or idx >= Progress.TOTAL:
		return false
	_sel = idx
	if for_test:
		Session.start_test(idx)
	else:
		Progress.select_level(idx)
		Session.start_campaign(false)
	return true

## 一关的简短说明：敌人数 + 有哪些机关
func _level_brief(i: int) -> String:
	var lm: Array = Levels.MAPS[i]
	var body := "".join(lm)
	var bits: Array = []
	var enemies := 0
	if LevelScript.ENEMY_BY_LEVEL.size() > i:
		enemies = int(LevelScript.ENEMY_BY_LEVEL[i])
	bits.append("敌 %d" % enemies)
	if body.count("D") > 0:
		bits.append("门")
	if body.count("K") > 0:
		bits.append("钥匙")
	if body.count("P") > 0:
		bits.append("压力板")
	if body.count("X") > 0:
		bits.append("静音区")
	if body.count("D") == 0 and body.count("K") == 0 and body.count("P") == 0 and body.count("X") == 0:
		bits.append("纯探索")
	return " · ".join(bits)


func _refresh_panel() -> void:
	var scroll := _panel.get_child(0) as ScrollContainer
	if scroll != null and _last_mode != _mode:
		_last_mode = _mode
		scroll.scroll_vertical = 0
	match _mode:
		"save":
			_save_list = Progress.list_saves()
			var pages := maxi(1, int(ceil(float(_save_list.size()) / 9.0)))
			_page = clampi(_page, 0, pages - 1)
			if Input.is_action_just_pressed("page_next"):
				_page = mini(_page + 1, pages - 1)
			if Input.is_action_just_pressed("page_prev"):
				_page = maxi(_page - 1, 0)
			if Input.is_action_just_pressed("slot_0"):
				_delete_mode = not _delete_mode
				_delete_armed = ""

			var head := "加载存档" if not _delete_mode else "删除存档（按 0 退出删除模式）"
			var lines := "%s（第 %d/%d 页 · 共 %d 个 · Esc 返回）\n\n" % [
				head, _page + 1, pages, _save_list.size()]
			if _save_list.is_empty():
				lines += "还没有存档，按 Esc 返回后选「新存档」\n"
			var start := _page * 9
			for k in 9:
				var i := start + k
				if i >= _save_list.size():
					break
				var sv: Dictionary = _save_list[i]
				var tag := "已通 %d/%d 关" % [int(sv["cleared_count"]), Progress.TOTAL]
				if bool(sv["finished"]):
					tag = "已全部通关"
				var mark := " "
				if _delete_mode:
					if _delete_armed == String(sv["id"]):
						mark = "!"
				elif k == _sel:
					mark = "▶"
				lines += "%s[%d]  %s 创建   第 %d 关   %s\n" % [
					mark, k + 1, _when(float(sv.get("created", sv["updated"]))),
					int(sv["level"]) + 1, tag]
			if _delete_mode:
				lines += "\n⚠ 选中后连按两次 Enter 才删除"
			else:
				lines += "\n↑↓ 选择   Enter 载入   0 删除存档   左右翻页"
			_panel_text.text = lines
			if _delete_mode:
				_pick_delete()
			else:
				_pick_save()
		"test":
			_sel = clampi(_sel, 0, Progress.TOTAL - 1)
			var rows := ""
			for i in Progress.TOTAL:
				var lm: Array = Levels.MAPS[i]
				var w := String(lm[0]).length()
				var cur := "▶" if i == _sel else "  "
				rows += "%s %2d   %2d×%2d   %s\n" % [cur, i + 1, w, lm.size(), _level_brief(i)]
			_panel_text.text = ("测试模式（Esc 返回）\n\n"
				+ "· 十关全部开放    · 不发词条\n"
				+ "· 不写存档、不影响正式进度\n\n"
				+ rows
				+ "\n↑↓ 选择   Enter 开始   1–9 直选（0 = 第 10 关）")
			_pick_level(true)
		"rank":
			_panel_text.text = _rank_text()
		"achv":
			_panel_text.text = _achv_text()
		"daily":
			var lv: int = (get_node_or_null("/root/Session") as Node).call("daily_level")
			var best: float = GameLog.call("today_best", lv)
			var best_txt := "今天还没通关" if best == INF else "今天最好 %.1f s" % best
			_panel_text.text = "每日挑战（Esc 返回）\n\n今天是第 %d 关\n%s\n\n按 1 开始" % [
				lv + 1, best_txt]
			if Input.is_action_just_pressed("slot_1"):
				(get_node_or_null("/root/Session") as Node).call("start_daily")
		"settings":
			if Input.is_action_just_pressed("slot_1"):
				Settings.cycle_dark()
			elif Input.is_action_just_pressed("slot_2"):
				Settings.cycle_volume()
			elif Input.is_action_just_pressed("slot_3"):
				Settings.cycle_palette()
			_panel_text.text = "设置（Esc 返回）\n\n%s\n\n[1] 亮度   [2] 音量   [3] 声呐配色" % Settings.describe()

## 成就 + 统计
func _achv_text() -> String:
	var lines := "成就与统计（Esc 返回）\n\n"
	var achv := get_node_or_null("/root/Achv")
	if achv != null:
		var got := 0
		for a in achv.call("status"):
			if bool(a["got"]):
				got += 1
				lines += "  [√] %s   %s\n" % [String(a["name"]), String(a["desc"])]
			else:
				lines += "  [ ] %s   %s\n" % [String(a["name"]), String(a["desc"])]
		lines += "\n共 %d/%d 个成就\n" % [got, achv.call("status").size()]
	lines += "\n累计：%d 局 · 通关 %d 局 · 声呐 %d 次 · 被听见 %d 次 · 碎片 %d 枚" % [
		Progress.total_runs, Progress.total_wins, Progress.total_sonar,
		Progress.total_alerts, Progress.fragments]
	return lines


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
const Levels = preload("res://scripts/levels.gd")
const LevelScript = preload("res://scripts/level.gd")
