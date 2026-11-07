# 07 · 工程目录结构与放置约定

> 状态：✅ 现行结构。新增目录时**必须**回来更新这一页。

## 当前树

```text
echo/
├── project.godot              # 主场景、autoload、窗口拉伸、清屏色
├── README.md                  # 周记录 + 复现命令（面向人和报告）
├── .gitignore                 # .godot/ 不进版本库
│
├── autoload/
│   ├── boot.gd                # 代码注册输入映射（不写 project.godot）
│   └── game_log.gd            # 遥测：session / 统计 / user://runs.json
│
├── scenes/
│   ├── Level01.tscn           # 关卡根：Walls + Player + HUD（Enemies 运行时生成）
│   ├── Player.tscn            # 玩家：碰撞 / 光圈 / 声呐 / 相机
│   └── Enemy.tscn             # 敌人：圆形碰撞体 + enemy.gd
│
├── scripts/                   # 一个系统一个文件，扁平放置
│   ├── level.gd               # @tool：MAP → 墙 / 遮挡 / 视觉 / 出口 / 敌人生成 / 相机 / 遥测
│   ├── player.gd              # 移动 / 发声呐 / 通关 / 被抓
│   ├── enemy.gd               # 听觉 / BFS 追击 / 接触判定
│   ├── maze.gd                # 格子 BFS（出生点 + 追击路径）
│   ├── sonar.gd               # 余晖（PointLight2D）
│   ├── sonar_wave.gd          # 波前 + 反射 + 撞墙记忆（核心算法）
│   ├── light_factory.gd       # 运行时生成径向/环状贴图
│   ├── grid.gd                # 地面网格（只在被照亮时可见）
│   └── hud.gd                 # 状态行 / 被听见提示 / 数据面板 / 结算面板
│
├── tools/                     # 验证脚本，不是游戏内容
│   ├── selfcheck.gd / .tscn   # 场景式自检（不依赖 --script）
│   ├── smoke.gd               # 移动 / 碰撞 / 冷却（SceneTree）
│   ├── test_win.gd            # 通关链路 + 结算截图（SceneTree）
│   ├── capture.gd             # 多时间点截图（SceneTree）
│   ├── darkness_shots.gd      # 三档黑暗对比
│   ├── wave_shots.gd          # 波前连拍
│   ├── hud_check.gd           # HUD 面板截图
│   ├── editor_preview.gd      # 一屏看全图
│   ├── wave_debug.gd          # 早期波动方程遗留，已失效（待清理）
│   └── make_maze2.py          # 纯 Python 迷宫生成器（不依赖 Godot）
│
├── docs/
│   ├── Echo_第5周_提案与验证.docx / .pdf
│   ├── Echo_项目准备说明_第4周作业.docx / .pdf
│   └── bible/                 # 本目录，设计与决策的单一事实源
│
└── _verify/                   # 验证产物（截图 / 自检 txt），可当提交材料
    ├── selfcheck.txt
    ├── selfcheck_wave.png
    ├── selfcheck_enemy.png
    ├── selfcheck_win.png
    ├── selfcheck_caught.png
    └── shot_*.png / wave_*.png / compare_*.png / win_panel.png
```

## 放置规则

| 要加的东西 | 放哪 | 命名 |
|---|---|---|
| 新系统脚本 | `scripts/` | 小写 snake_case，一个文件一个系统 |
| 新实体场景 | `scenes/` | `Enemy.tscn`、`Level02.tscn` |
| 敌人相关脚本 | `scripts/`（先扁平放） | `enemy.gd`、`maze.gd` |
| 音效 | `audio/`（做音效时建） | `audio_factory.gd`、`default_bus_layout.tres` |
| 关卡数据 | `levels/`（做多关卡时建） | `level01.tres` 或 `level01.txt` |
| 验证脚本 | `tools/` | `check_*.gd` / `*_shots.gd` |
| 验证产物 | `_verify/` | 见下 |
| 文档 | `docs/` | 周作业 `Echo_第N周_*.docx` |

## 脚本约定

- 跨文件引用一律 `const X = preload(...)`，**不用** `class_name`：不依赖编辑器的全局类缓存，命令行/自检都能解析。
- 常量放文件顶部，集中可调；注释写「为什么」，不写「做了什么」。
- 运行时创建节点（墙、光、波）优先于场景里手摆，方便测试与复现。
- `@tool` 只给 `level.gd` 用；其它脚本在编辑器里运行会出问题。
- 需要 autoload 时用 `get_node_or_null("/root/GameLog")` 并判空，方便在 `--script` / 编辑器环境跑。

## 场景组合约定

`Level01.tscn` 只有三样：`Walls`（空容器）、`Player`（实例）、`HUD`（CanvasLayer）。
`MapLayer`、`Darkness`、`SonarWave`、相机限位全部运行时生成 —— 这样编辑器里能看见全图，游戏里才全黑。

## 验证脚本约定

| 类型 | 入口 | 适合 |
|---|---|---|
| SceneTree 脚本 | `--script res://tools/xxx.gd` | 精确时间点断言、输入模拟 |
| 普通场景 | `godot <场景路径>` | 需要引擎正常跑主循环、截图、自检 |

- 断言失败要 `print("FAIL: ...")` 并让进程返回非 0（场景用 `get_tree().quit(1)`）。
- 新验证脚本必须能被 README 的复现命令跑到。
- 截图命名：
  - `shot_<序号>_<阶段>.png`（capture）
  - `wave_<毫秒>.png`（wave_shots）
  - `compare_<主题>.png`（对比图）
  - `selfcheck_<用途>.png`（自检）

## 导出注意事项

- 排除 `tools/`、`docs/`、`_verify/`、`.godot/`（导出预设里加过滤）。
- `user://runs.json` 是玩家数据，**不进**安装包。
- 工程零图片/零音频素材，所以导出包很小；新增素材前先想清楚是否必要。

## 清理清单

- `tools/wave_debug.gd` 引用的是已废弃的波动方程字段，跑不通；下次清理时删除。
- `_verify` 里的旧图（第 4/5 周）体积不大，可留作对比；提交前确认没有过期结论图。
