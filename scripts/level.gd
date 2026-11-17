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
const IconNode = preload("res://scripts/icon_node.gd")

const CELL := 64

# 敌人出生点不手写坐标：先算「起点 → 出口」的最短路，按路线长度取 30% 和 65% 两处，
# 放在路线旁边的开放格上（优先不在路线上，避免堵死唯一通道）。
# 这样玩家沿正常路线走一定会经过它们附近；地图改了也不用重对坐标。
# 每关敌人数（索引 = 关卡序，0 起）：第 1 关没有敌人，先把“找路”练熟
const ENEMY_BY_LEVEL := [0, 2, 3, 3, 4, 4, 5, 5, 6, 6]
## 每关敌人类型：0 普通 / 1 瞎子（只被强声呐惊动）/ 2 敏锐（听觉远、追得久）
const ENEMY_KINDS := [
	[],
	[0, 0],
	[2, 0, 0],
	[0, 1, 2],
	[2, 1, 0, 0],
	[0, 2, 1, 0],
	[0, 0, 2, 1, 2],
	[1, 2, 2, 0, 0],
	[0, 1, 2, 2, 1, 0],
	[2, 1, 1, 0, 2, 0],
]
const ENEMY_SEP := 10
const ENEMY_ROUTE_FRACS := [0.16, 0.30, 0.44, 0.58, 0.72, 0.86]

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

# 机关：门 / 钥匙 / 压力板 / 静音区
var _doors := {}         # 格子 -> {body, occ, vis}
var _plates := {}        # 格子 -> 视觉节点
var _keys := {}          # 格子 -> 视觉节点
var _silence := {}       # 格子 -> true
var _plate_door := {}    # 压力板 -> 它控制的门
var _active_plate := Vector2i(-99, -99)
var _keys_revealed := false     # 碰过门之后，小地图才标钥匙
var _frags := {}          # 格子 -> 节点
var _overlay: CanvasLayer     # 机关图标画在这层（不受全黑层影响）
var _reveals := []            # [{node, cell, seen}]

## 编辑器里预览哪一关（1–5）。游戏里不看这个值，游戏读 Progress.level_index。
@export_range(1, 10, 1) var editor_level: int = 1:
	set(v):
		editor_level = clampi(v, 1, Levels.MAPS.size())
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
	if map.is_empty():
		map = Levels.MAPS[level_index].duplicate().duplicate()   # 关门会改地图，不能改到常量里

	if not Engine.is_editor_hint():
		var cm := CanvasModulate.new()
		cm.name = "Darkness"
		cm.color = Settings.dark_color()
		add_child(cm)
		move_child(cm, 0)
	if Session.is_test() or _is_tool_run():
		Mods.current = ""
		Mods.pending = false        # 测试模式 / 自检都不发词条
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
	map = Levels.MAPS[level_index].duplicate()
	if Session.is_test() or _is_tool_run():
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
	var silent := is_silent_at(p)
	if _wave != null:
		_wave.emit_at(p, strong, silent)
	if not silent:
		_alarm(p, strong)        # 静音区里发声，敌人听不见

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

	# 路线长度要在关门之前算（门开着才是玩家该走的路线）
	_route_len = Maze.path(map, START, _goal_cell).size()

	# 边界墙
	_add_wall(walls, -1, -1, width + 2, 1)
	_add_wall(walls, -1, height, width + 2, 1)
	_add_wall(walls, -1, 0, 1, height)
	_add_wall(walls, width, 0, 1, height)

	if not Engine.is_editor_hint():
		var old_ov := get_node_or_null("Overlay")
		if old_ov != null:
			remove_child(old_ov)
			old_ov.queue_free()
		_overlay = CanvasLayer.new()
		_overlay.name = "Overlay"
		_overlay.follow_viewport_enabled = true
		add_child(_overlay)
	_reveals.clear()
	_build_objects()
	_spawn_fragments()

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
		_show_intro_card()

## 相机跟随玩家，但别让视口露出地图外：限位到地图矩形，并加一点平滑。
## 不设限位时，站在起点（地图左上角）会有半个屏幕是地图外的黑，很出戏。
## ---- 机关 ----

