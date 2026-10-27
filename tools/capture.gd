extends SceneTree
## 一次性验证脚本（不是游戏的一部分）：离屏跑关卡，在几个时间点截图。
## 用法：
##   Godot_v4.7.2-stable_win64.exe --path <项目目录> --script res://tools/capture.gd
##
## 注意：这里一律按真实时间卡点，不按帧数。帧数会随机器负载变化，
## 之前就出现过"声呐还在亮就拍了最后一张"的假象。

const T_DARK := 150          # ms：还没发声呐
const T_EMIT := 250          # ms：发光呐
const T_EARLY := 250         # 发出后多少 ms 拍"早期"
const T_MID := 600
const T_LATE := 1000
const T_AFTER := 300         # 声呐彻底结束之后再等多久

var _t0 := 0
var _emitted_at := -1
var _sonar: Node = null
var _shots := {}

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	root.add_child(ps.instantiate())
	_t0 = Time.get_ticks_msec()

func _ms() -> int:
	return Time.get_ticks_msec() - _t0

func _shot(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("res://_verify/shot_%s.png" % name)
	var info := "n/a"
	if _sonar != null:
		info = "energy=%.3f scale=%.3f active=%s" % [
			_sonar.get("energy"), _sonar.get("texture_scale"), _sonar.call("is_active")
		]
	print("[capture] %s  sonar %s" % [name, info])

func _process(_delta: float) -> bool:
	if _sonar == null:
		var p := root.get_node_or_null("Level01/Player")
		if p != null:
			_sonar = p.get_node_or_null("Sonar")

	if _ms() >= T_DARK and not _shots.has("0_dark"):
		_shots["0_dark"] = true
		_shot("0_dark")

	if _ms() >= T_EMIT and _emitted_at < 0:
		_emitted_at = _ms()
		if _sonar != null:
			_sonar.emit()
			print("[capture] sonar emitted")

	if _emitted_at >= 0:
		var since := _ms() - _emitted_at
		if since >= T_EARLY and not _shots.has("1_early"):
			_shots["1_early"] = true
			_shot("1_early")
		if since >= T_MID and not _shots.has("2_mid"):
			_shots["2_mid"] = true
			_shot("2_mid")
		if since >= T_LATE and not _shots.has("3_late"):
			_shots["3_late"] = true
			_shot("3_late")
		if (since >= T_LATE + T_AFTER and _sonar != null
				and not _sonar.call("is_active") and not _shots.has("4_after")):
			_shots["4_after"] = true
			_shot("4_after")
			return true
	return false
