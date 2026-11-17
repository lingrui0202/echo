extends RefCounted
## 全部图形都用矢量方式画，工程里仍然零图片资源。
## 玩家 / 敌人 / 门 / 钥匙 / 压力板 / 静音区 / 箱子 / 碎片 / 出口 各有一套形状，
## 世界里的实体和图鉴里的图标共用这里的函数，保证"图鉴里长什么样，场上就长什么样"。

const INK := Color(0.06, 0.07, 0.10, 0.9)

# ---------- 玩家 ----------
static func draw_player(c: CanvasItem, r: float, dir: Vector2) -> void:
	# 身体：中间实体 + 外圈呼吸环 + 朝向的小三角
	c.draw_circle(Vector2.ZERO, r * 0.62, Color(0.80, 0.92, 1.0))
	c.draw_circle(Vector2.ZERO, r * 0.42, Color(0.55, 0.78, 1.0))
	c.draw_arc(Vector2.ZERO, r * 0.95, 0.0, TAU, 36, Color(0.55, 0.82, 1.0, 0.75), 1.6, true)
	var d := dir.normalized() if dir.length() > 0.01 else Vector2.DOWN
	var tip := d * r * 1.05
	var side := d.orthogonal() * r * 0.26
	c.draw_colored_polygon(PackedVector2Array([
		tip, d * r * 0.55 + side, d * r * 0.55 - side,
	]), Color(0.85, 0.95, 1.0, 0.9))

# ---------- 敌人 ----------
## kind: 0 普通 / 1 瞎子 / 2 敏锐
static func draw_enemy(c: CanvasItem, r: float, kind: int, hot: bool, searching: bool) -> void:
	var body := Color(0.26, 0.07, 0.07)
	var edge := Color(0.70, 0.22, 0.20, 0.85)
	var eye := Color(1.0, 0.55, 0.45)
	if kind == 1:
		body = Color(0.20, 0.10, 0.30)
		edge = Color(0.62, 0.42, 0.92, 0.85)
		eye = Color(0.80, 0.65, 1.0)
	elif kind == 2:
		body = Color(0.30, 0.20, 0.05)
		edge = Color(0.92, 0.66, 0.20, 0.9)
		eye = Color(1.0, 0.85, 0.45)
	if hot:
		edge = edge.lightened(0.25)
		eye = Color(1, 1, 1)

	# 外壳：多边形的"甲壳"，敏锐者带尖角
	var n := 8
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n) + PI / 8.0
		var rr := r
		if kind == 2 and i % 2 == 0:
			rr = r * 1.35
		pts.append(Vector2(cos(a), sin(a)) * rr)
	c.draw_colored_polygon(pts, body)
	c.draw_polyline(pts + PackedVector2Array([pts[0]]), edge, 1.8, true)

	# 眼睛：普通是两只，瞎子是一条闭眼线，敏锐是三只
	if kind == 1:
		c.draw_line(Vector2(-r * 0.45, -r * 0.12), Vector2(r * 0.45, -r * 0.12), eye, 2.0)
	else:
		var ey := r * 0.30 if kind != 2 else r * 0.42
		c.draw_circle(Vector2(-r * 0.34, -r * 0.12), r * 0.15, eye)
		c.draw_circle(Vector2(r * 0.34, -r * 0.12), r * 0.15, eye)
		if kind == 2:
			c.draw_circle(Vector2(0, r * 0.30), r * 0.13, eye)

	# 状态：搜索时套一圈虚点
	if searching and not hot:
		for i in 10:
			var a2 := TAU * float(i) / 10.0
			c.draw_circle(Vector2(cos(a2), sin(a2)) * r * 1.5, 1.6, Color(1.0, 0.88, 0.40, 0.9))

