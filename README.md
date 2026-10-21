# 回声定位探索（垂直切片）

> **Echo（回声）** · 计算机图形学与游戏开发 · 两人小组项目
> 设计说明：[docs/Echo_项目准备说明_第4周作业.pdf](docs/Echo_项目准备说明_第4周作业.pdf)
> 引擎：Godot 4.7.2 · 入口场景：res://scenes/Level01.tscn


全黑洞穴里，你只能靠一次次的**声呐脉冲**看清周围——光波扩散出去，被墙挡住的地方依然漆黑。
这个工程已经把核心机制、关卡生成、通关判定和**遥测**都跑通了，是一个可以往上长骨架。

---

## 怎么运行

- 图形界面：用 Godot **4.7** 打开 `project.godot`，按 **F5**。
- 命令行：
  ```
  Godot_v4.7.2-stable_win64.exe --path <本目录>
  ```

## 操作

| 键 | 作用 |
|---|---|
| `WASD` / 方向键 | 移动 |
| `空格` | 发声呐（冷却 1.2 秒） |
| `Tab` | 打开/关闭数据面板 |
| `R` | 重开本关 |

---

## 现在有什么（都已实机验证）

- **全黑画面** + 玩家身上一圈小的常亮光（半径约 128px）——没有它玩家会 10 秒内放弃。
- **声呐脉冲**：一盏 `PointLight2D` 从玩家身上扩散，配一圈可见波纹；`shadow_enabled` 让光被
  `LightOccluder2D` 挡住，所以照亮的永远是"真的能看见"的区域，墙后会留下真实的黑色投影。
- **地图由 ASCII 生成**：碰撞体、光照遮挡体、视觉三样自动同步，改关卡只改字符串。
- **出口与通关**：走到绿色菱形即通关。
- **遥测**：每局结束（通关）自动记一条 JSON：用时、声呐次数、走过格子数、重复率、是否通关。
- **数据面板**：`Tab` 查看最近 10 局的均值——这是你报告里"证据"的来源。

## 文件结构

| 文件 | 作用 |
|---|---|
| `project.godot` | 工程配置（主场景、两个 autoload） |
| `autoload/boot.gd` | 在代码里注册输入映射（不用编辑器的 Input Map） |
| `autoload/game_log.gd` | **遥测**：记录每局数据、算统计、存 `user://runs.json` |
| `scripts/player.gd` | 移动、发声呐、通关 |
| `scripts/sonar.gd` | 声呐脉冲（光扩散 + 波纹淡出） |
| `scripts/level.gd` | ASCII 地图 → 墙 / 遮挡体 / 出口；地面与网格 |
| `scripts/light_factory.gd` | 运行时生成径向渐变贴图（所以工程里**零图片资源**） |
| `scripts/grid.gd` | 地面网格，只在被照亮时可见 |
| `scripts/hud.gd` | 状态行 + `Tab` 数据面板 |
| `scenes/Player.tscn` | 玩家：碰撞体 / 环境光 / 声呐光 / 相机 |
| `scenes/Level01.tscn` | 关卡：CanvasModulate（黑暗） + 墙容器 + 玩家 + HUD |
| `tools/capture.gd` | 验证脚本：离屏跑关卡并在多个时间点截图 |
| `tools/test_win.gd` | 验证脚本：瞬移到出口，检查通关链路 |
| `_verify/` | 上面两个脚本产出的截图，可直接当提交材料的"实际运行画面" |

---

## 你该动的三个参数（这就是实验变量）

一次**只改一个**，先写下预测，再运行，然后按 `Tab` 看数据。

1. `scripts/player.gd` → `SONAR_COOLDOWN = 1.2`
   声呐冷却。调大 → 更紧张、更依赖记忆；调小 → 更从容、更像"手电筒"。
2. `scripts/sonar.gd` → `DURATION` / `MAX_SCALE` / `PEAK_ENERGY`
   脉冲的持续时间与能照多远。
3. `scenes/Level01.tscn` → `CanvasModulate.color`
   整体黑暗程度。太暗会让人烦躁，太亮就没有探索感——这个阈值值得实测。

想改关卡：编辑 `scripts/level.gd` 里的 `MAP` 数组，`#` 是墙、`.` 是地面、`E` 是出口，
边界墙由代码自动补齐。起点在 `START` 里改。

---

## 已验证 / 未验证（照实写，这是加分项）

**已在本机验证**
- 工程可启动，无脚本报错（Godot 4.7.2 / Vulkan Forward+）。
- 光照与遮挡正确：声呐照亮的区域被墙截断，墙后有黑色投影（见 `_verify/shot_1_early.png`）。
- 脉冲会完整淡出并归零（`energy → 0`、`active = false`），不会残留。
- 出口 `Area2D` 能触发通关，`GameLog.last_reason = "win"`。
- 遥测的记录与统计逻辑正常运行。

