extends Node
## 图鉴自检：解锁、只提示一次、靠近机关触发、首页面板、存档持久化。
##   Godot_v4.7.2-stable_win64_console.exe --path <本目录> res://tools/codex_check.tscn

const MenuScript = preload("res://scripts/main_menu.gd")

var _fails := PackedStringArray()
var _pass := 0
var _signals := 0

func _check(cond: bool, ok: String, bad: String) -> void:
	if cond:
		_pass += 1
		print("PASS  ", ok)
	else:
		_fails.append(bad)
		print("FAIL  ", bad)

func _ready() -> void:
	var prog := get_node_or_null("/root/Progress")
	var codex := get_node_or_null("/root/Codex")
	_check(codex != null, "Codex 已注册", "缺少 Codex autoload")
	if codex == null or prog == null:
		_finish()
		return

	prog.set("save_dir", "user://saves_test")
	DirAccess.make_dir_recursive_absolute("user://saves_test")
	prog.set("persist", false)
	prog.set("codex", [])

	_check(codex.call("status").size() >= 11, "图鉴有 %d 条" % codex.call("status").size(),
		"图鉴条目太少")
	_check(not bool(codex.call("is_unlocked", "door")), "一开始门是锁着的", "一开始就解锁了")

	codex.discovered.connect(func(_e): _signals += 1)
	_check(bool(codex.call("unlock", "door")), "第一次遇到门：解锁", "解锁失败")
	_check(int(_signals) == 1, "解锁时发了一次提示信号", "提示信号次数不对：%d" % _signals)
	_check(not bool(codex.call("unlock", "door")), "同一项不会重复解锁", "重复解锁了")
	_check(int(_signals) == 1, "重复解锁不再提示", "重复弹了提示")
	_check(bool(prog.call("has_codex", "door")), "解锁写进了存档", "存档里没有")

	# 靠近机关自动解锁
	prog.set("level_index", 1)      # 第 2 关：门 + 钥匙
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	var lv: Node = ps.instantiate()
	add_child(lv)
	await get_tree().process_frame
	var doors: Array = lv.call("door_cells")
	var keys: Array = lv.call("key_cells")
	_check(doors.size() > 0 and keys.size() > 0, "第 2 关有门和钥匙",
		"第 2 关没有门/钥匙")
	if keys.size() > 0:
		# 用没解锁过的钥匙来测（门上面已经手动解锁过了，不会重复发信号）
		var k: Vector2i = keys[0]
		var p: Node2D = lv.get_node("Player")
		p.global_position = Vector2(k.x * 64 + 32, k.y * 64 + 32)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(bool(codex.call("is_unlocked", "key")), "靠近钥匙自动记进图鉴", "靠近钥匙没有解锁")

	# HUD 提示条
	var hud: Node = lv.get_node("HUD")
	var toast: Label = hud.get("_toast")
	_check(toast != null and toast.visible, "解锁时右上角弹出提示", "提示没有弹出来")

	# 游戏内图鉴面板（C 打开）：未解锁显示 ???
	prog.set("codex", ["door", "crate"])
	hud.set("_codex_open", true)
	hud.call("_update_codex_panel")
	await get_tree().process_frame
	var panel: PanelContainer = hud.get("_codex_panel")
	_check(panel.visible, "游戏内能打开图鉴", "图鉴面板没显示")

	var rows: VBoxContainer = hud.get("_codex_rows")
	await get_tree().process_frame
	var all_text := ""
	var icons := 0
	var hboxes := 0
	if rows != null:
		for c in rows.get_children():
			if c is Label:
				all_text += String(c.text) + "
"
			elif c is HBoxContainer:
				hboxes += 1
				for t in c.get_children():
					if String(t.get_class()).contains("IconRect") or t.get_script() != null:
						icons += 1
					if t is VBoxContainer:
						for l in t.get_children():
							if l is Label:
								all_text += String(l.text) + "
"
	_check(icons >= 11, "图鉴里有 %d 个图标" % icons, "图标数量不对：%d" % icons)
	_check(all_text.contains("门") and all_text.contains("？？？"), "图鉴同时显示已解锁与未解锁",
		"图鉴内容不对：%s" % all_text.left(80))
	_check(all_text.contains("机关") and all_text.contains("敌人"), "图鉴按类别分组", "没有分组")

	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://_verify/codex_icons.png")
	print("[shot] codex_icons.png")
	prog.set("persist", true)
	lv.queue_free()
	await get_tree().process_frame
	_finish()

func _finish() -> void:
	print("---- %d 项通过，%d 项失败" % [_pass, _fails.size()])
	get_tree().quit(0 if _fails.is_empty() else 1)
