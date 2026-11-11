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
const Levels = preload("res://scripts/levels.gd")
const EnemyScene = preload("res://scenes/Enemy.tscn")
const EnemyScript = preload("res://scripts/enemy.gd")

const CELL := 64

# 敌人出生点不手写坐标：先算「起点 → 出口」的最短路，按路线长度取 30% 和 65% 两处，
# 放在路线旁边的开放格上（优先不在路线上，避免堵死唯一通道）。
# 这样玩家沿正常路线走一定会经过它们附近；地图改了也不用重对坐标。
# 每关敌人数（索引 = 关卡序，0 起）：第 1 关没有敌人，先把“找路”练熟
const ENEMY_BY_LEVEL := [0, 1, 1, 2, 2]
## 每关敌人类型：0 普通 / 1 瞎子（只被强声呐惊动）/ 2 敏锐（听觉远、追得久）
const ENEMY_KINDS := [[], [0], [2], [0, 1], [2, 1]]
const ENEMY_SEP := 10
const ENEMY_ROUTE_FRACS := [0.30, 0.65]

## 当前关卡的地图（由 levels.gd 提供，运行时按 Progress 选）
var map: Array = []
var level_index := 0

# 全黑靠这层 modulate 实现。放在代码里而不是场景里：
# 编辑器里不生成它，2D 视图就能直接看到整张地图。
const DARK := Color(0.015, 0.017, 0.028)
const START := Vector2i(1, 1)


var _wave: Node2D = null
var _goal_cell := Vector2i(-1, -1)
var _enemy_cells: Array = []
var _crates := {}          # Vector2i -> StaticBody2D
var _map_w := 0
var _map_h := 0
var _route_len := 0

## 编辑器里预览哪一关（1–5）。游戏里不看这个值，游戏读 Progress.level_index。
@export_range(1, 5, 1) var editor_level: int = 1:
	set(v):
		editor_level = clampi(v, 1, 5)
		if Engine.is_editor_hint() and is_inside_tree():
			level_index = editor_level - 1
			map = Levels.MAPS[level_index]
			_build()
			print("[level] 编辑器：切到第 %d 关（%d×%d）" % [
				editor_level, String(map[0]).length(), map.size()])


func _ready() -> void:
	level_index = 0
	if not Engine.is_editor_hint():
		level_index = clampi(Progress.level_index, 0, Levels.MAPS.size() - 1)
	elif map.is_empty():
		level_index = editor_level - 1      # 编辑器里默认按 Inspector 里选的那关
	map = Levels.MAPS[level_index]

	if not Engine.is_editor_hint():
		var cm := CanvasModulate.new()
		cm.name = "Darkness"
		cm.color = Settings.dark_color()
		add_child(cm)
		move_child(cm, 0)
	if Session.is_test():
		Mods.current = ""
		Mods.pending = false        # 测试模式不发词条
	else:
		Mods.reset_for_level(level_index)
	_build()
	if Engine.is_editor_hint():
		print("[level] 编辑器模式：已按 MAP 生成 %d 面墙" % $Walls.get_child_count())

## 给工具/自检用的只读接口，避免测试再抄一份坐标。
func map_rows() -> Array:
	return map

func start_cell() -> Vector2i:
	return START

func enemy_cells() -> Array:
	return _enemy_cells

## 原地重建：换关、重开都走这里，不重载场景。
## 之前用 get_tree().reload_current_scene()，在编辑器里跑会退回编辑器窗口。
## 不传 idx 时以 Progress.level_index 为准 —— 设置里按 4/5 选的就是它。
func restart(idx: int = -1) -> void:
	if idx < 0:
		idx = Progress.level_index
	level_index = clampi(idx, 0, Levels.MAPS.size() - 1)
	map = Levels.MAPS[level_index]
	if Session.is_test():
		Mods.current = ""
		Mods.pending = false        # 测试模式换关也不发词条
	else:
		Mods.reset_for_level(level_index)
	_build()

	Progress.level_index = level_index

	var player: Node2D = get_node_or_null("Player")
	if player != null and player.has_method("reset_state"):
		player.reset_state(Vector2(START.x * CELL + CELL * 0.5, START.y * CELL + CELL * 0.5))

	# reset_state 里 start_session() 会把 config 清空，所以这里再写一遍地图参数
	_note_config(_map_w, _map_h)

	var hud: Node = get_node_or_null("HUD")
	if hud != null and hud.has_method("on_level_changed"):
		hud.on_level_changed()


