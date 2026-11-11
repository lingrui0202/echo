extends Control
## 左上角小地图：只画「走过的格子」。
## 不画没去过的墙 —— 那就等于开图了，声呐探索全废。
##
## 画的是：走过的格子（淡蓝）、当前位置（白点）、出口（只有靠近过才显示）。

const CELL_PX := 2.2
const PAD := 4.0
const GOAL_HINT := 6.0     # 离出口几格内算「发现了」
const FADE_MS := 60000.0   # 走过的格子多久淡到最暗（不是消失：地图记忆不该被抹掉）

var _rows: Array = []
var _visited := {}
var _player_cell := Vector2i(-1, -1)
var _goal := Vector2i(-1, -1)
var _goal_seen := false
var _map_w := 61
var _map_h := 34
var _open_total := 1


var _redraw_tick := 0

func _process(_delta: float) -> void:
	# 渐隐要看得见就得定时重绘；10 帧一次够用，也不浪费
	_redraw_tick += 1
	if _redraw_tick % 10 == 0 and not _visited.is_empty():
		queue_redraw()


## 换关时立刻清空（不等下一帧 setup）
func clear() -> void:
	_visited.clear()
	_player_cell = Vector2i(-1, -1)
	_goal_seen = false
	queue_redraw()


func setup(rows: Array, goal: Vector2i) -> void:
	_visited.clear()
	_player_cell = Vector2i(-1, -1)
	_goal_seen = false
	_rows = rows
	_map_w = rows[0].length()
	_map_h = rows.size()
	_goal = goal
	var open := 0
	for r in rows:
		for i in String(r).length():
			if String(r)[i] != "#":
				open += 1
	_open_total = maxi(open, 1)
	custom_minimum_size = Vector2(_map_w * CELL_PX + PAD * 2, _map_h * CELL_PX + PAD * 2)
	size = custom_minimum_size


func visit(cell: Vector2i) -> void:
	if cell.x < 0 or cell.y < 0 or cell.x >= _map_w or cell.y >= _map_h:
		return
	if _visited.has(cell):
		return
	_visited[cell] = Time.get_ticks_msec()
	if _goal.x >= 0 and Vector2(cell).distance_to(Vector2(_goal)) <= GOAL_HINT:
		_goal_seen = true
	queue_redraw()


func set_player(cell: Vector2i) -> void:
	if cell != _player_cell:
		_player_cell = cell
		queue_redraw()


func visited_count() -> int:
	return _visited.size()


func explored_ratio() -> float:
	return float(_visited.size()) / float(_open_total)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.08, 0.82))

	var now := Time.get_ticks_msec()
	for c in _visited.keys():
		var age := clampf(float(now - int(_visited[c])) / FADE_MS, 0.0, 1.0)
		var a := lerpf(0.75, 0.14, age)     # 刚走过的亮，越久越淡
		draw_rect(Rect2(Vector2(PAD, PAD) + Vector2(c) * CELL_PX, Vector2(CELL_PX, CELL_PX)),
			Color(0.34, 0.70, 1.0, a))

	if _goal_seen:
		draw_circle(Vector2(PAD, PAD) + (Vector2(_goal) + Vector2(0.5, 0.5)) * CELL_PX,
			2.4, Color(0.25, 1.0, 0.65))

	if _player_cell.x >= 0:
		draw_circle(Vector2(PAD, PAD) + (Vector2(_player_cell) + Vector2(0.5, 0.5)) * CELL_PX,
			2.6, Color(0.88, 0.98, 1.0))

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.40, 0.55, 0.72, 0.55), false, 1.0)
