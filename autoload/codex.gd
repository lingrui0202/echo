extends Node
## 图鉴：机关、道具、敌人。第一次遇到才解锁，解锁时弹一条提示。
##
## 解锁写进存档（Progress.codex），换存档会重新解锁 —— 每个档各自的认知进度。

signal discovered(entry: Dictionary)

const LIST := [
	# 机关
	{"id": "door", "cat": "机关", "name": "门", "desc": "关着的时候是墙：挡人、挡光、也挡敌人的路。拿到钥匙才会开。"},
	{"id": "key", "cat": "机关", "name": "钥匙", "desc": "踩到就收，一次开掉这一关所有的门。"},
	{"id": "plate", "cat": "机关", "name": "压力板", "desc": "踩一次就永久打开它最近的那扇门。蓝色的，踩下去会变亮。"},
	{"id": "silence", "cat": "机关", "name": "静音区", "desc": "在里面发声：回声只走得动一点点，敌人完全听不见。安全，但基本看不见路。"},
	# 目标
	{"id": "goal", "cat": "目标", "name": "出口", "desc": "绿色菱形，一进关就淡淡地亮着。被声呐扫到或走近之后转亮，并永久标在小地图上。"},
	# 道具
	{"id": "crate", "cat": "机关", "name": "木箱", "desc": "挡路的箱子，朝它走就能推一格。它也挡光 —— 推它会改变回声的形状。"},
	{"id": "fragment", "cat": "道具", "name": "回声碎片", "desc": "绿色的菱形碎片。每关 3 枚，多藏在死胡同里；每 3 枚永久提升一次能力。"},
	# 能力
	{"id": "sonar", "cat": "能力", "name": "声呐（空格）", "desc": "推出一圈波，撞墙会折回来。这是你在黑暗里唯一的眼睛，但敌人也听得见。"},
	{"id": "strong", "cat": "能力", "name": "强声呐（E）", "desc": "范围更大、多反射一次、橙色。代价是全场敌人不管多远都会听见。冷却 6 秒。"},
	# 敌人
	{"id": "enemy_normal", "cat": "敌人", "name": "听声者", "desc": "红色的敌人。700 px 内听见你的声呐就追 5.5 秒，追丢会在原地搜一会儿。"},
	{"id": "enemy_blind", "cat": "敌人", "name": "瞎子", "desc": "紫色的敌人。普通声呐它听不见，只有强声呐能惊动 —— 但它跑得比同类快。"},
	{"id": "enemy_sharp", "cat": "敌人", "name": "敏锐者", "desc": "橙色的敌人。听觉范围是同类 1.35 倍，追得也比同类久。"},
]

func _ready() -> void:
	pass

func entry(id: String) -> Dictionary:
	for e in LIST:
		if String(e["id"]) == id:
			return e
	return {}

## 第一次遇到：解锁 + 发信号（HUD 会弹提示）
func unlock(id: String) -> bool:
	var prog := get_node_or_null("/root/Progress")
	if prog == null:
		return false
	if prog.has_codex(id):
		return false
	prog.unlock_codex(id)
	var e := entry(id)
	if not e.is_empty():
		discovered.emit(e)
	return true

func is_unlocked(id: String) -> bool:
	var prog := get_node_or_null("/root/Progress")
	return prog != null and prog.has_codex(id)

## 图鉴面板用：[{id, cat, name, desc, got}]
func status() -> Array:
	var prog := get_node_or_null("/root/Progress")
	var out: Array = []
	for e in LIST:
		out.append({
			"id": String(e["id"]), "cat": String(e["cat"]),
			"name": String(e["name"]), "desc": String(e["desc"]),
			"got": prog != null and prog.has_codex(String(e["id"])),
		})
	return out

func unlocked_count() -> int:
	var n := 0
	for e in LIST:
		if is_unlocked(String(e["id"])):
			n += 1
	return n