func goal_cell() -> Vector2i:
	return _goal_cell

func level_no() -> int:
	return level_index + 1

func level_total() -> int:
	return Levels.MAPS.size()


## 玩家发声呐时把波注入到关卡里（真正的反射在这一层算），并把声音传给敌人。
func emit_wave(p: Vector2, strong: bool = false) -> void:
	if _wave != null:
		_wave.emit_at(p, strong)
	_alarm(p, strong)

func _build() -> void:
	_clear_map()
	var walls: Node2D = $Walls
	var width := 0
	for row in map:
		width = maxi(width, row.length())
	var height: int = map.size()

	_add_ground(width, height)

	# 内部墙：把每行里连续的 '#' 合并成一条长条，减少节点数、光照更干净
	for y in height:
		var row: String = map[y]
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
	_map_w = width
	_map_h = height
	var darkness := get_node_or_null("Darkness")
	if darkness != null:
		darkness.color = Settings.dark_color()   # 换关时亮度设置要重新生效

	if not Engine.is_editor_hint():
		if _wave != null:
			_wave.queue_free()      # 重建关卡时要清掉上一次的波场，否则会越叠越多
			_wave = null
		_wave = SonarWave.new()
		_wave.name = "SonarWave"
		_wave.setup(map, float(CELL))
		_wave.clear_memory()   # 上一张图的墙面记忆不能带到新图
		_wave.set_palette(Settings.palette)
		add_child(_wave)

		var player: Node2D = $Player
		player.global_position = Vector2(START.x * CELL + CELL * 0.5, START.y * CELL + CELL * 0.5)
		_setup_camera(player, width, height)
		_spawn_enemies()
		_spawn_crates()
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
			c.set_physics_process(false)     # 本帧别再追/抓了
			c.set_process(false)
			enemies.remove_child(c)
			c.queue_free()

	var route := Maze.path(map, START, _goal_cell)
	_route_len = route.size()
	_enemy_cells.clear()
	for frac in ENEMY_ROUTE_FRACS:
		if _enemy_cells.size() >= _enemy_target() or route.is_empty():
			break
		var idx := clampi(int(round(float(route.size()) * float(frac))), 0, route.size() - 1)
		var anchor: Vector2i = route[idx]
		# 半径 3 内找候选：优先「不在最短路上」的格子（不挡唯一通道），再按距离取近的。
		# 之前只看四邻，锚点四周全是路线时只能退回锚点，导致敌人正好堵在路上。
		var cands: Array = []
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				if dx == 0 and dy == 0:
					continue
				var cell: Vector2i = anchor + Vector2i(dx, dy)
				if cell == _goal_cell or cell == START or not Maze.is_open(map, cell):
					continue
				var ok := true
				for other in _enemy_cells:
					if Vector2i(other).distance_to(cell) < ENEMY_SEP:
						ok = false
						break
				if not ok:
					continue
				cands.append({"cell": cell, "d": absi(dx) + absi(dy), "on_route": route.has(cell)})
		cands.sort_custom(func(a, b):
			if bool(a["on_route"]) != bool(b["on_route"]):
				return not bool(a["on_route"])
			return int(a["d"]) < int(b["d"]))
		var best := Vector2i(-1, -1)
		if not cands.is_empty():
			best = cands[0]["cell"]
		if best.x >= 0:
			_enemy_cells.append(best)
		else:
			# 极端情况（锚点周围全被堵死）：退回锚点，自检会报出来
			_enemy_cells.append(anchor)

	var kinds: Array = ENEMY_KINDS[clampi(level_index, 0, ENEMY_KINDS.size() - 1)]
	for i in _enemy_cells.size():
		var cell: Vector2i = _enemy_cells[i]
		var e := EnemyScene.instantiate()
		enemies.add_child(e)
		var k := int(kinds[i]) if i < kinds.size() else 0
		e.setup(map, float(CELL), cell, k)


