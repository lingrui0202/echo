extends Node
## 新手引导自检：步骤按玩家的行为推进；测试模式不弹。
##   Godot_v4.7.2-stable_win64_console.exe --path <本目录> res://tools/tutorial_check.tscn

var _fails := PackedStringArray()
var _pass := 0
var _lv: Node
var _player: Node

func _check(cond: bool, ok: String, bad: String) -> void:
	if cond:
		_pass += 1
		print("PASS  ", ok)
	else:
		_fails.append(bad)
		print("FAIL  ", bad)

func _ready() -> void:
	var tut := get_node_or_null("/root/Tutorial")
	var session := get_node_or_null("/root/Session")
	var prog := get_node_or_null("/root/Progress")
	_check(tut != null, "Tutorial 已注册", "缺少 Tutorial autoload")
	if tut == null:
		_finish()
		return

	prog.set("level_index", 0)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	_lv = ps.instantiate()
	add_child(_lv)
	await get_tree().process_frame
	_player = _lv.get_node("Player")

	# 新存档：从开场卡开始
	session.set("tutorial", true)
	tut.call("begin", true)
	_check(int(tut.get("step")) == 0 and bool(tut.get("active")), "新存档从开场卡开始",
		"没有从第 0 步开始")
	_check(String(tut.call("current_text")).contains("看不见"), "开场卡讲清了「看不见」",
		"开场卡内容不对")
	# 顺手截一张开场卡（HUD 要刷新两帧才有字）
	_lv.get_node("HUD").call("_update_tutorial", 0.016)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://_verify/tutorial.png")
	print("[shot] _verify/tutorial.png")

	# 0.6 秒后按移动 → 第 1 步
	tut.call("tick", 0.7, _player, _lv)
	Input.action_press("move_right")
	tut.call("tick", 0.016, _player, _lv)
	Input.action_release("move_right")
	_check(int(tut.get("step")) == 1, "按方向键后离开开场卡", "按了方向键还停在开场卡")

	# 走两步 → 第 2 步
	var c0: Vector2i = _lv.start_cell()
	_player.global_position = Vector2((c0.x + 1) * 64 + 32, c0.y * 64 + 32)
	tut.call("tick", 0.016, _player, _lv)
	_player.global_position = Vector2((c0.x + 2) * 64 + 32, c0.y * 64 + 32)
	tut.call("tick", 0.016, _player, _lv)
	_check(int(tut.get("step")) == 2, "走两步后提示发声呐", "走路没有推进引导")

	# 发声呐 → 第 3 步
	GameLog.note_sonar()
	tut.call("tick", 0.016, _player, _lv)
	_check(int(tut.get("step")) == 3, "发第一声后讲「这就是回声」", "发声没有推进引导")
	_check(String(tut.call("current_text")).contains("回声"), "第 3 步在解释回声",
		"第 3 步内容不对")

	# 4 秒后 → 第 4 步
	tut.call("tick", 4.2, _player, _lv)
	_check(int(tut.get("step")) == 4, "看完回声后指向出口", "没有推进到出口提示")

	# 走到出口附近 → 结束
	var goal: Vector2i = _lv.goal_cell()
	_player.global_position = Vector2(goal.x * 64 + 32, goal.y * 64 + 32)
	tut.call("tick", 0.016, _player, _lv)
	_check(int(tut.get("step")) >= 5 and not bool(tut.get("active")), "到出口后引导结束",
		"到出口引导还没结束")

	# 测试模式不弹
	session.set("tutorial", true)
	tut.call("begin", true)
	session.set("mode", 1)
	var hud: Node = _lv.get_node("HUD")
	hud.call("_update_tutorial", 0.016)
	await get_tree().process_frame
	_check(not bool(tut.get("active")), "测试模式下引导不出现", "测试模式还在弹引导")
	session.set("mode", 0)

	_finish()

func _finish() -> void:
	print("---- %d 项通过，%d 项失败" % [_pass, _fails.size()])
	get_tree().quit(0 if _fails.is_empty() else 1)
