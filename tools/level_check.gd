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
	# 统一用测试模式：关卡不会弹词条面板（面板会暂停游戏，后续断言全会被冻住）
	var sess := get_node_or_null("/root/Session")
	if sess != null:
		sess.set("mode", 1)
	await _check_levels()
	_check_progress()
	await _check_strong_sonar()
	await _check_strong_key()
	await _check_fragments()
	await _check_enemy_search()
	await _check_key_hint()
	await _check_plate_and_silence()
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
	_check(Levels.MAPS.size() == 10, "关卡数 = 10", "关卡数不对：%d" % Levels.MAPS.size())

	for i in Levels.MAPS.size():
		prog.set("level_index", i)
		var ps: PackedScene = load("res://scenes/Level01.tscn")
		var lv: Node = ps.instantiate()
		add_child(lv)
		await get_tree().process_frame

		# 原始地图（门是 'D' 可通行）：门关着时 lv.map_rows() 里是 '#'，不能拿来判可达
		var rows: Array = Levels.MAPS[i]
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

		var raw_doors := 0
		for r in rows:
			raw_doors += String(r).count("D")
		if raw_doors > 0:
			var opened: Dictionary = load("res://scripts/maze.gd").distances(rows, start)
			var keys_ok := false
			for c in opened.keys():
				if String(rows[c.y])[c.x] == "K":
					keys_ok = true
					break
			_check(keys_ok, "第 %d 关门 %d 格、有钥匙" % [i + 1, raw_doors],
				"第 %d 关有门但没有钥匙" % (i + 1))

		# 箱子不能压在钥匙/碎片/压力板/门上
		var reserved_ok := true
		for cc in lv.call("crate_cells"):
			if lv.call("_cell_reserved", cc):
				reserved_ok = false
		_check(reserved_ok, "第 %d 关箱子没压住机关" % (i + 1), "第 %d 关箱子压住了机关" % (i + 1))

		# 敌人不能叠在一起
		var cells_e: Array = []
		var box0: Node = lv.get_node_or_null("Enemies")
		var min_d := 999
		if box0 != null:
			for e0 in box0.get_children():
				cells_e.append(Vector2i((e0.global_position / 64.0).floor()))
			for i2 in cells_e.size():
				for j2 in range(i2 + 1, cells_e.size()):
					min_d = mini(min_d, int(cells_e[i2].distance_to(cells_e[j2])))
		_check(cells_e.size() <= 1 or min_d >= 4, "第 %d 关敌人之间至少隔 %d 格" % [i + 1, min_d],
			"第 %d 关有两个敌人叠在一起（最近 %d 格）" % [i + 1, min_d])

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
	for i in Progress.TOTAL:
		var more: bool = prog.call("advance")
		var tag := "有下一关" if more else "最后一关"
		seq.append(str(int(prog.get("level_index"))) + ":" + tag)
	_check(int(prog.get("level_index")) == Progress.TOTAL - 1, "连推到最后一关",
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
## 碎片：每关有、能捡、捡完永久记在存档里、每 3 枚一档升级
## 压力板开门 / 静音区免疫警报
func _check_plate_and_silence() -> void:
	var prog := get_node_or_null("/root/Progress")
	var ps: PackedScene = load("res://scenes/Level01.tscn")

	# 压力板：踩上去，它连的那扇门必须开
	prog.set("level_index", 3)
	var lv: Node = ps.instantiate()
	add_child(lv)
	await get_tree().process_frame
	var plates: Array = lv.call("plate_cells")
	if plates.is_empty():
		_check(false, "第 4 关有压力板", "第 4 关没有压力板")
	else:
		var link: Dictionary = lv.get("_plate_door")
		var pcell: Vector2i = plates[0]
		var door: Vector2i = link.get(pcell, Vector2i(-1, -1))
		var player: Node2D = lv.get_node("Player")
		player.global_position = Vector2(pcell.x * 64 + 32, pcell.y * 64 + 32)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(door.x >= 0 and not bool(lv.call("is_door_closed", door)),
			"踩压力板后门开了", "踩了压力板门没开")
	lv.queue_free()
	await get_tree().process_frame

	# 静音区：在里面发声，敌人不该被惊动
	prog.set("level_index", 2)
	var lv2: Node = ps.instantiate()
	add_child(lv2)
	await get_tree().process_frame
	var sil: Array = lv2.call("silence_cells")
	if sil.is_empty():
		_check(false, "第 3 关有静音区", "第 3 关没有静音区")
	else:
		var gl := get_node_or_null("/root/GameLog")
		var before := 0
		if gl != null:
			before = int(gl.get("alert_count"))
			gl.set("alert_count", 0)
		var sc: Vector2i = sil[0]
		lv2.call("emit_wave", Vector2(sc.x * 64 + 32, sc.y * 64 + 32), false)
		await get_tree().process_frame
		var after := int(gl.get("alert_count")) if gl != null else 0
		_check(after == 0, "静音区里发声不惊动敌人", "静音区里还是惊动了 %d 个" % after)
		if gl != null:
			gl.set("alert_count", before)
	lv2.queue_free()
	await get_tree().process_frame


## 碰到门之后，小地图才会标出钥匙
func _check_key_hint() -> void:
	var prog := get_node_or_null("/root/Progress")
	prog.set("level_index", 1)                 # 第 2 关：门 + 钥匙
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	var lv: Node = ps.instantiate()
	add_child(lv)
	await get_tree().process_frame
	var doors: Array = lv.call("door_cells")
	if doors.is_empty():
		_check(false, "第 2 关有门（钥匙提示前提）", "第 2 关没有门")
		lv.queue_free()
		return

	_check(not bool(lv.call("keys_revealed")), "还没碰门时不显示钥匙", "一开始就显示了钥匙")

	var d: Vector2i = doors[0]
	var player: Node2D = lv.get_node("Player")
	player.global_position = Vector2(d.x * 64 + 32, d.y * 64 + 32)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(bool(lv.call("keys_revealed")), "碰到门之后开始显示钥匙", "碰了门也没有提示")

	var hud: Node = lv.get_node("HUD")
	var mm: Control = hud.get("_minimap")
	var keys: Array = mm.get("_keys")
	_check(keys.size() > 0, "小地图拿到钥匙位置（%d 个）" % keys.size(), "小地图没拿到钥匙")

	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://_verify/key_hint.png")
	print("[shot] _verify/key_hint.png")

	lv.queue_free()
	await get_tree().process_frame


## 敌人追丢后应该先搜索，而不是立刻回去巡逻
func _check_enemy_search() -> void:
	var prog := get_node_or_null("/root/Progress")
	prog.set("level_index", 3)          # 第 4 关有 2 个敌人
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	var lv: Node = ps.instantiate()
	add_child(lv)
	await get_tree().process_frame
	var box: Node = lv.get_node_or_null("Enemies")
	if box == null or box.get_child_count() == 0:
		_check(false, "第 4 关有敌人（搜索测试前提）", "没有敌人")
		lv.queue_free()
		return
	var e: Node = box.get_child(0)
	e.call("hear_any", e.global_position)
	_check(bool(e.call("is_chasing")), "敌人进入追击", "没进入追击")
	e.set("_chase_left", 0.01)
	e.call("_physics_process", 0.02)
	_check(bool(e.call("is_searching")), "追丢后进入搜索状态", "追丢后直接回去巡逻了")

	lv.queue_free()
	await get_tree().process_frame


func _check_fragments() -> void:
	var prog := get_node_or_null("/root/Progress")
	prog.set("persist", false)
	prog.set("level_index", 1)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	var lv: Node = ps.instantiate()
	add_child(lv)
	await get_tree().process_frame

	var cells: Array = lv.call("fragment_cells")
	_check(cells.size() > 0, "第 2 关生成了 %d 枚碎片" % cells.size(), "没有生成碎片")

	var before := int(prog.get("fragments"))
	if cells.size() > 0:
		lv.call("_collect_fragment", cells[0])
		await get_tree().process_frame
		_check(int(prog.get("fragments")) == before + 1, "捡到碎片后总数 +1", "碎片没记进存档")
		_check(lv.call("fragment_cells").size() == cells.size() - 1, "捡过的碎片消失", "碎片还在")
		_check(int(GameLog.get("fragment_count")) >= 1, "遥测记了碎片", "遥测没记碎片")

	# 同一存档再进这关，捡过的不会再出现
	lv.queue_free()
	await get_tree().process_frame
	var lv2: Node = ps.instantiate()
	add_child(lv2)
	await get_tree().process_frame
	_check(lv2.call("fragment_cells").size() == maxi(cells.size() - 1, 0),
		"捡过的碎片不会重生", "碎片重生了")
	lv2.queue_free()
	await get_tree().process_frame

	# 碎片必须刷在能走到的格子上，并且 HUD 文案写清「剩 X/3」
	var lv3: Node = ps.instantiate()
	add_child(lv3)
	await get_tree().process_frame
	var raw3: Array = Levels.MAPS[lv3.level_index]
	var dist3: Dictionary = load("res://scripts/maze.gd").distances(raw3, lv3.start_cell())
	var all_reach := true
	for c3 in lv3.call("fragment_cells"):
		if not dist3.has(c3):
			all_reach = false
	_check(all_reach, "碎片都刷在可达格上", "有碎片刷在走不到的地方")
	var hud3: Node = lv3.get_node("HUD")
	await get_tree().process_frame
	var hint: Label = hud3.get("_hint")
	_check(String(hint.text).contains("碎片 剩"), "HUD 写明「碎片 剩 X/3」",
		"HUD 碎片文案不清楚：%s" % String(hint.text).left(60))
	lv3.queue_free()
	await get_tree().process_frame

	# 升级档位
	prog.set("fragments", 0)
	_check(prog.call("upgrade_tier") == 0 and is_equal_approx(float(prog.call("cooldown_bonus")), 0.0),
		"0 碎片没有加成", "0 碎片就有加成")
	prog.set("fragments", 9)
	_check(prog.call("upgrade_tier") == 3, "9 碎片到第 3 档", "升级档位不对")
	_check(float(prog.call("cooldown_bonus")) > 0.4 and int(prog.call("light_bonus")) > 10,
		"第 3 档有冷却与光圈加成", "第 3 档没加成")
	prog.set("fragments", 0)
	prog.set("persist", true)


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
	# 五个词条都要真的产生效果
	var expect := {
		"quick": ["sonar_mul", 0.8],
		"swift": ["speed_mul", 1.1],
		"quiet": ["strong_mul", 0.7],
		"deaf": ["enemy_hear_mul", 0.75],
		"sharp": ["sonar_mul", 0.65],
	}
	for id in expect.keys():
		mods.set("current", id)
		var fn: String = expect[id][0]
		var want: float = expect[id][1]
		var got: float = float(mods.call(fn))
		_check(is_equal_approx(got, want), "词条 %s 的 %s = %.2f" % [id, fn, want],
			"词条 %s 的 %s 不对：%.2f（应 %.2f）" % [id, fn, got, want])
	mods.set("current", "")

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
	_check(not bool(prog.call("can_select", Progress.TOTAL)), "越界关卡选不了", "越界关卡竟然可选")

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
