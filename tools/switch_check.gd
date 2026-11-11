extends Node
## 换关自检：restart() 必须原地重建，不能重载场景；反复换关不能越叠越多节点。
##   Godot_v4.7.2-stable_win64_console.exe --path <本目录> res://tools/switch_check.tscn

const Levels = preload("res://scripts/levels.gd")

var _fails := PackedStringArray()
var _pass := 0
var _lv: Node

func _check(cond: bool, ok: String, bad: String) -> void:
	if cond:
		_pass += 1
		print("PASS  ", ok)
	else:
		_fails.append(bad)
		print("FAIL  ", bad)

func _ready() -> void:
	var prog := get_node_or_null("/root/Progress")
	prog.set("persist", false)
	prog.set("level_index", 0)

	var ps: PackedScene = load("res://scenes/Level01.tscn")
	_lv = ps.instantiate()
	_lv.name = "Level01"
	add_child(_lv)
	await get_tree().process_frame

	var w0 := String(_lv.map_rows()[0]).length()
	_check(_lv.level_no() == 1, "初始是第 1 关（宽 %d）" % w0, "初始关卡不对")

	# 换到第 3 关
	_lv.call("restart", 2)
	await get_tree().process_frame

	var rows: Array = _lv.map_rows()
	var w2 := String(rows[0]).length()
	var expect := String(Levels.MAPS[2][0]).length()
	_check(_lv.level_no() == 3, "换到第 3 关", "换关后 level_no 不是 3")
	_check(w2 == expect and w2 != w0, "地图换成第 3 关的尺寸（%d×%d）" % [w2, rows.size()],
		"地图尺寸没变：%d，应为 %d" % [w2, expect])
	_check(_lv.get_node_or_null("Walls").get_child_count() > 0, "墙重新生成了", "换关后没有墙")

	var start: Vector2i = _lv.start_cell()
	var player: Node2D = _lv.get_node("Player")
	var cell := Vector2i((player.global_position / 64.0).floor())
	_check(cell == start, "玩家回到新关起点 %s" % str(start), "玩家没回到起点：%s" % str(cell))

	# 反复换关：节点数不能增长
	var counts: Array = []
	for i in 5:
		_lv.call("restart", i % Levels.MAPS.size())
		await get_tree().process_frame
		var waves := 0
		var wave_script := load("res://scripts/sonar_wave.gd")
		for c in _lv.get_children():
			if c.get_script() == wave_script:
				waves += 1
		counts.append("%d:波%d" % [int(_lv.level_no()), waves])
	_check(String(counts[len(counts) - 1]).contains("波1"), "反复换关后只有一个波场（%s）" % str(counts),
		"波场越叠越多：%s" % str(counts))

	var enemies := _lv.get_node_or_null("Enemies")
	var expect_e := int(_lv.ENEMY_BY_LEVEL[_lv.level_index])
	_check(enemies == null or enemies.get_child_count() == expect_e,
		"第 %d 关敌人 %d 只" % [_lv.level_no(), expect_e], "敌人数量不对")

	# ---- 换关后的状态残留检查 ----
	var gl := get_node_or_null("/root/GameLog")
	var cfg: Dictionary = gl.get("config") if gl != null else {}
	var rows_now: Array = _lv.map_rows()
	_check(int(cfg.get("map_w", 0)) == String(rows_now[0]).length()
			and int(cfg.get("map_h", 0)) == rows_now.size(),
		"遥测 config 跟着换成新地图（%d×%d）" % [String(rows_now[0]).length(), rows_now.size()],
		"换关后 config 还是旧地图：%s" % str(cfg))
	_check(int(cfg.get("level_index", -1)) == _lv.level_index,
		"遥测 config 的关卡号同步（%d）" % _lv.level_index, "config 关卡号没同步：%s" % str(cfg))

	var wave: Node = _lv.get("_wave")
	var mem_clear := true
	if wave != null:
		var img: Image = wave.get("_edge_img")
		if img != null:
			for y in range(0, img.get_height(), 7):
				for x in range(0, img.get_width(), 7):
					if img.get_pixel(x, y).a > 0.01:
						mem_clear = false
	_check(mem_clear, "换关后墙上的记忆已清空", "上一张图的墙面记忆还在")

	var st := get_node_or_null("/root/Settings")
	var dark: CanvasModulate = _lv.get_node("Darkness")
	if st != null and dark != null:
		_check(dark.color == st.call("dark_color"), "黑暗层用当前亮度设置", "黑暗层没跟上设置")
		var player2: Node = _lv.get_node("Player")
		var ambient: PointLight2D = player2.get_node("AmbientLight")
		var want: float = float(player2.get("AMBIENT_ENERGY")) * float(st.call("light_mul"))
		_check(absf(ambient.energy - want) < 0.01,
			"光圈亮度跟着设置（%.2f）" % ambient.energy, "光圈亮度没跟上：%.2f ≠ %.2f" % [ambient.energy, want])

	var hud2: Node = _lv.get_node("HUD")
	if hud2 != null:
		var mm: Control = hud2.get("_minimap")
		if mm != null:
			# 换完这一帧玩家已经站在起点，所以最多 1 格；关键是别留着上一张图的那几十格
			var n_visited := int(mm.call("visited_count"))
			_check(n_visited <= 1, "换关后小地图只剩起点（%d 格）" % n_visited,
				"换关后小地图留着上一张图的足迹（%d 格）" % n_visited)

	var crates: Array = _lv.call("crate_cells")
	_check(_lv.level_index == 0 or crates.size() >= 2,
		"第 %d 关箱子 %d 个" % [_lv.level_no(), crates.size()], "箱子没生成")

	# ---- 真实路径：设置面板里按 5 ----
	prog.set("level_index", 0)
	_lv.call("restart")
	await get_tree().process_frame
	_check(_lv.level_no() == 1, "restart() 不带参数时读 Progress（回到第 1 关）",
		"restart() 没读 Progress，停在第 %d 关" % _lv.level_no())

	var hud3: Node = _lv.get_node("HUD")
	hud3.set("_settings_open", true)
	await get_tree().process_frame
	Input.action_press("slot_5")
	await get_tree().process_frame
	Input.action_release("slot_5")
	await get_tree().process_frame
	await get_tree().process_frame

	_check(_lv.level_no() == 2, "设置里按 5：当场换到第 2 关（现在是第 %d 关）" % _lv.level_no(),
		"按 5 之后还是第 %d 关，没换过去" % _lv.level_no())
	var rows_after: Array = _lv.map_rows()
	_check(String(rows_after[0]).length() == String(Levels.MAPS[1][0]).length(),
		"按 5 之后地图确实换成第 2 关（宽 %d）" % String(rows_after[0]).length(),
		"地图还是旧的：宽 %d" % String(rows_after[0]).length())

	prog.set("persist", true)
	print("---- %d 项通过，%d 项失败" % [_pass, _fails.size()])
	get_tree().quit(0 if _fails.is_empty() else 1)
