extends SceneTree
## 功能测试：把玩家瞬移到出口格，确认 Area2D 检测 → Player.win() → GameLog 记录 这条链真的通。
## 用法：
##   Godot_v4.7.2-stable_win64_console.exe --path <项目目录> --script res://tools/test_win.gd

const CELL := 64
const EXIT_CELL := Vector2i(29, 15)     # 必须和 level.gd 地图里的 'E' 位置一致

var _frames := 0
var _player: Node2D = null

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	root.add_child(ps.instantiate())

func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 5:
		_player = root.get_node_or_null("Level01/Player")
		if _player == null:
			print("FAIL: 找不到 Player")
			return true
		_player.global_position = Vector2(EXIT_CELL.x * CELL + CELL * 0.5, EXIT_CELL.y * CELL + CELL * 0.5)
		print("[test] 玩家已瞬移到出口 ", EXIT_CELL)

	if _frames == 20:
		var gl := root.get_node_or_null("GameLog")
		var reason: String = String(gl.get("last_reason")) if gl != null else "<no autoload>"
		if reason == "win":
			print("PASS: 走到出口触发通关，GameLog.last_reason = win")
		else:
			print("FAIL: last_reason = ", reason)
		return true
	return false
