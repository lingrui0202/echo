extends CharacterBody2D
## 玩家：移动 + 发声呐 + 通关判定。

const LightFactory = preload("res://scripts/light_factory.gd")

const SPEED := 235.0
const SONAR_COOLDOWN := 1.2     # ← 报告里的核心实验变量

@onready var sonar := $Sonar
@onready var ambient: PointLight2D = $AmbientLight

var _cd := 0.0
var _alive := true

func _ready() -> void:
	# 很小的常亮光圈：没有它，全黑画面会让人 10 秒内放弃
	ambient.texture = LightFactory.radial_texture(128)
	sonar.setup(LightFactory.radial_texture(256))
	GameLog.start_session()
	queue_redraw()

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("restart"):
		get_tree().reload_current_scene()
		return
	if not _alive:
		return

	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED
	move_and_slide()

	_cd = maxf(0.0, _cd - delta)
	if Input.is_action_just_pressed("sonar") and _cd <= 0.0:
		_cd = SONAR_COOLDOWN
		sonar.emit()
		GameLog.note_sonar()

	GameLog.note_position(global_position)

func _draw() -> void:
	draw_circle(Vector2.ZERO, 9.0, Color(0.88, 0.96, 1.0))
	draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 24, Color(0.6, 0.8, 1.0, 0.55), 1.5, true)

func win() -> void:
	if not _alive:
		return
	_alive = false
	velocity = Vector2.ZERO
	GameLog.end_session("win")
