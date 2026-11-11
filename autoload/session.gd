extends Node
## 这次运行处于什么模式：正式存档（campaign）还是测试（test）。
## 测试模式不写存档、不给词条、引导关不弹 —— 和正式存档完全隔开。

enum Mode { CAMPAIGN, TEST }

var mode := Mode.CAMPAIGN
## 新手引导是否显示：只有"新存档的第一关"才显示
var tutorial := false

func is_test() -> bool:
	return mode == Mode.TEST

func start_campaign(new_game: bool) -> void:
	mode = Mode.CAMPAIGN
	Progress.reload()          # 回到磁盘上的真实存档（可能刚从测试模式出来）
	Progress.persist = true
	GameLog.persist = true
	GameLog.mode_tag = "campaign"
	if new_game:
		Progress.new_save()          # 开一个新槽，从第 1 关开始
		tutorial = true
	else:
		tutorial = not Progress.is_cleared(0)
	get_tree().call_deferred("change_scene_to_file", "res://scenes/Level01.tscn")

## 测试：五关全开、没有词条、不碰存档
func start_test(level_index: int = 0) -> void:
	mode = Mode.TEST
	Progress.reload()
	Progress.persist = false
	GameLog.persist = false       # 测试模式不写遥测，免得污染排行榜
	GameLog.mode_tag = "test"
	Progress.level_index = clampi(level_index, 0, Progress.TOTAL - 1)
	tutorial = false
	get_tree().call_deferred("change_scene_to_file", "res://scenes/Level01.tscn")

func quit_to_menu() -> void:
	Progress.save_now()              # 回首页前先落盘
	Progress.reload()
	Progress.persist = true
	GameLog.persist = true
	GameLog.mode_tag = "campaign"
	mode = Mode.CAMPAIGN
	get_tree().call_deferred("change_scene_to_file", "res://scenes/MainMenu.tscn")

func quit_game() -> void:
	get_tree().quit()
