# -*- coding: utf-8 -*-
"""生成 2 格宽通道的迷宫。

布局：逻辑格 2x2 字符 + 1 字符墙 → 地图边长 = 逻辑数*3+1。
这样走廊宽 128px（两格），波在里面的反射比 1 格走廊好看得多。

用法：python make_maze2.py [seed]
"""
import random
import sys
from collections import deque

W, H = 20, 11          # 逻辑格
CELL = 2               # 每个逻辑格占几字符
GAP = 1                # 墙厚
SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 5

rnd = random.Random(SEED)
gw = W * (CELL + GAP) + GAP
gh = H * (CELL + GAP) + GAP
grid = [["#"] * gw for _ in range(gh)]


def block(x, y):
    """逻辑格 (x,y) 的 2x2 区域起点"""
    return GAP + x * (CELL + GAP), GAP + y * (CELL + GAP)


def carve_cell(x, y):
    bx, by = block(x, y)
    for dy in range(CELL):
        for dx in range(CELL):
            grid[by + dy][bx + dx] = "."


def carve_pass(a, b):
    ax, ay = block(*a)
    bx, by = block(*b)
    if ax == bx:            # 上下相邻
        y0 = min(ay + CELL - 1, by + CELL - 1) + 1
        for dy in range(GAP):
            for dx in range(CELL):
                grid[y0 + dy][ax + dx] = "."
    else:                   # 左右相邻
        x0 = min(ax + CELL - 1, bx + CELL - 1) + 1
        for dx in range(GAP):
            for dy in range(CELL):
                grid[ay + dy][x0 + dx] = "."


def maze():
    seen = {(0, 0)}
    stack = [(0, 0)]
    carve_cell(0, 0)
    while stack:
        x, y = stack[-1]
        nbrs = [(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                if 0 <= x + dx < W and 0 <= y + dy < H and (x + dx, y + dy) not in seen]
        if not nbrs:
            stack.pop()
            continue
        nx, ny = rnd.choice(nbrs)
        carve_cell(nx, ny)
        carve_pass((x, y), (nx, ny))
        seen.add((nx, ny))
        stack.append((nx, ny))


maze()

# 打一些环路
loops = 0
while loops < 12:
    x = rnd.randrange(1, gw - 1)
    y = rnd.randrange(1, gh - 1)
    if grid[y][x] != "#":
        continue
    if grid[y][x - 1] == "." and grid[y][x + 1] == "." and grid[y - 1][x] == "#" and grid[y + 1][x] == "#":
        grid[y][x] = "."
        loops += 1
    elif grid[y - 1][x] == "." and grid[y + 1][x] == "." and grid[y][x - 1] == "#" and grid[y][x + 1] == "#":
        grid[y][x] = "."
        loops += 1

# 几个 5x5 的房间
rooms = 0
while rooms < 5:
    rx = rnd.randrange(1, gw - 6)
    ry = rnd.randrange(1, gh - 6)
    for yy in range(ry, ry + 5):
        for xx in range(rx, rx + 5):
            grid[yy][xx] = "."
    rooms += 1

start = (1, 1)
dist = {start: 0}
q = deque([start])
while q:
    x, y = q.popleft()
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nx, ny = x + dx, y + dy
        if 0 <= nx < gw and 0 <= ny < gh and grid[ny][nx] != "#" and (nx, ny) not in dist:
            dist[(nx, ny)] = dist[(x, y)] + 1
            q.append((nx, ny))

goal = max(dist, key=dist.get)
grid[goal[1]][goal[0]] = "E"
print("地图 %dx%d，最长可达 %d 步，出口 %s" % (gw, gh, dist[goal], goal))

open("maze2_rows.txt", "w", encoding="utf-8").write(
    "\n".join('\t"%s",' % "".join(r) for r in grid))
print("已写入 maze2_rows.txt")
