extends Node
## 打印每一关的实际内容（给演示挑关用）
##   Godot_v4.7.2-stable_win64_console.exe --path <本目录> res://tools/level_report.tscn

const Levels = preload("res://scripts/levels.gd")
const Maze = preload("res://scripts/maze.gd")

func _ready() -> void:
	var prog := get_node_or_null("/root/Progress")
	var session := get_node_or_null("/root/Session")
	session.set("mode", 1)
	prog.set("persist", false)

	var ps: PackedScene = load("res://scenes/Level01.tscn")
	for i in Levels.MAPS.size():
		prog.set("level_index", i)
		var lv: Node = ps.instantiate()
		add_child(lv)
		await get_tree().process_frame
		var rows: Array = Levels.MAPS[i]
		var kinds := {}
		for e in lv.get_node("Enemies").get_children():
			var k := int(e.get("kind"))
			kinds[k] = int(kinds.get(k, 0)) + 1
		print("LEVEL %2d | %2d x %2d | 最短路 %3d 步 | 敌人 %d %s | 门 %d 钥匙 %d 压力板 %d 静音区 %d 格 | 箱子 %d | 碎片 %d" % [
			i + 1, String(rows[0]).length(), rows.size(), int(lv.get("_route_len")),
			lv.get_node("Enemies").get_child_count(), str(kinds),
			lv.call("door_cells").size(), lv.call("key_cells").size(),
			lv.call("plate_cells").size(), lv.call("silence_cells").size(),
			lv.call("crate_cells").size(), lv.call("fragment_cells").size()])
		print("        共鸣核 ", (lv.get("_cores") as Dictionary).size())
		lv.queue_free()
		await get_tree().process_frame

	session.set("mode", 0)
	get_tree().quit()
