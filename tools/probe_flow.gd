extends SceneTree
## 端到端探针：首页 → 新存档 → 游戏里按 7 → 应该回到首页。
##   Godot_v4.7.2-stable_win64_console.exe --path <本目录> --script res://tools/probe_flow.gd

var _t := 0.0
var _stage := 0

func _initialize() -> void:
	change_scene_to_file("res://scenes/MainMenu.tscn")

func _process(delta: float) -> bool:
	_t += delta
	match _stage:
		0:
			if _t > 0.5:
				print("[flow] 当前场景 = ", current_scene.scene_file_path if current_scene else "null")
				_stage = 1
				_t = 0.0
		1:
			# 模拟「新存档」
			if _t > 0.2:
				root.get_node("/root/Session").start_campaign(true)
				_stage = 2
				_t = 0.0
		2:
			if _t > 0.8:
				print("[flow] 进入游戏后场景 = ", current_scene.scene_file_path if current_scene else "null")
				var hud: Node = current_scene.get_node_or_null("HUD")
				if hud != null:
					hud.set("_settings_open", true)
				_stage = 3
				_t = 0.0
		3:
			if _t > 0.2:
				print("[flow] 按 7")
				Input.action_press("slot_7")
				_stage = 4
				_t = 0.0
		4:
			if _t > 0.1:
				Input.action_release("slot_7")
				_stage = 5
				_t = 0.0
		5:
			if _t > 0.8:
				var path := current_scene.scene_file_path if current_scene else "null"
				print("[flow] 按 7 之后场景 = ", path)
				if String(path).contains("MainMenu"):
					print("PASS: 7 回到了首页")
					quit(0)
				else:
					print("FAIL: 7 没有回到首页（当前 %s）" % path)
					quit(1)
				return true
	return false
