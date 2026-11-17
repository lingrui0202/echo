extends Node
## 首页 / 测试模式 自检（不触发换场景）。
##   Godot_v4.7.2-stable_win64_console.exe --path <本目录> res://tools/menu_check.tscn

const MenuScript = preload("res://scripts/main_menu.gd")

var _fails := PackedStringArray()
var _pass := 0

func _check(cond: bool, ok: String, bad: String) -> void:
	if cond:
		_pass += 1
		print("PASS  ", ok)
	else:
		_fails.append(bad)
		print("FAIL  ", bad)

func _ready() -> void:
	var session := get_node_or_null("/root/Session")
	var prog := get_node_or_null("/root/Progress")
	_check(session != null, "Session 已注册", "缺少 Session autoload")
	if session == null or prog == null:
		_finish()
		return

	# 整个测试都用临时存档目录，绝不碰玩家存档
	prog.set("persist", true)

	# 整个测试都用临时存档目录，绝不碰玩家存档
	prog.set("save_dir", "user://saves_test")
	DirAccess.make_dir_recursive_absolute("user://saves_test")
	_clean_dir("user://saves_test")
	prog.set("persist", true)

	# ---- 首页结构 ----
	var menu: Control = MenuScript.new()
	add_child(menu)
	await get_tree().process_frame
	var buttons := 0
	for c in menu.get_children():
		if c is Button:
			buttons += 1
		if c is VBoxContainer:
			buttons += c.get_child_count()
	_check(buttons >= 6, "首页有 6 个入口（新存档/加载/测试/排行榜/设置/退出）",
		"首页按钮数量不对：%d" % buttons)

	# ---- 加载存档面板 ----
	prog.set("persist", false)
	prog.set("persist", true)
	prog.call("new_save")
	prog.call("record_clear", 0, 30.0, "B")
	prog.set("level_index", 1)
	prog.call("save_now")
	menu.set("_mode", "save")
	menu.call("_refresh_panel")
	await get_tree().process_frame
	var txt: String = String(menu.get("_panel_text").text)
	_check(txt.contains("[1]") and txt.contains("第 2 关"), "加载面板列出存档槽（含所在关卡）",
		"加载面板内容不对：%s" % txt.left(90))
	_check(txt.contains("已通 1/%d 关" % Progress.TOTAL), "加载面板显示通了几个关卡",
		"没显示进度：%s" % txt.left(200))

	# ---- 排行榜：每关分开 ----
	menu.set("_mode", "rank")
	menu.call("_refresh_panel")
	await get_tree().process_frame
	var rank: String = String(menu.get("_panel_text").text)
	var heads := 0
	for i in Progress.TOTAL:
		if rank.contains("第 %d 关" % (i + 1)):
			heads += 1
	_check(heads == Progress.TOTAL, "排行榜按关分开（%d 个分段）" % Progress.TOTAL, "排行榜不是每关分开：%d 段" % heads)
	_check(rank.contains("还没有成绩") or rank.contains(" s "), "排行榜有内容（成绩或占位）",
		"排行榜是空的：%s" % rank.left(100))

	# ---- 设置面板 ----
	menu.set("_mode", "settings")
	menu.call("_refresh_panel")
	await get_tree().process_frame
	_check(String(menu.get("_panel_text").text).contains("亮度"), "设置面板在首页里也能开", "设置面板打不开")

	# ---- 成就：解锁条件 ----
	prog.set("persist", false)
	prog.set("achv", [])
	var achv := get_node_or_null("/root/Achv")
	_check(achv != null, "Achv 已注册", "缺少 Achv autoload")
	if achv != null:
		_check(achv.call("status").size() >= 10, "成就列表 %d 条" % achv.call("status").size(),
			"成就太少")
		achv.call("_on_run", {
			"reason": "win", "sonar_presses": 0, "alerts": 0, "grade": "S", "keys": 0,
			"config": {"level_index": 0},
		})
		_check(bool(prog.call("has_achv", "first_clear")), "通关第 1 关解锁「初次回声」", "没解锁")
		_check(bool(prog.call("has_achv", "silent_run")), "不用声呐通关解锁「静默行者」", "没解锁")
		_check(bool(prog.call("has_achv", "no_alert")), "没被听见解锁「没人听见」", "没解锁")
		_check(bool(prog.call("has_achv", "s_rank")), "S 评价解锁「快到回声」", "没解锁")

	menu.set("_mode", "achv")
	menu.call("_refresh_panel")
	await get_tree().process_frame
	var achv_txt: String = String(menu.get("_panel_text").text)
	_check(achv_txt.contains("初次回声") and achv_txt.contains("累计"),
		"成就面板列出成就与累计统计", "成就面板内容不对：%s" % achv_txt.left(60))

	# ---- 每日挑战：按日期选关 ----
	var sess2 := get_node_or_null("/root/Session")
	var dl: int = sess2.call("daily_level")
	menu.set("_mode", "daily")
	menu.call("_refresh_panel")
	await get_tree().process_frame
	var daily_txt: String = String(menu.get("_panel_text").text)
	_check(daily_txt.contains("第 %d 关" % (dl + 1)), "每日挑战显示今天的关卡",
		"每日面板内容不对：%s" % daily_txt.left(60))

	# ---- 测试模式：不发词条、不写存档 ----
	session.set("mode", 1)          # Mode.TEST
	prog.set("persist", false)
	prog.set("level_index", 2)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	var lv: Node = ps.instantiate()
	add_child(lv)
	await get_tree().process_frame
	var mods := get_node_or_null("/root/Mods")
	_check(not bool(mods.get("pending")), "测试模式不发词条（pending=false）", "测试模式还在要求选词条")
	_check(int(prog.get("level_index")) == 2, "测试模式能直接进第 3 关", "测试模式进不去第 3 关")
	_check(not bool(prog.get("persist")), "测试模式不写存档", "测试模式会写存档")
	# 测试模式里换关：不能再冒出词条面板
	lv.call("restart", 3)
	await get_tree().process_frame
	_check(not bool(mods.get("pending")), "测试模式换关也不发词条",
		"测试模式换到第 4 关又要求选词条了")

	# 测试模式下设置面板不该显示存档区
	var hud: Node = lv.get_node("HUD")
	var summary: String = hud.call("_save_summary")
	_check(summary.contains("测试模式") and not summary.contains("已解锁"),
		"测试模式下设置面板不显示存档", "测试模式还显示正式存档：%s" % summary.left(40))

	lv.queue_free()
	await get_tree().process_frame

	# ---- 多槽存档（用临时目录，别污染玩家存档）----
	prog.set("save_dir", "user://saves_test")
	DirAccess.make_dir_recursive_absolute("user://saves_test")
	_clean_dir("user://saves_test")
	prog.set("persist", true)
	var before: int = prog.call("list_saves").size()
	prog.call("new_save")
	var id_a := String(prog.get("slot_id"))
	prog.call("record_clear", 0, 30.0, "B")
	prog.call("record_clear", 1, 40.0, "A")
	prog.set("level_index", 2)
	prog.call("save_now")
	prog.call("new_save")
	var id_b := String(prog.get("slot_id"))
	_check(id_a != id_b, "新存档会开一个新槽", "新存档没开新槽")
	_check(int(prog.get("level_index")) == 0 and (prog.get("cleared") as Dictionary).is_empty(),
		"新存档从第 1 关、无记录开始", "新存档没清空进度")

	var slots: Array = prog.call("list_saves")
	_check(slots.size() >= 2, "存档列表里有多个槽（%d 个）" % slots.size(), "只有一个槽")
	if slots.size() >= 2:
			_check(String(slots[0]["id"]) == id_b, "最新的槽排在最前", "槽位没按时间排序")
	# 分页：只显示 9 条，翻页状态存在 _page
	_check(int(menu.get("_page")) == 0, "存档面板从第 1 页开始", "分页状态不对")

	# 删除：按同一个数字两次才删
	menu.set("_mode", "save")
	menu.call("_on_load")
	await get_tree().process_frame
	menu.set("_delete_mode", true)
	menu.call("_refresh_panel")
	await get_tree().process_frame
	var first_id := String((menu.get("_save_list")[0] as Dictionary)["id"])

	# 第一次按：只进入待删状态（交给菜单自己的 _process 处理，别双重调用）
	Input.action_press("slot_1")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release("slot_1")
	await get_tree().process_frame
	_check(String(menu.get("_delete_armed")) == first_id, "按一次只是标记待删（防手滑）",
		"按一次就删了：armed=%s" % String(menu.get("_delete_armed")))

	# 第二次按同一个：真删
	Input.action_press("slot_1")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release("slot_1")
	await get_tree().process_frame
	_check(not FileAccess.file_exists("user://saves_test/%s.json" % first_id),
		"第二次按同一个数字才真删", "删除没生效")
	menu.set("_delete_mode", false)

	_check(bool(prog.call("load_save", id_a)), "能载入旧槽", "载入旧槽失败")
	_check(String(prog.get("slot_id")) == id_a, "载入后当前槽切过去了", "当前槽没切")
	_check((prog.get("cleared") as Dictionary).size() == 2 and int(prog.get("level_index")) == 2,
		"旧槽的进度恢复了（第 3 关、通 2 关）", "旧槽进度没恢复")

	# 首页的加载面板应该把所有槽列出来
	menu.set("_mode", "save")
	menu.call("_refresh_panel")
	await get_tree().process_frame
	var save_txt: String = String(menu.get("_panel_text").text)
	_check(save_txt.contains("第 3 关") and save_txt.contains("已通 2/%d 关" % Progress.TOTAL),
		"加载面板显示槽的关卡与进度", "加载面板没显示进度：%s" % save_txt.left(90))
	_check(save_txt.contains(":"), "加载面板显示保存时间", "加载面板没有时间")

	# ---- 光标选择：↑↓ 移动，Enter 载入 ----
	# 先保证列表里至少两个槽（只有一条时光标没有可移动的目标）
	prog.call("new_save")
	prog.call("save_now")
	menu.set("_mode", "save")
	menu.call("_refresh_panel")
	await get_tree().process_frame
	_check(String(menu.get("_panel_text").text).contains("▶"), "存档面板有选中标记",
		"没有选中标记：%s" % String(menu.get("_panel_text").text).left(60))
	menu.set("_sel", 0)
	await _tap("move_down")
	_check(int(menu.get("_sel")) == 1, "↑↓ 能移动存档光标", "光标没动：%d" % int(menu.get("_sel")))
	await _tap("move_up")
	_check(int(menu.get("_sel")) == 0, "↑ 能把光标移回去", "光标回不去：%d" % int(menu.get("_sel")))

	# ---- 测试面板：10 关都能选，0 = 第 10 关 ----
	menu.set("_mode", "test")
	menu.call("_refresh_panel")
	await get_tree().process_frame
	var test_txt: String = String(menu.get("_panel_text").text)
	var listed := 0
	for line in test_txt.split("\n"):
		if line.strip_edges().begins_with("▶") or line.strip_edges().substr(0, 2).strip_edges().is_valid_int():
			listed += 1
	_check(listed >= 10, "测试面板列出十关（%d 行）" % listed, "测试面板只列了 %d 关" % listed)
	_check(test_txt.contains("0 = 第 10 关"), "测试面板说明 0 代表第 10 关", "没有说明 0 键")
	menu.set("_sel", 0)
	await _tap("move_down")
	_check(int(menu.get("_sel")) == 1, "测试面板光标能移动", "测试光标没动")
	menu.set("_sel", 9)
	_check(int(menu.get("_sel")) == 9 and Progress.TOTAL == 10, "光标能到第 10 关",
		"光标到不了第 10 关")
	menu.set("_mode", "")
	menu.call("_refresh_panel")
	await get_tree().process_frame

	_clean_dir("user://saves_test")

	# ---- 开新存档不影响排行榜（runs.json 是另一份数据）----
	var runs_before: int = GameLog.call("history_size")
	prog.call("new_save")
	_check(int(GameLog.call("history_size")) == runs_before,
		"新存档不清空历史成绩（排行榜独立）", "新存档把历史成绩也清了")

	# ---- 读档时过滤掉假的 0.1 秒成绩 ----
	prog.set("save_dir", "user://saves_test")
	var path := "user://saves_test/test_filter.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"id":"test_filter","unlocked":2,"level_index":0,"cleared":{"0":{"time":0.1,"grade":"S"},"1":{"time":42.0,"grade":"B"}}}')
	f.close()
	_check(bool(prog.call("load_save", "test_filter")), "能载入测试槽", "载入测试槽失败")
	_check(not bool(prog.call("is_cleared", 0)), "读档丢掉 0.1 秒的假成绩", "0.1 秒被当成真记录")
	_check(bool(prog.call("is_cleared", 1)), "正常的 42 秒记录保留", "真成绩被误删")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	prog.set("save_dir", "user://saves")

	session.set("mode", 0)
	_finish()

func _save_list_now(menu: Control) -> Array:
	menu.call("_refresh_panel")
	return menu.get("_save_list")


func _clean_dir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if n.ends_with(".json"):
			d.remove(n)
		n = d.get_next()
	d.list_dir_end()


func _finish() -> void:
	print("---- %d 项通过，%d 项失败" % [_pass, _fails.size()])
	get_tree().quit(0 if _fails.is_empty() else 1)


## 按一下某个动作（按两帧再松开）
func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame
	await get_tree().process_frame