**未验证（需要你在自己机器上确认一次）**
- `runs.json` 是否真的写进磁盘：我这边环境无法写 `%APPDATA%`，`user://` 写入被拦。
  你跑一局后按 `Tab`，如果面板出现"最近 1 局统计"，就说明写成功了。
  文件位置：`%APPDATA%\Godot\app_userdata\Echo Location\runs.json`
- `_verify/` 里的截图是**离屏低帧率**抓的，实机手感会更连贯。

> 以上两条已于 2026-10-21 在本机验证通过，结论见文末「工程自检记录」。

---

## 下一步（按性价比排）

1. **会听见你的敌人**（最该做）：`Area2D` + 听觉半径。你一发声呐，附近敌人就朝你走过来。
   这一步把声呐从"纯帮助"变成"有代价的选择"，机制才有张力，报告也才有可讨论的取舍。
2. **3 个关卡**：复制 `Level01.tscn` 改 `MAP` 即可，难度靠墙的密度和出口距离调节。
3. **音效**：声呐的 ping、脚步、敌人呼吸。黑暗里听觉是主要线索，这几个音效能顶很多美术。
4. **记忆层**：走过的路径留下逐渐变暗的轨迹（`Tween` 改 alpha），强化"我在记地图"的体验。

## 写报告时怎么用这些

- **目标体验一句话**：我希望玩家在 5 分钟内感到"紧张但逐渐掌控"——靠有限次数的声呐把黑暗变成一张记住的地图。
- **规则 → 系统 → 反馈链**：声呐（规则）→ 光照遮挡 + 冷却计时（系统）→ 可视范围扩散 + 波纹 + 音效 + 数据面板（反馈）→ 玩家因此敢往深处走。
- **一轮验证**：把 `SONAR_COOLDOWN` 从 1.2 改到 2.0，同一个人跑 10 局，比较 `Tab` 里的平均用时、平均重复率、平均声呐次数，再写"证据支持/否定了我的预测"。
- 记住这门课真正在看的是：**能不能运行、能不能解释、能不能发现偏差并修正**。所以每处改动都记下"改了哪个文件哪个参数、预测什么、实际观察到什么"。

---

## 工程自检记录（第 4 周作业，2026-10-21）

**环境**：Godot 4.7.2 stable official（build `ed1daf0bf`），Windows 64 位，Vulkan Forward+。
**打开方式**：编辑器「导入」→ 选 `project.godot`，按 F5；或命令行
`Godot_v4.7.2-stable_win64.exe --path <本目录>`。
**入口场景**：`res://scenes/Level01.tscn`（已写入 `run/main_scene`）。

| 检查 | 命令 / 方法 | 结果 |
|---|---|---|
| 导入与脚本 | `--headless --quit` | 无报错 |
| 通关链路 | `tools/test_win.gd` | PASS，`last_reason = "win"` |
| 移动 / 碰撞 / 冷却 | `tools/smoke.gd` | PASS（235 px/1.0 s；顶墙停在 x=247，墙面 256；冷却 1→1→2） |
| 脉冲归零 | `tools/capture.gd` 采样 | energy 2.188 → 1.065 → 0.000，`active=false` |
| 遮挡投影 | 截图像素采样 | 墙上方 53.7/255，墙后同距离 4.7/255 |
| 遥测落盘 | 跑一局后查 `user://` | `%APPDATA%\Godot\app_userdata\Echo Location\runs.json` 已生成 |

复现命令（在本目录下，把 `<本目录>` 换成本目录）：

```
Godot_v4.7.2-stable_win64_console.exe --headless --path <本目录> --script res://tools/test_win.gd
Godot_v4.7.2-stable_win64_console.exe --headless --path <本目录> --script res://tools/smoke.gd
Godot_v4.7.2-stable_win64_console.exe --path <本目录> --script res://tools/capture.gd
```

补充说明：
- 上面两条「未验证」本次都已确认：`runs.json` 写入成功；`_verify/` 的 5 张截图已用 4.7.2 重新生成。
- `tools/smoke.gd` 第一版按帧数计时，在 headless 下渲染帧多于物理帧，会误报「移动只有 94 px」；
  已改为按真实时间卡点。94 px ÷ 0.4 s ≈ 235 px/s，恰好等于 `SPEED`，游戏本身没问题。
- 详细的作业说明见同级的《Echo_项目准备说明_第4周作业.docx》。