# ---------- 机关 ----------
static func draw_door(c: CanvasItem, size: float) -> void:
	var h := size * 0.46
	# 门框
	c.draw_rect(Rect2(-h, -h, size * 0.92, size * 0.92), Color(0.72, 0.46, 0.14), true)
	c.draw_rect(Rect2(-h, -h, size * 0.92, size * 0.92), Color(1.0, 0.78, 0.42), false, 1.5)
	# 三道竖条
	for i in 3:
		var x := -h + size * 0.14 + float(i) * size * 0.24
		c.draw_rect(Rect2(x, -h + size * 0.10, size * 0.10, size * 0.72),
			Color(1.0, 0.86, 0.58, 0.85))
	# 锁孔
	c.draw_circle(Vector2(0, size * 0.02), size * 0.07, Color(0.20, 0.12, 0.05))

static func draw_key(c: CanvasItem, size: float, dim: bool = false) -> void:
	var col := Color(1.0, 0.86, 0.30) if not dim else Color(0.55, 0.48, 0.25)
	var r := size * 0.16
	c.draw_arc(Vector2(-size * 0.16, 0), r, 0, TAU, 20, col, 2.2, true)
	c.draw_line(Vector2(-size * 0.02, 0), Vector2(size * 0.30, 0), col, 2.2)
	c.draw_line(Vector2(size * 0.20, 0), Vector2(size * 0.20, size * 0.14), col, 2.2)
	c.draw_line(Vector2(size * 0.28, 0), Vector2(size * 0.28, size * 0.10), col, 2.2)

static func draw_plate(c: CanvasItem, size: float, active: bool) -> void:
	var h := size * 0.34
	var col := Color(0.35, 0.80, 1.0) if not active else Color(0.75, 1.0, 1.0)
	c.draw_rect(Rect2(-h, -h, h * 2, h * 2), Color(0.10, 0.22, 0.30), true)
	c.draw_rect(Rect2(-h, -h, h * 2, h * 2), col, false, 1.6)
	# 中间的向下箭头：表示"踩"
	c.draw_colored_polygon(PackedVector2Array([
		Vector2(-h * 0.5, -h * 0.2), Vector2(h * 0.5, -h * 0.2), Vector2(0, h * 0.5),
	]), col)

static func draw_silence(c: CanvasItem, size: float) -> void:
	var h := size * 0.42
	# 斜线底纹 + 虚线圈：能看出"这里吞声"
	c.draw_rect(Rect2(-h, -h, h * 2, h * 2), Color(0.30, 0.18, 0.52, 0.55), true)
	for i in 4:
		var x := -h + float(i) * h * 0.5
		c.draw_line(Vector2(x, h), Vector2(x + h * 0.5, -h), Color(0.70, 0.55, 1.0, 0.35), 1.2)
	for i in 12:
		var a := TAU * float(i) / 12.0
		c.draw_circle(Vector2(cos(a), sin(a)) * h * 0.92, 1.4, Color(0.85, 0.72, 1.0, 0.85))

static func draw_crate(c: CanvasItem, size: float) -> void:
	var h := size * 0.40
	c.draw_rect(Rect2(-h, -h, h * 2, h * 2), Color(0.52, 0.40, 0.24), true)
	c.draw_rect(Rect2(-h, -h, h * 2, h * 2), Color(0.82, 0.66, 0.42), false, 1.6)
	# 交叉木条
	c.draw_line(Vector2(-h, -h), Vector2(h, h), Color(0.72, 0.56, 0.34), 1.6)
	c.draw_line(Vector2(h, -h), Vector2(-h, h), Color(0.72, 0.56, 0.34), 1.6)

static func draw_fragment(c: CanvasItem, size: float) -> void:
	var d := size * 0.42
	var pts := PackedVector2Array([Vector2(0, -d), Vector2(d * 0.72, 0), Vector2(0, d), Vector2(-d * 0.72, 0)])
	c.draw_colored_polygon(pts, Color(0.30, 0.95, 0.80, 0.85))
	c.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.75, 1.0, 0.95), 1.6, true)
	# 切面高光
	c.draw_line(Vector2(0, -d), Vector2(0, d), Color(0.85, 1.0, 0.98, 0.65), 1.1)

