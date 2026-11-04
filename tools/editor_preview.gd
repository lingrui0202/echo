extends SceneTree
## 拍一张"编辑器里会看到的样子"：把运行时的 Darkness 摘掉再截。
##   Godot_v4.7.2-stable_win64_console.exe --path <工程目录> --script res://tools/editor_preview.gd

var _frames := 0
var _level: Node = null

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	_level = ps.instantiate()
	root.add_child(_level)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		var dark := _level.get_node_or_null("Darkness")
		if dark != null:
			dark.free()
		# 把相机拉到地图中间，一屏能看全
		var cam: Camera2D = _level.get_node("Player/Camera2D")
		cam.make_current()
		cam.zoom = Vector2(0.42, 0.42)
		cam.global_position = Vector2(61 * 64 * 0.5, 34 * 64 * 0.5)
	if _frames == 12:
		root.get_texture().get_image().save_png("res://_verify/editor_preview.png")
		print("[preview] saved _verify/editor_preview.png")
		return true
	return false
