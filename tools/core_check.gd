extends Node
## 共鸣核自检：捡到、按 Q 能震杀近处敌人、冷却/计数正确

func _ready() -> void:
	var prog := get_node_or_null("/root/Progress")
	var session := get_node_or_null("/root/Session")
	session.set("mode", 1)
	prog.set("persist", false)
	prog.set("level_index", 5)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	var lv: Node = ps.instantiate()
	add_child(lv)
	await get_tree().process_frame

	var cores: Dictionary = lv.get("_cores")
	print("[core] 本关共鸣核数量 = ", cores.size())
	if cores.is_empty():
		print("FAIL 第 6 关没有共鸣核")
		get_tree().quit(1)
		return

	var cell: Vector2i = cores.keys()[0]
	var player: Node2D = lv.get_node("Player")
	player.global_position = Vector2(cell.x * 64 + 32, cell.y * 64 + 32)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[core] 捡到后计数 = ", player.call("charge_count"))

	var box: Node = lv.get_node("Enemies")
	var before := box.get_child_count()
	var e0: Node2D = box.get_child(0) if before > 0 else null
	if e0 != null:
		e0.global_position = player.global_position + Vector2(120, 0)
	var killed: int = lv.call("resonance_blast", player.global_position)
	await get_tree().process_frame
	print("[core] 击杀 = ", killed, "  敌人 ", before, " → ", box.get_child_count())
	print("[core] 剩余计数 = ", player.call("charge_count"))
	var ok := killed >= 1 and box.get_child_count() < before
	print("PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
