extends SceneTree
## 把 5 张地图一次画成一张图，方便对照。
##   Godot_v4.7.2-stable_win64_console.exe --path <工程目录> --script res://tools/map_sheet.gd
## 输出：_verify/maps_all.png

const Levels = preload("res://scripts/levels.gd")
const CELL := 6
const PAD := 16
const TITLE_H := 22

func _initialize() -> void:
	var maps: Array = Levels.MAPS
	var max_w := 0
	var total_h := PAD
	for m in maps:
		max_w = maxi(max_w, String(m[0]).length())
		total_h += m.size() * CELL + TITLE_H + PAD

	var img := Image.create(max_w * CELL + PAD * 2, total_h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.06, 0.09))

	var y := PAD
	for i in maps.size():
		var rows: Array = maps[i]
		# 标题条
		img.fill_rect(Rect2i(PAD, y, max_w * CELL, TITLE_H - 6), Color(0.10, 0.14, 0.20))
		y += TITLE_H
		for ry in rows.size():
			var row: String = rows[ry]
			for rx in row.length():
				var c := row[rx]
				var col := Color(0.16, 0.18, 0.23)      # 地面
				if c == "#":
					col = Color(0.72, 0.78, 0.88)       # 墙
				elif c == "E":
					col = Color(0.25, 1.0, 0.55)        # 出口
				img.fill_rect(Rect2i(PAD + rx * CELL, y + ry * CELL, CELL, CELL), col)
		# 起点
		img.fill_rect(Rect2i(PAD + CELL, y + CELL, CELL, CELL), Color(0.35, 0.75, 1.0))
		y += rows.size() * CELL + PAD
		print("第 %d 关  %d×%d" % [i + 1, String(rows[0]).length(), rows.size()])

	img.save_png("res://_verify/maps_all.png")
	print("[sheet] 已保存 _verify/maps_all.png")
	quit()
