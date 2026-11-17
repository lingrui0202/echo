extends Node
## 程序化音效：不依赖任何音频素材，运行时合成几声短音。
##
## 黑暗里听觉比画面重要：声呐 ping、强声呐的低频、被抓住的一声闷响。
## 用 AudioStreamWAV 直接塞 PCM，避免引入 .wav 资源（和"零图片资源"一个思路）。

const RATE := 22050

var _players := {}

func _ready() -> void:
	_add("ping", _tone(880.0, 0.22, 0.35, 520.0))
	_add("strong", _tone(300.0, 0.5, 0.5, 90.0))
	_add("caught", _tone(140.0, 0.6, 0.6, 70.0))
	_add("win", _tone(660.0, 0.45, 0.4, 990.0))
	# 心跳：低频、很短，靠间隔表达"还有多远"
	_add("heart", _tone(56.0, 0.17, 0.95, 38.0))
	_add("frag", _tone(1046.0, 0.30, 0.35, 1568.0))
	_add("step", _tone(180.0, 0.07, 0.18, 120.0))
	_add("hit", _tone(90.0, 0.35, 0.55, 55.0))
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

func play(name: String) -> void:
	var p: AudioStreamPlayer = _players.get(name)
	if p != null:
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
