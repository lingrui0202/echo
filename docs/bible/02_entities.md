# 02 · 实体定义

> 状态：✅ 全部实现（第 7 周补上 Enemy 与 Maze）

## 实体总表

| 实体 | 位置 | 节点类型 | 层 / 掩码 | 一句话职责 |
|---|---|---|---|---|
| Player | [Player.tscn](../../scenes/Player.tscn) | `CharacterBody2D` | 2 / 1 | 移动、发声呐、通关 |
| AmbientLight | Player.tscn | `PointLight2D` | — | 环形常亮光圈（56 px） |
| Sonar | Player.tscn + [scripts/sonar.gd](../../scripts/sonar.gd) | `PointLight2D` | — | 声呐余晖（0.12 能量） |
| SonarWave | [scripts/level.gd](../../scripts/level.gd) 运行时创建 + [scripts/sonar_wave.gd](../../scripts/sonar_wave.gd) | `Node2D` + CanvasLayer | — | 波前推进 / 反射 / 撞墙记忆 |
| Walls | level.gd 生成 | `StaticBody2D` | 1 / 0 | 碰撞 + 光照遮挡 + 视觉 |
| Goal | level.gd 生成 | `Area2D` | 4 / 2 | 通关判定 + 灯塔 |
| MapLayer（地板/网格/出口） | level.gd + [scripts/grid.gd](../../scripts/grid.gd) | `Node2D` | — | 地面、网格、出口视觉 |
| Darkness | level.gd 运行时创建 | `CanvasModulate` | — | 全黑 |
| HUD | [Level01.tscn](../../scenes/Level01.tscn) + [scripts/hud.gd](../../scripts/hud.gd) | `CanvasLayer` | — | 状态行 / 数据面板 / 结算 |
| Boot | [autoload/boot.gd](../../autoload/boot.gd) | `Node`（autoload） | — | 代码注册输入映射 |
| GameLog | [autoload/game_log.gd](../../autoload/game_log.gd) | `Node`（autoload） | — | 遥测 / 统计 / 存盘 |
| Enemy | [Enemy.tscn](../../scenes/Enemy.tscn) + [scripts/enemy.gd](../../scripts/enemy.gd) | `CharacterBody2D` | 8 / 1 | 听见声呐后追击，碰到即 caught |
| Maze | [scripts/maze.gd](../../scripts/maze.gd) | `RefCounted` | — | 格子 BFS：出生点 + 追击路径 |

## Player

- **状态**：`_cd`（冷却剩余）、`_alive`（通关/被抓后 false）。
- **移动**：`Input.get_vector` 归一化 × `SPEED`，`move_and_slide()`；无加速度、无惯性。
- **发声呐**（`_physics_process`）：
  1. 冷却 ≤ 0 且按下 → `_cd = SONAR_COOLDOWN`；
  2. `Sonar.emit()`（余晖）；
  3. `level.emit_wave(global_position)`（波前 + 敌人广播）；
  4. `GameLog.note_sonar()`。
- **通关**：`win()` → `_alive = false`、速度清零、`GameLog.end_session("win")`。
- **被抓**：`caught()` → `_alive = false`、速度清零、`GameLog.end_session("caught")`。
- **重开**：`R` 在 `_alive` 判断之前处理，所以死了也能重开。
- **不变量**：Player 永远在 `collision_layer = 2`，否则出口检测不到。

## SonarWave（核心算法实体）

- **构造**：`setup(map_rows, cell_px)` 建 `CanvasLayer(follow_viewport)` + 边界记忆 `Sprite2D`（`BLEND_MODE_ADD`）+ 绘制节点。
- **状态**：`_t = -1` 表示空闲；`_pts` / `_energies` 是当前波前的 221 个采样。
- **一条射线**：`trace_ray(dir, distance, space)` 从原点直走，撞墙按法线反射、扣掉已走距离、能量 ×0.72，最多 5 跳。
- **一帧**：`_process` 推进 `_t` → `_compute_ring()` 重算 221 条 → `queue_redraw()`；超过 1.6 s 清空。
- **撞墙记忆**：只记第 1–2 跳命中的位置，按 32 px 网格写进 122×68 的 `Image`，每 4 帧 ×0.97。
- **不变量**：波前必须画在 `follow_viewport` 的 CanvasLayer 上（见 [_index](_index.md) 不变量 5）。

## Walls

