extends SceneTree
## 波场自检：每 0.2 秒打印一次振幅统计，确认波到底有没有在走。
##   Godot_v4.7.2-stable_win64_console.exe --headless --path <工程目录> --script res://tools/wave_debug.gd

var _level: Node = null
var _wave: Node = null
var _t0 := 0
var _next := 0
var _emitted := -1

func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	_level = ps.instantiate()
	root.add_child(_level)
	_t0 = Time.get_ticks_msec()

func _ms() -> int:
	return Time.get_ticks_msec() - _t0

func _process(_delta: float) -> bool:
	if _level == null:
		return false
	if _wave == null:
		_wave = _level.get_node_or_null("SonarWave")
		if _wave == null:
			for c in _level.get_children():
				if c.get("_u") != null:
					_wave = c
		if _wave == null:
			print("FAIL: 找不到波场节点")
			return true
		print("[debug] cols=", _wave.get("_cols"), " rows=", _wave.get("_rows"), " k=", _wave.get("_k"))

	if _ms() > 100 and _emitted < 0:
		_emitted = _ms()
		_wave.emit_at(Vector2(672, 608))
		print("[debug] emitted")

	if _ms() >= _next:
		_next += 200
		var u: PackedFloat32Array = _wave.get("_u")
		var mx := 0.0
		var cnt := 0
		for v in u:
			var a: float = absf(v)
			if a > mx:
				mx = a
			if a > 0.02:
				cnt += 1
		print("[debug] t=%4d ms  max=%.3f  (>0.02)=%d frames=%d" % [_ms(), mx, cnt, _wave.get("_frames")])
		var img: Image = _wave.get("_img")
		var tex: ImageTexture = _wave.get("_tex")
		var spr: Sprite2D = _wave.get("_sprite")
		var c := img.get_pixel(9, 15) if img != null else Color.BLACK
		var ti = tex.get_image() if tex != null else null
		print("        tex(40,20)=", ti.get_pixel(40, 20) if ti != null else Color.BLACK)
		print("        sprite visible=", spr.visible if spr != null else false, " rect=", spr.get_global_rect() if spr != null else Rect2())
		print("        img(9,15)=", c, "  tex=", tex.get_size() if tex != null else Vector2i.ZERO, "  scale=", spr.scale if spr != null else Vector2.ZERO)
		if _ms() > 2200:
			return true
	return false
