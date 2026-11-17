extends Node
## 拍一张"站在机关旁边"的画面，检查图标在游戏里到底看不看得见。
##   ... res://tools/icon_shot.tscn

var _n := 0
var _lv: Node

func _ready() -> void:
	var prog := get_node_or_null("/root/Progress")
	var session := get_node_or_null("/root/Session")
	session.set("mode", 1)
	prog.set("persist", false)
	prog.set("level_index", 5)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	_lv = ps.instantiate()
	add_child(_lv)

func _process(_d: float) -> void:
	_n += 1
	if _n == 6:
		# 站到门前一格
		var doors: Array = _lv.call("door_cells")
		if not doors.is_empty():
			var c: Vector2i = doors[0]
			var p: Node2D = _lv.get_node("Player")
			p.global_position = Vector2(c.x * 64 + 32, (c.y + 1) * 64 + 32)
			var cam: Camera2D = p.get_node("Camera2D")
			cam.global_position = Vector2(c.x * 64 + 32, c.y * 64 + 32)
			cam.reset_smoothing()
	if _n == 20:
		get_viewport().get_texture().get_image().save_png("res://_verify/icon_door.png")
		print("[shot] icon_door.png")
		# 再来一张：站在敌人旁边
		var box: Node = _lv.get_node("Enemies")
		if box.get_child_count() > 0:
			var e: Node2D = box.get_child(0)
			var p2: Node2D = _lv.get_node("Player")
			p2.global_position = e.global_position + Vector2(0, 96)
			var cam2: Camera2D = p2.get_node("Camera2D")
			cam2.global_position = e.global_position
			cam2.reset_smoothing()
	if _n == 34:
		get_viewport().get_texture().get_image().save_png("res://_verify/icon_enemy.png")
		print("[shot] icon_enemy.png")
		get_tree().quit()
