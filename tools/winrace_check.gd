extends Node
## 结算竞态自检：通关后在 2 秒等待里按 R，不能反而跳过一关。
##   Godot_v4.7.2-stable_win64_console.exe --path <本目录> res://tools/winrace_check.tscn

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
	session.set("mode", 1)          # 测试模式：不写存档
	prog.set("persist", false)

	_check(await _race_case(), "通关等待期间按 R：不会跳关", "按了 R 还是被推进到下一关")

	print("---- %d 项通过，%d 项失败" % [_pass, _fails.size()])
	session.set("mode", 0)
	get_tree().quit(0 if _fails.is_empty() else 1)

func _race_case() -> bool:
	var prog := get_node_or_null("/root/Progress")
	prog.set("level_index", 0)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	var lv: Node = ps.instantiate()
	add_child(lv)
	await get_tree().process_frame
	var player: Node = lv.get_node("Player")

	player.call("win")
	await get_tree().process_frame
	# 在这 2 秒里按 R
	lv.call("restart")
	await get_tree().process_frame
	var after_restart := int(lv.level_index)
	await get_tree().create_timer(2.4).timeout
	var after_wait := int(lv.level_index)

	var ok := after_restart == 0 and after_wait == 0
	if not ok:
		print("   重启后 level_index=%d，等 2.4 s 后=%d" % [after_restart, after_wait])
	lv.queue_free()
	await get_tree().process_frame
	return ok
