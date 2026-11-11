@tool
extends Node2D
## 地图总览（编辑器里双击就能看，不用运行游戏）。
##
## 在 Godot 的 FileSystem 里打开 scenes/MapPreview.tscn：
## 2D 视图里会从上到下摆出 5 张地图 —— 白=墙，深灰=地面，绿=出口，蓝=起点。
##
## 改完 scripts/levels.gd 保存，这里会自动重画（@tool）。

const Levels = preload("res://scripts/levels.gd")

const CELL := 8.0
const GAP := 28.0
const LABEL_H := 26.0

func _ready() -> void:
	queue_redraw()
	if Engine.is_editor_hint():
		return
	# 直接运行这个场景时：自动缩放，方便看全（也可以带 --shot 存一张图）
	var cam := Camera2D.new()
	var total := 0.0
	for m in Levels.MAPS:
		total += m.size() * CELL + GAP + LABEL_H
	var cw := _max_width() * CELL
	var vp := get_viewport_rect().size
	var fit := minf(vp.x / cw, vp.y / total) * 0.92
	cam.position = Vector2(cw * 0.5, total * 0.5)
	cam.zoom = Vector2(fit, fit)
	add_child(cam)
	cam.make_current()
	if OS.get_cmdline_args().has("--shot"):
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://_verify/maps_view.png")
		print("[preview] _verify/maps_view.png")
		get_tree().quit()


func _max_width() -> int:
	var w := 0
	for m in Levels.MAPS:
		w = maxi(w, String(m[0]).length())
	return w

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var y := 0.0
	for i in Levels.MAPS.size():
		var rows: Array = Levels.MAPS[i]
		var w: int = String(rows[0]).length()
		var h: int = rows.size()
		draw_string(font, Vector2(0, y + 18), "第 %d 关   %d × %d" % [i + 1, w, h],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.55, 0.72, 0.95))
		y += LABEL_H
		# 地面
		draw_rect(Rect2(0, y, w * CELL, h * CELL), Color(0.14, 0.16, 0.21))
		for ry in h:
			var row: String = rows[ry]
			for rx in row.length():
				var c := row[rx]
				if c == "#":
					draw_rect(Rect2(rx * CELL, y + ry * CELL, CELL, CELL),
						Color(0.70, 0.77, 0.88))
				elif c == "E":
					draw_rect(Rect2(rx * CELL, y + ry * CELL, CELL, CELL),
						Color(0.25, 1.0, 0.55))
		# 起点
		draw_rect(Rect2(CELL, y + CELL, CELL, CELL), Color(0.35, 0.75, 1.0))
		# 外框
		draw_rect(Rect2(0, y, w * CELL, h * CELL), Color(0.3, 0.42, 0.6), false, 2.0)
		y += h * CELL + GAP
