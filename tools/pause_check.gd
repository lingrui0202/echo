extends Node
## 面板暂停自检：Esc/C 打开时游戏必须停住，关掉后恢复。
##   ... res://tools/pause_check.tscn

var _fails := PackedStringArray()
var _pass := 0

func _check(cond: bool, ok: String, bad: String) -> void:
	if cond:
		_pass += 1
		print("PASS  ", ok)
	else:
		_fails.append(bad)
		print("FAIL  ", bad)

func _ready() -> void:
	var prog := get_node_or_null("/root/Progress")
	var session := get_node_or_null("/root/Session")
	session.set("mode", 1)
	prog.set("persist", false)
	prog.set("level_index", 1)

	var ps: PackedScene = load("res://scenes/Level01.tscn")
	var lv: Node = ps.instantiate()
	add_child(lv)
	await get_tree().process_frame
	var player: Node2D = lv.get_node("Player")
	# 自检运行（tools/）不该弹词条面板，否则一上来就被暂停
	var mods0 := get_node_or_null("/root/Mods")
	_check(not bool(mods0.get("pending")), "自检运行不要求选词条", "自检里弹出了词条面板")
	_check(not get_tree().paused, "自检运行一开始没有被暂停", "自检一开始就处于暂停")
	get_node_or_null("/root/Mods").set("pending", false)

	# 打开设置
	await _tap("settings")
	_check(get_tree().paused, "Esc 打开设置后游戏暂停", "打开设置没有暂停")

	# 暂停期间敌人与玩家都不该动
	var p0: Vector2 = player.global_position
	var enemies: Array = lv.get_node("Enemies").get_children()
	var e0: Vector2 = enemies[0].global_position if enemies.size() > 0 else Vector2.ZERO
	Input.action_press("move_right")
	for i in 20:
		await get_tree().process_frame
	Input.action_release("move_right")
	var moved: float = player.global_position.distance_to(p0)
	_check(moved < 1.0, "暂停时玩家不动（位移 %.1f px）" % moved, "暂停时玩家还在动：%.1f px" % moved)
	if enemies.size() > 0:
		var emoved: float = enemies[0].global_position.distance_to(e0)
		_check(emoved < 1.0, "暂停时敌人不动（位移 %.1f px）" % emoved, "暂停时敌人还在动：%.1f px" % emoved)

	# 关闭设置
	await _tap("settings")
	_check(not get_tree().paused, "Esc 关闭设置后恢复", "关掉设置没有恢复")

	# 冷却时间也不该在暂停时流逝：暂停 1 秒后立刻发声，应能按下去
	await _tap("codex")
	_check(get_tree().paused, "C 打开图鉴后游戏暂停", "打开图鉴没有暂停")
	await _tap("codex")
	_check(not get_tree().paused, "C 关闭图鉴后恢复", "关掉图鉴没有恢复")

	# 走到出口（结算面板）不应该暂停
	player.call("win")
	await get_tree().process_frame
	_check(not get_tree().paused, "结算面板不暂停（还能看到 2 秒后的推进）", "结算面板把游戏暂停了")

	print("---- %d 项通过，%d 项失败" % [_pass, _fails.size()])
	session.set("mode", 0)
	get_tree().paused = false
	get_tree().quit(0 if _fails.is_empty() else 1)

func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)
	await get_tree().process_frame
	await get_tree().process_frame