func _build_objects() -> void:
	var root := get_node_or_null("Objects")
	if root == null:
		root = Node2D.new()
		root.name = "Objects"
		add_child(root)
	for c in root.get_children():
		root.remove_child(c)
		c.queue_free()
	_doors.clear()
	_plates.clear()
	_keys.clear()
	_silence.clear()
	_plate_door.clear()
	_active_plate = Vector2i(-99, -99)
	_keys_revealed = false

	for y in map.size():
		var row: String = map[y]
		for x in row.length():
			var ch := row[x]
			var cell := Vector2i(x, y)
			match ch:
				"D":
					_add_door(root, cell)
				"P":
					_add_plate(root, cell)
				"K":
					_add_key(root, cell)
				"X":
					_silence[cell] = true
					_add_reveal("silence", cell, float(CELL) * 1.0)
	_link_plates()

	# 门一开始是关的（改了 map，寻路/射线就都过不去）
	for cell in _doors.keys():
		_set_door_closed(cell, true)

## 建一个"要被声呐发现"的图标
func _add_reveal(id: String, cell: Vector2i, size_px: float, always: bool = false) -> Node2D:
	var icon := IconNode.IconNode.new()
	icon.icon_id = id
	icon.icon_size = size_px
	icon.position = Vector2(cell.x * CELL + CELL * 0.5, cell.y * CELL + CELL * 0.5)
	icon.visible = always
	if _overlay != null:
		_overlay.add_child(icon)
	else:
		add_child(icon)
	_reveals.append({"node": icon, "cell": cell, "seen": always})
	return icon


func _add_door(root: Node2D, cell: Vector2i) -> void:
	var body := StaticBody2D.new()
	body.position = Vector2(cell.x * CELL + CELL * 0.5, cell.y * CELL + CELL * 0.5)
	body.collision_layer = 1
	body.collision_mask = 0

	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(CELL - 4, CELL - 4)
	cs.shape = shape
	body.add_child(cs)

	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-CELL * 0.5, -CELL * 0.5), Vector2(CELL * 0.5, -CELL * 0.5),
		Vector2(CELL * 0.5, CELL * 0.5), Vector2(-CELL * 0.5, CELL * 0.5)])
	var occ := LightOccluder2D.new()
	occ.occluder = poly
	body.add_child(occ)

	var vis := _add_reveal("door", cell, float(CELL) * 0.92)

	root.add_child(body)
	_doors[cell] = {"body": body, "occ": occ, "vis": vis, "closed": true, "poly": poly}

func _add_plate(root: Node2D, cell: Vector2i) -> void:
	var vis := _add_reveal("plate", cell, float(CELL) * 0.78)
	_plates[cell] = vis

func _add_key(root: Node2D, cell: Vector2i) -> void:
	var vis := _add_reveal("key", cell, float(CELL) * 0.62)
	_keys[cell] = vis

## 每块压力板连到最近的那扇门
func _link_plates() -> void:
	for pcell in _plates.keys():
		var best := Vector2i(-1, -1)
		var best_d := 99999
		for dcell in _doors.keys():
			var dist: int = absi(dcell.x - pcell.x) + absi(dcell.y - pcell.y)
			if dist < best_d:
				best_d = dist
				best = dcell
		if best.x >= 0:
			_plate_door[pcell] = best

func _set_door_closed(cell: Vector2i, closed: bool) -> void:
	if not _doors.has(cell):
		return
	var d: Dictionary = _doors[cell]
	d["closed"] = closed
	var body: StaticBody2D = d["body"]
	body.collision_layer = 1 if closed else 0
	var occ: LightOccluder2D = d["occ"]
	if closed:
		occ.occluder = d["poly"]
	else:
		occ.occluder = null        # Godot 4 的 LightOccluder2D 没有 enabled，置空即关闭
	var vis: Node2D = d["vis"]
	if is_instance_valid(vis):
		vis.visible = closed and _is_revealed(vis)
	# 地图也跟着改：敌人寻路、BFS、射线都用它
	var row: String = map[cell.y]
	if closed:
		map[cell.y] = row.substr(0, cell.x) + "#" + row.substr(cell.x + 1)
	else:
		map[cell.y] = row.substr(0, cell.x) + "D" + row.substr(cell.x + 1)

