extends Node
## 多关 / 强声呐 / 音效 的自检（不依赖人工）。
##   Godot_v4.7.2-stable_win64_console.exe --path <本目录> res://tools/level_check.tscn

const Levels = preload("res://scripts/levels.gd")
const CELL := 64

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
	await _check_levels()
	_check_progress()
	await _check_strong_sonar()
	await _check_strong_key()
	await _check_crates()
	_check_mods()
	_check_settings()
	await _check_brightness()
	_check_grade()
	_check_save()
	_check_sfx()
	print("---- %d 项通过，%d 项失败" % [_pass, _fails.size()])
	for f in _fails:
		print("FAIL: ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _check_levels() -> void:
	var prog := get_node_or_null("/root/Progress")
	_check(prog != null, "Progress 已注册", "缺少 Progress autoload")
	if prog == null:
		return
	_check(Levels.MAPS.size() == 5, "关卡数 = 5", "关卡数不是 5：%d" % Levels.MAPS.size())

	for i in Levels.MAPS.size():
		prog.set("level_index", i)
		var ps: PackedScene = load("res://scenes/Level01.tscn")
		var lv: Node = ps.instantiate()
		add_child(lv)
		await get_tree().process_frame

		var rows: Array = lv.map_rows()
		var w := String(rows[0]).length()
		var h := rows.size()
		_check(w > 20 and h > 15, "第 %d 关地图 %d×%d" % [i + 1, w, h], "第 %d 关地图尺寸异常" % (i + 1))

		var goal: Vector2i = lv.goal_cell()
		var g_ok := goal.y >= 0 and goal.y < h and goal.x >= 0 and goal.x < w \
			and String(rows[goal.y])[goal.x] == "E"
		_check(g_ok, "第 %d 关出口 %s 是 E" % [i + 1, str(goal)], "第 %d 关出口不对" % (i + 1))

		var start: Vector2i = lv.start_cell()
		_check(String(rows[start.y])[start.x] != "#", "第 %d 关起点是空地" % (i + 1),
			"第 %d 关起点在墙里" % (i + 1))

		var dist: Dictionary = load("res://scripts/maze.gd").distances(rows, start)
		_check(dist.has(goal), "第 %d 关出口可达（%d 步）" % [i + 1, int(dist.get(goal, 0))],
			"第 %d 关出口不可达" % (i + 1))

		var box: Node = lv.get_node_or_null("Enemies")
		var cnt := box.get_child_count() if box != null else 0
		var expect := int(lv.ENEMY_BY_LEVEL[i])
		_check(cnt == expect, "第 %d 关敌人 %d 只" % [i + 1, expect],
			"第 %d 关敌人数不对：%d（应 %d）" % [i + 1, cnt, expect])

		var cam: Camera2D = lv.get_node("Player/Camera2D")
		_check(cam.limit_right == w * CELL and cam.limit_bottom == h * CELL,
			"第 %d 关相机限位 %d×%d" % [i + 1, w * CELL, h * CELL],
			"第 %d 关相机限位不对" % (i + 1))

		lv.queue_free()
		await get_tree().process_frame

	prog.set("level_index", 0)

func _check_progress() -> void:
	var prog := get_node_or_null("/root/Progress")
	if prog == null:
		return
	prog.call("reset")
	var seq: Array = []
	for i in 5:
		var more: bool = prog.call("advance")
		var tag := "有下一关" if more else "最后一关"
		seq.append(str(int(prog.get("level_index"))) + ":" + tag)
	_check(int(prog.get("level_index")) == 4, "连推 5 次停在第 5 关",
		"进度推进不对：%s" % str(seq))
	prog.call("reset")
	_check(int(prog.get("level_index")) == 0, "reset 回到第 1 关", "reset 没回到第 1 关")

func _check_strong_sonar() -> void:
	var prog := get_node_or_null("/root/Progress")
	prog.set("level_index", 2)      # 第 3 关有 1 个敌人
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	var lv: Node = ps.instantiate()
	add_child(lv)
	await get_tree().process_frame

	var box: Node = lv.get_node_or_null("Enemies")
	if box == null or box.get_child_count() == 0:
		_check(false, "第 3 关有敌人（强声呐测试前提）", "没有敌人，测不了强声呐")
		lv.queue_free()
		return
	var e: Node = box.get_child(0)
	var player: Node2D = lv.get_node("Player")

	# 把敌人挪到很远的地方：普通声呐够不着，强声呐应该够得着
	e.global_position = player.global_position + Vector2(3000, 0)
	e.set("_has_target", false)
	lv.emit_wave(player.global_position, false)
	_check(not e.is_chasing(), "远处敌人：普通声呐听不见", "普通声呐不该听见 3000px 外的敌人")

	e.global_position = player.global_position + Vector2(3000, 0)
	lv.emit_wave(player.global_position, true)
	_check(e.is_chasing(), "强声呐：3000px 外也能惊动", "强声呐没惊动远处敌人")

	lv.queue_free()
	await get_tree().process_frame

## 模拟按一下 E：确认输入映射和玩家那边真的连上了（之前这里漏了处理代码，按 E 没反应）。
func _check_strong_key() -> void:
	var prog := get_node_or_null("/root/Progress")
	prog.set("level_index", 2)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	var lv: Node = ps.instantiate()
	add_child(lv)
	await get_tree().process_frame

	var wave: Node = lv.get_node_or_null("SonarWave")
	var player: Node = lv.get_node("Player")
	_check(wave != null and player != null, "强声呐按键测试：节点齐全", "缺 SonarWave 或 Player")
	if wave == null or player == null:
		lv.queue_free()
		return

	# 有词条要选时玩家会被卡住，先随便选一个
	var mods := get_node_or_null("/root/Mods")
	if mods != null and bool(mods.get("pending")):
		mods.call("pick", 0)
	Input.action_press("strong_sonar")
	await get_tree().physics_frame
	Input.action_release("strong_sonar")
	await get_tree().physics_frame

	_check(bool(wave.get("_strong")), "按 E 触发强声呐（波场进入强模式）",
		"按 E 没有触发强声呐（_strong 仍是 false）")
	_check(player.has_method("cooldown_ratios"), "玩家暴露 cooldown_ratios（HUD 用）", "缺少 cooldown_ratios")
	if player.has_method("cooldown_ratios"):
		var r: Vector2 = player.cooldown_ratios()
		_check(r.y > 0.0, "强声呐进入冷却（剩余 %.0f%%）" % (r.y * 100.0), "强声呐没进冷却")

	lv.queue_free()
	await get_tree().process_frame


## 箱子：第 3 关应该生成 2 个；能推动一格；推到墙上推不动
func _check_crates() -> void:
	var prog := get_node_or_null("/root/Progress")
	prog.set("level_index", 2)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	var lv: Node = ps.instantiate()
	add_child(lv)
	await get_tree().process_frame

	var cells: Array = lv.call("crate_cells")
	_check(cells.size() >= 2, "第 3 关有 %d 个可动箱子" % cells.size(), "没有生成箱子")
	if cells.is_empty():
		lv.queue_free()
		return

	var cell: Vector2i = cells[0]
	var moved := false
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if lv.call("push_crate", cell, d):
			_check(not lv.call("has_crate", cell) and lv.call("has_crate", cell + d),
				"箱子能推开一格（%s → %s）" % [str(cell), str(cell + d)],
				"推箱子后格子没更新")
			moved = true
			break
	if not moved:
		_check(false, "箱子能推开", "四个方向都推不动")

	# 负例：对不存在的格子推箱子，必须返回 false
	_check(not lv.call("push_crate", Vector2i(-3, -3), Vector2i(1, 0)),
		"对空格推箱子返回 false", "对空格推箱子竟然成功")

	# 负例：推到墙上（找一只旁边是墙的箱子；找不到就跳过，不算失败）
	var rows2: Array = lv.map_rows()
	var wall_case := false
	for c2 in lv.call("crate_cells"):
		for d2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var t2: Vector2i = c2 + d2
			if t2.y < 0 or t2.y >= rows2.size() or t2.x < 0 or t2.x >= String(rows2[t2.y]).length():
				continue
			if String(rows2[t2.y])[t2.x] == "#":
				_check(not lv.call("push_crate", c2, d2), "推到墙上被拒绝", "推到墙上竟然成功")
				wall_case = true
				break
		if wall_case:
			break
	if not wall_case:
		_check(true, "箱子周围没有贴墙（跳过推墙用例）", "")

	lv.queue_free()
	await get_tree().process_frame

func _check_mods() -> void:
	var mods := get_node_or_null("/root/Mods")
	_check(mods != null, "Mods 已注册", "缺少 Mods autoload")
	if mods == null:
		return
	mods.call("reset_for_level", 2)
	_check(bool(mods.get("pending")), "第 3 关开局要选词条", "第 3 关没有词条可选")
	_check(mods.call("pick", 0), "能选中第一个词条", "选词条失败")
	_check(not bool(mods.get("pending")), "选完不再卡住", "选完还在 pending")
	_check(mods.call("sonar_mul") > 0.0 and mods.call("sonar_mul") <= 1.0,
		"词条对声呐冷却有倍率（%.2f）" % float(mods.call("sonar_mul")), "词条倍率不对")
	mods.call("reset_for_level", 0)
	_check(not bool(mods.get("pending")), "第 1 关不用选词条", "第 1 关也在要求选词条")

func _check_settings() -> void:
	var st := get_node_or_null("/root/Settings")
	_check(st != null, "Settings 已注册", "缺少 Settings autoload")
	if st == null:
		return
	var before: Color = st.call("dark_color")
	st.call("cycle_dark")
	var after: Color = st.call("dark_color")
	_check(before != after, "亮度可以切换", "亮度切了没变化")
	_check(st.call("describe").length() > 0, "设置面板有可读的描述", "设置描述为空")
	st.call("cycle_palette")
	st.call("cycle_volume")
	_check(true, "配色/音量切换不报错", "")

## 亮度必须真的改变画面：暗档 / 亮档的玩家光圈能量不同
func _check_brightness() -> void:
	var st := get_node_or_null("/root/Settings")
	var prog := get_node_or_null("/root/Progress")
	if st == null or prog == null:
		return
	prog.set("level_index", 0)

	var energies: Array = []
	for idx in [0, 2]:
		st.set("dark_index", idx)
		var ps: PackedScene = load("res://scenes/Level01.tscn")
		var lv: Node = ps.instantiate()
		add_child(lv)
		await get_tree().process_frame
		var ambient: PointLight2D = lv.get_node("Player/AmbientLight")
		energies.append(ambient.energy)
		lv.queue_free()
		await get_tree().process_frame

	st.set("dark_index", 1)
	_check(float(energies[1]) > float(energies[0]) * 1.3,
		"亮档光圈明显更亮（%.2f → %.2f）" % [float(energies[0]), float(energies[1])],
		"亮度档没起作用：%.2f vs %.2f" % [float(energies[0]), float(energies[1])])


func _check_grade() -> void:
	var gl := get_node_or_null("/root/GameLog")
	if gl == null:
		return
	var fast: String = gl.call("grade_for", 20.0, 2, 0, 0)
	var slow: String = gl.call("grade_for", 200.0, 30, 3, 0)
	_check(fast in ["S", "A"], "快且省的评价是 %s" % fast, "快局评价过低：%s" % fast)
	_check(slow in ["C", "D"], "慢且吵的评价是 %s" % slow, "慢局评价过高：%s" % slow)


## 每关存档：记住最好成绩、能直接选任意关
func _check_save() -> void:
	var prog := get_node_or_null("/root/Progress")
	if prog == null:
		return
	prog.set("persist", false)
	prog.call("reset")
	_check(not bool(prog.call("is_cleared", 0)), "重置后第 1 关是未通关", "重置后还留着通关记录")

	prog.call("record_clear", 0, 12.5, "A")
	_check(prog.call("is_cleared", 0), "通关后第 1 关标记为已通", "通关没有记下来")
	_check(is_equal_approx(float(prog.call("best_time", 0)), 12.5),
		"第 1 关最好成绩 12.5 s", "最好成绩不对：%s" % str(prog.call("best_time", 0)))

	prog.call("record_clear", 0, 20.0, "C")
	_check(is_equal_approx(float(prog.call("best_time", 0)), 12.5),
		"更慢的一次不覆盖最好成绩", "慢的记录把快的覆盖了")

	_check(bool(prog.call("can_select", 4)), "可以直接选第 5 关（不用从头解锁）",
		"第 5 关选不了")
	_check(bool(prog.call("select_level", 3)) and int(prog.get("level_index")) == 3,
		"选中第 4 关后 level_index = 3", "选关没生效")
	_check(not bool(prog.call("can_select", 9)), "越界关卡选不了", "越界关卡竟然可选")

	prog.call("reset")
	prog.set("persist", true)


func _check_sfx() -> void:
	var sfx := get_node_or_null("/root/Sfx")
	_check(sfx != null, "Sfx 已注册", "缺少 Sfx autoload")
	if sfx == null:
		return
	var players: Dictionary = sfx.get("_players")
	_check(players.size() >= 3, "生成了 %d 个音效" % players.size(), "音效数量不足")
	for name in ["ping", "strong", "caught"]:
		var p = players.get(name)
		var stream: AudioStreamWAV = p.stream if p != null else null
		_check(stream != null and stream.data.size() > 1000,
			"音效 %s 有 PCM 数据（%d 字节）" % [name, stream.data.size() if stream != null else 0],
			"音效 %s 没有数据" % name)
	sfx.call("ping")
	_check(true, "播放 ping 不报错", "")
