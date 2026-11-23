extends Node
## 拍"敌人贴近 + 正在移动"的一帧，检查危险暗角与脚步涟漪

var _n := 0
var _lv: Node

func _ready() -> void:
	var prog := get_node_or_null("/root/Progress")
	var session := get_node_or_null("/root/Session")
	session.set("mode", 1)
	prog.set("persist", false)
	prog.set("level_index", 3)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	_lv = ps.instantiate()
	add_child(_lv)

func _process(_d: float) -> void:
	_n += 1
	if _n == 8:
		var box: Node = _lv.get_node("Enemies")
		var p: Node2D = _lv.get_node("Player")
		if box.get_child_count() > 0:
			var e: Node2D = box.get_child(0)
			e.global_position = p.global_position + Vector2(170, 0)
		Input.action_press("move_right")
	if _n == 40:
		Input.action_release("move_right")
	if _n == 44:
		get_viewport().get_texture().get_image().save_png("res://_verify/fx_danger.png")
		print("[shot] fx_danger.png")
		get_tree().quit()
