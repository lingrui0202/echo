extends Node
## 一帧里同时展示：共鸣核图标 / 方向箭头 / 成就弹窗 / 共鸣计数

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
	if _n == 10:
		var cores: Dictionary = _lv.get("_cores")
		var p: Node2D = _lv.get_node("Player")
		var hud: Node = _lv.get_node("HUD")
		if not cores.is_empty():
			var c: Vector2i = cores.keys()[0]
			# 站到共鸣核旁边两格：既能看到它，也模拟"捡完"
			p.global_position = Vector2(c.x * 64 + 32, (c.y - 2) * 64 + 32)
		# 触发一次"被听见"，看方向箭头
		var box: Node = _lv.get_node("Enemies")
		if box.get_child_count() > 0:
			var e: Node2D = box.get_child(0)
			e.global_position = p.global_position + Vector2(-320, 90)
			hud.call("note_alert_dir", e.global_position)
		# 弹一条成就
		hud.call("_on_achv", "first_clear", "初次回声", "通关第 1 关")
		p.call("add_charge", 1)
	if _n == 26:
		get_viewport().get_texture().get_image().save_png("res://_verify/fx_core.png")
		print("[shot] fx_core.png")
		get_tree().quit()
