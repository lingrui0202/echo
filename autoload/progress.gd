extends Node
## 存档：多槽位，每个槽记录「打到第几关、什么时候保存、通了哪几关」。
## 文件放 user://saves/<id>.json；槽位清单按最后保存时间倒序。
##
## 兼容旧接口：can_select / select_level / record_clear / best_time / is_cleared / advance / reset。

const TOTAL := 5
const DIR := "user://saves"
const LEGACY := "user://progress.json"

var unlocked := 0
var level_index := 0
var cleared := {}
var persist := true

var save_dir := DIR
var slot_id := ""
var created_at := 0.0
var updated_at := 0.0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)
	_load_last_or_legacy()

# ---------------- 槽位 ----------------

## 开一个新槽：清空进度，从第 1 关开始
func new_save() -> void:
	slot_id = _next_id()
	created_at = Time.get_unix_time_from_system()
	unlocked = 0
	level_index = 0
	cleared = {}
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

func load_save(id: String) -> bool:
	var d := _read(_path(id))
	if d.is_empty():
		return false
	slot_id = id
	created_at = float(d.get("created", 0.0))
	updated_at = float(d.get("updated", 0.0))
	unlocked = clampi(int(d.get("unlocked", 0)), 0, TOTAL - 1)
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
func _next_id() -> String:
	return "save_%d_%03d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec() % 1000]


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

	new_save()
