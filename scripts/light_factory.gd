extends RefCounted
## 运行时生成一张径向渐变贴图，给 PointLight2D 用。
## 这样工程里不需要任何图片资源文件 —— 美术成本为零。
##
## 用法：const LightFactory = preload("res://scripts/light_factory.gd")
## 这里故意不用 class_name —— class_name 依赖编辑器生成的全局类缓存，
## 用 preload 常量在哪都能解析，更稳。

static func radial_texture(size: int = 256) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 0.75))

	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t
