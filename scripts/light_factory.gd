extends RefCounted
## 运行时生成光斑贴图，给 PointLight2D 用 —— 工程里不需要任何图片资源。
##
## 两种：
##   radial_texture() 中心亮、向外渐隐（补光用，别拿它当声呐）
##   ring_texture()   一圈亮带、中心留暗（"看得见边界的光圈"和"波前"用）
##
## 用法：const LightFactory = preload("res://scripts/light_factory.gd")
## 这里故意不用 class_name —— class_name 依赖编辑器全局类缓存，preload 常量在哪都能解析。

static func radial_texture(size: int = 256) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 0.75))

	return _texture(g, size)


## 一圈亮带：center_alpha 是正中间的残留亮度（0=纯黑心），带子峰值在 peak 处。
static func ring_texture(size: int = 256, center_alpha: float = 0.12,
		peak: float = 0.86) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, peak * 0.55, peak, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, center_alpha),
		Color(1, 1, 1, center_alpha * 0.5),
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.0),
	])
	return _texture(g, size)


static func _texture(g: Gradient, size: int) -> GradientTexture2D:
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t
