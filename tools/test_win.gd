extends SceneTree
## 功能测试：把玩家瞬移到出口格，确认 Area2D 检测 → Player.win() → GameLog 记录 → 结算面板 这条链真的通。
## 用法：
##   Godot_v4.7.2-stable_win64_console.exe --path <项目目录> --script res://tools/test_win.gd
##
## 顺带把结算面板截下来：_verify/win_panel.png

const CELL := 64
const EXIT_CELL := Vector2i(26, 14)     # 仅当关卡没有暴露 _goal_cell 时兜底

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
		# 出口格从关卡里读，别和 level.gd 的 MAP 各写一份
		var cell := EXIT_CELL
		var level := root.get_node_or_null("Level01")
		if level != null:
			var v: Variant = level.get("_goal_cell")
			if v is Vector2i and (v as Vector2i).x >= 0:
				cell = v
		_player.global_position = Vector2(cell.x * CELL + CELL * 0.5, cell.y * CELL + CELL * 0.5)
		print("[test] 玩家已瞬移到出口 ", cell)

	if _frames == 20:
		var gl := root.get_node_or_null("GameLog")
		var reason: String = String(gl.get("last_reason")) if gl != null else "<no autoload>"
		if reason == "win":
			print("PASS: 走到出口触发通关，GameLog.last_reason = win")
		else:
			print("FAIL: last_reason = ", reason)

	if _frames == 34:
		var hud := root.get_node_or_null("Level01/HUD")
		var panel_visible := false
		if hud != null:
			var p = hud.get("_result")
			panel_visible = p != null and p.visible
		root.get_texture().get_image().save_png("res://_verify/win_panel.png")
		print("[test] 结算面板 visible = ", panel_visible, "，截图 _verify/win_panel.png")
		return true
	return false
