extends SceneTree
## 冒烟测试（不是游戏的一部分）：验证移动、墙体碰撞、声呐冷却三条最小链路。
## 用法：
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <项目目录> --script res://tools/smoke.gd
##
## 判据（全部满足才算 PASS）：
##   1. 按住右键 1 秒，位移接近 SPEED（235 px/s）的量级，且方向正确
##   2. 贴着墙往墙里按 1 秒，玩家 x 不会穿过墙面
##   3. 第一次按空格 sonar_count = 1；1.2 s 冷却内再按仍是 1；冷却结束后再按变 2
##
## 注意：headless 下渲染帧远多于物理帧，所以这里一律用真实时间（msec）卡点，
## 不能用帧数 —— 用帧数会得到"走得太慢"的假失败。

const CELL := 64
const SPEED := 235.0
const COOLDOWN_MS := 1200
const WALL_X := 4.0            # level.gd 第 2 行 "....##" 的墙左边缘
const WALL_ROW_Y := 2.5        # 第 2 行格子中心

var _t0 := 0
var _done: Array[String] = []
var _fails: Array[String] = []
var _player: Node2D = null
var _start_x := 0.0
var _move_from := 0
var _release_action: StringName = &""

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	root.add_child(ps.instantiate())
	_t0 = Time.get_ticks_msec()

func _ms() -> int:
	return Time.get_ticks_msec() - _t0

func _at(ms: int, tag: String) -> bool:
	# 每个时间点只返回一次 true
	if _ms() >= ms and not _done.has(tag):
		_done.append(tag)
		return true
	return false

func _gl_count() -> int:
	var gl := root.get_node_or_null("GameLog")
	if gl == null:
		return -1
	return int(gl.get("sonar_count"))

func _process(_delta: float) -> bool:
	# 上一拍按下的动作在这一拍松开，保证物理帧能看到一次完整的"按下"
	if _release_action != &"":
		Input.action_release(_release_action)
		_release_action = &""

	if _at(100, "find"):
		_player = root.get_node_or_null("Level01/Player")
		if _player == null:
			print("FAIL: 找不到 Player，关卡没建起来")
			return true
		_start_x = _player.global_position.x
		_move_from = _ms()

	if _at(150, "press_right"):
		Input.action_press("move_right")

	if _at(1150, "check_move"):
		Input.action_release("move_right")
		var dt := float(_ms() - _move_from) / 1000.0
		var dx := _player.global_position.x - _start_x
		var expect := SPEED * dt
		if dx < expect * 0.6:
			_fails.append("移动 %.1f px / %.2f s，期望约 %.0f px" % [dx, dt, expect])
		print("OK  移动：%.1f s 右移 %.1f px（理论 %.0f px，速度 %d px/s）" % [dt, dx, expect, int(SPEED)])

	if _at(1200, "place_wall"):
		_player.global_position = Vector2(WALL_X * CELL - 20.0, WALL_ROW_Y * CELL)

	if _at(1250, "press_wall"):
		Input.action_press("move_right")

	if _at(2250, "check_wall"):
		Input.action_release("move_right")
		if _player.global_position.x > WALL_X * CELL - 8.0:
			_fails.append("玩家穿墙了：x = %.1f，墙面在 %.1f" % [_player.global_position.x, WALL_X * CELL])
		print("OK  碰撞：顶墙 1 s 后 x = %.1f，墙面 %.1f，没穿过去" % [_player.global_position.x, WALL_X * CELL])

	if _at(2300, "tap1"):
		Input.action_press("sonar")
		_release_action = &"sonar"

	if _at(2450, "check_tap1"):
		if _gl_count() != 1:
			_fails.append("第一次发声呐后 sonar_count = %d（应为 1）" % _gl_count())

	if _at(2600, "tap2_in_cooldown"):
		Input.action_press("sonar")
		_release_action = &"sonar"

	if _at(2750, "check_tap2"):
		if _gl_count() != 1:
			_fails.append("冷却内重复触发：sonar_count = %d（应仍为 1）" % _gl_count())

	if _at(2300 + COOLDOWN_MS + 300, "tap3_after_cooldown"):
		Input.action_press("sonar")
		_release_action = &"sonar"

	if _at(2300 + COOLDOWN_MS + 500, "check_tap3"):
		if _gl_count() != 2:
			_fails.append("冷却结束后没恢复：sonar_count = %d（应为 2）" % _gl_count())
		print("OK  冷却：1 -> 冷却内仍 1 -> 冷却后 2")

	if _ms() > 2300 + COOLDOWN_MS + 800:
		if _fails.is_empty():
			print("PASS: 移动 / 碰撞 / 声呐冷却 三条链路均正常")
		else:
			for msg in _fails:
				print("FAIL: ", msg)
		return true
	return false
