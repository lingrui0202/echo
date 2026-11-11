extends CharacterBody2D
## 会听见声呐的敌人。
##
## 规则（见 docs/bible/03_rules.md）：
##   1. 玩家发声呐时，关卡把声源位置广播给所有敌人；
##   2. 声源在 HEAR_RADIUS 内 → 追过去，最多追 CHASE_TIME 秒；
##   3. 碰到玩家（CATCH_RADIUS 内）→ Player.caught()。
##   4. **强声呐**会惊动全场（`hear_any`），不管距离。
##
## 平时在出生点附近巡逻：每隔 PATROL_PERIOD 秒挑一个附近的空地走过去。
## 追完 CHASE_TIME 没抓到人就「忘掉」，回到巡逻 —— 这样玩家才有机会甩掉它。
##
## 听觉穿墙：声音会绕过拐角，所以不做视线判定 —— 这也是"发声有代价"的来源。
## 寻路用 MAP 上的格子 BFS（scripts/maze.gd），不用 Navigation 烘焙。

const Maze = preload("res://scripts/maze.gd")
const LightFactory = preload("res://scripts/light_factory.gd")

const HEAR_RADIUS := 700.0      # px，约 11 格
const SPEED := 168.0            # px/s：玩家 235，直线跑得掉，但拐弯会被抄近路
const CHASE_TIME := 5.5         # 听到后追多久
const REPATH := 0.25            # 每多久重算一次路径（同时刷新目标位置）
const CATCH_RADIUS := 38.0   # 比两个碰撞体的实际停距大：不然追到贴身也判不到「抓到」
const LOSE_RADIUS := 900.0      # 超出这个距离且持续 LOSE_TIME 秒就放弃
const LOSE_TIME := 1.5
const LIGHT_ENERGY := 0.32
const LIGHT_RADIUS := 192

## 三种类型：0 普通、1 瞎子（只被强声呐惊动）、2 敏锐（听觉更远，但慢一点、追得久）
const KIND_NORMAL := 0
const KIND_BLIND := 1
const KIND_SHARP := 2
const KIND_NAMES := ["普通", "瞎子", "敏锐"]

const PATROL_SPEED := 58.0      # 巡逻比追击慢，玩家能听出来它是不是在追
const PATROL_PERIOD := 4.0      # 每隔多久挑一个新点
const PATROL_RADIUS := 7        # 在出生点附近几格里晃

var kind := KIND_NORMAL
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

var _lost := 0.0
var _patrol_left := 1.0
var _patrol_path: Array = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("enemies")
	_player = get_tree().get_first_node_in_group("player")
	_rng.randomize()
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

func setup(rows: Array, cell_px: float, home: Vector2i, enemy_kind: int = KIND_NORMAL) -> void:
	_rows = rows
	_cell_px = cell_px
	_home = home
	kind = enemy_kind
	global_position = cell_center(home)

## 当前听觉半径（词条会改，类型也会改）
func hear_radius() -> float:
	var r := HEAR_RADIUS * Mods.enemy_hear_mul()
	if kind == KIND_SHARP:
		r *= 1.35
	return r

func move_speed() -> float:
	var v := SPEED * Mods.enemy_speed_mul()
	if kind == KIND_BLIND:
		v *= 1.15      # 瞎子平时慢，一旦被强声呐惊动就冲得很快
	elif kind == KIND_SHARP:
		v *= 0.92
	return v

func chase_seconds() -> float:
	return CHASE_TIME + (1.5 if kind == KIND_SHARP else 0.0)

func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * _cell_px + _cell_px * 0.5, c.y * _cell_px + _cell_px * 0.5)

func cell_of(p: Vector2) -> Vector2i:
	return Vector2i((p / _cell_px).floor())

## 声呐到达：在听觉半径内就把声源记为新的追击目标。返回「有没有听见」。
func hear(world_pos: Vector2) -> bool:
	if kind == KIND_BLIND:
		return false        # 瞎子听不见普通声呐，只有强声呐能惊动它
	if global_position.distance_to(world_pos) > hear_radius():
		return false
	return _start_chase(world_pos)

## 强声呐：不管多远都听得见。
func hear_any(world_pos: Vector2) -> bool:
	return _start_chase(world_pos)

func _start_chase(world_pos: Vector2) -> bool:
	var target := cell_of(world_pos)
	if not Maze.is_open(_rows, target):
		return false
	_target = target
	_has_target = true
	_chase_left = chase_seconds()
	_repath = 0.0
	_lost = 0.0
	_patrol_path.clear()
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
			# 追丢了：忘掉声源，继续巡逻
			_has_target = false
			_path.clear()
			_patrol_left = 0.0
			queue_redraw()
		# 追的是「实时位置」，不是发声那一刻的旧坐标：
		# 以前 _target 只在 hear() 里写一次，玩家一走它就到旧点干站着。
		if _player != null and is_instance_valid(_player):
			var pc := cell_of(_player.global_position)
			if Maze.is_open(_rows, pc):
				_target = pc
			if global_position.distance_to(_player.global_position) > LOSE_RADIUS:
				_lost += delta
				if _lost > LOSE_TIME:
					_has_target = false
					_path.clear()
					_lost = 0.0
					queue_redraw()
			else:
				_lost = 0.0

		_repath -= delta
		if _repath <= 0.0:
			_repath = REPATH
			_path = Maze.path(_rows, cell_of(global_position), _target)
		_move_along(_path, move_speed())
	else:
		_patrol(delta)

	_check_catch()

## 巡逻：每隔一段时间在出生点附近挑一个空地走过去，走到就停。
func _patrol(delta: float) -> void:
	_patrol_left -= delta
	if _patrol_left <= 0.0:
		_patrol_left = PATROL_PERIOD
		var here := cell_of(global_position)
		for _try in 8:
			var dx := _rng.randi_range(-PATROL_RADIUS, PATROL_RADIUS)
			var dy := _rng.randi_range(-PATROL_RADIUS, PATROL_RADIUS)
			var c := _home + Vector2i(dx, dy)
			if not Maze.is_open(_rows, c) or c == here:
				continue
			_patrol_path = Maze.path(_rows, here, c)
			break
	_move_along(_patrol_path, PATROL_SPEED)

## 沿格子中心逐点走；到点就弹掉，路径空了就停下。
func _move_along(path: Array, speed: float) -> void:
	while not path.is_empty():
		var wp: Vector2 = cell_center(path[0])
		if global_position.distance_to(wp) > 6.0:
			break
		path.pop_front()
	if path.is_empty():
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var next_wp: Vector2 = cell_center(path[0])
	velocity = (next_wp - global_position).normalized() * speed
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
	var base := Color(0.70, 0.22, 0.20, 0.7)
	var hot := Color(0.95, 0.35, 0.30, 0.9)
	if kind == KIND_BLIND:
		base = Color(0.55, 0.35, 0.85, 0.7)
		hot = Color(0.78, 0.50, 1.0, 0.95)
	elif kind == KIND_SHARP:
		base = Color(0.85, 0.55, 0.15, 0.75)
		hot = Color(1.0, 0.75, 0.25, 0.95)
	var ring := hot if _has_target else base
	draw_circle(Vector2.ZERO, 11.0, Color(0.22, 0.05, 0.05, 0.9))
	draw_arc(Vector2.ZERO, 13.0, 0.0, TAU, 24, ring, 2.0, true)
