@tool
extends Node2D
## 关卡：从一张 ASCII 地图生成碰撞体 + 光照遮挡体 + 视觉。
##
## 为什么用 ASCII 而不是在编辑器里手摆 200 个 StaticBody2D？
##   1. 改关卡 = 改几行字符串，一眼能看懂
##   2. 碰撞体和遮挡体永远对得上（手摆最容易漏）
##   3. 答辩时能讲清"数据驱动"这件事
##
## 地图规则：
##   61x34 格，通道 2 格宽（第 6 周把 1 格走廊改宽了：1 格走廊里波反射看着很碎）。
##   '#' = 墙     '.' = 地面
##   'E' = 出口
## 起点在 START 里改。边界墙由代码自动补齐，不用写。

const LightFactory = preload("res://scripts/light_factory.gd")
const GridScript = preload("res://scripts/grid.gd")
const SonarWave = preload("res://scripts/sonar_wave.gd")
const Maze = preload("res://scripts/maze.gd")
const EnemyScene = preload("res://scenes/Enemy.tscn")
const EnemyScript = preload("res://scripts/enemy.gd")

const CELL := 64

# 敌人出生点不手写坐标：先算「起点 → 出口」的最短路，按路线长度取 30% 和 65% 两处，
# 放在路线旁边的开放格上（优先不在路线上，避免堵死唯一通道）。
# 这样玩家沿正常路线走一定会经过它们附近；地图改了也不用重对坐标。
const ENEMY_COUNT := 2
const ENEMY_SEP := 10
const ENEMY_ROUTE_FRACS := [0.30, 0.65]

# 全黑靠这层 modulate 实现。放在代码里而不是场景里：
# 编辑器里不生成它，2D 视图就能直接看到整张地图。
const DARK := Color(0.015, 0.017, 0.028)
const START := Vector2i(1, 1)

const MAP := [
	"#############################################################",
	"#.....#........#.................#.....#..............#.....#",
	"#.....#........#......................................#.....#",
	"####..#..#####.#..####........#..#..#......######..#..####..#",
	"#..#..#...........#...........#..#..#..............#.....#..#",
	"#..#..#...........#...........#..#..#..............#.....#..#",
	"#..#..#..######.#.#..#######..#..#..##.......##########..#..#",
	"#.....#.....#.....#........#..#.....#.....#..#........#..#..#",
	"#.....#.....#.....#........#..#.....#.....#..#........#..#..#",
	"#..#######..####..#######..#..#######..#..#..#..#######..#..#",
	"#.....#..............#..#..............#..#..#..#........#..#",
	"#.....#..............#..#..............#..#..#..#........#..#",
	"####..#############..#..################..#..#..#..#######..#",
	"#..#..#...........#........#.....#........#..#..#........#..#",
	"#..#..#...........#.......E#.....#........#..#..#........#..#",
	"#..#..#..#######..#..#######..#..##########..#..#######..#..#",
	"#........#.....#..#..#.......................#........#.....#",
	"#..#...........#..#..#........#..............#........#.....#",
	"#..##.......####..#..#..################.########..#..####..#",
	"#.................#..#.....#.....#.................#.....#..#",
	"#.................#..#.....#.....#.................#.....#..#",
	"#..##.....#.#############..#..####..##########..#..#######..#",
	"#..#....................#..#.....#...........#..#..#........#",
	"#..#....................#..#.....#..............#..#........#",
	"#..####..#############..#..#..#..#######........#..#..#######",
	"#..#.....#..#........#.....#..#.....#...........#..#.....#..#",
	"#..#.....#..#........#..............#...........#..#........#",
	"#..#..####..#..####..##.......####..#..##.....#########..#..#",
	"#..#..#........#..#...........#..#..#..#..#.....#.....#..#..#",
	"#..#..#........#..#...........#..#..#..#..#.....#.....#..#..#",
	"#..#..#..#######..#####......##..#..#..#..####..#..#..#..#..#",
	"#.....#..........................#...........#.....#........#",
	"#.....#..........................#...........#.....#........#",
	"#############################################################",
]

var _wave: Node2D = null
var _goal_cell := Vector2i(-1, -1)
var _enemy_cells: Array = []

func _ready() -> void:
	if not Engine.is_editor_hint():
		var cm := CanvasModulate.new()
		cm.name = "Darkness"
		cm.color = DARK
		add_child(cm)
		move_child(cm, 0)
	_build()
	if Engine.is_editor_hint():
		print("[level] 编辑器模式：已按 MAP 生成 %d 面墙" % $Walls.get_child_count())

