extends Node
## 成就：每局结束算一次，达成条件就记进存档。
## 条件都基于「这一局的记录 + 存档累计」，不放模糊判断。

const LIST := [
	{"id": "first_clear", "name": "初次回声", "desc": "通关第 1 关"},
	{"id": "all_clear", "name": "十次回声", "desc": "通关全部 10 关"},
	{"id": "silent_run", "name": "静默行者", "desc": "一局不用声呐就通关"},
	{"id": "no_alert", "name": "没人听见", "desc": "通关且全程没被听见"},
	{"id": "loud", "name": "声呐全开", "desc": "一局发声呐 20 次以上还通关"},
	{"id": "s_rank", "name": "快到回声", "desc": "拿到 S 评价"},
	{"id": "keymaster", "name": "开锁匠", "desc": "拿到钥匙开门"},
	{"id": "frag10", "name": "拾荒者", "desc": "累计收集 10 枚碎片"},
	{"id": "frag30", "name": "收藏家", "desc": "累计收集 30 枚碎片"},
	{"id": "veteran", "name": "老规矩", "desc": "累计玩满 20 局"},
]

func _ready() -> void:
	var gl := get_node_or_null("/root/GameLog")
	if gl != null:
		gl.run_finished.connect(_on_run)

func _on_run(rec: Dictionary) -> void:
	var prog := get_node_or_null("/root/Progress")
	if prog == null:
		return
	prog.total_runs += 1
	prog.total_sonar += int(rec.get("sonar_presses", 0))
	prog.total_alerts += int(rec.get("alerts", 0))
	var win := String(rec.get("reason", "")) == "win"
	if win:
		prog.total_wins += 1
		var sonar := int(rec.get("sonar_presses", 0))
		var alerts := int(rec.get("alerts", 0))
		var lvl := int((rec.get("config", {}) as Dictionary).get("level_index", 0))
		if lvl == 0:
			_unlock("first_clear")
		if sonar == 0:
			_unlock("silent_run")
		if alerts == 0:
			_unlock("no_alert")
		if sonar >= 20:
			_unlock("loud")
		if String(rec.get("grade", "")) == "S":
			_unlock("s_rank")
		if int(rec.get("keys", 0)) > 0:
			_unlock("keymaster")
		if prog.cleared.size() >= prog.TOTAL:
			_unlock("all_clear")
	if prog.fragments >= 10:
		_unlock("frag10")
	if prog.fragments >= 30:
		_unlock("frag30")
	if prog.total_runs >= 20:
		_unlock("veteran")
	prog.save_now()

func _unlock(id: String) -> void:
	var prog := get_node_or_null("/root/Progress")
	if prog != null:
		prog.unlock_achv(id)

func status() -> Array:
	var prog := get_node_or_null("/root/Progress")
	var out: Array = []
	for a in LIST:
		out.append({
			"id": a["id"], "name": a["name"], "desc": a["desc"],
			"got": prog != null and prog.has_achv(String(a["id"])),
		})
	return out