func _collect_key(cell: Vector2i) -> void:
	if not _keys.has(cell):
		return
	var node: Node = _keys[cell]
	_keys.erase(cell)
	node.queue_free()
	var row: String = map[cell.y]
	map[cell.y] = row.substr(0, cell.x) + "." + row.substr(cell.x + 1)
	# 钥匙开了所有门
	for dcell in _doors.keys():
		_set_door_closed(dcell, false)
	Sfx.play("win")
	GameLog.note_key()

## 玩家每帧交互：踩钥匙、踩压力板
func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var player := get_node_or_null("Player")
	if player == null or not bool(player.get("_alive")):
		return                      # 死了就别再捡钥匙/踩板了
	var cell := Vector2i((player.global_position / float(CELL)).floor())
	# 碰到关着的门：从此小地图会标出钥匙位置（黑暗里否则根本不知道该往哪找）
	if not _keys_revealed:
		for dcell in _doors.keys():
			if is_door_closed(dcell) and cell.distance_to(Vector2i(dcell)) <= 1:
				_keys_revealed = true
				break

	_update_reveals(cell)
	_codex_proximity(cell)      # 先记图鉴：踩到钥匙会被立刻收走
	if _keys.has(cell):
		_collect_key(cell)
	if _frags.has(cell):
		_collect_fragment(cell)

	# 压力板：踩一次就永久开门（站着才能开的板子没法自己走过去）
	if _plates.has(cell) and cell != _active_plate:
		_active_plate = cell
		if _plate_door.has(cell):
			_set_door_closed(_plate_door[cell], false)
			GameLog.note_plate()

	for pcell in _plates.keys():
		_plates[pcell].call("set_active", pcell == _active_plate)

## 回声碎片：每关 3 枚，放在「死胡同」这种要多走两步的地方
func _spawn_fragments() -> void:
	var root := get_node_or_null("Fragments")
	if root == null:
		root = Node2D.new()
		root.name = "Fragments"
		add_child(root)
	for c in root.get_children():
		root.remove_child(c)
		c.queue_free()
	_frags.clear()

	var raw: Array = Levels.MAPS[level_index]
	var route := Maze.path(raw, START, _goal_cell)
	var on_route := {}
	for c in route:
		on_route[c] = true
	# 能走到的格子（门当作可通行：钥匙会把门打开）
	var reach: Dictionary = Maze.distances(raw, START)

	var cands: Array = []
	for y in raw.size():
		var row: String = raw[y]
		for x in row.length():
			if row[x] != ".":
				continue
			var c := Vector2i(x, y)
			if on_route.has(c) or c == START or c == _goal_cell:
				continue
			if not reach.has(c):
				continue
			if _silence.has(c):
				continue
			# 死胡同：只有一个可走邻居
			var deg := 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if Maze.is_open(raw, c + d):
					deg += 1
			if deg == 1:
				cands.append(c)

	# 没有死胡同就退一步：任何不在路线上的空地（避开机关/箱子）都能放
	if cands.size() < 3:
		for y in raw.size():
			var row2: String = raw[y]
			for x in row2.length():
				if row2[x] != ".":
					continue
				var c2 := Vector2i(x, y)
				if on_route.has(c2) or c2 == START or c2 == _goal_cell or _silence.has(c2):
					continue
				if _crates.has(c2) or _keys.has(c2) or _plates.has(c2) or _doors.has(c2):
					continue
				if not cands.has(c2):
					cands.append(c2)
	cands.sort_custom(func(a, b): return (a.x + a.y * 1000) < (b.x + b.y * 1000))
	# 每关总共只有 3 枚：已经拿过的也算，不能再刷新的
	var want := maxi(0, 3 - Progress.fragments_taken(level_index))
	var placed := 0
	for c in cands:
		if placed >= want:
			break
		var key := "%d,%d" % [c.x, c.y]
		if Progress.is_fragment_taken(level_index, key):
			continue            # 这个存档已经拿过，不再生成
		_add_fragment(root, c, key)
		placed += 1

