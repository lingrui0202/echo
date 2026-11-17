extends Node
## 存档：多槽位，每个槽记录「打到第几关、什么时候保存、通了哪几关」。
## 文件放 user://saves/<id>.json；槽位清单按最后保存时间倒序。
##
## 兼容旧接口：can_select / select_level / record_clear / best_time / is_cleared / advance / reset。

const TOTAL := 10
const DIR := "user://saves"
const LEGACY := "user://progress.json"

var unlocked := 0
var level_index := 0
var cleared := {}
var persist := true

var save_dir := DIR
var fragments := 0            # 总碎片数（永久）
var achv: Array = []          # 已解锁成就 id
var codex: Array = []         # 已解锁图鉴 id
var total_runs := 0
var total_wins := 0
var total_sonar := 0
var total_alerts := 0
var taken := {}               # 关卡 -> ["x,y", ...] 已经拿过的碎片
var slot_id := ""
var created_at := 0.0
var updated_at := 0.0

func _ready() -> void:
	if _should_use_test_dir():
		save_dir = "user://saves_test"      # 自检绝不碰玩家存档
	DirAccess.make_dir_recursive_absolute(save_dir)
	# 自检不能继承上一次跑剩下的临时存档：清空后从零开始，
	# 否则「上一轮捡过的碎片/通过的关卡」会影响这一轮的结果
	if _should_use_test_dir():
		_wipe_dir(save_dir)
		slot_id = ""
		level_index = 0
		cleared = {}
		taken = {}
		fragments = 0
		codex = []
		achv = []
		total_runs = 0
		total_wins = 0
		total_sonar = 0
		total_alerts = 0
	_load_last_or_legacy()

## 跑测试时 Godot 会把 res://tools/xxx.tscn 或 --script 的路径放进命令行参数
func _should_use_test_dir() -> bool:
	for a in OS.get_cmdline_args():
		if a == "--test" or a.contains("res://tools/"):
			return true
	return false

# ---------------- 槽位 ----------------

## 开一个新槽：清空进度，从第 1 关开始
func new_save() -> void:
	slot_id = _next_id()
	created_at = Time.get_unix_time_from_system()
	unlocked = 0
	level_index = 0
	cleared = {}
	fragments = 0
	taken = {}
	achv = []
	codex = []
	total_runs = 0
	total_wins = 0
	total_sonar = 0
	total_alerts = 0
	save_now()

## 保存当前槽（时间戳也刷新）
func save_now() -> void:
	if not persist or slot_id == "":
		return
	updated_at = Time.get_unix_time_from_system()
	var f := FileAccess.open(_path(slot_id), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({
			"id": slot_id,
			"created": created_at,
			"updated": updated_at,
			"unlocked": unlocked,
			"level_index": level_index,
			"cleared": cleared,
			"fragments": fragments,
			"taken": taken,
			"achv": achv,
			"codex": codex,
			"total_runs": total_runs,
			"total_wins": total_wins,
			"total_sonar": total_sonar,
			"total_alerts": total_alerts,
		}))

## 所有槽位，按最后保存时间倒序：[{id, updated, level, cleared_count, finished}]
func list_saves() -> Array:
	var out: Array = []
	var dir := DirAccess.open(save_dir)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".json"):
			var d := _read(save_dir + "/" + name)
			if not d.is_empty():
				out.append({
					"id": String(d.get("id", name.get_basename())),
					"created": float(d.get("created", 0.0)),
					"updated": float(d.get("updated", 0.0)),
					"level": int(d.get("level_index", 0)),
					"cleared_count": (d.get("cleared", {}) as Dictionary).size(),
					"finished": int(d.get("level_index", 0)) >= TOTAL - 1
						and (d.get("cleared", {}) as Dictionary).size() >= TOTAL,
				})
		name = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a, b):
		if float(a["updated"]) != float(b["updated"]):
			return float(a["updated"]) > float(b["updated"])
		return String(a["id"]) > String(b["id"]))   # 同一毫秒内按 id 兜底
	return out

## 删掉一个槽；删的是当前槽就清空当前状态
func delete_save(id: String) -> bool:
	if not FileAccess.file_exists(_path(id)):
		return false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path(id)))
	if id == slot_id:
		slot_id = ""
		level_index = 0
		unlocked = 0
		cleared = {}
		fragments = 0
		taken = {}
		codex = []
		achv = []
		total_runs = 0
		total_wins = 0
		total_sonar = 0
		total_alerts = 0
	return true


func load_save(id: String) -> bool:
	var d := _read(_path(id))
	if d.is_empty():
		return false
	slot_id = id
	created_at = float(d.get("created", 0.0))
	updated_at = float(d.get("updated", 0.0))
	unlocked = clampi(int(d.get("unlocked", 0)), 0, TOTAL - 1)
	fragments = int(d.get("fragments", 0))
	achv = d.get("achv", []) if typeof(d.get("achv", [])) == TYPE_ARRAY else []
	codex = d.get("codex", []) if typeof(d.get("codex", [])) == TYPE_ARRAY else []
	total_runs = int(d.get("total_runs", 0))
	total_wins = int(d.get("total_wins", 0))
	total_sonar = int(d.get("total_sonar", 0))
	total_alerts = int(d.get("total_alerts", 0))
	taken = {}
	var tk: Variant = d.get("taken", {})
	if typeof(tk) == TYPE_DICTIONARY:
		for k in tk.keys():
			taken[int(k)] = tk[k]
	level_index = clampi(int(d.get("level_index", 0)), 0, TOTAL - 1)
	cleared = {}
	var c: Variant = d.get("cleared", {})
	if typeof(c) == TYPE_DICTIONARY:
		for k in c.keys():
			var rec: Variant = c[k]
			if rec is Dictionary and float(rec.get("time", 0.0)) >= 3.0:
				cleared[int(k)] = rec
	return true

