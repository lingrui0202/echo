extends Node2D
## 声呐 = 一次发声推出一圈，圈向外扩；撞墙会反射，最多两跳（第三跳就吃掉）。
##
## 为什么这么写：纯一圈信息太少（走廊里只剩两个小弧），全反射又会在墙之间来回弹到看不清。
## 折中：每条射线允许反射两次，每次反射亮度降到 55%，所以你会看到
## "主圈 + 一两道从墙角拐过来的副圈"，但不会无限回响。
##
## 每条射线的做法：
##   从发声点出发，沿这个角度走 r 那么远；中途撞墙就按法线反射、
##   带着剩下的路程继续走，最多两跳。末端就是"波此刻到达的位置"。
##   把 220 条射线的末端连起来 = 这一帧的波前。
##
## 画在 follow_viewport 的 CanvasLayer 里，否则会被 CanvasModulate 压黑。

const RING_SPEED := 420.0     # 圈扩大的速度 px/s
const DURATION := 1.6         # 一圈活多久（反弹两次后要更久才看得清）
const SEGMENTS := 180         # 圆周采样点数（反射变多，点数降一点保帧率）
const MAX_BOUNCES := 5        # 允许反射几次：五跳之后基本也听不见了
const BOUNCE_LOSS := 0.72     # 每反射一次剩多少亮度（五跳后约 0.19）
const WALL_MASK := 1
const MIN_RADIUS := 6.0

var _t := -1.0
var _origin := Vector2.ZERO
var _layer: CanvasLayer
var _drawer: Node2D


class Drawer extends Node2D:
	var host: Node

	func _draw() -> void:
		host.draw_ring(self)


func setup(_map_rows: Array, _cell_px: float) -> void:
	_layer = CanvasLayer.new()
	_layer.follow_viewport_enabled = true
	add_child(_layer)
	_drawer = Drawer.new()
	_drawer.host = self
	_layer.add_child(_drawer)


func emit_at(world_pos: Vector2) -> void:
	_origin = world_pos
	_t = 0.0
	_drawer.queue_redraw()


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	if _t > DURATION:
		_t = -1.0
		_drawer.queue_redraw()
		return
	_drawer.queue_redraw()


## 一条射线：走 distance 远，中途最多反射 MAX_BOUNCES 次。返回 [末端, 剩余亮度]
func trace_ray(dir: Vector2, distance: float, space: PhysicsDirectSpaceState2D) -> Array:
	var pos := _origin
	var remaining := distance
	var energy := 1.0
	var d := dir
	for _b in MAX_BOUNCES + 1:
		if remaining <= 0.5:
			break
		var target := pos + d * remaining
		var q := PhysicsRayQueryParameters2D.create(pos, target, WALL_MASK)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return [target, energy]
		# 撞墙：扣掉走过的路程，按法线反射，亮度打折
		var hit_pos: Vector2 = hit["position"]
		var normal: Vector2 = hit["normal"]
		remaining -= pos.distance_to(hit_pos)
		pos = hit_pos + normal * 1.0
		d = d.bounce(normal)
		energy *= BOUNCE_LOSS
	return [pos, energy]


func draw_ring(d: CanvasItem) -> void:
	if _t < 0.0:
		return
	var r := maxf(MIN_RADIUS, RING_SPEED * _t)
	var k := clampf(_t / DURATION, 0.0, 1.0)
	var fade := pow(1.0 - k, 0.7)   # 前段慢一点变淡，别刚出门口就看不见
	var space := get_world_2d().direct_space_state

	var prev := Vector2.ZERO
	var prev_energy := 0.0
	var prev_ok := false
	for i in SEGMENTS + 1:
		var ang := TAU * float(i) / float(SEGMENTS)
		var res := trace_ray(Vector2(cos(ang), sin(ang)), r, space)
		var pt: Vector2 = res[0]
		var energy: float = res[1]
		var alpha := fade * 0.9 * energy

		if prev_ok and absf(energy - prev_energy) < 0.35:
			d.draw_line(prev, pt, Color(0.55, 0.88, 1.0, alpha), 5.0)
		else:
			# 反射切换处的端点单独点一下，免得线跨过墙角乱连
			d.draw_circle(pt, 3.0, Color(0.65, 0.92, 1.0, alpha))

		prev = pt
		prev_energy = energy
		prev_ok = true
