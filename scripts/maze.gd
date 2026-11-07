extends RefCounted
## 格子地图上的 BFS。敌人寻路和出生点选择共用，避免两套坐标各自实现。
##
## 地图是 Array[String]：'#' 是墙，其余（'.'、'E'）都可走。
## 说明：这里不依赖 Godot 的 Navigation，因为 MAP 本身就是权威数据，
## 运行时烘焙导航反而多一层不一致。

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

static func is_open(rows: Array, c: Vector2i) -> bool:
	if c.y < 0 or c.y >= rows.size():
		return false
	var row: String = rows[c.y]
	if c.x < 0 or c.x >= row.length():
		return false
	return row[c.x] != "#"

## 从 start 做 BFS，返回 {Vector2i: 步数}，只含可达格。
static func distances(rows: Array, start: Vector2i) -> Dictionary:
	var dist := {start: 0}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var next_d: int = int(dist[cur]) + 1
		for dir in DIRS:
			var nxt: Vector2i = cur + dir
			if dist.has(nxt) or not is_open(rows, nxt):
				continue
			dist[nxt] = next_d
			queue.append(nxt)
	return dist

## 最短路径：不含起点、含终点；不可达或原地返回空数组。
static func path(rows: Array, from: Vector2i, to: Vector2i) -> Array:
	if from == to:
		return []
	if not is_open(rows, from) or not is_open(rows, to):
		return []
	var came := {from: from}
	var queue: Array = [from]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if cur == to:
			break
		for dir in DIRS:
			var nxt: Vector2i = cur + dir
			if came.has(nxt) or not is_open(rows, nxt):
				continue
			came[nxt] = cur
			queue.append(nxt)
	if not came.has(to):
		return []
	var out: Array = []
	var walk: Vector2i = to
	while walk != from:
		out.push_front(walk)
		walk = came[walk]
	return out