## 给工具/自检用的只读接口，避免测试再抄一份坐标。
func map_rows() -> Array:
	return MAP

func start_cell() -> Vector2i:
	return START

func enemy_cells() -> Array:
	return _enemy_cells


## 玩家发声呐时把波注入到关卡里（真正的反射在这一层算），并把声音传给敌人。
func emit_wave(p: Vector2) -> void:
	if _wave != null:
		_wave.emit_at(p)
	_alarm(p)

func _build() -> void:
	_clear_map()
	var walls: Node2D = $Walls
	var width := 0
	for row in MAP:
		width = maxi(width, row.length())
	var height: int = MAP.size()

	_add_ground(width, height)

	# 内部墙：把每行里连续的 '#' 合并成一条长条，减少节点数、光照更干净
	for y in height:
		var row: String = MAP[y]
		var x := 0
		while x < row.length():
			var c := row[x]
			if c == "#":
				var x0 := x
				while x < row.length() and row[x] == "#":
					x += 1
				_add_wall(walls, x0, y, x - x0, 1)
			else:
				if c == "E":
					_add_goal(x, y)
				x += 1

	# 边界墙
	_add_wall(walls, -1, -1, width + 2, 1)
	_add_wall(walls, -1, height, width + 2, 1)
	_add_wall(walls, -1, 0, 1, height)
	_add_wall(walls, width, 0, 1, height)

	# 声呐波场：跟地图同一套坐标，墙就是反射面。编辑器里不需要，省得它一直刷新。
	if not Engine.is_editor_hint():
		_wave = SonarWave.new()
		_wave.name = "SonarWave"
		_wave.setup(MAP, float(CELL))
		add_child(_wave)

		var player: Node2D = $Player
		player.global_position = Vector2(START.x * CELL + CELL * 0.5, START.y * CELL + CELL * 0.5)
		_setup_camera(player, width, height)
		_spawn_enemies()
		_note_config(width, height)

## 相机跟随玩家，但别让视口露出地图外：限位到地图矩形，并加一点平滑。
## 不设限位时，站在起点（地图左上角）会有半个屏幕是地图外的黑，很出戏。
func _setup_camera(player: Node2D, width: int, height: int) -> void:
	var cam := player.get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = width * CELL
	cam.limit_bottom = height * CELL
	cam.limit_smoothed = true
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	cam.reset_smoothing()


## 敌人：出生点由 BFS 距离决定（不写死坐标），追击寻路也走同一张图。
## 放在独立容器 Enemies 里，重载/重建时整批清掉。
func _spawn_enemies() -> void:
	var enemies := get_node_or_null("Enemies")
	if enemies == null:
		enemies = Node2D.new()
		enemies.name = "Enemies"
		add_child(enemies)
	else:
		for c in enemies.get_children():
			c.free()

	var route := Maze.path(MAP, START, _goal_cell)
	_enemy_cells.clear()
	for frac in ENEMY_ROUTE_FRACS:
		if _enemy_cells.size() >= ENEMY_COUNT or route.is_empty():
			break
		var idx := clampi(int(round(float(route.size()) * float(frac))), 0, route.size() - 1)
		var anchor: Vector2i = route[idx]
		# 只取上下左右四邻格：相邻格之间没有墙，敌人一定在路线旁边、看得见。
		# 不取斜角/隔一格，那样可能隔着墙，算「近」其实看不见。
		var best := Vector2i(-1, -1)
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var cell: Vector2i = anchor + dir
			if cell == _goal_cell or cell == START or route.has(cell):
				continue
			if not Maze.is_open(MAP, cell):
				continue
			var ok := true
			for other in _enemy_cells:
				if Vector2i(other).distance_to(cell) < ENEMY_SEP:
					ok = false
					break
			if not ok:
				continue
			best = cell
			break
		if best.x >= 0:
			_enemy_cells.append(best)
		else:
			# 极端情况（锚点周围全被堵死）：退回锚点，自检会报出来
			_enemy_cells.append(anchor)

	for cell in _enemy_cells:
		var e := EnemyScene.instantiate()
		enemies.add_child(e)
		e.setup(MAP, float(CELL), cell)


## 声呐广播：听觉穿墙，不做视线判定。被惊动的数量记进遥测（HUD 会闪一下提示）。
func _alarm(p: Vector2) -> void:
	var enemies := get_node_or_null("Enemies")
	if enemies == null:
		return
	var heard := 0
	for e in enemies.get_children():
		if e.has_method("hear") and e.hear(p):
			heard += 1
	if heard > 0:
		GameLog.note_alert(heard)


