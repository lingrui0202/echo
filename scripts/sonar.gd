extends PointLight2D
## 声呐脉冲：一盏从玩家身上扩散出去的点光源 + 一圈可见的波纹。
##
## 关键点：shadow_enabled = true 时，光会被 LightOccluder2D 挡住，
## 所以"回声"只会照亮真正能看见的地方 —— 这就是这个游戏的核心视觉。
##
## 调参提示（这就是你报告里的实验变量）：
##   DURATION  —— 一次回声持续多久
##   MAX_SCALE —— 回声能照多远（texture_scale 的倍数）

const DURATION := 1.05
const MAX_SCALE := 6.5
const MIN_SCALE := 0.3
const PEAK_ENERGY := 2.6

var _t := -1.0
var _radius_px := 128.0

func setup(tex: Texture2D) -> void:
	texture = tex
	_t = -1.0
	energy = 0.0
	texture_scale = MIN_SCALE
	queue_redraw()

func emit() -> void:
	_t = 0.0

func is_active() -> bool:
	return _t >= 0.0

func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	var k := clampf(_t / DURATION, 0.0, 1.0)
	var grow := sqrt(k)                      # 先快后慢，像真实的波前
	texture_scale = lerpf(MIN_SCALE, MAX_SCALE, grow)
	energy = (1.0 - k) * PEAK_ENERGY
	queue_redraw()
	if k >= 1.0:
		_t = -1.0
		energy = 0.0
		texture_scale = MIN_SCALE

func _draw() -> void:
	if _t < 0.0:
		return
	var k := clampf(_t / DURATION, 0.0, 1.0)
	var r := _radius_px * texture_scale
	var a := (1.0 - k) * 0.85
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, Color(0.5, 0.85, 1.0, a), 2.5, true)
