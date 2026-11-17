extends Node
## 把某一关画成一张图（墙/出口/机关/敌人/箱子 + 最短路）
##   Godot_v4.7.2-stable_win64_console.exe --path <本目录> res://tools/level_map_shot.tscn -- 5
## 参数是关卡序号（0 起）；不传默认第 6 关。输出 _verify/level_map_<n>.png

const Maze = preload("res://scripts/maze.gd")
const CELL := 10

var _lv: Node

func _ready() -> void:
	var idx := 5
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			idx = int(a)

	var prog := get_node_or_null("/root/Progress")
	var session := get_node_or_null("/root/Session")
	session.set("mode", 1)
	prog.set("persist", false)
	prog.set("level_index", idx)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	_lv = ps.instantiate()
	add_child(_lv)
	await get_tree().process_frame

	var rows: Array = _lv.map_rows()
	var w: int = String(rows[0]).length()
	var h: int = rows.size()
	var img := Image.create(w * CELL, h * CELL, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.06, 0.09))

	# 地面 / 墙 / 出口
	for y in h:
		var row := String(rows[y])
		for x in row.length():
			var c := row[x]
			var col := Color(0.13, 0.15, 0.20)
			if c == "#":
				col = Color(0.62, 0.68, 0.80)
			elif c == "E":
				col = Color(0.25, 1.0, 0.55)
			img.fill_rect(Rect2i(x * CELL, y * CELL, CELL, CELL), col)

	# 最短路：用「门开着」的原始地图，否则会画成绕开门的路线
	var raw: Array = preload("res://scripts/levels.gd").MAPS[_lv.level_index]
	var route: Array = Maze.path(raw, _lv.start_cell(), _lv.goal_cell())
	for c in route:
		img.fill_rect(Rect2i(c.x * CELL + CELL * 2 / 5, c.y * CELL + CELL * 2 / 5, CELL / 5, CELL / 5),
			Color(0.35, 0.60, 0.95, 0.55))

	# 机关
	for c in _lv.call("door_cells"):
		img.fill_rect(Rect2i(c.x * CELL + 1, c.y * CELL + 1, CELL - 2, CELL - 2), Color(0.95, 0.62, 0.20))
	for c in _lv.call("key_cells"):
		_dot(img, c, Color(1.0, 0.88, 0.30), 3)
	for c in _lv.call("plate_cells"):
		_dot(img, c, Color(0.35, 0.75, 1.0), 3)
	for c in _lv.call("silence_cells"):
		img.fill_rect(Rect2i(c.x * CELL, c.y * CELL, CELL, CELL), Color(0.45, 0.30, 0.75, 0.55))

	# 敌人 / 箱子
	for e in _lv.get_node("Enemies").get_children():
		var cell := Vector2i((e.global_position / 64.0).floor())
		var k := int(e.get("kind"))
		var col := Color(0.95, 0.30, 0.25)
		if k == 1:
			col = Color(0.72, 0.45, 1.0)
		elif k == 2:
			col = Color(1.0, 0.72, 0.20)
		_dot(img, cell, col, 4)
	for c in _lv.call("crate_cells"):
		img.fill_rect(Rect2i(c.x * CELL + 2, c.y * CELL + 2, CELL - 4, CELL - 4), Color(0.60, 0.48, 0.30))

	# 起点
	_dot(img, _lv.start_cell(), Color(0.40, 0.80, 1.0), 4)

	# 放大 2 倍更好看
	img.resize(w * CELL * 2, h * CELL * 2, Image.INTERPOLATE_NEAREST)
	img.save_png("res://_verify/level_map_%d.png" % (idx + 1))
	print("[map] 第 %d 关 %dx%d，最短路 %d 步 → _verify/level_map_%d.png" % [
		idx + 1, w, h, route.size(), idx + 1])
	get_tree().quit()

func _dot(img: Image, c: Vector2i, col: Color, r: int) -> void:
	var cx := c.x * CELL + CELL / 2
	var cy := c.y * CELL + CELL / 2
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				var px := cx + dx
				var py := cy + dy
				if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
					img.set_pixel(px, py, col)
