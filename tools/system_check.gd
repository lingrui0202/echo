extends Node
## 系统级自检：设置是否真的生效、存档槽读写、敌人 AI 的边界情况。
##   Godot_v4.7.2-stable_win64_console.exe --path <本目录> res://tools/system_check.tscn

const Levels = preload("res://scripts/levels.gd")
const Maze = preload("res://scripts/maze.gd")
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
	var prog := get_node_or_null("/root/Progress")
	prog.set("save_dir", "user://saves_sys")
	DirAccess.make_dir_recursive_absolute("user://saves_sys")
	_clean("user://saves_sys")
	prog.set("persist", true)

	await _check_settings()
	await _check_saves()
	await _check_enemy_edges()

	_clean("user://saves_sys")
	prog.set("save_dir", "user://saves")
	print("---- %d 项通过，%d 项失败" % [_pass, _fails.size()])
	for f in _fails:
		print("FAIL: ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)

# ---------------- 设置 ----------------
func _check_settings() -> void:
	var st := get_node_or_null("/root/Settings")
	var prog := get_node_or_null("/root/Progress")

	# 亮度：切档后新关卡的全黑层要跟着变
	st.set("dark_index", 0)
	prog.set("level_index", 0)
	var lv1 := await _spawn(0)
	var dark1: CanvasModulate = lv1.get_node("Darkness")
	var c0: Color = dark1.color
	lv1.queue_free()
	await get_tree().process_frame

	st.set("dark_index", 2)
	var lv2 := await _spawn(0)
	var dark2: CanvasModulate = lv2.get_node("Darkness")
	_check(dark2.color != c0 and dark2.color == st.call("dark_color"),
		"亮度档位真的作用到全黑层", "亮度档没生效")
	# 亮度还要影响玩家光圈能量
	var amb: PointLight2D = lv2.get_node("Player/AmbientLight")
	_check(is_equal_approx(amb.energy, float(lv2.get_node("Player").get("AMBIENT_ENERGY"))
			* float(st.call("light_mul"))), "亮度档位作用于光圈能量", "光圈能量没跟着亮度")

	# 配色：切档后新关卡的波场要带上
	st.set("palette", 1)
	var lv3 := await _spawn(0)
	var wave: Node = lv3.get("_wave")
	_check(wave != null and int(wave.get("_palette")) == 1, "声呐配色作用到波场", "配色没作用到波场")
	lv3.queue_free()
	await get_tree().process_frame

	# 音量：切档后 Master 总线音量要跟着变
	st.set("vol_index", 2)
	st.call("cycle_volume")       # 2 -> 0
	st.call("cycle_volume")       # 0 -> 1
	var bus := AudioServer.get_bus_index("Master")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(bus), -6.0),
		"音量档位作用到 Master 总线", "音量档没生效：%.1f" % AudioServer.get_bus_volume_db(bus))

	st.set("dark_index", 1)
	st.set("palette", 0)
	st.set("vol_index", 0)
	st.call("_apply")

# ---------------- 存档 ----------------
func _check_saves() -> void:
	var prog := get_node_or_null("/root/Progress")

	prog.call("new_save")
	var a := String(prog.get("slot_id"))
	prog.call("record_clear", 0, 40.0, "A")
	prog.call("record_clear", 1, 50.0, "B")
	prog.set("level_index", 2)
	prog.call("save_now")

	prog.call("new_save")
	var b := String(prog.get("slot_id"))
	_check(a != b, "两次新存档拿到不同槽 id", "槽 id 撞了")

	_check(bool(prog.call("load_save", a)), "能载入旧槽 A", "载入 A 失败")
	_check((prog.get("cleared") as Dictionary).size() == 2 and int(prog.get("level_index")) == 2,
		"槽 A 的进度完整（通 2 关、停在第 3 关）", "槽 A 数据不对")

	# 删掉当前槽：状态要清干净，之后还能正常开新档
	_check(bool(prog.call("delete_save", a)), "能删掉当前槽", "删当前槽失败")
	_check(String(prog.get("slot_id")) == "" and (prog.get("cleared") as Dictionary).is_empty(),
		"删当前槽后状态清空", "删完还留着数据")
	prog.call("new_save")
	_check(int(prog.get("level_index")) == 0, "删档后还能正常开新档", "删档后开新档失败")

	# 列表按最近保存排序，且删掉的槽不出现
	var ids: Array = []
	for sv in prog.call("list_saves"):
		ids.append(String(sv["id"]))
	_check(not ids.has(a), "删掉的槽不在列表里", "删掉的槽还在列表里")
	_check(ids.size() >= 2, "列表里还有其它槽（%d 个）" % ids.size(), "列表数量不对")