func _add_fragment(root: Node2D, cell: Vector2i, key: String) -> void:
	var node := _add_reveal("fragment", cell, float(CELL) * 0.60)
	node.set_meta("key", key)
	_frags[cell] = node

func fragment_cells() -> Array:
	return _frags.keys()

## 本关碎片：场上还剩几个 / 一共 3 个（已经拿走的也算在总数里）
func fragment_total() -> int:
	return 3

func fragments_taken_here() -> int:
	return Progress.fragments_taken(level_index)

func _collect_fragment(cell: Vector2i) -> void:
	if not _frags.has(cell):
		return
	var node: Node = _frags[cell]
	var key := String(node.get_meta("key", ""))
	_frags.erase(cell)
	node.queue_free()
	Progress.take_fragment(level_index, key)
	GameLog.note_fragment()
	Sfx.play("frag")


## 第一次靠近某样东西就把它记进图鉴（HUD 会弹一条提示）
func _codex_proximity(cell: Vector2i) -> void:
	var codex := get_node_or_null("/root/Codex")
	if codex == null:
		return
	if _near_any(cell, _doors.keys(), 3):
		codex.call("unlock", "door")
	if _near_any(cell, _keys.keys(), 3):
		codex.call("unlock", "key")
	if _near_any(cell, _plates.keys(), 3):
		codex.call("unlock", "plate")
	if _near_any(cell, _silence.keys(), 1):
		codex.call("unlock", "silence")
	if _near_any(cell, _crates.keys(), 3):
		codex.call("unlock", "crate")
	if _near_any(cell, _frags.keys(), 3):
		codex.call("unlock", "fragment")

	var box := get_node_or_null("Enemies")
	if box != null:
		for e in box.get_children():
			var ec := Vector2i((e.global_position / float(CELL)).floor())
			if cell.distance_to(ec) > 10:
				continue
			match int(e.get("kind")):
				1:
					codex.call("unlock", "enemy_blind")
				2:
					codex.call("unlock", "enemy_sharp")
				_:
					codex.call("unlock", "enemy_normal")

func _near_any(cell: Vector2i, cells: Array, radius: int) -> bool:
	for c in cells:
		if cell.distance_to(Vector2i(c)) <= radius:
			return true
	return false


## 声呐波扫过，或玩家走到两步内，就把图标显出来（之后一直留着 = 记住了）
func _update_reveals(player_cell: Vector2i) -> void:
	var r := -1.0
	var org := Vector2.ZERO
	if _wave != null and _wave.has_method("is_active") and _wave.is_active():
		r = _wave.current_radius()
		org = _wave.origin()
	var pc := Vector2(player_cell.x * CELL + CELL * 0.5, player_cell.y * CELL + CELL * 0.5)
	for item in _reveals:
		if item["seen"]:
			continue
		var node: Node2D = item["node"]
		if not is_instance_valid(node):
			continue
		var cell: Vector2i = item["cell"]
		var wpos := Vector2(cell.x * CELL + CELL * 0.5, cell.y * CELL + CELL * 0.5)
		var by_wave := r >= 0.0 and org.distance_to(wpos) <= r + CELL * 0.6
		var by_player := pc.distance_to(wpos) <= CELL * 2.2
		if by_wave or by_player:
			item["seen"] = true
			node.visible = true
			node.modulate.a = 1.0


func _is_revealed(node: Node2D) -> bool:
	for item in _reveals:
		if item["node"] == node:
			return bool(item["seen"])
	return false


func is_silent_at(pos: Vector2) -> bool:
	return _silence.has(Vector2i((pos / float(CELL)).floor()))

func keys_revealed() -> bool:
	return _keys_revealed


func door_cells() -> Array:
	return _doors.keys()

func plate_cells() -> Array:
	return _plates.keys()

func key_cells() -> Array:
	return _keys.keys()

func silence_cells() -> Array:
	return _silence.keys()

