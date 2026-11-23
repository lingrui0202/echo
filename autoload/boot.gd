extends Node
## 输入映射在代码里注册，而不是写进 project.godot。
## 好处：不依赖 tscn / project.godot 的序列化格式，改键位只看这一个文件。

func _ready() -> void:
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("move_up", [KEY_W, KEY_UP])
	_bind("move_down", [KEY_S, KEY_DOWN])
	_bind("sonar", [KEY_SPACE])
	_bind("strong_sonar", [KEY_E])
	_bind("resonance", [KEY_Q])
	_bind("settings", [KEY_ESCAPE])
	_bind("slot_1", [KEY_1])
	_bind("slot_2", [KEY_2])
	_bind("slot_3", [KEY_3])
	_bind("slot_4", [KEY_4])
	_bind("slot_5", [KEY_5])
	_bind("slot_6", [KEY_6])
	_bind("slot_7", [KEY_7])
	_bind("slot_8", [KEY_8])
	_bind("slot_9", [KEY_9])
	_bind("slot_0", [KEY_0])
	_bind("codex", [KEY_C])
	_bind("page_prev", [KEY_LEFT])
	_bind("page_next", [KEY_RIGHT])
	_bind("confirm", [KEY_ENTER, KEY_KP_ENTER])
	_bind("restart", [KEY_R])
	_bind("stats", [KEY_TAB])
	_apply_ui_theme()

## F11：全屏 / 窗口切换（演示、投影时用；不写进设置文件）
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_F11:
		var win := get_window()
		if win == null:
			return
		if win.mode == Window.MODE_FULLSCREEN:
			win.mode = Window.MODE_WINDOWED
		else:
			win.mode = Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()


## 全局字体：Godot 自带字体渲染中文偏细、字重不统一，换成系统中文字体
func _apply_ui_theme() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC", "PingFang SC",
	])
	var th := Theme.new()
	th.default_font = f
	th.default_font_size = 16
	var root := get_tree().root if get_tree() != null else null
	if root != null and "theme" in root:
		root.theme = th


func _bind(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
