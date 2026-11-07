extends Node
## 工程自检（不是游戏的一部分）：不靠人工操作，跑关键断言 + 波前耗时采样 + 敌人链路。
##
## 用法（场景方式，不依赖 --script）：
##   Godot_v4.7.2-stable_win64_console.exe --path <本目录> res://tools/selfcheck.tscn
##
## 输出：
##   _verify/selfcheck.txt           文字结果与耗时
##   _verify/selfcheck_wave.png      声呐波前
##   _verify/selfcheck_enemy.png     敌人（红光 + 本体）
##   _verify/selfcheck_win.png       通关结算
##   _verify/selfcheck_caught.png    被抓结算
##
## 判据：关卡 / 相机 / 遥测 config / 波前 / 敌人出生点 / 听觉 / 被抓链路。
## 全部 PASS 时进程返回 0。

const CELL := 64
const MAP_W := 61
const MAP_H := 34
const Maze = preload("res://scripts/maze.gd")

var _level: Node2D
var _player: Node2D
var _cam: Camera2D
var _enemies: Array = []
var _fails := PackedStringArray()
var _frames := 0
var _ring_us := 0.0
var _decay_us := 0.0
var _spawn_text := ""
var _probe_enemy: Node2D = null
var _probe_from := Vector2.ZERO
var _route_len := 0
var _route_min := 9999

func _ready() -> void:
	var ps: PackedScene = load("res://scenes/Level01.tscn")
	_level = ps.instantiate()
	_level.name = "Level01"
	add_child(_level)

func _check(cond: bool, ok: String, bad: String) -> void:
	if cond:
		print("PASS  ", ok)
	else:
		_fails.append(bad)
		print("FAIL  ", bad)

func _process(_delta: float) -> void:
	_frames += 1
	match _frames:
		2:
			_check_static()
		4:
			_check_runtime()
		12:
			_check_movement()
		60:
			_capture("res://_verify/selfcheck_wave.png")
		62:
			_move_near_enemy()
		64:
			_capture("res://_verify/selfcheck_enemy.png")
		65:
			_fake_win()
		67:
			_check_hud("win")
			_capture("res://_verify/selfcheck_win.png")
		69:
			_setup_caught()
		76:
			_check_caught()
			_capture("res://_verify/selfcheck_caught.png")
		78:
			_report()
			get_tree().quit(0 if _fails.is_empty() else 1)