func is_door_closed(cell: Vector2i) -> bool:
	return _doors.has(cell) and bool(_doors[cell]["closed"])


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

	# 门关着时 map 里是 '#'，用它算不出路线（敌人一个都不会生成）；
	# 布点按「门开着」的原始地图算，落点再用当前状态校验。
	var raw: Array = Levels.MAPS[level_index]
	var route := Maze.path(raw, START, _goal_cell)
	_enemy_cells.clear()
	# 第一关之后敌人会变多，但都不能贴着起点埋伏：
	# 锚点至少离起点 22 步（第 2 关 30 步），并且相邻锚点至少错开 6 步
	var min_idx := 30 if level_index == 1 else 22
	var prev_idx := -999
	for frac in ENEMY_ROUTE_FRACS:
		if _enemy_cells.size() >= _enemy_target() or route.is_empty():
			break
		var idx := clampi(int(round(float(route.size()) * float(frac))), 0, route.size() - 1)
		idx = maxi(idx, min_idx)
		if idx <= prev_idx:
			idx = prev_idx + 6
		idx = mini(idx, route.size() - 1)
		prev_idx = idx
		var anchor: Vector2i = route[idx]
		# 半径 3 内找候选：优先「不在最短路上」的格子（不挡唯一通道），再按距离取近的。
		# 之前只看四邻，锚点四周全是路线时只能退回锚点，导致敌人正好堵在路上。
		# 敌人多了以后 10 格间隔常常放不下：依次放宽到 6 / 4，避免全挤在锚点上
		var sep := ENEMY_SEP
		if _enemy_target() >= 5:
			sep = 7
		if _enemy_target() >= 6:
			sep = 5
		var best := Vector2i(-1, -1)
		for radius in [3, 5, 7]:
			for try_sep in [sep, 7, 5]:
				var cands: Array = []
				for dy in range(-radius, radius + 1):
					for dx in range(-radius, radius + 1):
						if dx == 0 and dy == 0:
							continue
						var cell: Vector2i = anchor + Vector2i(dx, dy)
						if cell == _goal_cell or cell == START or not Maze.is_open(raw, cell) \
								or not Maze.is_open(map, cell):
							continue
						var ok := true
						for other in _enemy_cells:
							if Vector2i(other).distance_to(cell) < try_sep:
								ok = false
								break
						if not ok:
							continue
						cands.append({"cell": cell, "d": absi(dx) + absi(dy), "on_route": route.has(cell)})
				cands.sort_custom(func(a, b):
					if bool(a["on_route"]) != bool(b["on_route"]):
						return not bool(a["on_route"])
					return int(a["d"]) < int(b["d"]))
				if not cands.is_empty():
					best = cands[0]["cell"]
					break
			if best.x >= 0:
				break
		# 最后一招：整张图里挑一个离现有敌人最远、能站人的格子
		if best.x < 0:
			var far_cell := Vector2i(-1, -1)
			var far_d := -1
			for y2 in raw.size():
				var row3: String = raw[y2]
				for x2 in row3.length():
					var c4 := Vector2i(x2, y2)
					if c4 == START or c4 == _goal_cell or not Maze.is_open(map, c4):
						continue
					var mind := 9999
					for other in _enemy_cells:
						mind = mini(mind, int(Vector2i(other).distance_to(c4)))
					if _enemy_cells.is_empty():
						mind = 0
					if mind > far_d:
						far_d = mind
						far_cell = c4
			if far_cell.x >= 0 and far_d >= 4:
				best = far_cell
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

	var route := Maze.path(Levels.MAPS[level_index], START, _goal_cell)
	if route.is_empty():
		return
	var want := 2 if level_index < 3 else 3
	for frac in [0.28, 0.48, 0.68]:
		if _crates.size() >= want:
			break
		var idx := clampi(int(round(float(route.size()) * float(frac))), 0, route.size() - 1)
		var cell: Vector2i = route[idx]
		if _crates.has(cell) or not Maze.is_open(map, cell) or _cell_reserved(cell):
			continue
		# 敌人站在那就别放箱子
		var enemy_there := false
		var box := get_node_or_null("Enemies")
		if box != null:
			for e in box.get_children():
				if Vector2i((e.global_position / float(CELL)).floor()) == cell:
					enemy_there = true
					break
		if enemy_there:
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


