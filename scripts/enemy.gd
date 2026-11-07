extends CharacterBody2D
## 会听见声呐的敌人。
##
## 规则（见 docs/bible/03_rules.md）：
##   1. 玩家发声呐时，关卡把声源位置广播给所有敌人；
##   2. 声源在 HEAR_RADIUS 内 → 追过去，最多追 CHASE_TIME 秒；
##   3. 碰到玩家（CATCH_RADIUS 内）→ Player.caught()。
##
## 听觉穿墙：声音会绕过拐角，所以不做视线判定 —— 这也是"发声有代价"的来源。
## 寻路用 MAP 上的格子 BFS（scripts/maze.gd），不用 Navigation 烘焙。
##
## 视觉：本体是 CanvasItem，被光照到才显眼；另外挂一盏很弱的红光，
## 让玩家在 2 格内能提前察觉（不然完全不可见会变成"无故死亡"）。

const Maze = preload("res://scripts/maze.gd")
const LightFactory = preload("res://scripts/light_factory.gd")

const HEAR_RADIUS := 700.0      # px，约 11 格
const SPEED := 110.0            # px/s，玩家 235，跑得掉
const CHASE_TIME := 4.0         # 听到后追多久
const REPATH := 0.4             # 每多久重算一次格子路径
const CATCH_RADIUS := 20.0
const LIGHT_ENERGY := 0.32
const LIGHT_RADIUS := 192

var _rows: Array = []
var _cell_px := 64.0
var _home := Vector2i.ZERO
var _target := Vector2i.ZERO
var _has_target := false
var _chase_left := 0.0
var _repath := 0.0
var _path: Array = []
var _player: Node2D = null
var _glow: PointLight2D = null
var _pulse := 0.0

func _ready() -> void:
	add_to_group("enemies")
	_player = get_tree().get_first_node_in_group("player")
	var glow := PointLight2D.new()
	glow.name = "Glow"
	glow.texture = LightFactory.radial_texture(64)
	glow.color = Color(1.0, 0.35, 0.30)
	glow.energy = LIGHT_ENERGY
	glow.texture_scale = float(LIGHT_RADIUS * 2) / 64.0
	glow.shadow_enabled = true
	add_child(glow)
	_glow = glow
	queue_redraw()

## 呼吸式微光：静止时慢慢起伏，追击时整体变亮 1.6 倍。
## 暗处只靠本体（CanvasItem）是看不见的，这盏灯才是玩家发现敌人的线索。
func _process(delta: float) -> void:
	if _glow == null:
		return
	_pulse += delta
	var boost := 1.6 if _has_target else 1.0
	_glow.energy = maxf(0.0, LIGHT_ENERGY * boost + 0.03 * sin(_pulse * 2.0))

func setup(rows: Array, cell_px: float, home: Vector2i) -> void:
	_rows = rows
	_cell_px = cell_px
	_home = home
	global_position = cell_center(home)

func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * _cell_px + _cell_px * 0.5, c.y * _cell_px + _cell_px * 0.5)

func cell_of(p: Vector2) -> Vector2i:
	return Vector2i((p / _cell_px).floor())

## 声呐到达：在听觉半径内就把声源记为新的追击目标。返回「有没有听见」。
func hear(world_pos: Vector2) -> bool:
	if global_position.distance_to(world_pos) > HEAR_RADIUS:
		return false
	var target := cell_of(world_pos)
	if not Maze.is_open(_rows, target):
		return false
	_target = target
	_has_target = true
	_chase_left = CHASE_TIME
	_repath = 0.0
	queue_redraw()
	return true

func is_chasing() -> bool:
	return _has_target

func _physics_process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	if _has_target:
		_chase_left -= delta
		if _chase_left <= 0.0:
			_has_target = false
			_path.clear()
			queue_redraw()
	_repath -= delta
	if _has_target and _repath <= 0.0:
		_repath = REPATH
		_path = Maze.path(_rows, cell_of(global_position), _target)
	_move_along_path()
	_check_catch()

## 沿格子中心逐点走；到点就弹掉，路径空了就停下。
func _move_along_path() -> void:
	while not _path.is_empty():
		var wp: Vector2 = cell_center(_path[0])
		if global_position.distance_to(wp) > 6.0:
			break
		_path.pop_front()
	if _path.is_empty():
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var next_wp: Vector2 = cell_center(_path[0])
	velocity = (next_wp - global_position).normalized() * SPEED
	move_and_slide()

func _check_catch() -> void:
	if _player == null:
		return
	if global_position.distance_to(_player.global_position) > CATCH_RADIUS:
		return
	if _player.has_method("caught"):
		_player.caught()
		_has_target = false
		_path.clear()

func _draw() -> void:
	var ring := Color(0.95, 0.35, 0.30, 0.9) if _has_target else Color(0.70, 0.22, 0.20, 0.7)
	draw_circle(Vector2.ZERO, 11.0, Color(0.22, 0.05, 0.05, 0.9))
	draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 24, ring, 2.0, true)
