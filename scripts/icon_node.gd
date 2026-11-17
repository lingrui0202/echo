extends RefCounted
## 一个按 id 画图标的 Node2D，世界里的机关/道具都用它，保证形状统一。
## 用法：var n := IconNode.make("door", 56.0); add_child(n); n.position = ...

const IconArt = preload("res://scripts/icon_art.gd")


class IconNode extends Node2D:
	var icon_id := "door"
	var icon_size := 48.0
	var active := false

	func _draw() -> void:
		IconArt.draw_icon(self, icon_id, icon_size, active)

	func set_active(v: bool) -> void:
		if active == v:
			return
		active = v
		queue_redraw()


## Control 版（放进 HBoxContainer 里排版用，比如图鉴）
class IconRect extends Control:
	var icon_id := "door"
	var icon_size := 30.0
	var dim := false

	func _ready() -> void:
		custom_minimum_size = Vector2(icon_size, icon_size)

	func _draw() -> void:
		draw_set_transform(Vector2(icon_size * 0.5, icon_size * 0.5))
		IconArt.draw_icon(self, icon_id, icon_size, false)
		draw_set_transform(Vector2.ZERO)
		if dim:
			draw_rect(Rect2(-icon_size * 0.5, -icon_size * 0.5, icon_size, icon_size),
				Color(0.03, 0.04, 0.06, 0.62))
