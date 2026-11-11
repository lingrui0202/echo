extends Node
## 截两张：① 第 2 关开局的词条二选一 ② 第 3 关的箱子和 HUD
##   Godot_v4.7.2-stable_win64_console.exe --path <本目录> res://tools/feature_shots.tscn

var _frames := 0
var _lv: Node
var _stage := 0

func _ready() -> void:
	_load_level(1)

func _load_level(idx: int) -> void:
	if _lv != null:
		_lv.queue_free()
	var prog := get_node_or_null("/root/Progress")
	prog.set("level_index", idx)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	_lv = ps.instantiate()
	_lv.name = "Level01"
	add_child(_lv)

func _process(_delta: float) -> void:
	_frames += 1

	if _stage == 0 and _frames == 25:
		get_viewport().get_texture().get_image().save_png("res://_verify/feature_pick.png")
		print("[shot] 词条面板 _verify/feature_pick.png")
		var mods := get_node_or_null("/root/Mods")
		mods.call("pick", 0)
		_load_level(2)
		_stage = 1
		_frames = 0
		return

	if _stage == 1 and _frames == 25:
		# 站到箱子正左边一格，相机直接对准箱子（不然平滑还没跟上，截不到）
		var cells: Array = _lv.call("crate_cells")
		if not cells.is_empty():
			var c: Vector2i = cells[0]
			var p: Node2D = _lv.get_node("Player")
			p.global_position = Vector2(c.x * 64 + 32, c.y * 64 + 32) + Vector2(-34, 0)
			var cam: Camera2D = p.get_node("Camera2D")
			cam.global_position = Vector2(c.x * 64 + 32, c.y * 64 + 32)
			cam.reset_smoothing()
			print("[shot] 箱子格 %s，玩家 %s" % [str(c), str(p.global_position)])
		_stage = 2

	if _stage == 2 and _frames == 45:
		get_viewport().get_texture().get_image().save_png("res://_verify/feature_crate.png")
		print("[shot] 箱子 _verify/feature_crate.png")
		_stage = 3
		_frames = 0
		return

	if _stage == 3 and _frames == 10:
		var hud: Node = _lv.get_node("HUD")
		hud.set("_settings_open", true)
		hud.call("_update_settings_panel")

	if _stage == 3 and _frames == 14:
		get_viewport().get_texture().get_image().save_png("res://_verify/feature_settings.png")
		print("[shot] 设置面板 _verify/feature_settings.png")
		get_tree().quit()
