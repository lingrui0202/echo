extends Node
## 截一张「刚进关、没发声呐」的画面，用来核对基础亮度。
##   Godot_v4.7.2-stable_win64_console.exe --path <本目录> res://tools/light_shot.tscn

var _n := 0
var _lv: Node

func _ready() -> void:
	var prog := get_node_or_null("/root/Progress")
	prog.set("level_index", 0)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	_lv = ps.instantiate()
	add_child(_lv)

func _process(_d: float) -> void:
	_n += 1
	if _n == 20:
		# 挪到一块四面都通的空地：否则光被墙挡住一半，截图看不出真实效果
		var rows: Array = _lv.map_rows()
		var maze := load("res://scripts/maze.gd")
		var start: Vector2i = _lv.start_cell()
		var route: Array = maze.path(rows, start, _lv.goal_cell())
		var p2: Node2D = _lv.get_node("Player")
		for idx in range(route.size() / 3, route.size()):
			var c: Vector2i = route[idx]
			var open4 := true
			for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				if not maze.is_open(rows, c + d):
					open4 = false
			if open4:
				p2.global_position = Vector2(c.x * 64 + 32, c.y * 64 + 32)
				break
	if _n == 30:
		var cam: Camera2D = _lv.get_node("Player/Camera2D")
		cam.reset_smoothing()
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://_verify/base_light.png")
		print("[shot] _verify/base_light.png")
		get_tree().quit()
