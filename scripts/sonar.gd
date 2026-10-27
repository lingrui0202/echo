extends PointLight2D
## 声呐脉冲：向外推的一圈波前 + 一层很淡的余辉。
##
## 第 5 周试玩反馈："应该是波形向外，而不是中间亮四周暗"。
## 所以这里拆成两盏灯：
##   自己      —— 径向补光，energy 很低，只让扫过的区域留一点余辉
##   Wave 子灯 —— 环状贴图，energy 高，跟同一个 texture_scale 向外扩，这才是"波前"
##
## shadow_enabled = true，光会被 LightOccluder2D 挡住，所以波前只在真正看得到的地方出现。
##
## 调参提示：
##   DURATION  —— 一次回声持续多久
##   MAX_SCALE —— 回声能照多远（texture_scale 的倍数）
##   FILL_PEAK / RING_PEAK —— 余辉多亮 / 波前多亮

const DURATION := 1.05
const MAX_SCALE := 6.5
const MIN_SCALE := 0.3
const FILL_PEAK := 0.55
const RING_PEAK := 3.2

var _t := -1.0
var _radius_px := 128.0
var _wave: PointLight2D = null

func setup(fill_tex: Texture2D, ring_tex: Texture2D) -> void:
	texture = fill_tex
	if _wave == null:
		_wave = PointLight2D.new()
		_wave.name = "Wave"
		_wave.shadow_enabled = true
		_wave.color = Color(0.55, 0.88, 1.0)
		add_child(_wave)
	_wave.texture = ring_tex
	_wave.energy = 0.0
	_wave.texture_scale = MIN_SCALE
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
	energy = (1.0 - k) * FILL_PEAK
	if _wave != null:
		_wave.texture_scale = texture_scale
		_wave.energy = (1.0 - k) * RING_PEAK
	queue_redraw()
	if k >= 1.0:
		_t = -1.0
		energy = 0.0
		texture_scale = MIN_SCALE
		if _wave != null:
			_wave.energy = 0.0

func _draw() -> void:
	if _t < 0.0:
		return
	var k := clampf(_t / DURATION, 0.0, 1.0)
	var r := _radius_px * texture_scale
	var a := (1.0 - k) * 0.9
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 128, Color(0.55, 0.88, 1.0, a), 3.0, true)
