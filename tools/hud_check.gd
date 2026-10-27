extends SceneTree
## HUD 组织验证（作业 5「画面组织」那一项）：
## 把玩家（也就是相机）挪到几个位置，证明 HUD 始终贴在屏幕同一个位置，
## 而且文字会随实际状态变化；同时世界画面确实在动。
##
## 用法：
##   Godot_v4.7.2-stable_win64_console.exe --path <工程目录> --script res://tools/hud_check.gd
##
## 产出：_verify/hud_A.png、_verify/hud_B.png，控制台打印 HUD 文字的屏幕包围盒。

const HUD_REGION := Rect2i(0, 0, 900, 64)   # 只看左上角那条状态行
const BRIGHT := 150                          # 状态行文字是浅蓝色，取蓝通道阈值

var _t0 := 0
var _player: Node2D = null
var _shots := {}

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	root.add_child(ps.instantiate())
	_t0 = Time.get_ticks_msec()

func _ms() -> int:
	return Time.get_ticks_msec() - _t0

## HUD 文字在屏幕上的包围盒（找不到就返回空矩形）
func _text_bbox(path: String) -> Rect2i:
	var img := root.get_texture().get_image()
	img.save_png(path)
	var minx := 1 << 20
	var miny := 1 << 20
	var maxx := -1
	var maxy := -1
	for y in range(HUD_REGION.position.y, HUD_REGION.size.y):
		for x in range(HUD_REGION.position.x, HUD_REGION.size.x):
			var c := img.get_pixel(x, y)
			if c.b > 0.55 and c.g > 0.45:
				minx = mini(minx, x)
				miny = mini(miny, y)
				maxx = maxi(maxx, x)
				maxy = maxi(maxy, y)
	if maxx < 0:
		return Rect2i()
	return Rect2i(minx, miny, maxx - minx, maxy - miny)

func _hud_text() -> String:
	var hud := root.get_node_or_null("Level01/HUD")
	if hud == null:
		return "<no hud>"
	var hint: Label = hud.get("_hint")
	return hint.text if hint != null else "<no label>"

func _process(_delta: float) -> bool:
	if _player == null:
		var p := root.get_node_or_null("Level01/Player")
		if p != null:
			_player = p

	if _player != null:
		if _ms() >= 400 and not _shots.has("A"):
			_shots["A"] = true
			var b := _text_bbox("res://_verify/hud_A.png")
			print("[hud] A 玩家=", _player.global_position, " HUD 包围盒=", b, " 文本=", _hud_text())
			_player.global_position = Vector2(96 + 64 * 9, 96 + 64 * 5)   # 挪 9 格
		if _ms() >= 900 and not _shots.has("B"):
			_shots["B"] = true
			var b := _text_bbox("res://_verify/hud_B.png")
			print("[hud] B 玩家=", _player.global_position, " HUD 包围盒=", b, " 文本=", _hud_text())
			return true
	return false