## 可动墙：放在最短路上，挡一次；推开才能继续。
## 第 1 关不放（先学会走路），后面 2 / 3 个。
func _spawn_crates() -> void:
	var root := get_node_or_null("Crates")
	if root == null:
		root = Node2D.new()
		root.name = "Crates"
		add_child(root)
	for c in root.get_children():
		root.remove_child(c)
		c.queue_free()
	_crates.clear()
	if level_index == 0:
		return

	var route := Maze.path(map, START, _goal_cell)
	if route.is_empty():
		return
	var want := 2 if level_index < 3 else 3
	for frac in [0.28, 0.48, 0.68]:
		if _crates.size() >= want:
			break
		var idx := clampi(int(round(float(route.size()) * float(frac))), 0, route.size() - 1)
		var cell: Vector2i = route[idx]
		if cell == START or cell == _goal_cell or _crates.has(cell) or not Maze.is_open(map, cell):
			continue
		# 至少要有一个方向是空地，不然推不动
		var free_side := false
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			if Maze.is_open(map, cell + d):
				free_side = true
				break
		if not free_side:
			continue
		_add_crate(root, cell)


func _add_crate(root: Node2D, cell: Vector2i) -> void:
	var body := StaticBody2D.new()
	body.position = Vector2(cell.x * CELL + CELL * 0.5, cell.y * CELL + CELL * 0.5)
	body.collision_layer = 1
	body.collision_mask = 0

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(CELL - 6, CELL - 6)
	shape.shape = rect
	body.add_child(shape)

	# 挡光：箱子确实会挡住声呐，推它才真的改变信息
	var occ := LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-CELL * 0.5, -CELL * 0.5), Vector2(CELL * 0.5, -CELL * 0.5),
		Vector2(CELL * 0.5, CELL * 0.5), Vector2(-CELL * 0.5, CELL * 0.5),
	])
	occ.occluder = poly
	body.add_child(occ)

	var vis := Polygon2D.new()
	vis.polygon = PackedVector2Array([
		Vector2(-CELL * 0.42, -CELL * 0.42), Vector2(CELL * 0.42, -CELL * 0.42),
		Vector2(CELL * 0.42, CELL * 0.42), Vector2(-CELL * 0.42, CELL * 0.42),
	])
	vis.color = Color(0.55, 0.46, 0.32)
	body.add_child(vis)

	root.add_child(body)
	_crates[cell] = body


func crate_cells() -> Array:
	return _crates.keys()

func has_crate(cell: Vector2i) -> bool:
	return _crates.has(cell)

## 推一格：目标格必须是空地、不是出口、没有别的箱子。
func push_crate(cell: Vector2i, dir: Vector2i) -> bool:
	if not _crates.has(cell):
		return false
	var to: Vector2i = cell + dir
	if to == _goal_cell or _crates.has(to) or not Maze.is_open(map, to) or to == START:
		return false
	var body: Node2D = _crates[cell]
	_crates.erase(cell)
	body.position = Vector2(to.x * CELL + CELL * 0.5, to.y * CELL + CELL * 0.5)
	_crates[to] = body
	return true


func _enemy_target() -> int:
	if level_index >= 0 and level_index < ENEMY_BY_LEVEL.size():
		return int(ENEMY_BY_LEVEL[level_index])
	return 1


## 声呐广播：听觉穿墙，不做视线判定。被惊动的数量记进遥测（HUD 会闪一下提示）。
## strong = 强声呐：不管多远，全场敌人都听见。
func _alarm(p: Vector2, strong: bool = false) -> void:
	var enemies := get_node_or_null("Enemies")
	if enemies == null:
		return
	var heard := 0
	for e in enemies.get_children():
		if not e.has_method("hear"):
			continue
		var got: bool = e.hear_any(p) if (strong and e.has_method("hear_any")) else e.hear(p)
		if got:
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
		"level_index": level_index,
		"map_w": width,
		"map_h": height,
		"cell": CELL,
		"wave_speed": SonarWave.RING_SPEED,
		"wave_duration": SonarWave.DURATION,
		"max_bounces": SonarWave.MAX_BOUNCES,
		"segments": SonarWave.SEGMENTS,
		"route_len": _route_len,
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
			walls.remove_child(c)
			c.queue_free()
	var old := get_node_or_null("MapLayer")
	if old != null:
		remove_child(old)
		old.queue_free()
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
