extends Node
## 输入映射在代码里注册，而不是写进 project.godot。
## 好处：不依赖 tscn / project.godot 的序列化格式，改键位只看这一个文件。

func _ready() -> void:
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("move_up", [KEY_W, KEY_UP])
	_bind("move_down", [KEY_S, KEY_DOWN])
	_bind("sonar", [KEY_SPACE])
	_bind("restart", [KEY_R])
	_bind("stats", [KEY_TAB])

func _bind(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
