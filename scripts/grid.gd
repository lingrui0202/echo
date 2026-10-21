extends Node2D
## 地面网格：只在被光照到时才可见。
## 它比一整块纯色地板更好用 —— 玩家能借网格估算自己走了多远、回声覆盖了多大范围。

@export var cells := Vector2i(30, 16)
@export var cell := 64.0
@export var color := Color(0.36, 0.46, 0.78, 0.55)

func _draw() -> void:
	for x in cells.x + 1:
		draw_line(Vector2(x * cell, 0), Vector2(x * cell, cells.y * cell), color, 1.0)
	for y in cells.y + 1:
		draw_line(Vector2(0, y * cell), Vector2(cells.x * cell, y * cell), color, 1.0)
