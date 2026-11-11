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
	_check(txt.contains("已通 1/5 关"), "加载面板显示通了几个关卡",
		"没显示进度：%s" % txt.left(140))

	# ---- 排行榜：每关分开 ----
	menu.set("_mode", "rank")
	menu.call("_refresh_panel")
	await get_tree().process_frame
	var rank: String = String(menu.get("_panel_text").text)
	var heads := 0
	for i in 5:
		if rank.contains("第 %d 关" % (i + 1)):
			heads += 1
	_check(heads == 5, "排行榜按关分开（5 个分段）", "排行榜不是每关分开：%d 段" % heads)
	_check(rank.contains("还没有成绩") or rank.contains(" s "), "排行榜有内容（成绩或占位）",
		"排行榜是空的：%s" % rank.left(100))

	# ---- 设置面板 ----
	menu.set("_mode", "settings")
	menu.call("_refresh_panel")
	await get_tree().process_frame
	_check(String(menu.get("_panel_text").text).contains("亮度"), "设置面板在首页里也能开", "设置面板打不开")

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
	_check(bool(prog.call("load_save", id_a)), "能载入旧槽", "载入旧槽失败")
	_check(String(prog.get("slot_id")) == id_a, "载入后当前槽切过去了", "当前槽没切")
	_check((prog.get("cleared") as Dictionary).size() == 2 and int(prog.get("level_index")) == 2,
		"旧槽的进度恢复了（第 3 关、通 2 关）", "旧槽进度没恢复")

	# 首页的加载面板应该把所有槽列出来
	menu.set("_mode", "save")
	menu.call("_refresh_panel")
	await get_tree().process_frame
	var save_txt: String = String(menu.get("_panel_text").text)
	_check(save_txt.contains("第 3 关") and save_txt.contains("已通 2/5 关"),
		"加载面板显示槽的关卡与进度", "加载面板没显示进度：%s" % save_txt.left(90))
	_check(save_txt.contains(":"), "加载面板显示保存时间", "加载面板没有时间")

	_clean_dir("user://saves_test")
	prog.set("save_dir", "user://saves")

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
