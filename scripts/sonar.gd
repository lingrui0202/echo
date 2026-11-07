extends PointLight2D
## 声呐的"余晖"：一盏很淡的径向补光，让刚扫过的区域慢一点变黑。
##
## 真正的波前不在这里，在 scripts/sonar_wave.gd（几何线 + 反射）。
## 第 6 周把波前改成几何线后，这盏灯里的 Wave 子灯和圆形光环就成了死代码
## （RING_PEAK 恒为 0、_draw 是空的），一起删掉了，省得两套覆盖范围打架。
##
## 半径对齐：
##   余晖  256 * MAX_SCALE 5.25 = 1344 px 直径 → 672 px 半径
##   波前  420 px/s × 1.6 s                 → 672 px 半径
## 两者一样大，看上去才是"波推过去、身后留一点余晖"，而不是波还没到远处就先亮一片。
##
## shadow_enabled = true，余晖同样被墙挡住。
##
## 调参：DURATION 余晖留多久，FILL_PEAK 余晖多亮（0.12 很淡，别抢波前的戏）。

const DURATION := 1.05
const MAX_SCALE := 5.25
const MIN_SCALE := 0.3
const FILL_PEAK := 0.12

var _t := -1.0

func setup(fill_tex: Texture2D) -> void:
	texture = fill_tex
	_t = -1.0
	energy = 0.0
	texture_scale = MIN_SCALE

func emit() -> void:
	_t = 0.0

func is_active() -> bool:
	return _t >= 0.0

func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	var k := clampf(_t / DURATION, 0.0, 1.0)
	texture_scale = lerpf(MIN_SCALE, MAX_SCALE, sqrt(k))   # 先快后慢，像真实的波前
	energy = (1.0 - k) * FILL_PEAK
	if k >= 1.0:
		_t = -1.0
		energy = 0.0
		texture_scale = MIN_SCALE
