extends SceneTree
## 一次性验证脚本（不是游戏的一部分）。
## 用法：
##   Godot_v4.7.2-stable_win64_console.exe --path <项目目录> --script res://tools/capture.gd

const SHOT_FRAMES := {
	8: "0_dark",
	18: "1_early",
	32: "2_mid",
	60: "3_late",
	100: "4_after",
}

var _frames := 0
var _sonar: Node = null

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	root.add_child(ps.instantiate())

func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 10:
		var p := root.get_node_or_null("Level01/Player")
		if p != null:
			_sonar = p.get_node_or_null("Sonar")
		if _sonar != null:
			_sonar.emit()
			print("[capture] sonar emitted")

	if SHOT_FRAMES.has(_frames):
		var img := root.get_texture().get_image()
		img.save_png("res://_verify/shot_%s.png" % SHOT_FRAMES[_frames])
		var info := "n/a"
		if _sonar != null:
			info = "energy=%.3f scale=%.3f active=%s" % [
				_sonar.get("energy"), _sonar.get("texture_scale"), _sonar.call("is_active")
			]
		print("[capture] %s  sonar %s" % [SHOT_FRAMES[_frames], info])

	if _frames >= 104:
		return true
	return false
