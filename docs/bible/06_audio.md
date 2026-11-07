# 06 · 音效（分层、总线、事件清单）

> 状态：⬜ **全部未实现**。这一页是规格，不是现状。
> 约束：沿用「零素材」原则，音效全部程序化合成（`AudioStreamWAV`），不引入 wav/ogg 文件。

## 设计目标

1. **声音必须承载信息**，不只是氛围：左右有墙、远近、是否被听见。
2. 玩家闭眼也能玩：这是「回声」题材最便宜也最有效的表达。
3. 声音出现顺序与画面一致：波前到墙 → 回声音返回 → 颜色/亮度同步。

## 总线

```text
Master
├── Music        （当前不需要，先留空）
├── SFX          （声呐、脚步、敌人）
├── Ambience     （底噪、水滴）
└── UI           （按钮、面板）
```

| 总线 | 建议音量 | 说明 |
|---|---|---|
| Master | 0 dB | 峰值留 −6 dB 余量 |
| SFX | −3 dB | 最重要的一层 |
| Ambience | −18 dB | 不能盖过声呐 |
| UI | −10 dB | 短、轻 |

实现：`default_bus_layout.tres` + `autoload/audio.gd`（统一播放接口、限流、优先级）。

## 命名约定

`<总线小写>_<域>_<事件>`，全小写 snake_case：

- `sfx_sonar_ping`、`sfx_sonar_return`
- `sfx_footstep`
- `sfx_enemy_breath`、`sfx_enemy_alert`
- `sfx_caught`、`sfx_win`
- `ui_click`、`ui_panel_open`

事件名一旦上线**只增不改**，和遥测字段同样的规矩。

> 接入点已经就绪：`Enemy.hear()` 返回 bool，`level._alarm()` 统计并调用 `GameLog.note_alert()`。
> 以后加音效，只需在 `hear()`/`_alarm()` 里触发事件，不用改机制代码。

## 事件清单

| 事件 | 触发 | 总线 | 2D？ | 优先级 | 合成参数 | 状态 |
|---|---|---|---|---|---|---|
| `sfx_sonar_ping` | 按下空格 | SFX | 否 | 高 | 880 Hz 正弦，指数衰减 0.35 s，起音 5 ms | ⬜ |
| `sfx_sonar_return` | 波前撞墙后按距离延迟返回 | SFX | 否 | 高 | 660 Hz，衰减 0.5 s，低通随距离变闷 | ⬜ |
| `sfx_footstep` | 每走 1 格 | SFX | 是（玩家） | 中 | 60 ms 白噪声 + 低通，音量随速度 | ⬜ |
| `sfx_enemy_breath` | 敌人存在时循环 | SFX | 是（敌人） | 中 | 400 ms 噪声，LFO 2 Hz，低通 300 Hz | ⬜ |
| `sfx_enemy_alert` | 敌人被 ping 命中（`hear()` 返回 true） | SFX | 是（敌人） | 高 | 220 Hz 锯齿 0.2 s + 下滑 | ⬜ |
| `sfx_caught` | 被抓 | SFX | 否 | 最高 | 80 Hz 正弦 + 噪声，1.2 s | ⬜ |
| `sfx_win` | 通关 | SFX | 否 | 高 | 三音上行（523/659/784），各 0.15 s | ⬜ |
| `ui_click` | 面板按键 | UI | 否 | 低 | 1 kHz 方波 20 ms | ⬜ |

## 回声延迟（关键设计）

- 画面里波前速度是 **420 px/s**；返回音延迟 = `2 × 距离 / 420` 秒。
- 距离取该次脉冲**第一次**撞墙的距离。注意：现在 `trace_ray` 只回传末端位置/能量/跳数，
  要额外回传 `first_hit_distance`（做音效时的小改动，不影响现有画面）。
- 延迟超过 1.6 s（波已消失）就不再播，避免和下一声混在一起。
- 听觉效果：近墙「啪」一下立刻回来，远墙有明显的「等回声」感 —— 这就是距离信息。

## 合成规格

| 项 | 值 |
|---|---|
| 格式 | `AudioStreamWAV`，16-bit PCM，单声道 |
| 采样率 | 22050 Hz（足够，省内存） |
| 生成 | 参考 [scripts/light_factory.gd](../../scripts/light_factory.gd) 的写法，建 `audio/audio_factory.gd` |
| 随机 | 用固定种子，保证每次生成一致（便于对比） |

伪代码：

```gdscript
static func ping(freq := 880.0, dur := 0.35) -> AudioStreamWAV:
    # 采样点 = sin(2π f t) * exp(-t / 0.12)，前 5 ms 线性起音
```

## 空间化

| 声音 | 播放器 | 说明 |
|---|---|---|
| 声呐 ping / return | `AudioStreamPlayer`（非 2D） | 玩家自身，始终居中 |
| 脚步 | `AudioStreamPlayer2D` 挂在玩家 | 音量很小，只做节奏 |
| 敌人呼吸 / 警觉 | `AudioStreamPlayer2D` 挂在敌人 | 靠左右声道判断方向 |
| 结算 / UI | 非 2D | — |

## 混音规则

- 同类声音最多 3 个同时（脚步声限流），超出丢弃最旧。
- `sfx_caught` / `sfx_win` 播放时，SFX 总线瞬时压低其他声音 6 dB。
- 任何时刻峰值不超过 −1 dBFS。
- 敌人呼吸在 2 格内才可闻，避免全图噪音。

## 实现步骤

1. 建 `audio/audio_factory.gd`，生成 ping，先用 `print` 验证波形长度。
2. 建 `autoload/audio.gd` + `default_bus_layout.tres`，暴露 `play(event, pos)`。
3. 接 `player.gd` 的空格事件（ping + return 延迟）。
4. 接敌人（`hear()` 已经返回 bool，直接在里面触发 `sfx_enemy_alert`）。
5. 盲听测试：闭眼，仅凭声音判断「左/右/前」哪边有墙，10 次里 ≥ 8 次正确算通过。

## 待定

- 是否要环境底噪（水滴/低频）：**先不加**，会削弱 ping 的存在感。
- 音乐：当前不需要；如果要，只在结算面板播放 3 s 短句。