## 这一格有没有「不能被箱子盖住」的东西
func _cell_reserved(cell: Vector2i) -> bool:
	if cell == _goal_cell or cell == START:
		return true
	if _keys.has(cell) or _frags.has(cell) or _plates.has(cell) or _doors.has(cell) or _silence.has(cell):
		return true
	return false


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

	var vis := _add_reveal("crate", cell, float(CELL) * 0.9)

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
	if _crates.has(to) or not Maze.is_open(map, to) or _cell_reserved(to):
		return false
	var body: Node2D = _crates[cell]
	_crates.erase(cell)
	body.position = Vector2(to.x * CELL + CELL * 0.5, to.y * CELL + CELL * 0.5)
	_crates[to] = body
	return true


## 跑 tools/ 下的自检时也当测试模式：不发词条、不暂停
func _is_tool_run() -> bool:
	for a in OS.get_cmdline_args():
		if a == "--test" or a.contains("res://tools/"):
			return true
	return false


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

## 进关时：黑场淡入 + 居中的关卡标题（只在跑游戏时，编辑器里不建）
func _show_intro_card() -> void:
	if Engine.is_editor_hint():
		return
		# 这一关要先选词条时不放标题卡：否则卡和词条面板会叠在一起
	if Mods.pending:
		return
	var old := get_node_or_null("IntroCard")
	if old != null:
		remove_child(old)
		old.queue_free()

	var layer := CanvasLayer.new()
	layer.name = "IntroCard"
	layer.layer = 90
	add_child(layer)

	var black := ColorRect.new()
	black.color = Color(0.012, 0.016, 0.026, 1.0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(black)

	var title := Label.new()
	title.text = "第 %d 关" % (level_index + 1)
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(0.88, 0.95, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.offset_top = -150
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(title)

	var sub := Label.new()
	sub.text = "%d × %d    %s" % [String(Levels.MAPS[level_index][0]).length(),
		Levels.MAPS[level_index].size(), _intro_hint()]
	sub.add_theme_font_size_override("font_size", 17)
	sub.add_theme_color_override("font_color", Color(0.60, 0.72, 0.86))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_FULL_RECT)
	sub.offset_top = -86
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(sub)

	# 淡入：黑场 0.45 秒化开，标题停 1.4 秒再淡出
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)   # 选词条会暂停游戏，标题仍要淡出
	t.set_parallel(false)
	t.tween_property(black, "color:a", 0.0, 0.45)
	t.tween_interval(1.15)
	t.tween_property(title, "modulate:a", 0.0, 0.45)
	t.parallel().tween_property(sub, "modulate:a", 0.0, 0.45)
	t.tween_callback(func() -> void:
		if is_instance_valid(layer):
			layer.queue_free())


## 标题卡第二行：这一关有什么
func _intro_hint() -> String:
	var raw: Array = Levels.MAPS[level_index]
	var body := "".join(raw)
	var bits: Array = []
	var n := 0
	if ENEMY_BY_LEVEL.size() > level_index:
		n = int(ENEMY_BY_LEVEL[level_index])
	if n > 0:
		bits.append("敌人 %d" % n)
	if body.count("K") > 0:
		bits.append("钥匙")
	if body.count("P") > 0:
		bits.append("压力板")
	if body.count("X") > 0:
		bits.append("静音区")
	if n == 0:
		bits.append("没有敌人 · 先熟悉回声")
	return "   ".join(bits)


func _add_ground(width: int, height: int) -> void:
	var size := Vector2(width * CELL, height * CELL)

	# 纯色地板：本身很暗，只有被光照到才会显出来
	var floor_poly := Polygon2D.new()
	floor_poly.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y)
	])
	floor_poly.color = Color(0.14, 0.15, 0.19)
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
	vis.color = Color(0.55, 0.60, 0.70)
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

	var vis := _add_reveal("goal", Vector2i(cx, cy), float(CELL) * 0.9)

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