- 每一行里连续的 `#` 合并成一个 `StaticBody2D`（碰撞 + 顺时针 `LightOccluder2D` + `Polygon2D`）。
- **为什么合并**：节点数少、光照缝隙少；61×34 的地图最终约 330 个墙体节点。
- **不变量**：遮挡体必须顺时针，否则光会从墙里漏出来。

## Goal

- `Area2D`，`layer = 4`、`mask = 2`，尺寸 0.8 格。
- 视觉：0.28 格绿色菱形 + 一盏 `shadow_enabled = true` 的绿光（第 7 周修过穿墙）。
- 事件：`body_entered` → 若 body 有 `win()` 就调用。
- 关卡把出口格存进 `_goal_cell`，测试与自检从这里读，不重复写坐标。

## HUD

- `CanvasLayer`，不受 `CanvasModulate` 影响。
- 三个部件：状态行 `_hint`、`Tab` 数据面板 `_panel`、结算面板 `_result`。
- 详见 [05_ui_hud.md](05_ui_hud.md)。

## 自动加载

| 名称 | 职责 | 不变量 |
|---|---|---|
| `Boot` | 在 `_ready` 里注册 7 个动作 | 不写进 `project.godot` 的 Input Map |
| `GameLog` | 开局/结束/统计/落盘 | `start_session()` 清空本局，`end_session()` 才写盘 |

## Enemy（✅ 第 7 周）

| 项 | 实现值 | 说明 |
|---|---|---|
| 场景 / 脚本 | `scenes/Enemy.tscn` + `scripts/enemy.gd` | 圆形碰撞体 r=12 |
| 层 / 掩码 | `layer 8` / `mask 1` | 只被墙挡，不挡玩家 |
| 听觉半径 | 700 px | 穿墙，只判距离 |
| 追击 | 4 s，110 px/s | 到点后原地停，等计时结束 |
| 寻路 | `Maze.path(MAP, 当前格, 声源格)`，每 0.4 s 重算 | 格子中心逐点走 |
| 接触 | 距离 ≤ 20 px → `Player.caught()` | 不靠碰撞层 |
| 自光 | 192 px 红色微光，能量 0.32，`shadow_enabled`，缓慢呼吸 | 3 格内能提前看到；追击时亮 1.6 倍 |
| 出生 | 由 `level.gd` 按「起点→出口」路线取 30% / 65% 处的旁格 | 不写死坐标 |

**出生点规则**（`ENEMY_ROUTE_FRACS = [0.30, 0.65]`）：

- 先算 `Maze.path(START → 出口)` 的最短路（144 步）；
- 在路线 30% 和 65% 的位置取锚点，在锚点的上下左右四邻里找一个**不在路线上**的开放格；
- 两只至少隔 `ENEMY_SEP = 10` 格，且不落在起点/出口上；
- 找不到旁格才退回锚点（自检会报出来，正常地图不会发生）。

这样玩家沿正常路线走一定会经过它们附近（最近 1 格），又不会把唯一通道堵死。

**被听见的反馈**：`hear()` 返回是否听见；`level._alarm()` 统计数量并调 `GameLog.note_alert()`，
HUD 在左上角闪 1.5 s「！有东西听见了」。没有这个提示，玩家不会知道自己暴露了。

## Maze（工具）

- 静态方法 `distances(rows, start)` 和 `path(rows, from, to)`，只依赖 `Array[String]` 地图。
- `path` 用于两件事：算「起点→出口」路线（选出生点）、敌人每 0.4 s 重算追击路径；
  `distances` 用于距离统计/校验（出生点离起点多少步、路线离敌人多少格）。
- 复杂度 O(格子数)，61×34 = 2074 格，单次 BFS 约几千次操作，敌人每 0.4 s 一次可接受。
- 不引入 `NavigationRegion2D`：MAP 已经是权威数据，运行时烘焙反而多一层不一致。

## 交互矩阵

| 发起 \ 目标 | 墙 | 玩家 | 出口 | 敌人 |
|---|---|---|---|---|
| 玩家 | 碰撞（层 1） | — | 触发通关 | 20 px 内被抓住 → caught |
| 波前 | 射线查询（层 1） | 不检测 | 不检测 | 不检测 |
| 声呐广播 | — | — | — | 700 px 内听见 → 追 4 s |
| 敌人 | 碰撞 + BFS | 20 px 接触判定 | 忽略 | — |
| 光圈/余晖 | 被遮挡 | 跟随玩家 | 不相关 | 不相关 |
