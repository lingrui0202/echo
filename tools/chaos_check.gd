extends Node
## 模糊测试：随机乱按 10 关（移动 / 声呐 / 强声呐 / 重开 / 开面板），
## 每步检查状态一致性，抓「走着走着卡进墙里」「门和地图不同步」这类 bug。
##   Godot_v4.7.2-stable_win64_console.exe --path <本目录> res://tools/chaos_check.tscn

const Levels = preload("res://scripts/levels.gd")
const Maze = preload("res://scripts/maze.gd")
const CELL := 64

var _fails := PackedStringArray()
var _lv: Node
var _player: Node
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 20261117
	var prog := get_node_or_null("/root/Progress")
	var session := get_node_or_null("/root/Session")
	session.set("mode", 1)
	prog.set("persist", false)
	get_node_or_null("/root/Mods").set("pending", false)

	for idx in Levels.MAPS.size():
		await _chaos_level(idx)

	session.set("mode", 0)
	print("---- %d 个问题" % _fails.size())
	for f in _fails:
		print("FAIL: ", f)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _chaos_level(idx: int) -> void:
	var prog := get_node_or_null("/root/Progress")
	prog.set("level_index", idx)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	_lv = ps.instantiate()
	add_child(_lv)
	await get_tree().process_frame
	_player = _lv.get_node("Player")

	await get_tree().process_frame
	var baseline := _counts()
	await _run_steps(idx)

	var after := _counts()
	for k in baseline.keys():
		if int(after[k]) != int(baseline[k]):
			_tag("第 %d 关：%s 数量变了 %d → %d（重建泄漏）" % [idx + 1, k, baseline[k], after[k]])

	_lv.queue_free()
	await get_tree().process_frame

func _counts() -> Dictionary:
	var out := {}
	for name in ["Walls", "Objects", "Fragments", "Enemies", "Crates"]:
		var n := _lv.get_node_or_null(name)
		out[name] = n.get_child_count() if n != null else 0
	out["children"] = _lv.get_child_count()
	return out

func _run_steps(idx: int) -> void:
	for step in 240:
		var roll := _rng.randi_range(0, 99)
		if roll < 55:
			var dirs := ["move_left", "move_right", "move_up", "move_down"]
			var a: String = dirs[_rng.randi_range(0, 3)]
			Input.action_press(a)
			await get_tree().physics_frame
			await get_tree().physics_frame
			Input.action_release(a)
		elif roll < 68:
			Input.action_press("sonar")
			await get_tree().process_frame
			Input.action_release("sonar")
		elif roll < 74:
			Input.action_press("strong_sonar")
			await get_tree().process_frame
			Input.action_release("strong_sonar")
		elif roll < 78:
			_lv.call("restart")
			_player = _lv.get_node("Player")
			await get_tree().process_frame
		elif roll < 82:
			CodexShim.toggle(_lv)
		elif roll < 86:
			# 随便挑一个空地瞬移，制造「玩家突然出现在机关旁」
			var rows: Array = _lv.map_rows()
			var open_cells: Array = []
			for y in rows.size():
				for x in String(rows[y]).length():
					if String(rows[y])[x] != "#":
						open_cells.append(Vector2i(x, y))
			if not open_cells.is_empty():
				var c: Vector2i = open_cells[_rng.randi_range(0, open_cells.size() - 1)]
				_player.global_position = Vector2(c.x * CELL + 32, c.y * CELL + 32)
			await get_tree().process_frame
		else:
			await get_tree().process_frame

		_check_invariants(idx, step)

## 每一步都查：玩家没进墙、门和地图同步、数量没失控
func _check_invariants(idx: int, step: int) -> void:
	var rows: Array = _lv.map_rows()
	var cell := Vector2i((_player.global_position / float(CELL)).floor())
	if cell.y < 0 or cell.y >= rows.size() or cell.x < 0 or cell.x >= String(rows[cell.y]).length():
		_tag("第 %d 关 第 %d 步：玩家跑到地图外 %s" % [idx + 1, step, str(cell)])
		return
	if String(rows[cell.y])[cell.x] == "#":
		_tag("第 %d 关 第 %d 步：玩家卡进墙里 %s" % [idx + 1, step, str(cell)])

	for dcell in _lv.call("door_cells"):
		var closed: bool = _lv.call("is_door_closed", dcell)
		var ch: String = String(rows[dcell.y])[dcell.x]
		if closed and ch != "#":
			_tag("第 %d 关 第 %d 步：门关着但地图是 %s" % [idx + 1, step, ch])
		elif not closed and ch == "#":
			_tag("第 %d 关 第 %d 步：门开着但地图是墙" % [idx + 1, step])

	var keys: Array = _lv.call("key_cells")
	var doors: Array = _lv.call("door_cells")
	if keys.is_empty():
		for d in doors:
			if _lv.call("is_door_closed", d):
				_tag("第 %d 关 第 %d 步：钥匙已收但门还锁着" % [idx + 1, step])
				break

	if _lv.call("fragment_cells").size() > _lv.call("fragment_total"):
		_tag("第 %d 关 第 %d 步：碎片数量超过上限" % [idx + 1, step])

func _tag(msg: String) -> void:
	if not _fails.has(msg):
		_fails.append(msg)
		print("FAIL  ", msg)


## 图鉴面板开关（不确定节点存在时静默跳过）
class CodexShim:
	static func toggle(lv: Node) -> void:
		var hud := lv.get_node_or_null("HUD")
		if hud == null:
			return
		hud.set("_codex_open", not bool(hud.get("_codex_open")))
