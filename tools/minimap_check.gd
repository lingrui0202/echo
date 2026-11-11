extends Node
## 小地图自检：沿「起点 → 出口」的真实路线走一段，确认左上角小地图把足迹记下来了。
##   Godot_v4.7.2-stable_win64_console.exe --path <本目录> res://tools/minimap_check.tscn

const CELL := 64
const Maze = preload("res://scripts/maze.gd")
const STEPS := 40          # 走路线的前多少格
const FRAMES_PER_CELL := 3

var _level: Node
var _player: Node
var _hud: Node
var _route: Array = []
var _frames := 0
var _idx := 0

func _ready() -> void:
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	_level = ps.instantiate()
	_level.name = "Level01"
	add_child(_level)
	_player = _level.get_node("Player")
	_hud = _level.get_node("HUD")

	var rows: Array = _level.map_rows()
	var start: Vector2i = _level.start_cell()
	var goal: Vector2i = _level.goal_cell()
	var dist: Dictionary = Maze.distances(rows, start)

	# 从出口沿距离下降走回起点，得到真实路线
	var cur := goal
	var rev: Array = [cur]
	while cur != start:
		var best := cur
		var best_d := int(dist.get(cur, 999999))
		for dir in Maze.DIRS:
			var nxt: Vector2i = cur + dir
			if dist.has(nxt) and int(dist[nxt]) < best_d:
				best = nxt
				best_d = int(dist[nxt])
		if best == cur:
			break
		cur = best
		rev.append(cur)
	rev.reverse()
	_route = rev
	print("[minimap] 路线 %d 格，走前 %d 格" % [_route.size(), STEPS])

func _process(_delta: float) -> void:
	_frames += 1
	if _idx < STEPS and _route.size() > 0 and _frames % FRAMES_PER_CELL == 0:
		var c: Vector2i = _route[mini(_idx, _route.size() - 1)]
		_player.global_position = Vector2(c.x * CELL + CELL * 0.5, c.y * CELL + CELL * 0.5)
		_idx += 1

	if _idx >= STEPS and _frames % FRAMES_PER_CELL == 0:
		var mm: Control = _hud.get("_minimap")
		var n: int = mm.call("visited_count") if mm != null else -1
		var ratio: float = mm.call("explored_ratio") if mm != null else 0.0
		print("[minimap] 走过 %d 格，已探索 %.1f%%" % [n, ratio * 100.0])
		if n < STEPS - 2:
			print("FAIL: 小地图漏格（期望约 %d）" % STEPS)
		else:
			print("PASS: 小地图记录了足迹")
		get_viewport().get_texture().get_image().save_png("res://_verify/minimap.png")
		print("[minimap] 截图 _verify/minimap.png")
		get_tree().quit()
