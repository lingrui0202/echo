extends SceneTree
## 亮度对照工具（不是游戏的一部分）：同一张关卡，跑三种"黑暗档位"，各拍两张。
##   一张是没发声呐（只看常亮光圈），一张是声呐最亮的那一帧。
## 用法：
##   Godot_v4.7.2-stable_win64_console.exe --path <工程目录> --script res://tools/darkness_shots.gd
##
## 产出：_verify/dark_<tag>_idle.png、_verify/dark_<tag>_sonar.png

const PRESETS := [
	{"tag": "A_now", "mod": Color(0.05, 0.055, 0.09), "amb_r": 128, "amb_e": 0.9},
	{"tag": "B_dark", "mod": Color(0.03, 0.033, 0.05), "amb_r": 72, "amb_e": 0.55},
	{"tag": "C_black", "mod": Color(0.015, 0.017, 0.028), "amb_r": 40, "amb_e": 0.30},
]

const BLOCK := 70          # 每个档位占多少帧
const SONAR_AT := 12       # 发光呐
const SONAR_SHOT := 45     # 拍"声呐中"

var _f := 0
var _level: Node = null
var _player: Node = null
var _sonar: Node = null
var _mod: CanvasModulate = null
var _done: Array = []

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	_level = ps.instantiate()
	root.add_child(_level)

func _apply(p: Dictionary) -> void:
	var light: PointLight2D = _player.get_node("AmbientLight")
	light.texture = load("res://scripts/light_factory.gd").radial_texture(p["amb_r"])
	light.energy = p["amb_e"]
	light.texture_scale = 1.0
	_mod.color = p["mod"]

func _shot(tag: String, suffix: String) -> void:
	var img := root.get_texture().get_image()
	var path := "res://_verify/dark_%s_%s.png" % [tag, suffix]
	img.save_png(path)
	print("[dark] saved ", path)

func _process(_delta: float) -> bool:
	_f += 1

	for i in PRESETS.size():
		var base: int = i * BLOCK
		var p: Dictionary = PRESETS[i]
		if _f == base + 2:
			if _player == null:
				_player = _level.get_node("Player")
				_sonar = _player.get_node("Sonar")
				_mod = _level.get_node("CanvasModulate")
			_player.global_position = Vector2(96, 96)
			_apply(p)
		if _f == base + 8:
			_shot(p["tag"], "idle")
		if _f == base + SONAR_AT:
			_sonar.emit()
		if _f == base + SONAR_SHOT:
			_shot(p["tag"], "sonar")
		if _f == base + SONAR_SHOT + 2:
			_sonar.set("energy", 0.0)
			_sonar.set("texture_scale", 0.3)
			_sonar.set("_t", -1.0)

	if _f > PRESETS.size() * BLOCK:
		print("[dark] done ", PRESETS.size(), " presets")
		return true
	return false
