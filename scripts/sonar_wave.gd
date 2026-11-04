extends Node2D
## 声呐 = 一次发声推出一圈波前，向外扩；撞墙会反射（最多 5 次），
## 撞到的墙面会留下**淡淡的边界**，几秒内慢慢退掉 —— 相当于"记住摸过的墙"。
##
## 两条图层：
##   1. 波前：一圈几何线，随半径推进、随距离变淡
##   2. 边界记忆：射线打到墙上的点，按位置戳进一张小图里，缓慢衰减
##
## 为什么不用波动方程：波场每帧正负翻转、还会在墙之间来回弹，屏幕光暗一直在变。
##
## 画在 follow_viewport 的 CanvasLayer 里，否则会被 CanvasModulate 压黑。

const RING_SPEED := 420.0     # 圈扩大的速度 px/s
const DURATION := 1.6         # 一圈活多久
const SEGMENTS := 220         # 圆周采样点数
const MAX_BOUNCES := 5        # 允许反射几次
const BOUNCE_LOSS := 0.72     # 每反射一次剩多少亮度
const WALL_MASK := 1
const MIN_RADIUS := 6.0

const SIM_CELL := 32.0        # 边界记忆图的一格多少像素
const EDGE_ALPHA := 0.26      # 撞墙时戳进去的亮度（淡，别抢波前的戏）
const EDGE_DECAY := 0.97      # 每 4 帧衰减一次（约 6–7 秒退完）

var _t := -1.0
var _origin := Vector2.ZERO
var _layer: CanvasLayer
var _drawer: Node2D

var _pts := PackedVector2Array()
var _energies := PackedFloat32Array()

var _edge_img: Image
var _edge_tex: ImageTexture
var _edge_sprite: Sprite2D
var _edge_cols := 0
var _edge_rows := 0
var _tick := 0
var _edge_dirty := false


class Drawer extends Node2D:
	var host: Node

	func _draw() -> void:
		host.draw_ring(self)


var _map_w := 61
var _map_h := 34
var _per := 2


func setup(map_rows: Array, cell_px: float) -> void:
	_map_w = map_rows[0].length()
	_map_h = map_rows.size()
	_per = int(round(cell_px / SIM_CELL))
	_layer = CanvasLayer.new()
	_layer.follow_viewport_enabled = true
	add_child(_layer)

	# 边界记忆：底层，淡蓝色
	_edge_cols = _map_w * _per
	_edge_rows = _map_h * _per
	_edge_img = Image.create_empty(_edge_cols, _edge_rows, false, Image.FORMAT_RGBA8)
	_edge_img.fill(Color(0, 0, 0, 0))
	_edge_tex = ImageTexture.create_from_image(_edge_img)
	_edge_sprite = Sprite2D.new()
	_edge_sprite.texture = _edge_tex
	_edge_sprite.centered = false
	_edge_sprite.scale = Vector2(SIM_CELL, SIM_CELL)
	_edge_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var m1 := CanvasItemMaterial.new()
	m1.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_edge_sprite.material = m1
	_layer.add_child(_edge_sprite)

	# 波前：上层
	_drawer = Drawer.new()
	_drawer.host = self
	_layer.add_child(_drawer)


func emit_at(world_pos: Vector2) -> void:
	_origin = world_pos
	_t = 0.0
	_pts.clear()
	_energies.clear()
	_drawer.queue_redraw()


func _process(delta: float) -> void:
	# 衰减必须无条件跑：之前写在“圈还活着”的分支里，
	# 圈一结束就直接 return，边界记忆会永远停在屏幕上。
	_tick += 1
	if _tick % 4 == 0:
		_decay_edges()
		if _edge_dirty:
			_edge_tex.update(_edge_img)
			_edge_dirty = false

	if _t < 0.0:
		return
	_t += delta

	if _t > DURATION:
		_t = -1.0
		_pts.clear()
		_energies.clear()
		_drawer.queue_redraw()
	else:
		_compute_ring()
		_drawer.queue_redraw()


## 一条射线：走 distance 远，中途最多反射 MAX_BOUNCES 次。
## 返回 [末端位置, 剩余亮度, 撞墙次数]
func trace_ray(dir: Vector2, distance: float, space: PhysicsDirectSpaceState2D) -> Array:
	var pos := _origin
	var remaining := distance
	var energy := 1.0
	var hits := 0
	var d := dir
	for _b in MAX_BOUNCES + 1:
		if remaining <= 0.5:
			break
		var target := pos + d * remaining
		var q := PhysicsRayQueryParameters2D.create(pos, target, WALL_MASK)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return [target, energy, hits]
		var hit_pos: Vector2 = hit["position"]
		var normal: Vector2 = hit["normal"]
		remaining -= pos.distance_to(hit_pos)
		pos = hit_pos + normal * 1.0
		d = d.bounce(normal)
		energy *= BOUNCE_LOSS
		hits += 1
	return [pos, energy, hits]


func _compute_ring() -> void:
	var r := maxf(MIN_RADIUS, RING_SPEED * _t)
	var space := get_world_2d().direct_space_state
	_pts.clear()
	_energies.clear()
	for i in SEGMENTS + 1:
		var ang := TAU * float(i) / float(SEGMENTS)
		var res := trace_ray(Vector2(cos(ang), sin(ang)), r, space)
		var pt: Vector2 = res[0]
		var energy: float = res[1]
		var hits: int = res[2]
		_pts.append(pt)
		_energies.append(energy)
		# 只记前两跳打到的墙：再往后都是来回弹的余波，记下来整张图都会亮
		if hits > 0 and hits <= 2:
			_stamp_edge(pt, energy)


## 把"打到墙上的点"戳进边界记忆图。第一次反射（hits==1）才最亮，后面几跳更淡。
func _stamp_edge(world_pos: Vector2, energy: float) -> void:
	var x := int(world_pos.x / SIM_CELL)
	var y := int(world_pos.y / SIM_CELL)
	if x < 0 or y < 0 or x >= _edge_cols or y >= _edge_rows:
		return
	var c := _edge_img.get_pixel(x, y)
	var want := clampf(EDGE_ALPHA * energy, 0.0, 1.0)
	if c.a >= want:
		return
	_edge_img.set_pixel(x, y, Color(0.38, 0.62, 0.85, want))
	_edge_dirty = true


func _decay_edges() -> void:
	var any := false
	for y in _edge_rows:
		for x in _edge_cols:
			var c := _edge_img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var a: float = c.a * EDGE_DECAY
			_edge_img.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0 if a < 0.02 else a))
			any = true
	if any:
		_edge_dirty = true


func draw_ring(d: CanvasItem) -> void:
	if _t < 0.0 or _pts.size() < 2:
		return
	var k := clampf(_t / DURATION, 0.0, 1.0)
	var fade := pow(1.0 - k, 0.7)

	var prev := Vector2.ZERO
	var prev_energy := 0.0
	var prev_ok := false
	for i in _pts.size():
		var pt := _pts[i]
		var energy := _energies[i]
		var alpha := fade * 0.9 * energy

		if prev_ok and absf(energy - prev_energy) < 0.35:
			d.draw_line(prev, pt, Color(0.55, 0.88, 1.0, alpha), 5.0)
		else:
			d.draw_circle(pt, 3.0, Color(0.65, 0.92, 1.0, alpha))

		prev = pt
		prev_energy = energy
		prev_ok = true
