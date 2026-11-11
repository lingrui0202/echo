extends Node
## 词条：第 2 关开始，每关开局二选一。选完当关生效，下一关重新选。
##
## 设计意图：给「重玩」一点变化 —— 同一张图，这局轻装那局疾行，走法不一样。

const POOL := [
	[
		{"id": "quick", "title": "轻  装", "desc": "声呐冷却 −20%"},
		{"id": "swift", "title": "疾  行", "desc": "移动速度 +10%"},
	],
	[
		{"id": "quiet", "title": "省  电", "desc": "强声呐冷却 −30%"},
		{"id": "deaf", "title": "隔  音", "desc": "敌人听觉 −25%"},
	],
	[
		{"id": "swift", "title": "疾  行", "desc": "移动速度 +10%"},
		{"id": "sharp", "title": "冒  险", "desc": "声呐冷却 −35%，但敌人快 10%"},
	],
]

var current := ""
var pending := false
var choices: Array = []

func reset_for_level(idx: int) -> void:
	current = ""
	choices = []
	pending = idx > 0
	if pending:
		choices = POOL[(idx - 1) % POOL.size()]

func pick(slot: int) -> bool:
	if not pending or slot < 0 or slot >= choices.size():
		return false
	current = String(choices[slot]["id"])
	pending = false
	return true

func sonar_mul() -> float:
	match current:
		"quick":
			return 0.8
		"sharp":
			return 0.65
	return 1.0

func strong_mul() -> float:
	return 0.7 if current == "quiet" else 1.0

func speed_mul() -> float:
	return 1.1 if current == "swift" else 1.0

func enemy_hear_mul() -> float:
	return 0.75 if current == "deaf" else 1.0

func enemy_speed_mul() -> float:
	return 1.1 if current == "sharp" else 1.0

func label() -> String:
	return current if current != "" else "无"