## 把这一局的地图/波参数写进遥测。改完参数后数据才解释得通：
## "1.8 s 冷却那 10 局" 和 "2.4 s 冷却那 10 局" 必须能分开。
func _note_config(width: int, height: int) -> void:
	var gl := get_node_or_null("/root/GameLog")
	if gl == null:
		return
	gl.set_config({
		"level": scene_file_path.get_file(),
		"map_w": width,
		"map_h": height,
		"cell": CELL,
		"wave_speed": SonarWave.RING_SPEED,
		"wave_duration": SonarWave.DURATION,
		"max_bounces": SonarWave.MAX_BOUNCES,
		"segments": SonarWave.SEGMENTS,
		"enemy_count": _enemy_cells.size(),
		"enemy_hear_radius": EnemyScript.HEAR_RADIUS,
		"enemy_speed": EnemyScript.SPEED,
		"enemy_chase_time": EnemyScript.CHASE_TIME,
	})


## 编辑器里改 MAP 会重复生成，先把上一次的产物清掉
func _clear_map() -> void:
	var walls := get_node_or_null("Walls")
	if walls != null:
		for c in walls.get_children():
			c.free()
	var old := get_node_or_null("MapLayer")
	if old != null:
		old.free()
	var layer := Node2D.new()
	layer.name = "MapLayer"
	add_child(layer)

func _map_layer() -> Node2D:
	return get_node("MapLayer")

func _add_ground(width: int, height: int) -> void:
	var size := Vector2(width * CELL, height * CELL)

	# 纯色地板：本身很暗，只有被光照到才会显出来
	var floor_poly := Polygon2D.new()
	floor_poly.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y)
	])
	floor_poly.color = Color(0.22, 0.25, 0.34)
	floor_poly.z_index = -10
	_map_layer().add_child(floor_poly)

	var grid := GridScript.new()
	grid.cells = Vector2i(width, height)
	grid.cell = float(CELL)
	grid.z_index = -9
	_map_layer().add_child(grid)

func _add_wall(parent: Node2D, cx: int, cy: int, cw: int, ch: int) -> void:
	var size := Vector2(cw * CELL, ch * CELL)
	var body := StaticBody2D.new()
	body.position = Vector2(cx * CELL, cy * CELL) + size * 0.5
	body.collision_layer = 1
	body.collision_mask = 0

	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)

	# 遮挡体：必须顺时针。y 轴向下，"上左→上右→下右→下左"就是顺时针。
	var pts := PackedVector2Array([
		Vector2(-size.x, -size.y) * 0.5,
		Vector2(size.x, -size.y) * 0.5,
		Vector2(size.x, size.y) * 0.5,
		Vector2(-size.x, size.y) * 0.5,
	])
	var poly := OccluderPolygon2D.new()
	poly.polygon = pts
	var occ := LightOccluder2D.new()
	occ.occluder = poly
	body.add_child(occ)

	var vis := Polygon2D.new()
	vis.polygon = pts
	vis.color = Color(0.82, 0.90, 1.0)
	body.add_child(vis)

	parent.add_child(body)

func _add_goal(cx: int, cy: int) -> void:
	_goal_cell = Vector2i(cx, cy)
	var area := Area2D.new()
	area.position = Vector2(cx * CELL, cy * CELL) + Vector2(CELL, CELL) * 0.5
	area.collision_layer = 4
	area.collision_mask = 2

	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(CELL * 0.8, CELL * 0.8)
	cs.shape = shape
	area.add_child(cs)

	var d := CELL * 0.28
	var vis := Polygon2D.new()
	vis.polygon = PackedVector2Array([Vector2(0, -d), Vector2(d, 0), Vector2(0, d), Vector2(-d, 0)])
	vis.color = Color(0.30, 1.0, 0.65)
	area.add_child(vis)

	# 出口自己是弱光源，黑暗中像一个灯塔。
	# shadow_enabled 必须打开：PointLight2D 默认不吃遮挡体，不打开的话
	# 这道绿光会穿墙亮出来，等于提前剧透出口位置。
	var glow := PointLight2D.new()
	glow.texture = LightFactory.radial_texture(128)
	glow.energy = 0.55
	glow.texture_scale = 0.7
	glow.color = Color(0.4, 1.0, 0.7)
	glow.shadow_enabled = true
	area.add_child(glow)

	area.body_entered.connect(_on_goal_entered)
	_map_layer().add_child(area)

func _on_goal_entered(body: Node2D) -> void:
	if body.has_method("win"):
		body.win()