## 同一秒里连开两个存档也不能撞 id
var _seq := 0

func _next_id() -> String:
	_seq += 1
	return "save_%d_%03d" % [int(Time.get_unix_time_from_system()), _seq]


## 这一关还有哪几枚碎片没拿
func is_fragment_taken(level_idx: int, key: String) -> bool:
	var arr: Variant = taken.get(level_idx)
	return arr is Array and arr.has(key)

func has_codex(id: String) -> bool:
	return codex.has(id)

func unlock_codex(id: String) -> bool:
	if codex.has(id):
		return false
	codex.append(id)
	save_now()
	return true


func has_achv(id: String) -> bool:
	return achv.has(id)

func unlock_achv(id: String) -> bool:
	if achv.has(id):
		return false
	achv.append(id)
	save_now()
	return true

func fragments_taken(level_idx: int) -> int:
	var arr: Variant = taken.get(level_idx)
	return arr.size() if arr is Array else 0

func take_fragment(level_idx: int, key: String) -> bool:
	if is_fragment_taken(level_idx, key):
		return false
	var arr: Array = taken.get(level_idx, [])
	arr.append(key)
	taken[level_idx] = arr
	# 自检只验"这一局能不能捡到"，不往玩家的总碎片/升级里记
	if not _scoring():
		return true
	fragments += 1
	save_now()
	return true


## 是否在"给玩家记账"：自检 / 测试目录下统统不记账
func _scoring() -> bool:
	return persist and not _should_use_test_dir()

## 永久升级：每 3 枚一档
func upgrade_tier() -> int:
	return mini(fragments / 3, 3)

## 强声呐冷却倍率（3 枚 -0.15，6 枚 -0.3，9 枚 -0.45）
func cooldown_bonus() -> float:
	return [0.0, 0.15, 0.3, 0.45][upgrade_tier()]

## 光圈半径加成（3/6/9 枚 +6/+12/+18 px）
func light_bonus() -> int:
	return [0, 6, 12, 18][upgrade_tier()]

func slot_summary() -> String:
	if slot_id == "":
		return "没有当前存档"
	return "%s · 第 %d 关 · 已通 %d/%d" % [
		_time_text(updated_at), level_index + 1, cleared.size(), TOTAL]

## unix 时间戳 → 本地时间文本（之前直接转是 UTC，差了 8 小时）
func _time_text(ts: float) -> String:
	if ts <= 0.0:
		return "未知时间"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(int(ts) + bias)
	return "%02d-%02d %02d:%02d" % [d["month"], d["day"], d["hour"], d["minute"]]

# ---------------- 进度 ----------------

func can_select(i: int) -> bool:
	return i >= 0 and i < TOTAL

func select_level(i: int) -> bool:
	if not can_select(i):
		return false
	level_index = i
	save_now()
	return true

func next_index() -> int:
	return mini(level_index + 1, TOTAL - 1)

func prev_index() -> int:
	return maxi(level_index - 1, 0)

func record_clear(idx: int, duration: float, grade: String) -> void:
	var old: Variant = cleared.get(idx)
	if old == null or duration < float(old.get("time", INF)):
		cleared[idx] = {"time": snappedf(duration, 0.01), "grade": grade}
	unlocked = maxi(unlocked, mini(idx + 1, TOTAL - 1))
	save_now()

func best_time(idx: int) -> float:
	var r: Variant = cleared.get(idx)
	return float(r.get("time", -1.0)) if r != null else -1.0

func best_grade(idx: int) -> String:
	var r: Variant = cleared.get(idx)
	return String(r.get("grade", "-")) if r != null else "-"

func is_cleared(idx: int) -> bool:
	return cleared.has(idx)

## 返回 true 表示还有下一关
func advance() -> bool:
	if level_index + 1 < TOTAL:
		level_index += 1
		save_now()
		return true
	return false

func reset() -> void:
	level_index = 0
	unlocked = 0
	cleared = {}
	save_now()

## 从磁盘重读当前槽（测试模式结束后用）
func reload() -> void:
	if slot_id != "":
		load_save(slot_id)

# ---------------- 读写 ----------------

func _path(id: String) -> String:
	return save_dir + "/" + id + ".json"

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if typeof(d) == TYPE_DICTIONARY else {}

## 启动时：有槽就载入最近一个；没有就迁移旧的 progress.json；再没有就开一个新槽
func _load_last_or_legacy() -> void:
	var list := list_saves()
	if not list.is_empty():
		load_save(String(list[0]["id"]))
		return

	if FileAccess.file_exists(LEGACY):
		var d := _read(LEGACY)
		slot_id = _next_id()
		created_at = Time.get_unix_time_from_system()
		unlocked = clampi(int(d.get("unlocked", 0)), 0, TOTAL - 1)
		level_index = clampi(int(d.get("level_index", 0)), 0, TOTAL - 1)
		var c: Variant = d.get("cleared", {})
		if typeof(c) == TYPE_DICTIONARY:
			for k in c.keys():
				var rec: Variant = c[k]
				if rec is Dictionary and float(rec.get("time", 0.0)) >= 3.0:
					cleared[int(k)] = rec
		save_now()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY))
		return

	# 没有存档也不自动建：否则每跑一次游戏/测试就多一个空槽
	slot_id = ""
	level_index = 0
	unlocked = 0
	cleared = {}


## 删除某个目录下的所有存档文件（只用于自检的临时目录）
func _wipe_dir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if n.ends_with(".json"):
			d.remove(n)
		n = d.get_next()
	d.list_dir_end()
