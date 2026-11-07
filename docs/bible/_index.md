# Echo 设计圣经 · 索引

> 版本 1.1 · 2026-11-07 · Godot 4.7.2 / Vulkan Forward+
> 这份文档描述**这个工程实际上是什么样**，以及**下一刀该往哪切**。
> 阅读顺序：[`_index`](_index.md) → [`01_core_loop`](01_core_loop.md) → [`03_rules`](03_rules.md) → 你正在改的那个系统。

## 怎么用

1. 动代码前，先看下面的「不变量」和对应系统的数值表。
2. **代码是事实，bible 是解释**。两者不一致 → 以代码为准，并在 [99_decisions.md](99_decisions.md) 记一条。
3. 任何数值/规则的改动，先写预测，再改，再跑 [tools/selfcheck.tscn](../../tools/selfcheck.tscn)，最后补一条决策。

## 文件地图

| 文件 | 回答什么问题 | 状态 |
|---|---|---|
| [00_world.md](00_world.md) | 这是什么世界、什么调性、为什么黑 | 稳定 |
| [01_core_loop.md](01_core_loop.md) | 玩家每秒/每局在做什么 | 稳定，冷却实验会微调 |
| [02_entities.md](02_entities.md) | 场上有什么东西、各自负责什么 | 稳定，敌人已加 |
| [03_rules.md](03_rules.md) | 怎么算赢/输、数值边界 | 稳定 |
| [04_physics.md](04_physics.md) | 尺寸、速度、光照、声呐几何 | 稳定 |
| [05_ui_hud.md](05_ui_hud.md) | 屏幕上显示什么、怎么排版 | 稳定 |
| [06_audio.md](06_audio.md) | 声音分几层、事件怎么命名 | **规划中（尚未实现）** |
| [07_file_layout.md](07_file_layout.md) | 新文件放哪、怎么命名 | 稳定 |
| [99_decisions.md](99_decisions.md) | 为什么是现在这样 | 仅追加 |

## 一句话

在全黑的迷宫里，你只能靠一次次声呐脉冲把墙「照」出来；波推出去、被墙挡住、反射回来。
**看不见，所以要发声；发声就要付代价**——后半句第 8 周已经补上（敌人会听见）。

## 速查表（改数值前先看这里）

| 量 | 值 | 定义位置 |
|---|---|---|
| 格边长 | 64 px | [scripts/level.gd](../../scripts/level.gd) `CELL` |
| 地图 | 61×34 格 = 3904×2176 px | `MAP` |
| 起点 / 出口 | (1,1) / (26,14) | `START` / `'E'` |
| 最短通路 | 144 步（BFS 核对） | [README](../../README.md) 第 6 周 |
| 玩家速度 | 235 px/s | [scripts/player.gd](../../scripts/player.gd) `SPEED` |
| 声呐冷却 | 1.8 s | `SONAR_COOLDOWN` |
| 波前速度 / 时长 | 420 px/s / 1.6 s → 半径 672 px | [scripts/sonar_wave.gd](../../scripts/sonar_wave.gd) |
| 反射 | 最多 5 次，每次 ×0.72 | `MAX_BOUNCES` / `BOUNCE_LOSS` |
| 波前采样 | 220 段（221 点） | `SEGMENTS` |
| 常亮光圈 | 半径 56 px，能量 0.75，环状 | `AMBIENT_RADIUS` / `AMBIENT_ENERGY` |
| 余晖 | 半径 672 px，能量 0.12，1.05 s | [scripts/sonar.gd](../../scripts/sonar.gd) |
| 黑暗 | CanvasModulate 0.015/0.017/0.028 | [scripts/level.gd](../../scripts/level.gd) `DARK` |
| 墙记忆 | 32 px 网格，α0.26，约 6–7 s 退完 | `sonar_wave.gd` |
| 视口 | 1152×648，`canvas_items` 拉伸 | [project.godot](../../project.godot) |
| 遥测 | `user://runs.json`，最多 200 条 | [autoload/game_log.gd](../../autoload/game_log.gd) |
| 敌人听觉 / 速度 / 追击 | 700 px / 110 px/s / 4 s | [scripts/enemy.gd](../../scripts/enemy.gd) |
| 敌人出生 | 沿「起点→出口」路线的 30% / 65% 旁格 | [scripts/level.gd](../../scripts/level.gd) `ENEMY_ROUTE_FRACS` |
| 接触判定 | 20 px（不靠碰撞，靠距离） | `enemy.gd` `CATCH_RADIUS` |

## 不变量（违反会直接坏体验或坏数据）

1. **地图唯一权威是 `level.gd` 的 `MAP`**；碰撞体、遮挡体、视觉、波反射全部由它生成，不许手摆。
2. **1 格 = 64 px**，原点在地图左上角，y 轴向下。任何新系统都用这套坐标。
3. **碰撞层**：1=墙，2=玩家，4=出口。新增实体不许复用这三层。
4. **遮挡体多边形必须顺时针**（y 向下时「上左→上右→下右→下左」），逆时针会让光从墙里漏出来。
5. **波前只能画在 `follow_viewport_enabled` 的 CanvasLayer 上**；画在关卡里会被 CanvasModulate 乘到 0.015，等于没画。
6. **编辑器模式不生成 Darkness / SonarWave / 相机限位**，否则在编辑器里看不到地图。
7. **通道至少 2 格宽**。1 格走廊里反射会碎成小光斑，屏幕很乱（第 6 周结论）。
8. **遥测记录只追加不改写**（除超过 200 条截断）；字段只增不删，旧记录必须还能读。
9. **HUD 在 CanvasLayer 上**，不受黑暗影响；任何可读文本都不能画在世界层。
10. **零图片/零音频素材**是当前约束：贴图运行时生成，音效将来也走程序化合成。
11. **敌人听觉穿墙**（只判距离，不做视线）；这是「发声有代价」的根据，不要加视线判定。
12. **敌人寻路只走 `scripts/maze.gd` 的 MAP BFS**，不要引入 NavigationRegion2D 烘焙。
13. **敌人层 8、玩家 mask 不含 8**：敌人不挡玩家，接触靠 20 px 距离判定。

## 系统状态

| 系统 | 状态 | 备注 |
|---|---|---|
| 移动 / 碰撞 | ✅ | smoke 验证过 |
| 声呐波前 + 反射 | ✅ | 截图 + 自检 |
| 撞墙记忆 | ✅ | 6–7 s 衰减 |
| 全黑 + 光圈 | ✅ | 暗场均值 5.5/255 |
| 出口 / 通关 / 结算 | ✅ | test_win 验证 |
| 遥测 runs.json | ✅ | 第 7 周加 config |
| 相机限位 | ✅ | 第 7 周 |
| 敌人 / 失败 | ✅ | 第 8 周：听觉 + 追击 + caught |
| 音效 | ⬜ | 待做 |
| 多关卡 | ⬜ | 待做 |
| 自动 A/B 实验 | ⬜ | 待做 |
| 性能优化 | ⬜（暂缓） | 实测 1.2 ms/帧，不紧迫 |

## 变更协议

- **改数值**：写预测 → 改 → 跑 selfcheck → 用 `runs.json` 的 `config` 对比 → 记 [99_decisions.md](99_decisions.md)。
- **加系统**：先在 [02_entities.md](02_entities.md) 写实体与交互，再在 [03_rules.md](03_rules.md) 写规则，最后写代码。
- **文档与代码冲突**：改文档，或改代码并在 99 记录原因；**不允许两边都放着不管**。