static func draw_goal(c: CanvasItem, size: float) -> void:
	var d := size * 0.40
	# 外圈光晕：出口是全黑里唯一需要"一眼看到"的东西
	c.draw_circle(Vector2.ZERO, d * 1.75, Color(0.35, 1.0, 0.65, 0.10))
	c.draw_circle(Vector2.ZERO, d * 1.30, Color(0.40, 1.0, 0.70, 0.18))
	var pts := PackedVector2Array([Vector2(0, -d), Vector2(d, 0), Vector2(0, d), Vector2(-d, 0)])
	c.draw_colored_polygon(pts, Color(0.42, 1.0, 0.68, 1.0))
	c.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.92, 1.0, 0.96), 2.4, true)
	# 内芯
	var inner := PackedVector2Array([
		Vector2(0, -d * 0.45), Vector2(d * 0.45, 0), Vector2(0, d * 0.45), Vector2(-d * 0.45, 0),
	])
	c.draw_colored_polygon(inner, Color(0.95, 1.0, 0.98, 0.95))
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI / 4.0
		c.draw_line(Vector2(cos(a), sin(a)) * d * 0.95, Vector2(cos(a), sin(a)) * d * 1.55,
			Color(0.70, 1.0, 0.85, 0.75), 1.8)
	# 直接在图下标「出口」：玩家一进关就知道这个绿菱形是什么
	var font := ThemeDB.fallback_font
	var pos := Vector2(-13.0, d + 19.0)
	c.draw_string_outline(font, pos, "出口", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5,
		Color(0.01, 0.03, 0.02, 0.95))
	c.draw_string(font, pos, "出口", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.72, 1.0, 0.84))


## 声呐：中心一点 + 三圈逐渐变淡的弧（强声呐用橙色、圈更大）
static func draw_sonar(c: CanvasItem, size: float, strong: bool = false) -> void:
	var col := Color(1.0, 0.78, 0.42) if strong else Color(0.55, 0.88, 1.0)
	var r := size * 0.10 if strong else size * 0.09
	c.draw_circle(Vector2.ZERO, r, col)
	for i in 3:
		var rr := size * (0.20 + 0.13 * float(i))
		var a := 0.85 - 0.22 * float(i)
		c.draw_arc(Vector2.ZERO, rr, -PI * 0.75, PI * 0.75, 20, Color(col.r, col.g, col.b, a), 2.0, true)
		c.draw_arc(Vector2.ZERO, rr, PI * 0.25, PI * 1.25, 20, Color(col.r, col.g, col.b, a * 0.5), 1.4, true)


## 统一入口：按名字画一个图标（图鉴也用这个）
static func draw_icon(c: CanvasItem, id: String, size: float, active: bool = false) -> void:
	match id:
		"player":
			draw_player(c, size * 0.5, Vector2.DOWN)
		"enemy_normal":
			draw_enemy(c, size * 0.42, 0, false, false)
		"enemy_blind":
			draw_enemy(c, size * 0.42, 1, false, false)
		"enemy_sharp":
			draw_enemy(c, size * 0.42, 2, false, false)
		"door":
			draw_door(c, size * 0.92)
		"key":
			draw_key(c, size * 0.9)
		"plate":
			draw_plate(c, size * 0.9, active)
		"silence":
			draw_silence(c, size * 0.9)
		"crate":
			draw_crate(c, size * 0.9)
		"fragment":
			draw_fragment(c, size * 0.9)
		"goal":
			draw_goal(c, size * 0.9)
		"sonar":
			draw_sonar(c, size * 0.9, false)
		"strong":
			draw_sonar(c, size * 0.9, true)
		_:
			c.draw_circle(Vector2.ZERO, size * 0.25, Color(0.6, 0.6, 0.7))
