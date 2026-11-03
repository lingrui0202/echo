extends SceneTree
## 声呐波截图：在几个时间点拍下来，看波是怎么走的、有没有被墙挡住又反弹。
## 用法：
##   Godot_v4.7.2-stable_win64_console.exe --path <工程目录> --script res://tools/wave_shots.gd
##
## 产出：_verify/wave_<ms>.png

const T_EMIT := 200
const SHOTS := [200, 400, 600, 800, 1000, 1200, 1600]
const EMIT_CELL := Vector2i(30, 2)   # 第 2 行那条长走廊，能看清波怎么走

var _t0 := 0
var _emitted := -1
var _level: Node = null
var _done := {}

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	_level = ps.instantiate()
	root.add_child(_level)
	_t0 = Time.get_ticks_msec()

func _ms() -> int:
	return Time.get_ticks_msec() - _t0

func _shot(tag: int) -> void:
	var img := root.get_texture().get_image()
	img.save_png("res://_verify/wave_%d.png" % tag)
	print("[wave] %d ms  shot" % tag)

func _process(_delta: float) -> bool:
	if _level == null:
		return false

	if _ms() >= T_EMIT and _emitted < 0:
		_emitted = _ms()
		var p: Node = _level.get_node("Player")
		p.global_position = Vector2(EMIT_CELL.x * 64 + 32, EMIT_CELL.y * 64 + 32)
		_level.emit_wave(p.global_position)
		print("[wave] emitted at ", p.global_position)

	if _emitted >= 0:
		var since := _ms() - _emitted
		for tag in SHOTS:
			if since >= tag and not _done.has(tag):
				_done[tag] = true
				_shot(tag)
		if _done.size() == SHOTS.size():
			return true
	return false
