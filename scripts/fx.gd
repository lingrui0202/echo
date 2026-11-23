extends RefCounted
## 一小段可复用的视觉小件：脚步涟漪、撞击亮斑等
## 都是"一次性播放完自己消失"的节点，避免碰撞点每帧重建。

const IconArt = preload("res://scripts/icon_art.gd")


class Ripple extends Node2D:
	var life := 0.0
	var span := 0.55
	var radius0 := 10.0
	var radius1 := 34.0
	var col := Color(0.55, 0.85, 1.0, 0.55)

	func _process(delta: float) -> void:
		life += delta
		queue_redraw()
		if life >= span:
			queue_free()

	func _draw() -> void:
		var k := clampf(life / span, 0.0, 1.0)
		var r := lerpf(radius0, radius1, k)
		var a := (1.0 - k) * col.a
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, Color(col.r, col.g, col.b, a), 1.6, true)
