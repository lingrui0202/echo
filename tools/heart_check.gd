extends Node
## 心跳自检：生成出来的波形有没有声音、能不能播放

func _ready() -> void:
	var sfx := get_node_or_null("/root/Sfx")
	var p: AudioStreamPlayer = sfx.get("_players").get("heart")
	if p == null or p.stream == null:
		print("[heart] 没有心跳流")
		get_tree().quit(1)
		return
	var w: AudioStreamWAV = p.stream
	var data := w.data
	var peak := 0
	for i in range(0, data.size(), 2):
		var v := absi(data.decode_s16(i))
		peak = maxi(peak, v)
	print("[heart] 时长 %.2fs  峰值 %d/32767  采样率 %d" % [float(data.size()) / 2.0 / float(w.mix_rate), peak, w.mix_rate])
	w.save_to_wav("res://_verify/heart.wav")
	p.volume_db = 0.0
	sfx.call("heart")
	await get_tree().process_frame
	print("[heart] 正在播放: ", p.playing)
	get_tree().quit(0 if (peak > 8000 and p.playing) else 1)
