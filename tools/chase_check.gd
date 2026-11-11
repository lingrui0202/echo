extends Node
## 追击自检：
##   A. 玩家站着不动，敌人在同一条路线上 4 格外 → 应在 4 秒内抓到（追击有威胁）
##   B. 玩家沿路线全速跑 → 5 秒内不应被抓（还能逃）
##   Godot_v4.7.2-stable_win64_console.exe --path <本目录> res://tools/chase_check.tscn

const Maze = preload("res://scripts/maze.gd")
const CELL := 64
const PLAYER_SPEED := 235.0

var _level: Node
var _player: Node
var _enemy: Node
var _route: Array = []
var _phase := 0
var _t := 0.0
var _route_i := 0
var _caught_a := false
var _caught_b := false
var _fails := PackedStringArray()

func _ready() -> void:
	var _gl := get_node_or_null("/root/GameLog")
	if _gl != null:
		_gl.set("mode_tag", "tool")
		_gl.set("persist", false)
	var prog := get_node_or_null("/root/Progress")
	prog.set("level_index", 2)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	_level = ps.instantiate()
	_level.name = "Level01"
	add_child(_level)
	_player = _level.get_node("Player")
	var box: Node = _level.get_node("Enemies")
	if box.get_child_count() == 0:
		print("FAIL: 第 3 关没有敌人")
		get_tree().quit(1)
		return
	_enemy = box.get_child(0)

	var rows: Array = _level.map_rows()
	_route = Maze.path(rows, _level.start_cell(), _level.goal_cell())
	_start_case_a()

func _cell_pos(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL * 0.5, c.y * CELL + CELL * 0.5)

## 玩家在路线第 10 格，敌人在第 14 格（同一条路上，一定连通）
func _start_case_a() -> void:
	_player.global_position = _cell_pos(_route[10])
	_enemy.global_position = _cell_pos(_route[14])
	_enemy.call("hear_any", _player.global_position)
	_phase = 0
	_t = 0.0
	print("[chase] A: 玩家静止，敌人 4 格外，开始追")

func _start_case_b() -> void:
	_player.set("_alive", true)
	# 敌人放在玩家「身后」（路线更靠前的格），玩家朝出口方向跑
	_player.global_position = _cell_pos(_route[10])
	_enemy.global_position = _cell_pos(_route[6])
	_route_i = 10
	_enemy.call("hear_any", _player.global_position)
	_phase = 1
	_t = 0.0
	print("[chase] B: 玩家全速跑，敌人 4 格外，开始追")

func _physics_process(delta: float) -> void:
	if _player == null or _enemy == null:
		return
	_t += delta

	if _phase == 0:
		if _player.get("_alive") == false:
			_caught_a = true
			print("[chase] A: 被抓，用时 %.1f s" % _t)
			_start_case_b()
		elif _t > 4.0:
			_fails.append("静止玩家 4 s 内没被抓到（追击太弱）")
			print("[chase] A: 4 s 没抓到")
			_start_case_b()
	elif _phase == 1:
		_run_away(delta)
		if _player.get("_alive") == false:
			_caught_b = true
			_fails.append("全速跑还是被抓了（追击太强）")
			print("[chase] B: 被抓（%.1f s）" % _t)
			_done()
		elif _t > 5.0:
			print("[chase] B: 5 s 没被抓到（能逃）")
			_done()

func _run_away(delta: float) -> void:
	if _route_i >= _route.size() - 1:
		return
	var tp := _cell_pos(_route[_route_i + 1])
	var p: Vector2 = _player.global_position
	var step := PLAYER_SPEED * delta
	if p.distance_to(tp) <= step:
		_player.global_position = tp
		_route_i += 1
	else:
		_player.global_position = p + (tp - p).normalized() * step

func _done() -> void:
	print("---- A 被抓=%s  B 被抓=%s" % [_caught_a, _caught_b])
	if _fails.is_empty():
		print("PASS: 追击强度合适（追得上站桩的，追不上全速跑的）")
		get_tree().quit(0)
	else:
		for f in _fails:
			print("FAIL: ", f)
		get_tree().quit(1)
