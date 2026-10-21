extends Node2D
## 关卡：从一张 ASCII 地图生成碰撞体 + 光照遮挡体 + 视觉。
##
## 为什么用 ASCII 而不是在编辑器里手摆 200 个 StaticBody2D？
##   1. 改关卡 = 改几行字符串，一眼能看懂
##   2. 碰撞体和遮挡体永远对得上（手摆最容易漏）
##   3. 答辩时能讲清"数据驱动"这件事
##
## 地图规则：
##   '#' = 墙     '.' = 地面
##   'E' = 出口
## 起点在 START 里改。边界墙由代码自动补齐，不用写。

const LightFactory = preload("res://scripts/light_factory.gd")
const GridScript = preload("res://scripts/grid.gd")

const CELL := 64
const START := Vector2i(1, 1)

const MAP := [
	"..............................",
	"..............................",
	"....##......##......##....##..",
	"....##......##......##....##..",
	"....########........####......",
	"..............................",
	"........##......##.....##.....",
	"........##......##.....##.....",
	"..############......####......",
	"..............................",
	"....##......##......##.....##.",
	"....##......##......##.....##.",
	"......####........####........",
	"..............................",
	"........##......##......##....",
	"........##......##......##...E",
]

func _ready() -> void:
	_build()

func _build() -> void:
	var walls: Node2D = $Walls
	var width := 0
	for row in MAP:
		width = maxi(width, row.length())
	var height: int = MAP.size()

	_add_ground(width, height)

	# 内部墙：把每行里连续的 '#' 合并成一条长条，减少节点数、光照更干净
	for y in height:
		var row: String = MAP[y]
		var x := 0
		while x < row.length():
			var c := row[x]
			if c == "#":
				var x0 := x
				while x < row.length() and row[x] == "#":
					x += 1
				_add_wall(walls, x0, y, x - x0, 1)
			else:
				if c == "E":
					_add_goal(x, y)
				x += 1

	# 边界墙
	_add_wall(walls, -1, -1, width + 2, 1)
	_add_wall(walls, -1, height, width + 2, 1)
	_add_wall(walls, -1, 0, 1, height)
	_add_wall(walls, width, 0, 1, height)

	var player: Node2D = $Player
	player.global_position = Vector2(START.x * CELL + CELL * 0.5, START.y * CELL + CELL * 0.5)

func _add_ground(width: int, height: int) -> void:
	var size := Vector2(width * CELL, height * CELL)

	# 纯色地板：本身很暗，只有被光照到才会显出来
	var floor_poly := Polygon2D.new()
	floor_poly.polygon = PackedVector2Array([
		Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y)
	])
	floor_poly.color = Color(0.22, 0.25, 0.34)
	floor_poly.z_index = -10
	add_child(floor_poly)

	var grid := GridScript.new()
	grid.cells = Vector2i(width, height)
	grid.cell = float(CELL)
	grid.z_index = -9
	add_child(grid)

func _add_wall(parent: Node2D, cx: int, cy: int, cw: int, ch: int) -> void:
	var size := Vector2(cw * CELL, ch * CELL)
	var body := StaticBody2D.new()
	body.position = Vector2(cx * CELL, cy * CELL) + size * 0.5
	body.collision_layer = 1
	body.collision_mask = 0

	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)

	# 遮挡体：必须顺时针。y 轴向下，"上左→上右→下右→下左"就是顺时针。
	var pts := PackedVector2Array([
		Vector2(-size.x, -size.y) * 0.5,
		Vector2(size.x, -size.y) * 0.5,
		Vector2(size.x, size.y) * 0.5,
		Vector2(-size.x, size.y) * 0.5,
	])
	var poly := OccluderPolygon2D.new()
	poly.polygon = pts
	var occ := LightOccluder2D.new()
	occ.occluder = poly
	body.add_child(occ)

	var vis := Polygon2D.new()
	vis.polygon = pts
	vis.color = Color(0.82, 0.90, 1.0)
	body.add_child(vis)

	parent.add_child(body)

func _add_goal(cx: int, cy: int) -> void:
	var area := Area2D.new()
	area.position = Vector2(cx * CELL, cy * CELL) + Vector2(CELL, CELL) * 0.5
	area.collision_layer = 4
	area.collision_mask = 2

	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(CELL * 0.8, CELL * 0.8)
	cs.shape = shape
	area.add_child(cs)

	var d := CELL * 0.28
	var vis := Polygon2D.new()
	vis.polygon = PackedVector2Array([Vector2(0, -d), Vector2(d, 0), Vector2(0, d), Vector2(-d, 0)])
	vis.color = Color(0.30, 1.0, 0.65)
	area.add_child(vis)

	# 出口自己是弱光源，黑暗中像一个灯塔
	var glow := PointLight2D.new()
	glow.texture = LightFactory.radial_texture(128)
	glow.energy = 0.55
	glow.texture_scale = 0.9
	glow.color = Color(0.4, 1.0, 0.7)
	area.add_child(glow)

	area.body_entered.connect(_on_goal_entered)
	add_child(area)

func _on_goal_entered(body: Node2D) -> void:
	if body.has_method("win"):
		body.win()
