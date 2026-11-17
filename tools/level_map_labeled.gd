extends Node
## 把某一关画成带标注的地图：机关/敌人/箱子都直接写在图上，底部有图例。
##   ... -- 5
## 输出 _verify/level_map_<n>_labeled.png

const Maze = preload("res://scripts/maze.gd")
const Levels = preload("res://scripts/levels.gd")
const CELL := 24
const LEGEND_H := 64
const FONT_SIZE := 13

var _lv: Node
var _data := {}


class Painter extends Node2D:
	var data: Dictionary
	var rows: Array
	var route: Array
	var w := 0
	var h := 0

	func _font() -> Font:
		return ThemeDB.fallback_font

	func _draw() -> void:
		var font := _font()
		# 地面 / 墙 / 出口
		for y in h:
			var row := String(rows[y])
			for x in row.length():
				var ch := row[x]
				var col := Color(0.10, 0.12, 0.16)
				if ch == "#":
					col = Color(0.52, 0.58, 0.70)
				elif ch == "E":
					col = Color(0.20, 0.85, 0.45)
				draw_rect(Rect2(x * CELL, y * CELL, CELL, CELL), col)

		# 最短路（门当可通行）
		for c in route:
			draw_rect(Rect2(c.x * CELL + CELL * 0.4, c.y * CELL + CELL * 0.4, CELL * 0.2, CELL * 0.2),
				Color(0.35, 0.60, 0.95, 0.55))

		# 静音区
		for c in data["silence"]:
			draw_rect(Rect2(c.x * CELL, c.y * CELL, CELL, CELL), Color(0.42, 0.28, 0.72, 0.65))

		# 门
		for c in data["doors"]:
			draw_rect(Rect2(c.x * CELL + 1, c.y * CELL + 1, CELL - 2, CELL - 2), Color(0.95, 0.62, 0.20))

		# 钥匙 / 压力板 / 敌人 / 箱子 / 起点
		for c in data["keys"]:
			_circle(c, CELL * 0.3, Color(1.0, 0.88, 0.30))
		for c in data["plates"]:
			_circle(c, CELL * 0.3, Color(0.30, 0.80, 1.0))
		for e in data["enemies"]:
			_circle(e["cell"], CELL * 0.32, e["color"])
		for c in data["crates"]:
			draw_rect(Rect2(c.x * CELL + 4, c.y * CELL + 4, CELL - 8, CELL - 8), Color(0.62, 0.48, 0.30))

		# 标注文字（带描边，压在图上也能看清）
		_label(font, data["start"], "起", Color(0.55, 0.85, 1.0))
		for c in _cluster(data["doors"]):
			_label(font, c, "门", Color(1.0, 0.80, 0.45))
		for c in _cluster(data["keys"]):
			_label(font, c, "钥匙", Color(1.0, 0.92, 0.45))
		for c in _cluster(data["plates"]):
			_label(font, c, "板", Color(0.55, 0.90, 1.0))
		for c in _cluster(data["silence"]):
			_label(font, c, "静音", Color(0.85, 0.72, 1.0))
		for e in data["enemies"]:
			_label(font, e["cell"], e["name"], e["color"].lightened(0.25))
		for c in data["crates"]:
			_label(font, c, "箱", Color(0.90, 0.78, 0.55))
		_label(font, data["goal"], "出口", Color(0.45, 1.0, 0.65))

		# 图例
		var ly := h * CELL + 18
		var items := [
			["起", Color(0.55, 0.85, 1.0), "起点"],
			["门", Color(1.0, 0.80, 0.45), "门（关着=墙）"],
			["钥匙", Color(1.0, 0.92, 0.45), "钥匙（开全部）"],
			["板", Color(0.55, 0.90, 1.0), "压力板"],
			["静音", Color(0.85, 0.72, 1.0), "静音区"],
			["普通", Color(0.95, 0.30, 0.25), "普通敌人"],
			["敏锐", Color(1.0, 0.72, 0.20), "敏锐（听觉×1.35）"],
			["瞎子", Color(0.72, 0.45, 1.0), "瞎子（只吃强声呐）"],
			["箱", Color(0.90, 0.78, 0.55), "可推箱子"],
			["出口", Color(0.45, 1.0, 0.65), "出口"],
		]
		var x := 16.0
		for it in items:
			draw_string(_font(), Vector2(x, h * CELL + LEGEND_H - 22), String(it[0]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, it[1])
			draw_string(_font(), Vector2(x + 40, h * CELL + LEGEND_H - 22), String(it[2]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1, Color(0.80, 0.86, 0.94))
			x += 40 + _text_w(String(it[2])) + 28

	## 相邻的同类（门一横排、静音 2x2）只标一次，取簇里最靠左上的那格
	func _cluster(cells: Array) -> Array:
		var out: Array = []
		for c in cells:
			var near := false
			for o in out:
				if absi(c.x - o.x) <= 1 and absi(c.y - o.y) <= 1:
					near = true
					break
			if not near:
				out.append(c)
		return out

	func _text_w(s: String) -> float:
		return _font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 1).x

	func _circle(c: Vector2i, r: float, col: Color) -> void:
		draw_circle(Vector2(c.x * CELL + CELL * 0.5, c.y * CELL + CELL * 0.5), r, col)

	func _label(font: Font, c: Vector2i, text: String, col: Color) -> void:
		var pos := Vector2(c.x * CELL - 2, maxf(c.y * CELL - 3, FONT_SIZE + 1))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
			Color(0.02, 0.03, 0.05, 0.95))
		draw_string(font, pos + Vector2(1, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
			Color(0.02, 0.03, 0.05, 0.95))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)


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

	var rows: Array = Levels.MAPS[idx]
	var w: int = String(rows[0]).length()
	var h: int = rows.size()

	var enemies := []
	for e in _lv.get_node("Enemies").get_children():
		var k := int(e.get("kind"))
		var names := ["普通", "瞎子", "敏锐"]
		var cols := [Color(0.95, 0.30, 0.25), Color(0.72, 0.45, 1.0), Color(1.0, 0.72, 0.20)]
		enemies.append({
			"cell": Vector2i((e.global_position / 64.0).floor()),
			"name": names[k], "color": cols[k],
		})

	_data = {
		"start": _lv.start_cell(),
		"goal": _lv.goal_cell(),
		"doors": _lv.call("door_cells"),
		"keys": _lv.call("key_cells"),
		"plates": _lv.call("plate_cells"),
		"silence": _lv.call("silence_cells"),
		"crates": _lv.call("crate_cells"),
		"enemies": enemies,
	}

	var vp := SubViewport.new()
	vp.size = Vector2i(w * CELL, h * CELL + LEGEND_H)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	add_child(vp)

	var painter := Painter.new()
	painter.rows = rows
	painter.w = w
	painter.h = h
	painter.data = _data
	painter.route = Maze.path(rows, _lv.start_cell(), _lv.goal_cell())
	vp.add_child(painter)

	for i in 4:
		await get_tree().process_frame
	var img := vp.get_texture().get_image()
	img.save_png("res://_verify/level_map_%d_labeled.png" % (idx + 1))
	print("[map] 第 %d 关 %dx%d 标注图 → _verify/level_map_%d_labeled.png" % [idx + 1, w, h, idx + 1])
	get_tree().quit()
