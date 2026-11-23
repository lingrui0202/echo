extends Node
## 程序化音效：不依赖任何音频素材，运行时合成几声短音。
##
## 黑暗里听觉比画面重要：声呐 ping、强声呐的低频、被抓住的一声闷响。
## 用 AudioStreamWAV 直接塞 PCM，避免引入 .wav 资源（和"零图片资源"一个思路）。

const RATE := 22050

## 优先级：数字大的先响。低优先级的音如果碰上刚响起的高优先级音，就让位。
## caught/hit（被抓）> heart（心跳）> frag/win（奖励）> ping/strong（发声）> exitpulse（出口）> step（脚步）
const PRIORITY := {
	"caught": 9, "hit": 9, "win": 8, "heart": 7, "frag": 6,
	"strong": 5, "ping": 5, "exitpulse": 3, "step": 1, "ambient": 0,
}
const BLOCK_MS := 260        # 高优先级音响起后多久内，低优先级让位
const SAME_GAP_MS := 70      # 同一个音的最小重触发间隔

var _players := {}

func _ready() -> void:
	_add("ping", _tone(880.0, 0.22, 0.35, 520.0))
	_add("strong", _tone(300.0, 0.5, 0.5, 90.0))
	_add("caught", _tone(140.0, 0.6, 0.6, 70.0))
	_add("win", _tone(660.0, 0.45, 0.4, 990.0))
	# 心跳：低频、很短，靠间隔表达"还有多远"
	_add("heart", _tone(58.0, 0.15, 0.88, 42.0))
	_add("frag", _tone(1046.0, 0.30, 0.35, 1568.0))
	_add("step", _tone(180.0, 0.07, 0.18, 120.0))
	_add("hit", _tone(90.0, 0.35, 0.55, 55.0))
	_add("exitpulse", _tone(150.0, 0.42, 0.42, 104.0))
	_add("ambient", _loop_tone(46.0, 3.0, 0.10))

func _tone(freq: float, dur: float, amp: float, end_freq: float = -1.0) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(RATE)
		var f := freq if end_freq < 0.0 else lerpf(freq, end_freq, t / dur)
		var env := exp(-5.0 * t / dur) * (1.0 - exp(-60.0 * t))   # 起音快、余音衰减
		var v: float = sin(TAU * f * t) * env * amp
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w

## 循环低频环境音
func _loop_tone(freq: float, dur: float, amp: float) -> AudioStreamWAV:
	var w := _tone(freq, dur, amp)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = int(RATE * dur)
	return w


func _add(name: String, stream: AudioStreamWAV) -> void:
	var p := AudioStreamPlayer.new()
	p.name = name
	p.stream = stream
	p.volume_db = -6.0
	add_child(p)
	_players[name] = p

var _last_ms := {}


func play(name: String) -> void:
	var p: AudioStreamPlayer = _players.get(name)
	if p == null:
		return
	var now := Time.get_ticks_msec()
	var pri := int(PRIORITY.get(name, 3))

	# 同一个音不要叠着炸（脚步之类高频音）
	var last_same := int(_last_ms.get(name, -9999))
	if now - last_same < SAME_GAP_MS:
		return
	# 刚响过更高优先级的音，就安静让位
	for other in _last_ms.keys():
		if other == name:
			continue
		if int(PRIORITY.get(other, 3)) > pri and now - int(_last_ms[other]) < BLOCK_MS:
			return

	_last_ms[name] = now
	p.play()
	# 发声/被抓时环境低频让路，避免糊成一片
	if pri >= 7:
		_duck_ambient()


## 进/出静音区：环境音变闷（压低 + 慢速衰减）
func set_muffled(on: bool) -> void:
	var amb: AudioStreamPlayer = _players.get("ambient")
	if amb == null:
		return
	var t := create_tween()
	t.tween_property(amb, "volume_db", -24.0 if on else -10.0, 0.35)


func _duck_ambient() -> void:
	var amb: AudioStreamPlayer = _players.get("ambient")
	if amb == null:
		return
	amb.volume_db = -26.0
	var t := create_tween()
	t.tween_interval(0.18)
	t.tween_property(amb, "volume_db", -10.0, 0.5)

## 出口的呼吸声：越近越响（volume_db 由调用方给）
func exit_pulse(volume_db: float = -6.0) -> void:
	var p: AudioStreamPlayer = _players.get("exitpulse")
	if p == null:
		return
	p.volume_db = volume_db
	p.play()


func ping() -> void:
	play("ping")

func strong() -> void:
	play("strong")

func caught() -> void:
	play("caught")

func win() -> void:
	play("win")

func heart() -> void:
	var p: AudioStreamPlayer = _players.get("heart")
	if p != null:
		p.volume_db = 2.0
	play("heart")

func step() -> void:
	play("step")

func hit() -> void:
	play("hit")

func start_ambient() -> void:
	var p: AudioStreamPlayer = _players.get("ambient")
	if p != null and not p.playing:
		p.volume_db = -20.0
		p.play()
