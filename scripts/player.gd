extends CharacterBody2D
## 玩家：移动 + 发声呐 + 通关判定。

const LightFactory = preload("res://scripts/light_factory.gd")

const SPEED := 235.0
const SONAR_COOLDOWN := 1.8     # ← 报告里的核心实验变量
const STRONG_COOLDOWN := 6.0    # 强声呐：范围大、惊动全场，所以冷却长得多

# 常亮光圈：只要"看得见边界的一小圈"，看不见下一个格子。
# 第 5 周试玩反馈：太亮 → 压到 0.015 的 CanvasModulate；随后要求"周围一圈要可见"，
# 所以光圈改成环状贴图（中心留暗、半径处最亮），仍然很小。
const AMBIENT_RADIUS := 56
const AMBIENT_ENERGY := 0.75

@onready var sonar := $Sonar
@onready var ambient: PointLight2D = $AmbientLight

var _cd := 0.0
var _cd_strong := 0.0
var _alive := true

func _ready() -> void:
	add_to_group("player")
	ambient.texture = LightFactory.ring_texture(AMBIENT_RADIUS * 2, 0.45, 0.82)
	ambient.energy = AMBIENT_ENERGY * Settings.light_mul()
	ambient.texture_scale = 1.0
	sonar.setup(LightFactory.radial_texture(256))
	GameLog.start_session()
	GameLog.set_config({
		"sonar_cooldown": SONAR_COOLDOWN,
		"ambient_radius": AMBIENT_RADIUS,
		"ambient_energy": AMBIENT_ENERGY,
	})
	queue_redraw()

## 重开/换关：复位状态、重置这一局的遥测
func reset_state(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	_alive = true
	_cd = 0.0
	_cd_strong = 0.0
	# 设置里改了亮度，重开时要重新套到光圈上
	ambient.energy = AMBIENT_ENERGY * Settings.light_mul()
	GameLog.start_session()
	GameLog.set_config({
		"sonar_cooldown": SONAR_COOLDOWN,
		"ambient_radius": AMBIENT_RADIUS,
		"ambient_energy": AMBIENT_ENERGY,
	})


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		var lv := get_parent()
		if lv != null and lv.has_method("restart"):
			lv.restart()
			return
		return
	if not _alive:
		return

	# 选词条时先别动
	if Mods.pending:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir != Vector2.ZERO:
		_try_push(dir)
	velocity = dir * SPEED * Mods.speed_mul()
	move_and_slide()

	_cd = maxf(0.0, _cd - delta)
	if Input.is_action_just_pressed("sonar") and _cd <= 0.0:
		_cd = SONAR_COOLDOWN * Mods.sonar_mul()
		sonar.emit()
		Sfx.ping()
		var level := get_parent()
		if level != null and level.has_method("emit_wave"):
			level.emit_wave(global_position)
		GameLog.note_sonar()

	# 强声呐（E）：范围大、多一跳，全场敌人不管多远都听见 —— 独立的 6 秒冷却
	_cd_strong = maxf(0.0, _cd_strong - delta)
	if Input.is_action_just_pressed("strong_sonar") and _cd_strong <= 0.0:
		_cd_strong = STRONG_COOLDOWN * Mods.strong_mul()
		sonar.emit()
		Sfx.strong()
		var lv := get_parent()
		if lv != null and lv.has_method("emit_wave"):
			lv.emit_wave(global_position, true)
		GameLog.note_sonar()

	GameLog.note_position(global_position)

func strong_cooldown() -> float:
	return STRONG_COOLDOWN

## 给 HUD 用：两个冷却的剩余比例（0 = 好了，1 = 刚按完）
func cooldown_ratios() -> Vector2:
	var c1 := maxf(SONAR_COOLDOWN * Mods.sonar_mul(), 0.01)
	var c2 := maxf(STRONG_COOLDOWN * Mods.strong_mul(), 0.01)
	return Vector2(_cd / c1, _cd_strong / c2)


## 朝移动方向撞到箱子就推一格；推不动就停住（不然会一直顶着箱子抖）
func _try_push(dir: Vector2) -> void:
	var lvl := get_parent()
	if lvl == null or not lvl.has_method("has_crate"):
		return
	var probe: Vector2 = global_position + dir.normalized() * 44.0
	var cell := Vector2i((probe / 64.0).floor())
	if not lvl.has_crate(cell):
		return
	var dcell := Vector2i.ZERO
	if absf(dir.x) >= absf(dir.y):
		dcell = Vector2i(signi(int(round(dir.x))), 0)
	else:
		dcell = Vector2i(0, signi(int(round(dir.y))))
	lvl.push_crate(cell, dcell)

func _draw() -> void:
	draw_circle(Vector2.ZERO, 9.0, Color(0.88, 0.96, 1.0))
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 24, Color(0.6, 0.8, 1.0, 0.55), 1.5, true)

func win() -> void:
	if not _alive:
		return
	_alive = false
	velocity = Vector2.ZERO
	Sfx.win()
	GameLog.end_session("win")
	var rec: Dictionary = GameLog.last_run()
	if not Session.is_test():
		Progress.record_clear(Progress.level_index, float(rec.get("duration_s", 0.0)),
			String(rec.get("grade", "-")))
	# 先让结算面板停一会儿，再进下一关；最后一关就停在这里。
	await get_tree().create_timer(2.0).timeout
	if not is_inside_tree():
		return
	var lv := get_parent()
	if Progress.advance() and lv != null and lv.has_method("restart"):
		lv.restart()

## 被敌人碰到：和通关共用同一套结算，只是 reason 不同。
## 顺序不能反：先停再记，否则最后一帧还会移动。
func caught() -> void:
	if not _alive:
		return
	_alive = false
	velocity = Vector2.ZERO
	Sfx.caught()
	GameLog.end_session("caught")
