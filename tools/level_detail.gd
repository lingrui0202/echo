extends Node
## 打印某一关的关键坐标（演示前对照地图用）
##   ... -- 5

const CELL := 64

func _ready() -> void:
	var idx := 5
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			idx = int(a)
	var prog := get_node_or_null("/root/Progress")
	var session := get_node_or_null("/root/Session")
	session.set("mode", 1)
	prog.set("persist", false)
	prog.set("level_index", idx)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	var lv: Node = ps.instantiate()
	add_child(lv)
	await get_tree().process_frame

	print("=== 第 %d 关 ===" % (idx + 1))
	print("起点 ", lv.start_cell(), "   出口 ", lv.goal_cell(), "   最短路 ", lv.get("_route_len"), " 步")
	print("门 ", lv.call("door_cells"), "（关着：", _closed(lv), "）")
	print("钥匙 ", lv.call("key_cells"))
	print("压力板 ", lv.call("plate_cells"), " -> ", lv.get("_plate_door"))
	print("静音区 ", lv.call("silence_cells"))
	var enemies := []
	for e in lv.get_node("Enemies").get_children():
		enemies.append("%s@%s" % [["普通", "瞎子", "敏锐"][int(e.get("kind"))],
			str(Vector2i((e.global_position / float(CELL)).floor()))])
	print("敌人 ", enemies)
	print("箱子 ", lv.call("crate_cells"))
	print("碎片 ", lv.call("fragment_cells"))
	get_tree().quit()

func _closed(lv: Node) -> Array:
	var out := []
	for d in lv.call("door_cells"):
		if bool(lv.call("is_door_closed", d)):
			out.append(d)
	return out