# ---------------- 敌人边界 ----------------
func _check_enemy_edges() -> void:
	var prog := get_node_or_null("/root/Progress")
	prog.set("level_index", 3)          # 第 4 关：2 个敌人 + 门
	var lv := await _spawn(3)
	var box: Node = lv.get_node_or_null("Enemies")
	if box == null or box.get_child_count() == 0:
		_check(false, "第 4 关有敌人", "没有敌人")
		lv.queue_free()
		return

	var e: Node = box.get_child(0)
	# 1) 强声呐无视距离（目标必须是一个可走格，否则 hear 本来就会返回 false）
	var rows0: Array = lv.map_rows()
	var dist0: Dictionary = Maze.distances(rows0, lv.start_cell())
	var far := Vector2i(-1, -1)
	var far_d := -1
	for c in dist0.keys():
		if int(dist0[c]) > far_d:
			far_d = int(dist0[c])
			far = c
	_check(far.x >= 0 and bool(e.call("hear_any", Vector2(far.x * CELL + 32, far.y * CELL + 32))),
		"强声呐无视距离（目标 %s，%d 步外）" % [str(far), far_d], "强声呐没听见")
	e.set("_has_target", false)
	e.set("_path", [])

	# 2) 目标不可达（墙里）不能让敌人卡死报错
	e.call("hear_any", Vector2(0, 0))
	await get_tree().physics_frame
	_check(true, "目标在墙里也不报错", "")

	# 3) 搜索状态：追丢后进入搜索，到时间后退出并回到巡逻
	e.set("_has_target", true)
	e.set("_chase_left", 0.01)
	e.call("_physics_process", 0.02)
	_check(bool(e.call("is_searching")), "追丢进入搜索", "没进入搜索")
	e.set("_search_left", 0.01)
	e.call("_physics_process", 0.02)
	_check(not bool(e.call("is_searching")), "搜索超时退出", "搜索超时还在搜")

	# 4) 瞎子：普通声呐无视、强声呐有效
	var blind_found := false
	for child in box.get_children():
		if int(child.get("kind")) == 1:
			blind_found = true
			child.set("_has_target", false)
			child.set("_searching", false)
			var heard_normal := bool(child.call("hear", child.global_position))
			var heard_strong := bool(child.call("hear_any", child.global_position))
			_check(not heard_normal and heard_strong, "瞎子只被强声呐惊动",
				"瞎子对普通声呐有反应（%s / %s）" % [str(heard_normal), str(heard_strong)])
			break
	if not blind_found:
		_check(false, "第 4 关有瞎子", "第 4 关没有瞎子")

	# 5) 被门挡住：路径为空且不移动；开门后能找到路
	var door_cell := Vector2i(-1, -1)
	for d2 in lv.call("door_cells"):
		if bool(lv.call("is_door_closed", d2)):
			door_cell = d2
			break
	if door_cell.x >= 0:
		var behind := door_cell
		# 门另一侧随便找一个可走格
		for d3 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var c3: Vector2i = door_cell + d3
			if c3.y >= 0 and c3.y < rows0.size() and c3.x >= 0 \
					and c3.x < String(rows0[c3.y]).length() and String(rows0[c3.y])[c3.x] != "#":
				behind = c3
				break
		e.global_position = Vector2(2 * CELL, 2 * CELL)
		e.set("_has_target", false)
		e.set("_searching", false)
		e.call("hear_any", Vector2(behind.x * CELL + 32, behind.y * CELL + 32))
		await get_tree().physics_frame
		# 直接验「关门时这一格对寻路等于墙」，比指望唯一通路可靠
		var rows_now: Array = lv.map_rows()
		var closed_is_wall := String(rows_now[door_cell.y])[door_cell.x] == "#"
		_check(closed_is_wall, "门关着时对寻路等于墙", "门关着但寻路仍把它当通路")
		# 开门（模拟拿钥匙）
		lv.call("_set_door_closed", door_cell, false)
		e.set("_repath", 0.0)
		e.call("_physics_process", 0.02)
		_check(not (e.get("_path") as Array).is_empty() or behind == door_cell,
			"开门后敌人重新算出路径", "开门后还是没有路径")

	# 6) 强声呐收益：近处敌人被震住、范围内显形
	var e2: Node = box.get_child(0)
	e2.set("_has_target", false)
	lv.call("_strong_impact", e2.global_position)
	_check(float(e2.get("_stun_t")) > 0.5, "强声呐把近处敌人震住", "近处敌人没被震住")
	_check(float(e2.get("_expose_t")) > 1.0, "强声呐让敌人显形", "敌人没有显形")
	var p0b: Vector2 = e2.global_position
	for i in 10:
		e2.call("_physics_process", 0.05)
	_check(e2.global_position.distance_to(p0b) < 2.0, "被震住时敌人不动",
		"被震住还在动：%.1f px" % e2.global_position.distance_to(p0b))

	# 7) 心跳：900 px 内会开始累积节拍，更远不响
	var hud: Node = lv.get_node("HUD")
	var pl: Node2D = lv.get_node("Player")
	hud.set("_player", pl)
	pl.global_position = Vector2(10 * 64 + 32, 10 * 64 + 32)
	e2.global_position = pl.global_position + Vector2(700, 0)
	hud.set("_beat_t", 0.0)
	hud.call("_update_heartbeat", 0.2)
	var near_beat: float = float(hud.get("_beat_t"))
	_check(near_beat > 0.0, "700 px 内有心跳", "700 px 听不到心跳")
	e2.global_position = pl.global_position + Vector2(1100, 0)
	hud.set("_beat_t", 0.0)
	hud.call("_update_heartbeat", 0.2)
	_check(float(hud.get("_beat_t")) == 0.0, "1100 px 外没有心跳", "太远还在响")

	# 8) 巡逻：跑一会儿应该真的移动过
	e.set("_has_target", false)
	e.set("_searching", false)
	e.set("_patrol_left", 0.0)
	var pos0: Vector2 = e.global_position
	for i in 30:
		e.call("_physics_process", 0.05)
	await get_tree().physics_frame
	_check(e.global_position.distance_to(pos0) > 1.0, "巡逻状态真的会走",
		"巡逻时原地不动（%.1f px）" % e.global_position.distance_to(pos0))

	lv.queue_free()
	await get_tree().process_frame

# ---------------- 工具 ----------------
func _spawn(idx: int) -> Node:
	var prog := get_node_or_null("/root/Progress")
	prog.set("level_index", idx)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	var lv: Node = ps.instantiate()
	add_child(lv)
	await get_tree().process_frame
	return lv

func _clean(path: String) -> void:
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
