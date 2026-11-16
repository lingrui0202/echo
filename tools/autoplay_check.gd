extends Node
## 自动通关压力测试：10 关各跑一遍（找路 → 拿钥匙 → 开门 → 到出口），顺便制造各种交互。
##   Godot_v4.7.2-stable_win64_console.exe --path <本目录> res://tools/autoplay_check.tscn
##
## 目的不是"能不能过"，而是把每一关的机关/敌人/碎片/重开都触发一遍，看有没有运行时报错。

const Maze = preload("res://scripts/maze.gd")
const Levels = preload("res://scripts/levels.gd")
const CELL := 64

var _fails := PackedStringArray()
var _pass := 0
var _lv: Node
var _player: Node

func _check(cond: bool, ok: String, bad: String) -> void:
	if cond:
		_pass += 1
		print("PASS  ", ok)
	else:
		_fails.append(bad)
		print("FAIL  ", bad)

func _ready() -> void:
	var prog := get_node_or_null("/root/Progress")
	var session := get_node_or_null("/root/Session")
	session.set("mode", 1)                   # 测试模式：不写存档
	prog.set("persist", false)
	get_node_or_null("/root/Mods").set("pending", false)

	for i in Levels.MAPS.size():
		await _play_level(i)

	session.set("mode", 0)
	print("---- %d 项通过，%d 项失败" % [_pass, _fails.size()])
	for f in _fails:
		print("FAIL: ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _play_level(idx: int) -> void:
	var prog := get_node_or_null("/root/Progress")
	prog.set("level_index", idx)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	_lv = ps.instantiate()
	add_child(_lv)
	await get_tree().process_frame
	_player = _lv.get_node("Player")

	# 开关一次：顺便测重建
	_lv.call("restart", idx)
	await get_tree().process_frame

	var start: Vector2i = _lv.start_cell()
	var goal: Vector2i = _lv.goal_cell()
	_place(start)

	var steps := 0
	var keys_taken := 0
	var fired := 0
	while steps < 4000:
		steps += 1
		var here := _cell()
		if here == goal:
			break
		var path: Array = Maze.path(_lv.map_rows(), here, goal)
		if path.is_empty():
			# 被门挡住了：去拿钥匙
			var k := _nearest_key(here)
			if k.x < 0:
				_check(false, "第 %d 关：门后无路且找不到钥匙" % (idx + 1), "第 %d 关走不通" % (idx + 1))
				_lv.queue_free()
				await get_tree().process_frame
				return
			var kp: Array = Maze.path(_lv.map_rows(), here, k)
			if kp.is_empty():
				_check(false, "第 %d 关：钥匙不可达" % (idx + 1), "第 %d 关钥匙走不到" % (idx + 1))
				_lv.queue_free()
				await get_tree().process_frame
				return
			_place(kp[mini(1, kp.size() - 1)])
			await get_tree().process_frame
			keys_taken += 1
			continue

		_place(path[mini(1, path.size() - 1)])
		# 每 12 步发一次声呐，制造敌人/波前/图鉴的交互
		if steps % 12 == 0 and fired < 6:
			fired += 1
			Input.action_press("sonar")
			await get_tree().process_frame
			Input.action_release("sonar")
		await get_tree().process_frame

	var arrived := _cell() == goal
	_check(arrived, "第 %d 关：能走到出口（%d 步，拿钥匙 %d）" % [idx + 1, steps, keys_taken],
		"第 %d 关走不到出口（停在 %s）" % [idx + 1, str(_cell())])

	# 到出口后应该触发通关（Area2D 重叠要等物理帧）
	for _i in 6:
		await get_tree().physics_frame
	var gl := get_node_or_null("/root/GameLog")
	_check(String(gl.get("last_reason")) == "win", "第 %d 关：到出口触发通关" % (idx + 1),
		"第 %d 关没触发通关" % (idx + 1))

	_lv.queue_free()
	await get_tree().process_frame

func _cell() -> Vector2i:
	return Vector2i((_player.global_position / float(CELL)).floor())

func _place(c: Vector2i) -> void:
	_player.global_position = Vector2(c.x * CELL + CELL * 0.5, c.y * CELL + CELL * 0.5)

func _nearest_key(from: Vector2i) -> Vector2i:
	var keys: Array = _lv.call("key_cells")
	var best := Vector2i(-1, -1)
	var best_d := 99999
	for k in keys:
		var d: int = absi(k.x - from.x) + absi(k.y - from.y)
		if d < best_d:
			best_d = d
			best = k
	return best