func _capture(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(path)

func _check_static() -> void:
	_player = _level.get_node_or_null("Player")
	_check(_player != null, "Player 节点存在", "找不到 Player")
	if _player == null:
		return

	var walls := _level.get_node_or_null("Walls")
	_check(walls != null and walls.get_child_count() > 0,
		"墙体已生成（%d 个）" % (walls.get_child_count() if walls != null else 0),
		"墙体没生成")

	var goal: Variant = _level.get("_goal_cell")
	_check(goal is Vector2i and goal == Vector2i(26, 14),
		"出口格 = (26, 14)", "出口格不对：%s" % str(goal))

	_check(_level.get_node_or_null("Darkness") != null,
		"全黑层 CanvasModulate 已创建", "缺少全黑层")

	_cam = _player.get_node_or_null("Camera2D") as Camera2D
	_check(_cam != null and _cam.limit_right == MAP_W * CELL and _cam.limit_bottom == MAP_H * CELL,
		"相机限位 = %d×%d px" % [MAP_W * CELL, MAP_H * CELL],
		"相机限位不对：%s" % (str(_cam.limit_right) + "×" + str(_cam.limit_bottom) if _cam != null else "无相机"))
	_check(_cam != null and _cam.position_smoothing_enabled,
		"相机平滑已开启", "相机平滑没开")

	var wave := _level.get_node_or_null("SonarWave")
	_check(wave != null, "SonarWave 节点存在", "缺少 SonarWave")

	var gl := get_node_or_null("/root/GameLog")
	var cfg: Dictionary = gl.config if gl != null else {}
	_check(is_equal_approx(float(cfg.get("sonar_cooldown", 0.0)), 1.8),
		"遥测 config 记录冷却 1.8 s", "config 里没有正确的 sonar_cooldown：%s" % str(cfg))
	_check(int(cfg.get("map_w", 0)) == MAP_W and int(cfg.get("map_h", 0)) == MAP_H,
		"遥测 config 记录地图 %d×%d" % [MAP_W, MAP_H], "config 地图尺寸不对：%s" % str(cfg))
	_check(int(cfg.get("enemy_count", 0)) == 2,
		"遥测 config 记录敌人 2 只", "config 里的 enemy_count 不对：%s" % str(cfg))
	_check(is_equal_approx(float(cfg.get("enemy_hear_radius", 0.0)), 700.0),
		"遥测 config 记录听觉半径 700 px", "config 里的 enemy_hear_radius 不对：%s" % str(cfg))
	_check(is_equal_approx(float(cfg.get("enemy_speed", 0.0)), 110.0),
		"遥测 config 记录敌人速度 110 px/s", "config 里的 enemy_speed 不对：%s" % str(cfg))

	var box := _level.get_node_or_null("Enemies")
	var count := box.get_child_count() if box != null else 0
	_check(count == 2, "敌人已生成 2 只", "敌人数量不对：%d" % count)
	if box != null:
		_enemies = box.get_children()
	if _enemies.is_empty():
		return

	var rows: Array = _level.map_rows()
	var start: Vector2i = _level.start_cell()
	var goal_cell: Vector2i = _level.get("_goal_cell")
	var dist := Maze.distances(rows, start)
	var player_cell := Vector2i((_player.global_position / CELL).floor())
	var parts := PackedStringArray()
	for e in _enemies:
		var c: Vector2i = e.get("_home")
		parts.append("%s/%d步" % [str(c), int(dist.get(c, 0))])
		_check(Maze.is_open(rows, c), "敌人出生点 %s 在空地上" % str(c), "敌人出生点 %s 在墙里" % str(c))
		_check(dist.has(c) and int(dist[c]) >= 20,
			"敌人出生点 %s 距起点 %d 步" % [str(c), int(dist.get(c, 0))],
			"敌人出生点离起点太近：%s" % str(c))
		_check(c != goal_cell, "敌人没有站在出口上", "敌人出生点和出口重合")
		_check(not Maze.path(rows, c, player_cell).is_empty(),
			"从 %s 能走到玩家出生点" % str(c), "敌人出生点不可达")
	_spawn_text = ", ".join(parts)

	# 玩家实际会走的路线：最短路上离敌人最近多少格？
	# 这个数太大就说明敌人根本不在玩家会经过的地方（玩的时候看不见）。
	var route := Maze.path(rows, start, goal_cell)
	_route_len = route.size()
	for c in route:
		for e in _enemies:
			var ec: Vector2i = e.get("_home")
			_route_min = mini(_route_min, int(c.distance_to(ec)))
	_check(_route_min >= 1,
		"敌人不在最短路上（离路线最近 %d 格）" % _route_min,
		"敌人挡在最短路上：最近 %d 格" % _route_min)

func _check_runtime() -> void:
	if _enemies.is_empty():
		return
	var e: Node = _enemies[0]
	_check(not e.is_chasing(), "初始状态：敌人没在追", "敌人一开始就在追")
	e.hear(e.global_position + Vector2(2000, 0))
	_check(not e.is_chasing(), "听觉半径外：不追", "超出听觉半径仍然追击")
	e.hear(e.global_position + Vector2(100, 0))
	_check(e.is_chasing(), "听觉半径内：开始追", "在听觉半径内没有追击")
	_reset_enemy(e)

	# 端到端：声呐广播 → 敌人听见 → 朝开放邻格走（第 12 帧再验位移）
	var gl := get_node_or_null("/root/GameLog")
	var alerts_before := int(gl.get("alert_count")) if gl != null else 0
	var home: Vector2i = e.get("_home")
	var rows: Array = _level.map_rows()
	var target_pos: Vector2 = e.global_position
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = home + dir
		if Maze.is_open(rows, n):
			target_pos = Vector2(n.x * CELL + CELL * 0.5, n.y * CELL + CELL * 0.5)
			break
	_probe_enemy = e
	_probe_from = e.global_position
	_level.emit_wave(target_pos)
	_check(e.is_chasing(), "声呐广播能惊动敌人", "声呐广播没有惊动敌人")
	_check(gl != null and int(gl.get("alert_count")) > alerts_before,
		"被听见次数 +1", "遥测没有记录被听见")

	# 最后在玩家位置发一次，给截图用（同时测波前）
	_level.emit_wave(_player.global_position)
	var wave := _level.get_node_or_null("SonarWave")
	if wave == null:
		return
	for i in 3:
		wave._process(0.1)
	_check(wave._pts.size() == 221,
		"波前采样点 %d 个" % wave._pts.size(),
		"波前采样点数量不对：%d" % wave._pts.size())
	wave._t = 0.5
	var t0 := Time.get_ticks_usec()
	for i in 60:
		wave._compute_ring()
	_ring_us = float(Time.get_ticks_usec() - t0) / 60.0
	t0 = Time.get_ticks_usec()
	for i in 60:
		wave._decay_edges()
	_decay_us = float(Time.get_ticks_usec() - t0) / 60.0

func _reset_enemy(e: Node) -> void:
	e.set("_has_target", false)
	e.set("_chase_left", 0.0)
	e.set("_path", [])

## 第 12 帧：确认敌人在收到声呐后真的动了（不是只把标志位翻了一下）。
func _check_movement() -> void:
	if _probe_enemy == null:
		return
	var moved := _probe_enemy.global_position.distance_to(_probe_from)
	_check(moved > 0.5, "敌人会沿路径移动（%.1f px）" % moved, "敌人听到了但没有移动")
	_reset_enemy(_probe_enemy)
	var home: Vector2i = _probe_enemy.get("_home")
	_probe_enemy.global_position = Vector2(home.x * CELL + CELL * 0.5, home.y * CELL + CELL * 0.5)
	_probe_enemy = null

func _move_near_enemy() -> void:
	if _enemies.is_empty() or _player == null:
		return
	var e: Node2D = _enemies[0]
	# 站到同一格边缘：看得见敌人，又不触发 20 px 的接触判定
	_player.global_position = e.global_position + Vector2(30, 0)
	if _cam != null:
		_cam.reset_smoothing()

func _fake_win() -> void:
	var gl := get_node_or_null("/root/GameLog")
	if gl != null:
		gl.set("last_reason", "win")

func _setup_caught() -> void:
	var gl := get_node_or_null("/root/GameLog")
	if gl != null:
		gl.set("persist", false)     # 自检不写 runs.json
	if not _enemies.is_empty():
		_player.global_position = _enemies[0].global_position

func _check_caught() -> void:
	var gl := get_node_or_null("/root/GameLog")
	_check(_player.get("_alive") == false, "被抓后玩家停止", "被抓后玩家还能动")
	_check(gl != null and String(gl.get("last_reason")) == "caught",
		"遥测 reason = caught", "被抓后 reason 不是 caught")
	_check_hud("caught")
	if gl != null:
		gl.set("persist", true)

func _check_hud(reason: String) -> void:
	var hud := _level.get_node_or_null("HUD")
	var hint: Variant = hud.get("_hint") if hud != null else null
	var result: Variant = hud.get("_result") if hud != null else null
	var body_label: Variant = hud.get("_result_text") if hud != null else null
	var hint_s := String(hint.text) if hint != null else ""
	var body := String(body_label.text) if body_label != null else ""
	# 第 7 周修的就是这个：之前 tail 里又拼了一遍「[R] 重开」
	_check(hint_s.count("[R] 重开") == 1,
		"HUD 里「[R] 重开」只出现一次", "HUD 重开提示重复：%s" % hint_s)
	_check(result != null and result.visible,
		"结算面板已弹出（%s）" % reason, "结算面板没弹（%s）" % reason)
	if reason == "win":
		_check(hint_s.contains("通关！") and body.begins_with("通  关"),
			"结算文案 = 通关", "通关文案不对：%s" % body)
	else:
		_check(hint_s.contains("被听见了") and body.contains("被 听 见 了"),
			"结算文案 = 被听见了", "被抓文案不对：%s" % body)

func _report() -> void:
	var lines := PackedStringArray()
	lines.append("Echo selfcheck  %s" % Time.get_datetime_string_from_system())
	lines.append("波前 _compute_ring   %.0f µs/帧（221 条射线，最多 5 次反射）" % _ring_us)
	lines.append("边界记忆 _decay_edges %.0f µs/次（每 4 帧一次，122×68 像素）" % _decay_us)
	lines.append("敌人出生格           %s" % _spawn_text)
	lines.append("最短路 %d 步；路径上离敌人最近 %d 格" % [_route_len, _route_min])
	if _fails.is_empty():
		lines.append("PASS: 全部通过")
	else:
		for msg in _fails:
			lines.append("FAIL: " + msg)
	var txt := "\n".join(lines)
	print(txt)
	# Godot 的 stdout 在管道里是块缓冲，写文件最稳。
	var f := FileAccess.open("res://_verify/selfcheck.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(txt + "\n")
