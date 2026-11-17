extends Node
## 新手引导：只在「新存档的第 1 关」跑一遍，按玩家的行为推进，不靠计时。
##
## 步骤：
##   0 开场卡（讲这是什麼游戏）—— 任意移动键或空格消失
##   1 走两步 —— 提示 WASD
##   2 发出第一声 —— 提示空格
##   3 看回声 —— 说明波会反射、墙面会留痕
##   4 找出口 —— 说明绿色菱形
##   5 结束

const STEPS := {
	0: "你什么都看不见。\n\n目标：找到绿色出口。\n\n按 空格 发出一声回声，波碰到墙会折回来 —— 那就是你的眼睛。\n\n但声音也会被别的东西听见。",
	1: "W A S D 移动。\n\n先走两步试试。",
	2: "按 空格 发声呐。\n\n光圈向外扩，撞到墙就画出一道边。",
	3: "这就是回声。\n\n墙越近越亮；撞过的墙会留一会儿淡蓝色。\n远处的东西，只能靠再发一声。",
	4: "绿色菱形是出口。\n\n走过去就通关。走错了按 R 重开。",
}

var active := false
var step := 5
var _t := 0.0
var _start_cell := Vector2i(-99, -99)
var _moved := 0

func begin(new_game: bool) -> void:
	active = true
	step = 0 if new_game else 1
	_t = 0.0
	_moved = 0
	_start_cell = Vector2i(-99, -99)

func stop() -> void:
	active = false
	step = 5

func current_text() -> String:
	if not active or step >= 5:
		return ""
	return String(STEPS.get(step, ""))

func tick(delta: float, player: Node, level: Node) -> void:
	if not active or step >= 5:
		return
	_t += delta

	if _start_cell.x < 0 and player != null:
		_start_cell = Vector2i((player.global_position / 64.0).floor())

	match step:
		0:
			# 0.6 秒防误触，之后任意移动/发声都算"看过了"
			if _t > 0.6:
				var moved := Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right") \
					or Input.is_action_pressed("move_up") or Input.is_action_pressed("move_down")
				if moved or Input.is_action_just_pressed("sonar"):
					_advance()
		1:
			if player != null:
				var c := Vector2i((player.global_position / 64.0).floor())
				if c != _start_cell:
					_moved += 1
					_start_cell = c
				if _moved >= 2:
					_advance()
		2:
			if GameLog.sonar_count > 0:
				_advance()
		3:
			if _t > 4.0:
				_advance()
		4:
			if level != null and level.has_method("goal_cell"):
				var goal: Vector2i = level.goal_cell()
				if player != null:
					var c2 := Vector2i((player.global_position / 64.0).floor())
					if c2.distance_to(goal) <= 2:
						_advance()

func _advance() -> void:
	step += 1
	_t = 0.0
	if step >= 5:
		active = false
